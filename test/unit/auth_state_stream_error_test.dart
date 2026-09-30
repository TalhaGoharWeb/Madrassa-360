// Regression test: an error on the Supabase auth-state stream must not
// crash the app to the CrashScreen.
//
// Root cause of the "Something went wrong / AuthRetryableFetchException
// (Failed host lookup)" crash report (2026-09-30): when the device has no
// working DNS at launch and the persisted session's access token is
// expired, gotrue's background token refresh fails and gotrue reports it
// via `notifyException`, which is `Stream.addError` on its BROADCAST
// auth-state stream. The app's listener (AuthNotifier._init) had no
// `onError`, so the error became an unhandled async error →
// runZonedGuarded → CrashScreen — even though the persisted session was
// still perfectly usable offline.
//
// This test pins the contract: pushing an AuthRetryableFetchException
// into the auth-state stream leaves the notifier alive with its state
// untouched, and no error escapes the zone.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../widget/fake_auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'auth-state stream error (failed background refresh) does not escape '
      'as an unhandled async error', () async {
    SharedPreferences.setMockInitialValues({});
    // Dead address: Supabase.initialize touches no network; the URL is
    // never requested because the fake repository overrides every path
    // that could hit it (see FakeAuthRepository docs).
    await sb.Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'test-anon-key',
    );

    final fake = FakeAuthRepository();
    addTearDown(fake.dispose);

    final unhandled = <Object>[];
    await runZonedGuarded(() async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      // Creating the notifier attaches the auth-state stream listener.
      final notifier = container.read(authProvider.notifier);
      final before = container.read(authProvider);

      // Simulate gotrue's notifyException: a failed background token
      // refresh surfaces as addError on the broadcast auth-state stream.
      fake.emitError(sb.AuthRetryableFetchException(
        message: 'ClientException with SocketException: '
            'Failed host lookup: \'ffhsrnkvjjedvclfwgmr.supabase.co\' '
            '(OS Error: No such host is known, errno = 11001)',
      ));

      // Let the async error propagate through the stream.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // The notifier must be alive and its state untouched: a transient
      // stream error must neither sign the user out nor crash the app.
      expect(container.read(authProvider), same(before));
      expect(notifier.mounted, isTrue);
    }, (Object error, StackTrace stack) {
      unhandled.add(error);
    });

    expect(
      unhandled,
      isEmpty,
      reason: 'auth-state stream errors must be handled by the listener, '
          'not escape the zone (that escape path shows the CrashScreen)',
    );
  });
}
