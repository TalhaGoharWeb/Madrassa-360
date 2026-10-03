// Login-hardening unit tests — progressive client-side backoff.
//
// What is real here: AuthNotifier.backoffSecondsForFailures, the exact
// pure function the login flow consults before attempting sign-in.
// 0-1 failures → no delay; then 2s, 4s, 8s, 16s, capped at 30s.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/providers/auth_provider.dart';

void main() {
  group('backoffSecondsForFailures', () {
    test('no delay for the first failures (legitimate typos)', () {
      expect(AuthNotifier.backoffSecondsForFailures(0), 0);
      expect(AuthNotifier.backoffSecondsForFailures(1), 0);
    });

    test('doubles with each failure', () {
      expect(AuthNotifier.backoffSecondsForFailures(2), 2);
      expect(AuthNotifier.backoffSecondsForFailures(3), 4);
      expect(AuthNotifier.backoffSecondsForFailures(4), 8);
      expect(AuthNotifier.backoffSecondsForFailures(5), 16);
    });

    test('caps at 30 seconds', () {
      expect(AuthNotifier.backoffSecondsForFailures(6), 30);
      expect(AuthNotifier.backoffSecondsForFailures(20), 30);
      expect(AuthNotifier.backoffSecondsForFailures(1000), 30);
    });
  });
}
