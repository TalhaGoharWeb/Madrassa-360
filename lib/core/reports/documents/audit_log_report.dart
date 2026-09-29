/// آڈٹ لاگ PDF
/// Client-side audit-log PDF built with the SHARED report pipeline —
/// [PdfKit] assembly + [UrduPdf] rasterisation (the same machinery the
/// offline report documents use). No parallel PDF implementation.
///
/// Branding is platform-level (there is no tenant here): a fixed
/// Madrassa 360 header in the app's primary colour.

import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;

import '../../../core/constants/app_colors.dart';
import '../pdf_kit.dart';
import '../report_branding.dart';
import '../urdu_pdf.dart';

class AuditLogReport {
  AuditLogReport._();

  /// Builds the audit-log PDF for the given export rows.
  ///
  /// [headers]/[rows] come from the audit-export helpers; only network
  /// columns actually observed in the data are included.
  static Future<Uint8List> build({
    required List<String> headers,
    required List<List<String>> rows,
    String? filterSummaryUr,
  }) {
    const branding = ReportBranding(
      name: 'Madrassa 360',
      nameUrdu: 'مدرسہ 360',
      primary: AppColors.primary,
      secondary: AppColors.primaryDark,
      accent: Color(0xFFF59E0B),
    );
    return PdfKit.build(
      branding: branding,
      urdu: UrduPdf(),
      titleUr: 'آڈٹ لاگ',
      titleEn: 'Audit Log Export',
      subtitleUr: filterSummaryUr,
      body: (s) async {
        if (rows.isEmpty) {
          return [
            await s.emptyNotice(
              'موجودہ فلٹرز سے کوئی ریکارڈ نہیں ملا۔',
              'No records matched the active filters.',
            ),
          ];
        }
        return [
          await s.dataTable(
            headers: headers,
            rows: rows,
            maxCellWidth: 140,
          ),
        ];
      },
    );
  }
}
