/// Money-formatting unit tests.
///
/// Implementation file under test:
///   lib/core/utils/money_format.dart (formatRs, formatPK)
///
/// What is real here: the exact Pakistani digit-grouping rules every
/// financial surface renders (dashboards, fee rows, invoices, payments,
/// ledger, receipts, reports). A grouping regression would misrender
/// amounts users act on (Rs 1,25,000 vs Rs 125,000) — this pins the rule.
///
/// Pure Dart, no widgets.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/utils/money_format.dart';

void main() {
  group('formatRs — Pakistani grouping', () {
    test('small amounts are ungrouped', () {
      expect(formatRs(0), 'Rs 0');
      expect(formatRs(5), 'Rs 5');
      expect(formatRs(999), 'Rs 999');
    });

    test('thousands use Pakistani grouping (last 3, then 2s)', () {
      expect(formatRs(1000), 'Rs 1,000');
      expect(formatRs(25000), 'Rs 25,000');
      expect(formatRs(125000), 'Rs 1,25,000');
      expect(formatRs(380000), 'Rs 3,80,000');
      expect(formatRs(1000000), 'Rs 10,00,000');
      expect(formatRs(12345678), 'Rs 1,23,45,678');
    });

    test('rounds fractional rupees (app never records paisa)', () {
      expect(formatRs(125000.4), 'Rs 1,25,000');
      expect(formatRs(125000.5), 'Rs 1,25,001');
    });

    test('negative amounts keep the minus outside the marker', () {
      expect(formatRs(-5000), '-Rs 5,000');
      expect(formatRs(-125000), '-Rs 1,25,000');
    });
  });

  group('formatPK — Urdu suffix variant', () {
    test('small amounts are ungrouped with the Urdu marker', () {
      expect(formatPK(0), '0 روپے');
      expect(formatPK(999), '999 روپے');
    });

    test('thousands use Pakistani grouping', () {
      expect(formatPK(1000), '1,000 روپے');
      expect(formatPK(125000), '1,25,000 روپے');
      expect(formatPK(380000), '3,80,000 روپے');
      expect(formatPK(10000000), '1,00,00,000 روپے');
    });

    test('rounds and signs like formatRs', () {
      expect(formatPK(125000.6), '1,25,001 روپے');
      expect(formatPK(-25000), '-25,000 روپے');
    });

    test('agrees with formatRs on the digit grouping', () {
      for (final amount in [0, 7, 999, 1000, 25000, 125000, 1000000]) {
        final rsDigits =
            formatRs(amount.toDouble()).replaceAll(RegExp(r'[^0-9,]'), '');
        final pkDigits = formatPK(amount).replaceAll(RegExp(r'[^0-9,]'), '');
        expect(pkDigits, rsDigits, reason: 'amount $amount');
      }
    });
  });
}
