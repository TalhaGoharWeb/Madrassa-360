// v3 — Hijri date conversion tests.
//
// Pure unit tests: no widgets, no providers, no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/utils/hijri_date.dart';

void main() {
  group('HijriDate.fromGregorian', () {
    test('converts 2026-09-26 to Rabi al-Thani 1448 (±1 day tabular)', () {
      final h = HijriDate.fromGregorian(DateTime(2026, 9, 26));
      expect(h.year, 1448);
      expect(h.month, 4); // ربیع الثانی
      expect(h.day, inInclusiveRange(11, 14));
    });

    test('converts 2026-01-01 to Rajab 1447 (±1 day tabular)', () {
      final h = HijriDate.fromGregorian(DateTime(2026, 1, 1));
      expect(h.year, 1447);
      expect(h.month, 7); // رجب
      expect(h.day, inInclusiveRange(10, 13));
    });

    test('converts 2025-03-01 to Ramadan 1446 (±1 day tabular)', () {
      final h = HijriDate.fromGregorian(DateTime(2025, 3, 1));
      expect(h.year, 1446);
      expect(h.month, 9); // رمضان
      expect(h.day, inInclusiveRange(1, 3));
    });

    test('month is always within 1..12 and day within 1..30', () {
      var d = DateTime(2024, 1, 1);
      for (var i = 0; i < 800; i++) {
        final h = HijriDate.fromGregorian(d);
        expect(h.month, inInclusiveRange(1, 12));
        expect(h.day, inInclusiveRange(1, 30));
        d = d.add(const Duration(days: 1));
      }
    });
  });

  group('HijriDate.formatUrdu', () {
    test('formats as "<day> <month> <year>ھ"', () {
      const h = HijriDate(year: 1448, month: 4, day: 13);
      expect(h.formatUrdu(), '13 ربیع الثانی 1448ھ');
    });

    test('has 12 Urdu month names starting with محرم', () {
      expect(HijriDate.monthNamesUrdu.length, 12);
      expect(HijriDate.monthNamesUrdu.first, 'محرم');
      expect(HijriDate.monthNamesUrdu[8], 'رمضان');
      expect(HijriDate.monthNamesUrdu.last, 'ذوالحجہ');
    });
  });
}
