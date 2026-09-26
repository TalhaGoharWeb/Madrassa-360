/// ٹیبلر ڈیٹا — واحد ذریعہ
/// Tabular data — the SINGLE source of headers+rows for tabular reports.
///
/// The PDF builders in `documents/` and the CSV/XLSX exporters both
/// consume these tables, so a number can never disagree between formats.
/// Every table is computed from the local Drift database only.
///
/// Empty data → null (callers render the standard empty notice / write
/// headers only). Zeros are never synthesised.

import '../data/report_models.dart';
import '../report_context.dart';

/// One exportable sheet.
class ReportTable {
  final String sheetName; // short English sheet/tab name
  final String titleUr;
  final List<String> headers;
  final List<List<String>> rows;

  const ReportTable({
    required this.sheetName,
    required this.titleUr,
    required this.headers,
    required this.rows,
  });

  bool get isEmpty => rows.isEmpty;
}

const _dash = '—';

String _pct(double? v) => v == null ? _dash : '${v.toStringAsFixed(1)}%';

/// Builds the tabular payload for [reportId], or null when the report
/// is not tabular / has no data. Used by PDF tables, CSV and XLSX.
class TabularData {
  TabularData._();

  static Future<List<ReportTable>?> build(
      String reportId, ReportContext ctx) async {
    switch (reportId) {
      case 'student_register':
        return [await _studentRegister(ctx)];
      case 'teacher_register':
        return [await _teacherRegister(ctx)];
      case 'attendance_summary':
        return [await _attendanceSummary(ctx)];
      case 'fee_collection':
        return [await _feeCollection(ctx)];
      case 'outstanding_fees':
        return [await _outstandingFees(ctx)];
      case 'income_expense':
        return [await _incomeExpense(ctx)];
      case 'exam_results':
        return [await _examResults(ctx)];
      case 'academic_performance':
        return [await _academicPerformance(ctx)];
      case 'attendance_report':
        return [await _studentAttendance(ctx)];
      case 'fee_statement':
        return await _feeStatement(ctx);
      default:
        return null;
    }
  }

  // ── admin ──────────────────────────────────────────────────────

  static Future<ReportTable> _studentRegister(ReportContext ctx) async {
    final p = ctx.params;
    final list = await ctx.data
        .students(p.tenantId, classId: p.classId, darjaId: p.darjaId);
    return ReportTable(
      sheetName: 'Students',
      titleUr: 'طلبہ رجسٹر',
      headers: const ['رول نمبر', 'نام', 'ولدیت', 'جماعت', 'درجہ', 'فون'],
      rows: [
        for (final s in list)
          [
            s.rollNo ?? _dash,
            s.name,
            s.fatherName ?? _dash,
            s.className ?? _dash,
            s.darjaName ?? _dash,
            s.phone ?? _dash,
          ],
      ],
    );
  }

  static Future<ReportTable> _teacherRegister(ReportContext ctx) async {
    final list = await ctx.data.staff(ctx.params.tenantId);
    return ReportTable(
      sheetName: 'Staff',
      titleUr: 'اساتذہ رجسٹر',
      headers: const ['نام', 'عہدہ', 'فون'],
      rows: [
        for (final s in list)
          [s.name, s.designation ?? _dash, s.phone ?? _dash],
      ],
    );
  }

  static Future<ReportTable> _attendanceSummary(ReportContext ctx) async {
    final p = ctx.params;
    final list = await ctx.data.attendanceSummary(
      p.tenantId,
      classId: p.classId,
      fromIso: p.fromIso,
      toIso: p.toIso,
    );
    return ReportTable(
      sheetName: 'Attendance',
      titleUr: 'حاضری خلاصہ',
      headers: const [
        'رول نمبر',
        'نام',
        'حاضر',
        'غیر حاضر',
        'چھٹی',
        'تاخیر',
        'نامعلوم',
        'فیصد'
      ],
      rows: [
        for (final s in list)
          [
            s.rollNo ?? _dash,
            s.studentName,
            '${s.present}',
            '${s.absent}',
            '${s.leave}',
            '${s.late}',
            '${s.unknown}',
            _pct(s.percentage),
          ],
      ],
    );
  }

  static Future<ReportTable> _feeCollection(ReportContext ctx) async {
    final p = ctx.params;
    final payments = await ctx.data.payments(
      p.tenantId,
      fromIso: p.fromIso,
      toIso: p.toIso,
    );
    final roster = await ctx.data.students(p.tenantId);
    final names = {for (final s in roster) s.id: s.name};
    final invoices = await ctx.data.invoices(p.tenantId);
    final invNo = {for (final i in invoices) i.id: i.invoiceNumber};
    return ReportTable(
      sheetName: 'Collection',
      titleUr: 'فیس وصولی',
      headers: const ['تاریخ', 'طالب علم', 'بل نمبر', 'رقم', 'طریقہ'],
      rows: [
        for (final pay in payments)
          [
            pay.paymentDate ?? _dash,
            pay.studentId == null ? _dash : (names[pay.studentId] ?? _dash),
            pay.invoiceId == null ? _dash : (invNo[pay.invoiceId] ?? _dash),
            fmtMoney(pay.amount),
            pay.method ?? _dash,
          ],
      ],
    );
  }

