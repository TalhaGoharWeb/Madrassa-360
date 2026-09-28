/// فیس رسید — PDF بلڈر
/// Fee receipt PDF builder (offline, tenant-branded).
///
/// Every row comes from the real [Fee] record — never invented names,
/// dates or amounts.

import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../data/models/fee.dart';
import '../pdf_kit.dart';
import '../report_branding.dart';
import '../urdu_pdf.dart';
import 'document_helpers.dart';

class FeeReceiptPdf {
  FeeReceiptPdf._();

  static String _rs(double v) => '${v.toInt()} روپے';

  /// Builds a one-page branded fee receipt for [record].
  static Future<Uint8List> build({
    required ReportBranding branding,
    required UrduPdf urdu,
    required Fee record,
    required String receiptNo,
    required String monthLabel,
  }) async {
    return PdfKit.build(
      branding: branding,
      urdu: urdu,
      titleUr: 'فیس کی رسید',
      titleEn: 'Fee Receipt',
      subtitleUr: receiptNo,
      body: (s) async {
        return <pw.Widget>[
          await s.sectionTitle('رسید کی تفصیل', 'Receipt details'),
          await fieldRow(s, 'رسید نمبر', receiptNo),
          await fieldRow(s, 'طالب علم کا نام', record.studentName),
          await fieldRow(s, 'جماعت', record.studentClass),
          await fieldRow(s, 'مہینہ', monthLabel),
          await fieldRow(s, 'واجب الادا', _rs(record.amountDue)),
          await fieldRow(s, 'وصول شدہ', _rs(record.amountPaid)),
          await fieldRow(s, 'باقی', _rs(record.remaining)),
          await fieldRow(s, 'حیثیت', record.status.urduLabel),
          await fieldRow(
            s,
            'ادائیگی کی تاریخ',
            (record.paidDate == null || record.paidDate!.isEmpty)
                ? '—'
                : record.paidDate!,
          ),
          pw.SizedBox(height: 28),
          await s.signatureRow(['دستخط وصول کنندہ', 'مہر']),
        ];
      },
    );
  }
}
