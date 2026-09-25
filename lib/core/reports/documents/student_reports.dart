/// طلبہ رپورٹس — PDF بلڈرز
/// Student reports — PDF builders (offline, tenant-branded).

import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:pdf/widgets.dart' as pw;

import '../data/report_models.dart';
import '../export/tabular_data.dart';
import '../pdf_kit.dart';
import '../report_context.dart';
import 'document_helpers.dart';

class StudentReports {
  StudentReports._();

  // ── رزلٹ کارڈ / Result card ───────────────────────────────────

  static Future<Uint8List> resultCard(ReportContext ctx) async {
    final student = await ctx.data
        .studentById(ctx.params.tenantId, ctx.params.studentId ?? '');
    if (student == null) {
      return _missing(ctx, 'رزلٹ کارڈ', 'Result Card');
    }
    // Resolve the exam: explicit choice, else the student's latest exam
    // with results (by exam date, then id).
    var examId = ctx.params.examId;
    String? examName;
    String? examDate;
    if (examId == null) {
      final exams =
          await ctx.data.exams(ctx.params.tenantId, classId: student.classId);
      ReportExam? pick;
      for (final ex in exams) {
        final r = await ctx.data.results(ctx.params.tenantId,
            examId: ex.id, studentId: student.id);
        if (r.isNotEmpty) {
          if (pick == null ||
              (ex.examDate ?? '').compareTo(pick.examDate ?? '') > 0) {
            pick = ex;
          }
        }
      }
      if (pick == null) {
        return _empty(ctx, 'رزلٹ کارڈ', 'Result Card',
            'اس طالب علم کا کوئی امتحانی نتیجہ مقامی ریکارڈ میں نہیں ملا۔',
            'No exam results found for this student in the local database.');
      }
      examId = pick.id;
      examName = pick.name;
      examDate = pick.examDate;
    } else {
      final exams = await ctx.data.exams(ctx.params.tenantId);
      final match = exams.where((e) => e.id == examId);
      if (match.isNotEmpty) {
        examName = match.first.name;
        examDate = match.first.examDate;
      }
    }

    final results = await ctx.data.results(
      ctx.params.tenantId,
      examId: examId,
      studentId: student.id,
    );
    if (results.isEmpty) {
      return _empty(ctx, 'رزلٹ کارڈ', 'Result Card',
          'منتخب امتحان کا نتیجہ مقامی ریکارڈ میں نہیں ملا۔',
          'No results found for the selected exam in the local database.');
    }

    // Class position across the whole exam.
    var position = 0;
    final outcomes =
        await ctx.data.examOutcomes(ctx.params.tenantId, examId!);
    for (final o in outcomes) {
      if (o.studentId == student.id) position = o.position;
    }

    // Totals only over rows with usable marks; missing marks are
    // "not entered", never zeroes.
    final usable = results.where((r) => r.usable).toList();
    if (usable.isEmpty) {
      return _empty(ctx, 'رزلٹ کارڈ', 'Result Card',
          'اس امتحان کے نمبرات مقامی ریکارڈ میں درج نہیں ہیں۔',
          'Marks for this exam have not been entered in the local database yet.');
    }
    final obtained =
        usable.fold<double>(0, (a, r) => a + r.obtained!);
    final total =
        usable.fold<double>(0, (a, r) => a + r.totalMarks!);
    final pct = total <= 0 ? null : obtained * 100.0 / total;
    final partial = usable.length < results.length;

    return PdfKit.build(
      branding: ctx.branding,
      urdu: ctx.urdu,
      titleUr: 'رزلٹ کارڈ',
      titleEn: 'Result Card',
      subtitleUr: examName,
      subtitleEn: examDate,
      body: (s) async {
        return [
          await s.sectionTitle('کوائف', 'Particulars'),
          pw.Row(children: [
            pw.Expanded(
                child: await fieldRow(s, 'نام', student.name)),
            pw.SizedBox(width: 16),
            pw.Expanded(
                child:
                    await fieldRow(s, 'رول نمبر', student.rollNo)),
          ]),
          pw.Row(children: [
            pw.Expanded(
                child: await fieldRow(s, 'جماعت', student.className)),
            pw.SizedBox(width: 16),
            pw.Expanded(
                child: await fieldRow(s, 'امتحان', examName)),
          ]),
          pw.SizedBox(height: 8),
          await s.sectionTitle('نتائج', 'Results'),
          await s.dataTable(
            headers: const ['مضمون', 'کل نمبر', 'حاصل کردہ', 'فیصد', 'گریڈ'],
            rows: [
              for (final r in results)
                [
                  r.subject,
                  r.totalMarks == null ? '—' : fmtMoney(r.totalMarks!),
                  r.obtained == null ? '—' : fmtMoney(r.obtained!),
                  r.percent == null
                      ? '—'
                      : '${r.percent!.toStringAsFixed(1)}%',
                  gradeFor(r.percent),
                ],
              [
                'کل',
                fmtMoney(total),
                fmtMoney(obtained),
                pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
                gradeFor(pct),
              ],
            ],
          ),
          if (partial) ...[
            pw.SizedBox(height: 6),
            await s.u(
              'نوٹ: کچھ مضامین کے نمبرات درج نہیں ہیں — مجموعہ صرف درج شدہ نمبروں پر مبنی ہے۔',
              size: 9,
              color: const Color(0xFF9E9E9E),
            ),
          ],
          pw.SizedBox(height: 12),
          await s.statRow([
            StatBox('فیصد', pct == null ? '—' : '${pct.toStringAsFixed(1)}%'),
            StatBox('گریڈ', gradeFor(pct)),
            StatBox('پوزیشن',
                position == 0 ? '—' : '$position'),
          ]),
          pw.SizedBox(height: 24),
          await s.signatureRow(['دستخط کلاس انچارج', 'دستخط پرنسپل']),
        ];
      },
    );
  }

