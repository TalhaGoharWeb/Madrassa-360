/// انتظامی رپورٹس — PDF بلڈرز
/// Admin reports — PDF builders (offline, tenant-branded).
///
/// Tabular content comes from [TabularData] (shared with CSV/XLSX);
/// these builders add titles, filter subtitles and summary bands.

import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:pdf/widgets.dart' as pw;

import '../data/report_models.dart';
import '../export/tabular_data.dart';
import '../pdf_kit.dart';
import '../report_context.dart';

class AdminReports {
  AdminReports._();

  // ── helpers ────────────────────────────────────────────────────

  static Future<String?> _filterSubtitle(ReportContext ctx) async {
    final p = ctx.params;
    final parts = <String>[];
    if (p.classId != null) {
      final classes = await ctx.data.classes(p.tenantId);
      final c = classes.where((e) => e.id == p.classId);
      if (c.isNotEmpty) parts.add('جماعت: ${c.first.name}');
    } else if (p.darjaId != null) {
      final darjas = await ctx.data.darjas(p.tenantId);
      final d = darjas.where((e) => e.id == p.darjaId);
      if (d.isNotEmpty) parts.add('درجہ: ${d.first.name}');
    }
    if (p.fromIso != null || p.toIso != null) {
      parts.add('مدت: ${p.fromIso ?? '…'} تا ${p.toIso ?? '…'}');
    }
    if (p.examId != null) {
      final exams = await ctx.data.exams(p.tenantId);
      final e = exams.where((x) => x.id == p.examId);
      if (e.isNotEmpty) parts.add('امتحان: ${e.first.name}');
    }
    return parts.isEmpty ? null : parts.join('   |   ');
  }

  static Future<Uint8List> _tabular(
    ReportContext ctx,
    String titleUr,
    String titleEn,
    String emptyUr,
    String emptyEn, {
    Future<List<pw.Widget>> Function(PdfBuildScope s, List<ReportTable> tables)?
        extra,
  }) async {
    final def = ctx.definition;
    final tables = await TabularData.build(def.id, ctx);
    final subtitle = await _filterSubtitle(ctx);
    return PdfKit.build(
      branding: ctx.branding,
      urdu: ctx.urdu,
      titleUr: titleUr,
      titleEn: titleEn,
      subtitleUr: subtitle,
      body: (s) async {
        final nonEmpty = tables?.where((t) => t.rows.isNotEmpty).toList() ?? [];
        if (nonEmpty.isEmpty) {
          return [await s.emptyNotice(emptyUr, emptyEn)];
        }
        final w = <pw.Widget>[];
        for (var i = 0; i < nonEmpty.length; i++) {
          final t = nonEmpty[i];
          if (nonEmpty.length > 1) {
            w.add(await s.sectionTitle(t.titleUr));
          }
          w.add(await s.dataTable(headers: t.headers, rows: t.rows));
          if (i < nonEmpty.length - 1) {
            w.add(pw.SizedBox(height: 12));
          }
        }
        if (extra != null) {
          w.add(pw.SizedBox(height: 12));
          w.addAll(await extra(s, nonEmpty));
        }
        return w;
      },
    );
  }

  // ── طلبہ رجسٹر ────────────────────────────────────────────────

  static Future<Uint8List> studentRegister(ReportContext ctx) => _tabular(
        ctx,
        'طلبہ رجسٹر',
        'Student Register',
        'مقامی ڈیٹا بیس میں کوئی طالب علم نہیں ملا۔',
        'No students found in the local database.',
        extra: (s, tables) async {
          final n = tables.first.rows.length;
          return [
            await s.u('کل طلبہ: $n',
                size: 11, bold: true, color: ctx.branding.primary),
          ];
        },
      );

  // ── اساتذہ رجسٹر ──────────────────────────────────────────────

  static Future<Uint8List> teacherRegister(ReportContext ctx) => _tabular(
        ctx,
        'اساتذہ رجسٹر',
        'Teacher / Staff Register',
        'مقامی ڈیٹا بیس میں عملے کا کوئی ریکارڈ نہیں ملا۔',
        'No staff records found in the local database.',
        extra: (s, tables) async {
          final n = tables.first.rows.length;
          return [
            await s.u('کل عملہ: $n',
                size: 11, bold: true, color: ctx.branding.primary),
          ];
        },
      );

