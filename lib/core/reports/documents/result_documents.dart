/// نتائج دستاویزات — PDF بلڈرز
/// Result document PDF builders (offline, tenant-branded).
///
/// Every number comes from real [StudentResult] rows — never invented.

import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../data/models/result.dart';
import '../pdf_kit.dart';
import '../report_branding.dart';
import '../urdu_pdf.dart';
import 'document_helpers.dart';

class ResultDocuments {
  ResultDocuments._();

  /// One student's result card (used by "شیئر کریں").
  static Future<Uint8List> resultCard({
    required ReportBranding branding,
    required UrduPdf urdu,
    required StudentResult result,
  }) async {
    return PdfKit.build(
      branding: branding,
      urdu: urdu,
      titleUr: 'نتیجہ کارڈ',
      titleEn: 'Result Card',
      subtitleUr: result.examName,
      body: (s) async {
        final rows = <List<String>>[
          for (final sub in result.subjects)
            [
              sub.subject,
              '${sub.marksObtained.toInt()}',
              '${sub.totalMarks.toInt()}',
              sub.grade,
            ],
        ];
        final w = <pw.Widget>[
          await s.sectionTitle('کوائفِ طالب علم', 'Student particulars'),
          await fieldRow(s, 'نام', result.studentName),
          await fieldRow(s, 'جماعت', result.className),
          await fieldRow(s, 'امتحان', result.examName),
          pw.SizedBox(height: 8),
        ];
        if (rows.isEmpty) {
          // Honest empty state — never a headers-only table, and no
          // zeros-as-data totals when nothing was recorded.
          w.add(await s.emptyNotice(
            'اس نتیجے میں مضامین کی تفصیل درج نہیں ہے۔',
            'No subject details were recorded for this result.',
          ));
        } else {
          w.add(await s.sectionTitle('مضامین کی تفصیل', 'Subject results'));
          w.add(await s.dataTable(
            headers: const ['مضمون', 'حاصل نمبر', 'کل نمبر', 'گریڈ'],
            rows: rows,
          ));
          w.add(pw.SizedBox(height: 10));
          w.add(
              await fieldRow(s, 'کل حاصل', '${result.totalObtained.toInt()}'));
          w.add(await fieldRow(s, 'کل نمبر', '${result.totalMarks.toInt()}'));
          w.add(await fieldRow(
              s, 'فیصد', '${result.percentage.toStringAsFixed(1)}٪'));
          w.add(await fieldRow(s, 'گریڈ', result.grade));
        }
        w.add(pw.SizedBox(height: 28));
        w.add(await s.signatureRow(['دستخط استاد', 'دستخط پرنسپل مع مہر']));
        return w;
      },
    );
  }

  /// Multi-student results summary table (used by "نتیجہ پرنٹ کریں").
  static Future<Uint8List> resultsSummary({
    required ReportBranding branding,
    required UrduPdf urdu,
    required String titleUr,
    required String titleEn,
    required List<StudentResult> results,
  }) async {
    return PdfKit.build(
      branding: branding,
      urdu: urdu,
      titleUr: titleUr,
      titleEn: titleEn,
      body: (s) async {
        if (results.isEmpty) {
          return <pw.Widget>[
            await s.emptyNotice(
                'اس زمرے میں کوئی نتیجہ نہیں', 'No results in this category'),
          ];
        }
        final rows = <List<String>>[
          for (final r in results)
            [
              r.studentName,
              r.className,
              r.examName,
              '${r.totalObtained.toInt()}/${r.totalMarks.toInt()}',
              '${r.percentage.toStringAsFixed(1)}٪',
              r.grade,
            ],
        ];
        return <pw.Widget>[
          await s.dataTable(
            headers: const [
              'نام',
              'جماعت',
              'امتحان',
              'حاصل/کل',
              'فیصد',
              'گریڈ'
            ],
            rows: rows,
          ),
        ];
      },
    );
  }
}
