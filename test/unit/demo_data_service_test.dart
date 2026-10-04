/// ڈیمو ڈیٹا سروس کے یونٹ ٹیسٹ — pure logic, no mocks.
///
/// Tests [DemoDataStatus.fromJson] parsing and [DemoDataException].
/// Server behavior (install/remove/status) is verified against the live
/// database, not mocked.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/services/demo_data_service.dart';

void main() {
  group('DemoDataStatus.fromJson', () {
    test('parses installed status with counts', () {
      final status = DemoDataStatus.fromJson({
        'installed': true,
        'counts': {'students': 12, 'darjas': 3, 'invoices': 0},
      });
      expect(status.installed, isTrue);
      expect(status.counts['students'], 12);
      expect(status.counts['darjas'], 3);
      expect(status.totalRows, 15);
    });

    test('parses empty status as not installed', () {
      final status = DemoDataStatus.fromJson({
        'installed': false,
        'counts': {'students': 0},
      });
      expect(status.installed, isFalse);
      expect(status.totalRows, 0);
    });

    test('tolerates missing counts', () {
      final status = DemoDataStatus.fromJson({'installed': false});
      expect(status.installed, isFalse);
      expect(status.counts, isEmpty);
      expect(status.totalRows, 0);
    });

    test('tolerates null values in counts', () {
      final status = DemoDataStatus.fromJson({
        'installed': true,
        'counts': {'students': null, 'darjas': 3},
      });
      expect(status.counts['students'], 0);
      expect(status.counts['darjas'], 3);
      expect(status.totalRows, 3);
    });
  });

  group('DemoDataException', () {
    test('carries the Urdu message', () {
      const e = DemoDataException('آزمائشی خرابی');
      expect(e.message, 'آزمائشی خرابی');
      expect(e.toString(), contains('آزمائشی خرابی'));
    });
  });
}
