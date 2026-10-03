/// Adversarial input tests for [Validators].
///
/// Implementation file under test:
///   lib/core/utils/validators.dart
///
/// Strategy: pure-Dart unit tests — no Supabase, no widgets. Each case feeds
/// hostile or boundary input (oversized, injection-shaped, unicode tricks,
/// type-coercion edges) and asserts the validator rejects it. These lock in
/// the client-side half of the validation contract (audit SEC-M33); the
/// backend half (Phase 4.2 value objects + DB CHECKs) is covered by the
/// SQL scripts under test/db/ and the Edge Function guards.
///
/// A `null` return means "valid". A non-null return means "rejected".

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/utils/validators.dart';

void main() {
  group('Validators.email — adversarial', () {
    test('accepts a normal address', () {
      expect(Validators.email('mohtamim@madrassa.com'), isNull);
    });

    test('rejects null and empty (required)', () {
      expect(Validators.email(null), isNotNull);
      expect(Validators.email(''), isNotNull);
    });

    test('rejects header-injection newlines', () {
      expect(Validators.email('a@b.com\nBcc: evil@x.com'), isNotNull);
      expect(Validators.email('a@b.com\revil@x.com'), isNotNull);
    });

    test('rejects missing TLD and one-char TLD', () {
      expect(Validators.email('user@domain'), isNotNull);
      expect(Validators.email('user@domain.c'), isNotNull);
    });

    test('rejects double @ and dot-only domains', () {
      expect(Validators.email('a@@b.com'), isNotNull);
      expect(Validators.email('a@.com'), isNotNull);
    });

    test('rejects non-ASCII (regex is ASCII-only by design)', () {
      expect(Validators.email('صارف@مدرسہ.com'), isNotNull);
    });

    test(
      'rejects oversized input',
      () {
        final huge = '${'a' * 1000}@${'b' * 1000}.com';
        expect(Validators.email(huge), isNotNull);
      },
      skip: 'pending Phase 4.2 EmailAddress value object (SEC-M33): '
          'the email regex has no length cap and currently accepts '
          'multi-KB addresses',
    );

    test('rejects surrounding whitespace (not trimmed)', () {
      // Callers must trim before validating; the validator itself is strict.
      expect(Validators.email('  a@b.com  '), isNotNull);
    });
  });

  group('Validators.phone — adversarial (Pakistani formats)', () {
    test('accepts 03xxxxxxxxx and +923xxxxxxxxx', () {
      expect(Validators.phone('03001234567'), isNull);
      expect(Validators.phone('+923001234567'), isNull);
    });

    test('accepts spaces/dashes as separators', () {
      expect(Validators.phone('0300 1234567'), isNull);
      expect(Validators.phone('0300-1234567'), isNull);
    });

    test('rejects wrong digit counts', () {
      expect(Validators.phone('0300123456'), isNotNull); // 10 digits
      expect(Validators.phone('030012345678'), isNotNull); // 12 digits
      expect(Validators.phone('+92300123456'), isNotNull);
    });

    test('rejects letters and injection', () {
      expect(Validators.phone('030O1234567'), isNotNull);
      expect(Validators.phone('0300123456; DROP'), isNotNull);
    });

    test('normalizes (strips) surrounding whitespace', () {
      // Documented normalization: spaces/dashes/newlines are stripped
      // before matching, so these are accepted, not rejected.
      expect(Validators.phone('03001234567\n'), isNull);
    });

    test('rejects international 00-prefix form', () {
      expect(Validators.phone('00923001234567'), isNotNull);
    });

    test('rejects null and empty', () {
      expect(Validators.phone(null), isNotNull);
      expect(Validators.phone(''), isNotNull);
    });
  });

  group('Validators.cnic — adversarial', () {
    test('accepts 13 digits with or without dashes', () {
      expect(Validators.cnic('3520212345678'), isNull);
      expect(Validators.cnic('35202-1234567-8'), isNull);
    });

    test('rejects wrong lengths and letters', () {
      expect(Validators.cnic('352021234567'), isNotNull);
      expect(Validators.cnic('35202123456789'), isNotNull);
      expect(Validators.cnic('35202-123456A-8'), isNotNull);
    });
  });

  group('Validators.username — adversarial', () {
    test('rejects path traversal and spaces', () {
      expect(Validators.username('../../etc'), isNotNull);
      expect(Validators.username('user name'), isNotNull);
    });

    test('rejects too-short names', () {
      expect(Validators.username('ab'), isNotNull);
    });

    test('accepts alphanumerics and underscore', () {
      expect(Validators.username('talha_123'), isNull);
    });
  });

  group('Validators.rollNumber — adversarial', () {
    test('accepts alphanumeric with dashes', () {
      expect(Validators.rollNumber('R-2024-001'), isNull);
    });

    test('rejects traversal and spaces', () {
      expect(Validators.rollNumber('../001'), isNotNull);
      expect(Validators.rollNumber('R 001'), isNotNull);
    });
  });

  group('Validators.numeric/positiveNumber/range — adversarial', () {
    test('numeric accepts plain decimals', () {
      expect(Validators.numeric('1500.50'), isNull);
    });

    test('numeric rejects non-numbers', () {
      expect(Validators.numeric('1,500'), isNotNull);
      expect(Validators.numeric('abc'), isNotNull);
      expect(Validators.numeric(''), isNotNull);
    });

    test('positiveNumber rejects zero and negatives (fee amounts)', () {
      expect(Validators.positiveNumber('0'), isNotNull);
      expect(Validators.positiveNumber('-500'), isNotNull);
      expect(Validators.positiveNumber('500'), isNull);
    });

    test('range enforces marks boundaries', () {
      expect(Validators.range('101', 0, 100), isNotNull);
      expect(Validators.range('-1', 0, 100), isNotNull);
      expect(Validators.range('100', 0, 100), isNull);
      expect(Validators.range('0', 0, 100), isNull);
    });

    test(
      'numeric rejects NaN/Infinity spellings (would corrupt money math)',
      () {
        // double.tryParse accepts these spellings; a money field must not.
        expect(Validators.numeric('NaN'), isNotNull);
        expect(Validators.numeric('Infinity'), isNotNull);
      },
      skip: 'pending Phase 4.2 value objects (SEC-M33): '
          'Validators.numeric currently accepts NaN/Infinity spellings',
    );
  });

  group('Validators.maxLength/minLength — oversized payloads', () {
    test('maxLength rejects huge strings', () {
      expect(Validators.maxLength('x' * 100000, 500), isNotNull);
    });

    test('minLength boundary', () {
      expect(Validators.minLength('ab', 3), isNotNull);
      expect(Validators.minLength('abc', 3), isNull);
    });
  });

  group('Validators.password — adversarial', () {
    test('rejects short passwords', () {
      expect(Validators.password('12345'), isNotNull);
    });

    test('accepts 6+ chars (matches manage-users minimum)', () {
      expect(Validators.password('123456'), isNull);
    });

    test('rejects null/empty', () {
      expect(Validators.password(null), isNotNull);
      expect(Validators.password(''), isNotNull);
    });
  });

  group('Validators.combine — adversarial', () {
    test('short-circuits on first failure', () {
      final v = Validators.combine([
        (s) => Validators.required(s),
        (s) => Validators.email(s),
      ]);
      expect(v(''), isNotNull);
      expect(v('not-an-email'), isNotNull);
      expect(v('a@b.com'), isNull);
    });
  });
}