  // ── حاضری رپورٹ / Attendance report ────────────────────────────

  static Future<Uint8List> attendanceReport(ReportContext ctx) async {
    final student = await ctx.data
        .studentById(ctx.params.tenantId, ctx.params.studentId ?? '');
    if (student == null) {
      return _missing(ctx, 'حاضری رپورٹ', 'Attendance Report');
    }
    final p = ctx.params;
    final marks = await ctx.data.attendance(
      p.tenantId,
      studentId: student.id,
      fromIso: p.fromIso,
      toIso: p.toIso,
    );
    const urduStatus = {
      'present': 'حاضر',
      'absent': 'غیر حاضر',
      'leave': 'چھٹی',
      'late': 'تاخیر',
    };
    final rangeUr = _rangeUr(p.fromIso, p.toIso);
    return PdfKit.build(
      branding: ctx.branding,
      urdu: ctx.urdu,
      titleUr: 'حاضری رپورٹ',
      titleEn: 'Attendance Report',
      subtitleUr: rangeUr == null ? student.name : '${student.name}  |  $rangeUr',
      body: (s) async {
        if (marks.isEmpty) {
          return [
            await s.emptyNotice(
              'منتخب مدت میں اس طالب علم کی کوئی حاضری ریکارڈ نہیں ملی۔',
              'No attendance records found for this student in the selected period.',
            ),
          ];
        }
        var present = 0, absent = 0, leave = 0, late = 0, unknown = 0;
        for (final m in marks) {
          switch (m.status) {
            case 'present':
              present++;
            case 'absent':
              absent++;
            case 'leave':
              leave++;
            case 'late':
              late++;
            default:
              // Unrecognised statuses are never counted as present.
              unknown++;
          }
        }
        final marked = present + absent + leave + late + unknown;
        final pct =
            marked == 0 ? null : (present + late) * 100.0 / marked;
        final boxes = <StatBox>[
          StatBox('حاضر', '$present'),
          StatBox('غیر حاضر', '$absent'),
          StatBox('چھٹی', '$leave'),
          StatBox('تاخیر', '$late'),
          if (unknown > 0) StatBox('نامعلوم', '$unknown'),
          StatBox('حاضری فیصد',
              pct == null ? '—' : '${pct.toStringAsFixed(1)}%'),
        ];
        return [
          await s.statRow(boxes),
          pw.SizedBox(height: 12),
          await s.sectionTitle('یومیہ تفصیل', 'Day-wise detail'),
          await s.dataTable(
            headers: const ['تاریخ', 'حاضری'],
            rows: [
              for (final m in marks)
                [m.date, urduStatus[m.status] ?? m.status],
            ],
          ),
          pw.SizedBox(height: 8),
          await s.u(
            'فیصد = (حاضر + تاخیر) ÷ کل نشان زدہ دن × 100',
            size: 9,
            color: const Color(0xFF9E9E9E),
          ),
        ];
      },
    );
  }