  // ── حاضری خلاصہ ───────────────────────────────────────────────

  static Future<Uint8List> attendanceSummary(ReportContext ctx) => _tabular(
        ctx,
        'حاضری خلاصہ',
        'Attendance Summary',
        'منتخب مدت/جماعت میں حاضری کا کوئی ریکارڈ نہیں ملا۔',
        'No attendance records found for the selected period/class.',
        extra: (s, tables) async {
          final rows = tables.first.rows;
          var sum = 0.0, n = 0;
          for (final r in rows) {
            // فیصد column is last; '—' when unmarked.
            final pct = double.tryParse(r.last.replaceAll('%', ''));
            if (pct != null) {
              sum += pct;
              n++;
            }
          }
          return [
            await s.statRow([
              StatBox('کل طلبہ', '$n'),
              StatBox('اوسط حاضری',
                  n == 0 ? '—' : '${(sum / n).toStringAsFixed(1)}%'),
            ]),
          ];
        },
      );

  // ── فیس وصولی ─────────────────────────────────────────────────

  static Future<Uint8List> feeCollection(ReportContext ctx) => _tabular(
        ctx,
        'فیس وصولی رپورٹ',
        'Fee Collection Report',
        'منتخب مدت میں کوئی ادائیگی ریکارڈ نہیں ملی۔',
        'No payments found in the local database for the selected period.',
        extra: (s, tables) async {
          final rows = tables.first.rows;
          var total = 0.0;
          final byMethod = <String, double>{};
          for (final r in rows) {
            final amt = double.tryParse(r[3]) ?? 0;
            total += amt;
            final m = r[4];
            byMethod[m] = (byMethod[m] ?? 0) + amt;
          }
          return [
            await s.statRow([
              StatBox('کل وصولی', fmtMoney(total), '${rows.length} ادائیگیاں'),
              StatBox(
                  'طریقے',
                  '${byMethod.length}',
                  byMethod.entries
                      .map((e) => '${e.key}: ${fmtMoney(e.value)}')
                      .join(', ')),
            ]),
          ];
        },
      );

  // ── واجب الادا فیس ────────────────────────────────────────────

  static Future<Uint8List> outstandingFees(ReportContext ctx) => _tabular(
        ctx,
        'واجب الادا فیس',
        'Outstanding Fees',
        'کوئی واجب الادا فیس نہیں — تمام حسابات مقامی ریکارڈ کے مطابق صاف ہیں۔',
        'No outstanding fees — all accounts are clear per the local records.',
        extra: (s, tables) async {
          var total = 0.0;
          for (final r in tables.first.rows) {
            total += double.tryParse(r[5]) ?? 0;
          }
          return [
            await s.statRow([
              StatBox('طلبہ', '${tables.first.rows.length}'),
              StatBox('کل واجب الادا', fmtMoney(total)),
            ]),
          ];
        },
      );

  // ── آمدن و اخراجات ────────────────────────────────────────────

