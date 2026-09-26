/// CSV ایکسپورٹ
/// CSV export for tabular reports.
///
/// UTF-8 with BOM so Excel opens Urdu headers correctly. One section
/// per sheet (multi-sheet reports like the fee statement are stacked
/// with a title row); XLSX keeps real sheets — see excel_export.dart.

import 'tabular_data.dart';

class CsvExport {
  CsvExport._();

  /// Builds the CSV text (with BOM) for [tables].
  static String build(List<ReportTable> tables) {
    final sb = StringBuffer()..write('\uFEFF');
    for (var i = 0; i < tables.length; i++) {
      final t = tables[i];
      if (tables.length > 1) {
        sb.writeln(_esc(t.titleUr));
      }
      sb.writeln(t.headers.map(_esc).join(','));
      for (final row in t.rows) {
        sb.writeln(row.map(_esc).join(','));
      }
      if (i < tables.length - 1) sb.writeln();
    }
    return sb.toString();
  }

  static String _esc(String v) {
    if (v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