  // ── فیس اسٹیٹمنٹ / Fee statement ───────────────────────────────

  static Future<Uint8List> feeStatement(ReportContext ctx) async {
    final student = await ctx.data
        .studentById(ctx.params.tenantId, ctx.params.studentId ?? '');
    if (student == null) {
      return _missing(ctx, 'فیس اسٹیٹمنٹ', 'Fee Statement');
    }
    final p = ctx.params;
    final tables = await TabularData.build('fee_statement', ctx);
    final invTable = tables![0];
    final payTable = tables[1];
    if (invTable.isEmpty && payTable.isEmpty) {
      return PdfKit.build(
        branding: ctx.branding,
        urdu: ctx.urdu,
        titleUr: 'فیس اسٹیٹمنٹ',
        titleEn: 'Fee Statement',
        subtitleUr: student.name,
        body: (s) async => [
          await s.emptyNotice(
            'اس طالب علم کا کوئی بل یا ادائیگی مقامی ریکارڈ میں نہیں ملی۔',
            'No invoices or payments found for this student in the local database.',
          ),
        ],
      );
    }
    final invoices =
        await ctx.data.invoices(p.tenantId, studentId: student.id);
    final payments =
        await ctx.data.payments(p.tenantId, studentId: student.id);
    var billed = 0.0, paid = 0.0, discount = 0.0;
    for (final i in invoices) {
      billed += i.total;
      paid += i.amountPaid;
      discount += i.discountTotal;
    }
    for (final pay in payments) {
      paid += pay.amount;
    }
    final balance = billed - paid - discount;
    return PdfKit.build(
      branding: ctx.branding,
      urdu: ctx.urdu,
      titleUr: 'فیس اسٹیٹمنٹ',
      titleEn: 'Fee Statement',
      subtitleUr: student.name,
      subtitleEn: student.rollNo,
      body: (s) async {
        final w = <pw.Widget>[
          await s.statRow([
            StatBox('کل واجب', fmtMoney(billed)),
            StatBox('ادا شدہ', fmtMoney(paid)),
            StatBox('رعایت', fmtMoney(discount)),
            StatBox('بیلنس', fmtMoney(balance < 0 ? 0 : balance)),
          ]),
          pw.SizedBox(height: 12),
        ];
        if (invTable.rows.isNotEmpty) {
          w.add(await s.sectionTitle('بل', 'Invoices'));
          w.add(await s.dataTable(
              headers: invTable.headers, rows: invTable.rows));
          w.add(pw.SizedBox(height: 12));
        }
        if (payTable.rows.isNotEmpty) {
          w.add(await s.sectionTitle('ادائیگیاں', 'Payments'));
          w.add(await s.dataTable(
              headers: payTable.headers, rows: payTable.rows));
        }
        return w;
      },
    );
  }

  // ── helpers ────────────────────────────────────────────────────

  static String? _rangeUr(String? from, String? to) {
    if (from == null && to == null) return null;
    return 'مدت: ${from ?? '…'} تا ${to ?? '…'}';
  }

  static Future<Uint8List> _missing(
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

  static Future<Uint8List> _empty(ReportContext ctx, String titleUr,
      String titleEn, String msgUr, String msgEn) {
    return PdfKit.build(
      branding: ctx.branding,
      urdu: ctx.urdu,
      titleUr: titleUr,
      titleEn: titleEn,
      body: (s) async => [await s.emptyNotice(msgUr, msgEn)],
    );
  }
}