  static Future<Uint8List> incomeExpense(ReportContext ctx) async {
    final p = ctx.params;
    final income = await ctx.data.moneyEntries(p.tenantId,
        income: true, fromIso: p.fromIso, toIso: p.toIso);
    final expense = await ctx.data.moneyEntries(p.tenantId,
        income: false, fromIso: p.fromIso, toIso: p.toIso);
    final subtitle = await _filterSubtitle(ctx);
    return PdfKit.build(
      branding: ctx.branding,
      urdu: ctx.urdu,
      titleUr: 'آمدن و اخراجات رپورٹ',
      titleEn: 'Income & Expense Report',
      subtitleUr: subtitle,
      body: (s) async {
        List<MoneyEntry> priced(List<MoneyEntry> l) =>
            l.where((e) => e.amount != null).toList();
        final inPriced = priced(income);
        final exPriced = priced(expense);
        if (inPriced.isEmpty && exPriced.isEmpty) {
          final anyRows = income.isNotEmpty || expense.isNotEmpty;
          return [
            await s.emptyNotice(
              anyRows
                  ? 'ریکارڈ موجود ہے مگر کسی اندراج میں قابلِ استعمال رقم نہیں — خلاصہ نہیں بنایا جا سکتا۔'
                  : 'منتخب مدت میں آمدن/اخراجات کا کوئی ریکارڈ نہیں ملا۔',
              anyRows
                  ? 'Entries exist but none carry a usable amount; no summary was computed.'
                  : 'No income/expense records found for the selected period.',
            ),
          ];
        }
        final inTotal = inPriced.fold<double>(0, (a, e) => a + e.amount!);
        final exTotal = exPriced.fold<double>(0, (a, e) => a + e.amount!);
        final w = <pw.Widget>[
          await s.statRow([
            StatBox('کل آمدن', fmtMoney(inTotal)),
            StatBox('کل اخراجات', fmtMoney(exTotal)),
            StatBox('خالص بیلنس', fmtMoney(inTotal - exTotal)),
          ]),
          pw.SizedBox(height: 12),
        ];
        Future<pw.Widget> section(
            String titleUr, String titleEn, List<MoneyEntry> list) async {
          final w2 = <pw.Widget>[
            await s.sectionTitle(titleUr, titleEn),
          ];
          if (list.isEmpty) {
            w2.add(await s.u('کوئی ریکارڈ نہیں۔',
                size: 10, color: const Color(0xFF9E9E9E)));
          } else {
            w2.add(await s.dataTable(
              headers: const ['تاریخ', 'تفصیل', 'زمرہ', 'رقم'],
              rows: [
                for (final e in list)
                  [
                    e.entryDate ?? '—',
                    e.description ?? '—',
                    e.category ?? '—',
                    e.amount == null ? '—' : fmtMoney(e.amount!),
                  ],
              ],
            ));
          }
          return pw.Column(children: w2);
        }

        w.add(await section('آمدن', 'Income', inPriced));
        w.add(pw.SizedBox(height: 12));
        w.add(await section('اخراجات', 'Expenses', exPriced));
        final unpriced = (income.length - inPriced.length) +
            (expense.length - exPriced.length);
        if (unpriced > 0) {
          w.add(pw.SizedBox(height: 8));
          w.add(await s.u(
            'نوٹ: $unpriced اندراجات میں رقم درج نہیں تھی — خلاصے سے خارج ہیں۔',
            size: 9,
            color: const Color(0xFF9E9E9E),
            maxWidth: 480,
          ));
        }
        return w;
      },
    );
  }

  // ── امتحانی نتائج ─────────────────────────────────────────────

  static Future<Uint8List> examResults(ReportContext ctx) => _tabular(
        ctx,
        'امتحانی نتائج',
        'Exam Results',
        'منتخب امتحان کا کوئی نتیجہ مقامی ریکارڈ میں نہیں ملا۔',
        'No results found for the selected exam in the local database.',
        extra: (s, tables) async {
          final rows = tables.first.rows;
          var sum = 0.0, n = 0, pass = 0;
          for (final r in rows) {
            final pct = double.tryParse(r[5].replaceAll('%', ''));
            if (pct != null) {
              sum += pct;
              n++;
              if (pct >= 50) pass++;
            }
          }
          return [
            await s.statRow([
              StatBox('طلبہ', '$n'),
              StatBox('اوسط فیصد',
                  n == 0 ? '—' : '${(sum / n).toStringAsFixed(1)}%'),
              StatBox('کامیابی',
                  n == 0 ? '—' : '${(pass * 100 / n).toStringAsFixed(1)}%'),
            ]),
          ];
        },
      );

  // ── تعلیمی کارکردگی ───────────────────────────────────────────

  static Future<Uint8List> academicPerformance(ReportContext ctx) => _tabular(
        ctx,
        'تعلیمی کارکردگی',
        'Academic Performance',
        'منتخب جماعت/درجہ کے لیے امتحانی نتائج مقامی ریکارڈ میں نہیں ملے۔',
        'No exam results found for the selected class/darja in the local database.',
      );
}
