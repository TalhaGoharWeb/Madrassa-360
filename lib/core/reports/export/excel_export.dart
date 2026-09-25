/// XLSX ایکسپورٹ
/// XLSX export for tabular reports (pure-Dart `excel` package, fully
/// offline). One real sheet per [ReportTable]; the header row is styled
/// bold with the tenant's primary colour.

import 'package:excel/excel.dart';
import 'package:flutter/material.dart' show Color;

import '../report_branding.dart';
import 'tabular_data.dart';

class ExcelExport {
  ExcelExport._();

  /// Builds the .xlsx bytes for [tables].
  static List<int> build(
    List<ReportTable> tables, {
    ReportBranding? branding,
  }) {
    final excel = Excel.createExcel();
    final primary = branding?.primary ?? const Color(0xFF0E7C5B);
    final headerBg = ExcelColor.fromHexString(
      '#${primary.value.toRadixString(16).padLeft(8, '0').substring(2)}',
    );

    for (var i = 0; i < tables.length; i++) {
      final t = tables[i];
      final sheetName = _uniqueName(t.sheetName, i);
      if (i == 0) {
        excel.rename('Sheet1', sheetName);
      }
      final sheet = excel[sheetName];

      // Header row.
      sheet.appendRow(
          [for (final h in t.headers) TextCellValue(h)]);
      for (var c = 0; c < t.headers.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(
                columnIndex: c, rowIndex: 0))
            .cellStyle = CellStyle(
          bold: true,
          fontColorHex: ExcelColor.white,
          backgroundColorHex: headerBg,
          horizontalAlign: HorizontalAlign.Right,
          verticalAlign: VerticalAlign.Center,
        );
      }
      // Data rows.
      for (final row in t.rows) {
        sheet.appendRow(
            [for (final v in row) TextCellValue(v)]);
      }
      // Readable column widths for Urdu text.
      for (var c = 0; c < t.headers.length; c++) {
        var width = 12.0;
        for (final row in t.rows) {
          if (c < row.length) {
            final w = row[c].length * 1.4 + 4;
            if (w > width) width = w;
          }
        }
        sheet.setColumnWidth(c, width.clamp(12.0, 48.0));
      }
    }

    return excel.encode() ?? [];
  }

  static String _uniqueName(String base, int index) {
    final clean = base.trim().isEmpty ? 'Sheet' : base.trim();
    return index == 0 ? clean : '$clean${index + 1}';
  }
}
