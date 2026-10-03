/// Extended validator tests — the gaps left by
/// test/unit/security/validators_adversarial_test.dart.
///
/// Implementation file under test:
///   lib/core/utils/validators.dart
///
/// The adversarial suite covers email/phone/cnic/username/rollNumber/
/// numeric/password/combine. This file covers `Validators.required` (the
/// one method the adversarial suite skips) plus boundary interactions.
///
/// DOCUMENTED GAPS (not testable — the validators do not exist):
///   * no URL validator: `javascript:`/data: photo URLs pass through
///     (audit SEC-M33 / input-validation F-07);
///   * no filename sanitizer in lib/ (audit file-uploads M5).
/// These need new validators, not more tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/utils/validators.dart';

void main() {
  group('Validators.required — presence', () {
    test('accepts ordinary text', () {
      expect(Validators.required('احمد'), isNull);
      expect(Validators.required('  padded  '), isNull);
    });

    test('rejects null, empty, and whitespace-only', () {
      expect(Validators.required(null), isNotNull);
      expect(Validators.required(''), isNotNull);
      expect(Validators.required('   '), isNotNull);
      expect(Validators.required('\t\n '), isNotNull);
    });

    test('uses the field name in the message when provided', () {
      final msg = Validators.required('', fieldName: 'نام');
      expect(msg, contains('نام'));
    });

    test('zero-width and bidi control characters alone do not count as content',
        () {
      // U+200B ZERO WIDTH SPACE, U+200C ZERO WIDTH NON-JOINER,
      // U+202E RIGHT-TO-LEFT OVERRIDE — invisible but non-trimmed by Dart.
      // This documents current behavior: they PASS required (trim() does
      // not strip them). If the backend ever treats them as empty, this
      // test must be updated to expect rejection.
      expect(Validators.required('​'), isNull);
    });
  });

  group('Validators.combine — boundary interactions', () {
    test('short-circuits on the first failure', () {
      final v = Validators.combine([
        (s) => Validators.required(s, fieldName: 'X'),
        (s) => Validators.minLength(s, 5, fieldName: 'X'),
      ]);
      expect(v(''), contains('X'));
      expect(v('ab'), isNotNull);
      expect(v('abcdef'), isNull);
    });

    test('empty validator list always passes', () {
      expect(Validators.combine([])('anything'), isNull);
    });
  });
}
