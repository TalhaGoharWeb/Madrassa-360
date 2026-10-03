/// RED-TEAM RT-06: CSV formula-injection guard.
///
/// Implementation file under test:
///   lib/core/reports/export/csv_export.dart
///
/// A hostile value synced into the DB (e.g. a student name typed as
/// `=cmd|'/c calc'!A0`) must NOT survive into an exported CSV in a form
/// Excel/LibreOffice would evaluate. These tests pin the neutralization
/// rule: any cell starting with = + - @ (or tab/CR) gets Excel's
/// text-marker apostrophe prefix.
///
/// Pure-Dart unit tests — no Supabase, no widgets, no mocks.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/reports/export/csv_export.dart';
import 'package:madrasa_360/core/reports/export/tabular_data.dart';

ReportTable _table(List<List<String>> rows) => ReportTable(
      sheetName: 'test',
      titleUr: 'ٹیسٹ',
      headers: ['نام', 'رقم'],
      rows: rows,
    );

void main() {
  group('CsvExport formula-injection guard (RT-06)', () {
    test('neutralizes a classic =cmd payload', () {
      final out = CsvExport.build([
        _table([
          ["=cmd|'/c calc'!A0", '100']
        ])
      ]);
      expect(out, contains("'=cmd|'/c calc'!A0"));
      // The raw dangerous prefix must not appear un-neutralized.
      expect(out.contains(',"=cmd'), isFalse);
    });

    test('neutralizes +, -, @ prefixes', () {
      final out = CsvExport.build([
        _table([
          ['+1+1', '1'],
          ['-2+3', '2'],
          ['@SUM(A1:A10)', '3'],
        ])
      ]);
      expect(out, contains("'+1+1"));
      expect(out, contains("'-2+3"));
      expect(out, contains("'@SUM(A1:A10)"));
    });

    test('neutralizes tab / carriage-return prefixed cells', () {
      final out = CsvExport.build([
        _table([
          ['\t=1+1', '1'],
          ['\r=2+2', '2'],
        ])
      ]);
      expect(out, contains("'\t=1+1"));
      expect(out, contains("'\r=2+2"));
    });

    test('leaves normal Urdu text and numbers untouched', () {
      final out = CsvExport.build([
        _table([
          ['محمد احمد', '1500'],
          ['فیس - مارچ', '2000'],
        ])
      ]);
      // A '-' in the MIDDLE of a cell is not a formula trigger.
      expect(out, contains('محمد احمد'));
      expect(out, contains('فیس - مارچ'));
      expect(out.contains("'محمد"), isFalse);
    });

    test('quoting still applies after neutralization', () {
      final out = CsvExport.build([
        _table([
          ['=1+1, dangerous', '5'],
        ])
      ]);
      // Neutralized AND quoted: "'=1+1, dangerous"
      expect(out, contains("\"'=1+1, dangerous\""));
    });

    test('a cell already starting with the text-marker is left alone', () {
      final out = CsvExport.build([
        _table([
          ["'=1+1", '1'],
        ])
      ]);
      // First char is the apostrophe, not a formula trigger: no second
      // prefix is added.
      expect(out, contains("'=1+1"));
      expect(out.contains("''=1+1"), isFalse);
    });
  });
}
