/// طلبہ دستاویزات — PDF بلڈرز
/// Student documents — PDF builders (offline, tenant-branded).
///
/// Builders receive a [ReportContext] and return finished PDF bytes.
/// Missing students → a clean one-page notice, never fabricated data.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/report_models.dart';
import '../pdf_kit.dart';
import '../report_context.dart';
import '../urdu_pdf.dart';
import 'document_helpers.dart';

class StudentDocuments {
  StudentDocuments._();

  // ── داخلہ فارم / Admission form ────────────────────────────────

  static Future<Uint8List> admissionForm(ReportContext ctx) async {
    final student = await ctx.data
        .studentById(ctx.params.tenantId, ctx.params.studentId ?? '');
    if (student == null) {
      return _missingStudent(ctx, 'داخلہ فارم', 'Admission Form');
    }
    return PdfKit.build(
      branding: ctx.branding,
      urdu: ctx.urdu,
      titleUr: 'داخلہ فارم',
      titleEn: 'Admission Form',
      body: (s) async {
        final w = <pw.Widget>[
          await s.sectionTitle('کوائفِ طالب علم', 'Student particulars'),
          // Photo placeholder (right) + key fields (left).
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(children: [
                  await fieldRow(s, 'نام', student.name),
                  await fieldRow(
                      s, 'ولدیت', student.fatherName),
                  await fieldRow(s, 'تاریخ پیدائش',
                      student.dateOfBirth),
                  await fieldRow(s, 'تاریخ داخلہ',
                      student.dateOfAdmit),
                ]),
              ),
              pw.SizedBox(width: 16),
              pw.Container(
                width: 96,
                height: 112,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfBuildScope.line)),
                child: pw.Center(
                  child: await s.u('تصویر',
                      size: 10,
                      color: const Color(0xFF9E9E9E)),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          await fieldRow(s, 'رول نمبر', student.rollNo),
          await fieldRow(s, 'جماعت', student.className),
          await fieldRow(s, 'درجہ', student.darjaName),
          await fieldRow(s, 'فون', student.phone),
          await fieldRow(s, 'پتہ', student.address),
          pw.SizedBox(height: 14),
          await s.sectionTitle('اقرار نامہ', 'Declaration'),
          await s.u(
            'میں اقرار کرتا/کرتی ہوں کہ درج بالا کوائف درست ہیں اور ادارے کے '
            'قواعد و ضوابط کی پابندی کروں گا/گی۔',
            size: 11,
            maxWidth: 480,
          ),
          pw.SizedBox(height: 24),
          await s.signatureRow(
              ['دستخط طالب علم', 'دستخط والد/سرپرست', 'دستخط پرنسپل مع مہر']),
        ];
        return w;
      },
    );
  }

  // ── شناختی کارڈ / ID card ─────────────────────────────────────

  static Future<Uint8List> idCard(ReportContext ctx) async {
    final student = await ctx.data
        .studentById(ctx.params.tenantId, ctx.params.studentId ?? '');
    if (student == null) {
      return _missingStudent(
          ctx, 'طالب علم کا شناختی کارڈ', 'Student ID Card');
    }
    // CR80: 85.60 × 53.98 mm → points.
    final card = const PdfPageFormat(242.65, 153.0);
    return PdfKit.build(
      branding: ctx.branding,
      urdu: ctx.urdu,
      titleUr: 'شناختی کارڈ',
      titleEn: 'ID Card',
      pageFormat: card,
      margin: const pw.EdgeInsets.all(8),
      bare: true,
      body: (s) async {
        final white = const Color(0xFFFFFFFF);
        return [
          // Brand band.
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 8, vertical: 5),
            decoration: pw.BoxDecoration(color: s.primary),
            child: pw.Row(
              children: [
                if (ctx.branding.hasLogo)
                  pw.Image(
                    pw.MemoryImage(ctx.branding.logoBytes!),
                    width: 26,
                    height: 26,
                    fit: pw.BoxFit.contain,
                  ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: await s.u(
                    ctx.branding.nameUrdu ?? ctx.branding.name,
                    size: 12,
                    bold: true,
                    color: white,
                    align: ui.TextAlign.left,
                  ),
                ),
                await s.u('شناختی کارڈ',
                    size: 10, bold: true, color: white),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 56,
                height: 66,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfBuildScope.line)),
                child: pw.Center(
                  child: await s.u('تصویر',
                      size: 9, color: const Color(0xFF9E9E9E)),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    await _idLine(s, 'نام', student.name),
                    await _idLine(s, 'ولدیت',
                        student.fatherName ?? '—'),
                    await _idLine(s, 'رول نمبر',
                        student.rollNo ?? '—'),
                    await _idLine(s, 'جماعت',
                        student.className ?? '—'),
                  ],
                ),
              ),
            ],
          ),
          pw.Spacer(),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            decoration: pw.BoxDecoration(color: s.primary),
            child: pw.Center(
              child: s.e(
                ctx.branding.contactLine
                        ?.replaceAll('فون: ', 'Ph: ') ??
                    '',
                size: 7,
                color: PdfColors.white,
              ),
            ),
          ),
        ];
      },
    );
  }

  // ── کردار سرٹیفکیٹ / Character certificate ────────────────────

  static Future<Uint8List> characterCertificate(ReportContext ctx) async {
    final student = await ctx.data
        .studentById(ctx.params.tenantId, ctx.params.studentId ?? '');
    if (student == null) {
      return _missingStudent(
          ctx, 'کردار سرٹیفکیٹ', 'Character Certificate');
    }
    return PdfKit.build(
      branding: ctx.branding,
      urdu: ctx.urdu,
      titleUr: 'کردار سرٹیفکیٹ',
      titleEn: 'Character Certificate',
      body: (s) async {
        final body = 'تصدیق کی جاتی ہے کہ ${student.name}'
            '${student.fatherName == null ? '' : ' ولد ${student.fatherName}'}'
            '${student.className == null ? '' : ' جماعت ${student.className} میں'}'
            ' اس ادارے کے طالب علم رہے ہیں۔';
        return [
          pw.SizedBox(height: 12),
          pw.Center(
            child: await s.u('کردار سرٹیفکیٹ',
                size: 20, bold: true, color: ctx.branding.primary),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
              child: s.e('CHARACTER CERTIFICATE',
                  size: 10, color: PdfBuildScope.muted)),
          pw.SizedBox(height: 20),
          await s.u(body, size: 13, maxWidth: 470),
          pw.SizedBox(height: 14),
          await fieldRow(s, 'برتاؤ و اخلاق', null), // principal fills by hand
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                  child: await fieldRow(
                      s, 'داخلہ نمبر', student.rollNo)),
              pw.SizedBox(width: 16),
              pw.Expanded(
                  child: await fieldRow(
                      s, 'تاریخ اجراء', todayIso())),
            ],
          ),
          pw.SizedBox(height: 30),
          await s.signatureRow(['دستخط پرنسپل', 'مہر']),
          pw.SizedBox(height: 12),
          await s.u(
            'نوٹ: برتاؤ سے متعلق حتمی توثیق پرنسپل کے دستخط و مہر سے ہوگی۔',
            size: 9,
            color: const Color(0xFF9E9E9E),
            maxWidth: 470,
          ),
        ];
      },
    );
  }

  // ── منتقلی سرٹیفکیٹ / Transfer certificate ─────────────────────

  static Future<Uint8List> transferCertificate(ReportContext ctx) async {
    final student = await ctx.data
        .studentById(ctx.params.tenantId, ctx.params.studentId ?? '');
    if (student == null) {
      return _missingStudent(
          ctx, 'منتقلی سرٹیفکیٹ', 'Transfer Certificate');
    }
    final dues = await ctx.data
        .invoices(ctx.params.tenantId, studentId: student.id)
        .then((invoices) async {
      final payments = await ctx.data
          .payments(ctx.params.tenantId, studentId: student.id);
      var billed = 0.0, paid = 0.0;
      for (final i in invoices) {
        billed += i.total;
        paid += i.amountPaid + i.discountTotal;
      }
      for (final p in payments) {
        paid += p.amount;
      }
      return billed - paid;
    });
    return PdfKit.build(
      branding: ctx.branding,
      urdu: ctx.urdu,
      titleUr: 'منتقلی سرٹیفکیٹ',
      titleEn: 'Transfer / School Leaving Certificate',
      body: (s) async {
        return [
          pw.SizedBox(height: 8),
          pw.Center(
            child: await s.u('منتقلی سرٹیفکیٹ',
                size: 20, bold: true, color: ctx.branding.primary),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
              child: s.e('SCHOOL LEAVING CERTIFICATE',
                  size: 10, color: PdfBuildScope.muted)),
          pw.SizedBox(height: 16),
          await fieldRow(s, 'نام', student.name),
          await fieldRow(s, 'ولدیت', student.fatherName),
          await fieldRow(s, 'داخلہ نمبر / رول نمبر', student.rollNo),
          await fieldRow(s, 'آخری جماعت', student.className),
          await fieldRow(s, 'تاریخ داخلہ', student.dateOfAdmit),
          await fieldRow(s, 'تاریخ رخصت', todayIso()),
          await fieldRow(s, 'رخصت کی وجہ', null), // handwritten
          await fieldRow(
            s,
            'واجبات (بمطابق مقامی ریکارڈ)',
            dues > 0.5 ? 'روپے ${fmtMoney(dues)} واجب الادا' : 'کوئی واجب الادا نہیں',
          ),
          pw.SizedBox(height: 28),
          await s.signatureRow(
              ['دستخط کلاس انچارج', 'دستخط پرنسپل مع مہر']),
        ];
      },
    );
  }

  // ── helpers ────────────────────────────────────────────────────

  static Future<Uint8List> _missingStudent(
      ReportContext ctx, String titleUr, String titleEn) {
    return PdfKit.build(
      branding: ctx.branding,
      urdu: ctx.urdu,
      titleUr: titleUr,
      titleEn: titleEn,
      body: (s) async => [
        await s.emptyNotice(
          'مطلوبہ طالب علم کا ریکارڈ مقامی ڈیٹا بیس میں نہیں ملا۔',
          'The requested student was not found in the local database.',
        ),
      ],
    );
  }

  static Future<pw.Widget> _idLine(
      PdfBuildScope s, String labelUr, String value) async {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 62,
            child: await s.u('$labelUr :',
                size: 9, bold: true, color: const Color(0xFF616161)),
          ),
          pw.Expanded(child: await s.auto(value, size: 9)),
        ],
      ),
    );
  }
}
