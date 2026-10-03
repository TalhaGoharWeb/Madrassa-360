/// Unit tests for [AppLogger.redact] PII scrubbing (2026-10-03).
///
/// `redact` is a pure function: secrets were already masked, and this locks
/// in the PII extension — emails and Pakistani phone numbers in free-form
/// error/log text must never persist in plaintext log files on disk.
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/observability/app_logger.dart';

void main() {
  group('AppLogger.redact PII', () {
    test('redacts an email inside a constraint-violation message', () {
      const input =
          'duplicate key value violates unique constraint "users_email_key" '
          '(email)=(clerk@example.com)';
      final out = AppLogger.redact(input) as String;
      expect(out, isNot(contains('clerk@example.com')));
      expect(out, contains(AppLogger.emailMask));
      // Non-PII structure survives.
      expect(out, contains('duplicate key value'));
    });

    test('redacts Pakistani mobile numbers in common formats', () {
      for (final phone in [
        '03001234567',
        '0300-1234567',
        '0300 1234567',
        '+923001234567',
      ]) {
        final out = AppLogger.redact('call $phone now') as String;
        expect(out, isNot(contains(phone)), reason: phone);
        expect(out, contains(AppLogger.phoneMask), reason: phone);
      }
    });

    test('does not mask plain digit runs (amounts, ids)', () {
      const input = 'invoice INV-00000103 total 15000 rows 42';
      expect(AppLogger.redact(input), input);
    });

    test('still redacts secrets alongside PII', () {
      const input =
          'login failed for admin@school.pk with password=hunter2 token=abc';
      final out = AppLogger.redact(input) as String;
      expect(out, isNot(contains('admin@school.pk')));
      expect(out, isNot(contains('hunter2')));
      expect(out, contains(AppLogger.emailMask));
      expect(out, contains(AppLogger.mask));
    });

    test('redacts PII inside nested context maps', () {
      final out = AppLogger.redact({
        'email': 'parent@example.com',
        'phone': '03009876543',
        'nested': ['a@b.co'],
      });
      final text = out.toString();
      expect(text, isNot(contains('parent@example.com')));
      expect(text, isNot(contains('03009876543')));
      expect(text, isNot(contains('a@b.co')));
    });

    test('passes through non-string values untouched', () {
      expect(AppLogger.redact(42), 42);
      expect(AppLogger.redact(null), isNull);
      expect(AppLogger.redact(true), isTrue);
    });
  });
}