  static Future<ReportTable> _outstandingFees(ReportContext ctx) async {
    final dues = await _dues(ctx);
    return ReportTable(
      sheetName: 'Outstanding',
      titleUr: 'واجب الادا فیس',
      headers: const [
        'رول نمبر',
        'نام',
        'جماعت',
        'کل واجب',
        'ادا شدہ',
        'بیلنس'
      ],
      rows: [
        for (final d in dues)
          [
            d.student.rollNo ?? _dash,
            d.student.name,
            d.student.className ?? _dash,
            fmtMoney(d.billed),
            fmtMoney(d.paid),
            fmtMoney(d.balance),
          ],
      ],
    );
  }

  static Future<ReportTable> _incomeExpense(ReportContext ctx) async {
    final p = ctx.params;
    final income = await ctx.data.moneyEntries(p.tenantId,
        income: true, fromIso: p.fromIso, toIso: p.toIso);
    final expense = await ctx.data.moneyEntries(p.tenantId,
        income: false, fromIso: p.fromIso, toIso: p.toIso);
    final rows = <List<String>>[
      for (final e in income)
        [
          'آمدن',
          e.entryDate ?? _dash,
          e.description ?? _dash,
          e.category ?? _dash,
          e.amount == null ? _dash : fmtMoney(e.amount!),
        ],
      for (final e in expense)
        [
          'خرچ',
          e.entryDate ?? _dash,
          e.description ?? _dash,
          e.category ?? _dash,
          e.amount == null ? _dash : fmtMoney(e.amount!),
        ],
    ];
    return ReportTable(
      sheetName: 'IncomeExpense',
      titleUr: 'آمدن و اخراجات',
      headers: const ['قسم', 'تاریخ', 'تفصیل', 'زمرہ', 'رقم'],
      rows: rows,
    );
  }

  static Future<ReportTable> _examResults(ReportContext ctx) async {
    final examId = ctx.params.examId;
    if (examId == null) {
      return const ReportTable(
        sheetName: 'Results',
        titleUr: 'امتحانی نتائج',
        headers: [
          'پوزیشن',
          'رول نمبر',
          'نام',
          'حاصل کردہ',
          'کل',
          'فیصد',
          'گریڈ'
        ],
        rows: [],
      );
    }
    final outcomes = await ctx.data.examOutcomes(ctx.params.tenantId, examId);
    return ReportTable(
      sheetName: 'Results',
      titleUr: 'امتحانی نتائج',
      headers: const [
        'پوزیشن',
        'رول نمبر',
        'نام',
        'حاصل کردہ',
        'کل',
        'فیصد',
        'گریڈ'
      ],
      rows: [
        for (final o in outcomes)
          [
            o.position == 0 ? _dash : '${o.position}',
            o.rollNo ?? _dash,
            o.studentName,
            o.hasMarks ? fmtMoney(o.obtained) : _dash,
            o.hasMarks ? fmtMoney(o.total) : _dash,
            _pct(o.percentage),
            gradeFor(o.percentage),
          ],
      ],
    );
  }

  static Future<ReportTable> _academicPerformance(ReportContext ctx) async {
    final p = ctx.params;
    final exams = await ctx.data.exams(p.tenantId, classId: p.classId);
    final roster = await ctx.data
        .students(p.tenantId, classId: p.classId, darjaId: p.darjaId);
    final agg = <String, _Perf>{};
    for (final ex in exams) {
      final outcomes = await ctx.data.examOutcomes(p.tenantId, ex.id);
      for (final o in outcomes) {
        if (o.percentage == null) continue;
        final a = agg.putIfAbsent(
            o.studentId, () => _Perf(name: o.studentName, rollNo: o.rollNo));
        a.sum += o.percentage!;
        a.count++;
      }
    }
    final rows = <List<String>>[];
    for (final s in roster) {
      final a = agg[s.id];
      if (a == null || a.count == 0) continue;
      final avg = a.sum / a.count;
      rows.add([
        s.rollNo ?? _dash,
        s.name,
        '${a.count}',
        '${avg.toStringAsFixed(1)}%',
        gradeFor(avg),
      ]);
    }
    rows.sort((a, b) => b[3].compareTo(a[3]));
    return ReportTable(
      sheetName: 'Performance',
      titleUr: 'تعلیمی کارکردگی',
      headers: const ['رول نمبر', 'نام', 'امتحانات', 'اوسط فیصد', 'گریڈ'],
      rows: rows,
    );
  }

