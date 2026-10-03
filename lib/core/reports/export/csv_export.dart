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
    var out = v;
    // RED-TEAM RT-06: formula injection — a hostile value synced into the
    // DB (e.g. a student name like "=cmd|'/c calc'!A0") would be evaluated
    // by Excel/LibreOffice on open. Neutralize any cell that starts with
    // a formula trigger character; the leading apostrophe is Excel's
    // text-marker and is not displayed.
    if (out.startsWith(RegExp(r'[=+\-@]')) ||
        out.startsWith('\t') ||
        out.startsWith('\r')) {
      out = "'$out";
    }
    if (out.contains(',') ||
        out.contains('"') ||
        out.contains('\n') ||
        out.contains('\r')) {
      return '"${out.replaceAll('"', '""')}"';
    }
    return out;
  }
}
