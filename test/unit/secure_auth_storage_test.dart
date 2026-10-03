// SEC-H11 regression tests — the Supabase session must live in encrypted
// platform storage, never plaintext SharedPreferences.
//
// What is real here:
//   * SecureAuthStorage / SecureGotrueAsyncStorage — the exact adapters
//     wired into Supabase.initialize via SupabaseService.buildAuthOptions.
//   * The migration path from the legacy SharedPreferences key.
// The fake store stands in for flutter_secure_storage (platform channels
// are unavailable in unit tests); the assertion that matters is that every
// session byte flows through the injected secure store and nothing else.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/security/secure_auth_storage.dart';
import 'package:madrasa_360/core/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSecureStore implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureAuthStorage', () {
    test('round-trips the session through the secure store only', () async {
      final fake = FakeSecureStore();
      final storage = SecureAuthStorage(
        persistSessionKey: 'sb-xyz-auth-token',
        store: fake,
      );
      await storage.initialize();

      expect(await storage.hasAccessToken(), isFalse);
      await storage.persistSession('{"access_token":"abc"}');
      expect(await storage.hasAccessToken(), isTrue);
      expect(await storage.accessToken(), '{"access_token":"abc"}');
      expect(fake.values, {'sb-xyz-auth-token': '{"access_token":"abc"}'});

      await storage.removePersistedSession();
      expect(await storage.hasAccessToken(), isFalse);
      expect(fake.values, isEmpty);
    });

    test('migrateFromLegacy copies the plaintext session then deletes it',
        () async {
      SharedPreferences.setMockInitialValues(
          {'sb-xyz-auth-token': 'legacy-session-json'});
      final fake = FakeSecureStore();
      final storage = SecureAuthStorage(
        persistSessionKey: 'sb-xyz-auth-token',
        store: fake,
      );

      await storage.migrateFromLegacy();

      expect(fake.values['sb-xyz-auth-token'], 'legacy-session-json');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('sb-xyz-auth-token'), isFalse);
      expect(await storage.hasAccessToken(), isTrue);
    });

    test('migrateFromLegacy is a no-op when nothing was stored', () async {
      SharedPreferences.setMockInitialValues({});
      final fake = FakeSecureStore();
      final storage = SecureAuthStorage(
        persistSessionKey: 'sb-xyz-auth-token',
        store: fake,
      );
      await storage.migrateFromLegacy(); // must not throw
      expect(fake.values, isEmpty);
    });
  });

  group('SecureGotrueAsyncStorage', () {
    test('get/set/remove round-trip', () async {
      final fake = FakeSecureStore();
      final storage = SecureGotrueAsyncStorage(store: fake);
      expect(await storage.getItem(key: 'k'), isNull);
      await storage.setItem(key: 'k', value: 'v');
      expect(await storage.getItem(key: 'k'), 'v');
      await storage.removeItem(key: 'k');
      expect(await storage.getItem(key: 'k'), isNull);
    });
  });

  group('SupabaseService.buildAuthOptions', () {
    test('wires the secure adapters (regression: no SharedPreferences)', () {
      final options =
          SupabaseService.buildAuthOptions('https://xyzcompany.supabase.co');

      expect(options.localStorage, isA<SecureAuthStorage>());
      final authStorage = options.localStorage as SecureAuthStorage;
      // Same key the SDK used before, so migration finds the legacy copy.
      expect(authStorage.persistSessionKey, 'sb-xyzcompany-auth-token');
      expect(options.pkceAsyncStorage, isA<SecureGotrueAsyncStorage>());
      expect(options.detectSessionInUri, isTrue);
      // The singleton the service exposes is the wired adapter.
      expect(SupabaseService.authStorage, same(authStorage));
    });
  });
}