  // ── student ────────────────────────────────────────────────────

  static Future<ReportTable> _studentAttendance(ReportContext ctx) async {
    const urduStatus = {
      'present': 'حاضر',
      'absent': 'غیر حاضر',
      'leave': 'چھٹی',
      'late': 'تاخیر',
    };
    final p = ctx.params;
    final marks = await ctx.data.attendance(
      p.tenantId,
      studentId: p.studentId,
      fromIso: p.fromIso,
      toIso: p.toIso,
    );
    return ReportTable(
      sheetName: 'Attendance',
      titleUr: 'حاضری رپورٹ',
      headers: const ['تاریخ', 'حاضری'],
      rows: [
        for (final m in marks) [m.date, urduStatus[m.status] ?? m.status],
      ],
    );
  }

  static Future<List<ReportTable>> _feeStatement(ReportContext ctx) async {
    final p = ctx.params;
    final invoices =
        await ctx.data.invoices(p.tenantId, studentId: p.studentId);
    final payments =
        await ctx.data.payments(p.tenantId, studentId: p.studentId);
    final invNo = {for (final i in invoices) i.id: i.invoiceNumber};
    return [
      ReportTable(
        sheetName: 'Invoices',
        titleUr: 'بل',
        headers: const [
          'بل نمبر',
          'ماہ',
          'جاری تاریخ',
          'آخری تاریخ',
          'کل',
          'ادا شدہ',
          'رعایت',
          'بیلنس'
        ],
        rows: [
          for (final i in invoices)
            [
              i.invoiceNumber ?? _dash,
              i.billingMonth ?? _dash,
              i.issueDate ?? _dash,
              i.dueDate ?? _dash,
              fmtMoney(i.total),
              fmtMoney(i.amountPaid),
              fmtMoney(i.discountTotal),
              fmtMoney(i.balanceDue),
            ],
        ],
      ),
      ReportTable(
        sheetName: 'Payments',
        titleUr: 'ادائیگیاں',
        headers: const ['تاریخ', 'رقم', 'طریقہ', 'بل نمبر', 'نوٹ'],
        rows: [
          for (final pay in payments)
            [
              pay.paymentDate ?? _dash,
              fmtMoney(pay.amount),
              pay.method ?? _dash,
              pay.invoiceId == null ? _dash : (invNo[pay.invoiceId] ?? _dash),
              pay.notes ?? _dash,
            ],
        ],
      ),
    ];
  }

  // ── shared dues computation ────────────────────────────────────

  /// Per-student dues: invoices minus payments (invoice-linked first,
  /// then unallocated student payments). Only balances > 0.5 returned.
  static Future<List<_Due>> _dues(ReportContext ctx) async {
    final p = ctx.params;
    final invoices = await ctx.data.invoices(p.tenantId);
    final payments = await ctx.data.payments(p.tenantId);
    final roster = await ctx.data
        .students(p.tenantId, classId: p.classId, darjaId: p.darjaId);
    final inClass = {for (final s in roster) s.id};

    final billed = <String, double>{};
    final paid = <String, double>{};
    for (final i in invoices) {
      if (!inClass.contains(i.studentId)) continue;
      billed[i.studentId] = (billed[i.studentId] ?? 0) + i.total;
      paid[i.studentId] =
          (paid[i.studentId] ?? 0) + i.amountPaid + i.discountTotal;
    }
    for (final pay in payments) {
      final sid = pay.studentId;
      if (sid == null || !inClass.contains(sid)) continue;
      paid[sid] = (paid[sid] ?? 0) + pay.amount;
    }
    final names = {for (final s in roster) s.id: s};
    final out = <_Due>[];
    for (final sid in inClass) {
      final b = (billed[sid] ?? 0) - (paid[sid] ?? 0);
      if (b > 0.5) {
        out.add(_Due(
          student: names[sid]!,
          billed: billed[sid] ?? 0,
          paid: paid[sid] ?? 0,
          balance: b,
        ));
      }
    }
    out.sort((a, b) => b.balance.compareTo(a.balance));
    return out;
  }

  /// Exposed for the transfer certificate (single-student dues).
  static Future<double> studentBalance(ReportContext ctx) async {
    final dues = await _dues(ctx);
    final sid = ctx.params.studentId;
    if (sid == null) return 0;
    for (final d in dues) {
      if (d.student.id == sid) return d.balance;
    }
    return 0;
  }
}

class _Due {
  final ReportStudent student;
  final double billed;
  final double paid;
  final double balance;
  _Due({
    required this.student,
    required this.billed,
    required this.paid,
    required this.balance,
  });
}

class _Perf {
  final String name;
  final String? rollNo;
  double sum = 0;
  int count = 0;
  _Perf({required this.name, this.rollNo});
}
