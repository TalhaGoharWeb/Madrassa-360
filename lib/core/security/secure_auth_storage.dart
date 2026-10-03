/// محفوظ ٹوکن ذخیرہ
/// Secure auth storage (SEC-H11) — persists the Supabase session through
/// encrypted platform storage instead of plaintext SharedPreferences.
///
/// Two adapters, both constructor-injectable so they are unit-testable:
///
/// * [SecureAuthStorage] implements supabase_flutter's [LocalStorage] and
///   holds the session JSON (access + refresh tokens).
/// * [SecureGotrueAsyncStorage] implements gotrue's [GotrueAsyncStorage]
///   and holds the PKCE code verifier.
///
/// On first launch after the upgrade, [SecureAuthStorage.migrateFromLegacy]
/// copies any session left in the old SharedPreferences key
/// (`sb-<project-ref>-auth-token`) into secure storage and deletes the
/// plaintext copy, so existing installs do not get signed out.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../observability/app_logger.dart';

/// Narrow interface over the encrypted store so the adapters can be
/// unit-tested with a fake instead of platform channels.
abstract class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// Production [SecureValueStore] backed by flutter_secure_storage
/// (Keychain on iOS, EncryptedSharedPreferences on Android, Credential
/// Vault on Windows).
class FlutterSecureValueStore implements SecureValueStore {
  FlutterSecureValueStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> remove(String key) => _storage.delete(key: key);
}

/// supabase_flutter [LocalStorage] that keeps the session JSON in encrypted
/// storage. The [persistSessionKey] must match the SDK default
/// (`sb-<project-ref>-auth-token`) so [migrateFromLegacy] finds the old copy.
class SecureAuthStorage extends LocalStorage {
  SecureAuthStorage({
    required this.persistSessionKey,
    SecureValueStore? store,
  }) : _store = store ?? FlutterSecureValueStore();

  final String persistSessionKey;
  final SecureValueStore _store;

  @override
  Future<void> initialize() async {
    // Nothing to warm up — the platform store is ready on first use.
  }

  @override
  Future<bool> hasAccessToken() async =>
      (await _store.read(persistSessionKey)) != null;

  @override
  Future<String?> accessToken() => _store.read(persistSessionKey);

  @override
  Future<void> removePersistedSession() => _store.remove(persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(persistSessionKey, persistSessionString);

  /// One-time migration for installs that stored the session in plaintext
  /// SharedPreferences before SEC-H11. Copies the value into secure storage
  /// and deletes the plaintext key. Never throws — a failed migration must
  /// not block app start; the user simply signs in again.
  Future<void> migrateFromLegacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(persistSessionKey);
      if (legacy == null || legacy.isEmpty) return;
      if (await hasAccessToken()) {
        // A secure copy already exists — just drop the plaintext one.
        await prefs.remove(persistSessionKey);
        return;
      }
      await persistSession(legacy);
      await prefs.remove(persistSessionKey);
      AppLogger().info('[Auth] migrated session from SharedPreferences '
          'to secure storage');
    } catch (e) {
      AppLogger()
          .warning('[Auth] session migration failed (non-fatal)', error: e);
    }
  }
}

/// gotrue [GotrueAsyncStorage] for the PKCE code verifier, kept in encrypted
/// storage alongside the session (it is equally credential-equivalent
/// during the auth flow).
class SecureGotrueAsyncStorage extends GotrueAsyncStorage {
  SecureGotrueAsyncStorage({SecureValueStore? store})
      : _store = store ?? FlutterSecureValueStore();

  final SecureValueStore _store;

  @override
  Future<String?> getItem({required String key}) => _store.read(key);

  @override
  Future<void> setItem({required String key, required String value}) =>
      _store.write(key, value);

  @override
  Future<void> removeItem({required String key}) => _store.remove(key);
}
