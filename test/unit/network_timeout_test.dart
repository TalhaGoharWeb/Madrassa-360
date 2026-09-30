/// Regression test: network timeouts must fail fast, never hang forever.
///
/// A Supabase query with no timeout can stall indefinitely (slow DNS,
/// captive portal, dropped connection), leaving every screen that watches
/// the provider stuck on its loading skeleton with no error and no retry.
/// [withNetworkTimeout] converts a stall into a [TimeoutException] so the
/// provider's catch block runs and the UI shows an error/empty state.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/utils/network_timeout.dart';

void main() {
  group('withNetworkTimeout', () {
    test('completes normally when the future finishes in time', () async {
      final result =
          await Future.delayed(const Duration(milliseconds: 50), () => 42)
              .withNetworkTimeout(const Duration(seconds: 5));
      expect(result, 42);
    });

    test('throws TimeoutException when the future hangs', () async {
      final hung = Completer<String>().future;
      await expectLater(
        hung.withNetworkTimeout(const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('uses the default 20s timeout when no limit is given', () {
      expect(networkTimeout, const Duration(seconds: 20));
    });

    test('a hung provider-style load fails fast instead of forever', () async {
      // Simulates: state = loading; await query; state = done.
      // Without the timeout the await never returns.
      var resolved = false;
      try {
        await Completer<void>()
            .future
            .withNetworkTimeout(const Duration(milliseconds: 100));
      } on TimeoutException {
        resolved = true;
      }
      expect(resolved, isTrue,
          reason: 'hung query must surface as an error, not infinite loading');
    });
  });
}
