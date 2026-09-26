/// ڈیش بورڈ ڈیٹا — رول ڈیش بورڈز
/// Dashboard data providers (Phase 7a).
///
/// Every number on the role dashboards comes from a REAL query here or in
/// an existing provider (`dashboardStatsProvider`, `feeSummaryProvider`,
/// `teacher*` providers). Nothing is hard-coded: when a query fails or the
/// tenant is unresolved, providers return honest empty values (0 / []),
/// and the dashboards render those as empty states — never invented data.
///
/// * [todayCollectionProvider] — fees collected TODAY (paid_date = today).
/// * [examsWithoutResultsProvider] — exams with zero result rows
///   (drives the "نتائج باقی" alert).
/// * [teacherTodayAttendanceStatusProvider] — how many of the teacher's
///   assigned classes have attendance marked today.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/tenant_context.dart';
import '../data/models/darja.dart';
import '../data/models/finance.dart';
import '../data/models/result.dart';
import '../data/models/student.dart';
import 'admin_dashboard_provider.dart';
import 'attendance_provider.dart';
import 'darja_provider.dart';
import 'fee_provider.dart';
import 'finance_provider.dart';
import 'library_provider.dart';
import 'result_provider.dart';
import 'student_provider.dart';
import 'teacher_portal_provider.dart';

String _todayStr() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

/// Total fee amount collected today (Rs), from real fee rows whose
/// `paid_date` is today. 0 when logged out or on query failure.
final todayCollectionProvider = FutureProvider<double>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return 0.0;
  try {
    final fees = await ref.watch(allFeesProvider.future);
    final today = _todayStr();
    return fees
        .where((f) => f.paidDate == today)
        .fold<double>(0.0, (sum, f) => sum + f.amountPaid);
  } catch (_) {
    return 0.0;
  }
});

/// Exams that have no results entered yet (drives the "نتائج باقی" alert).
/// Empty when logged out or on failure — the alert simply doesn't render.
final examsWithoutResultsProvider = FutureProvider<List<Exam>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  try {
    final exams = await ref.watch(allExamsProvider.future);
    final pending = <Exam>[];
    for (final exam in exams) {
      final results = await ref.watch(examResultsProvider(exam.id).future);
      if (results.isEmpty) pending.add(exam);
    }
    return pending;
  } catch (_) {
    return const [];
  }
});

/// How many of the teacher's assigned classes have attendance marked today.
/// `(done: 0, total: 0)` when logged out, unassigned, or on failure.
final teacherTodayAttendanceStatusProvider =
    FutureProvider<({int done, int total})>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return (done: 0, total: 0);
  try {
    final classIds = ref.watch(teacherAssignedClassIdsProvider);
    if (classIds.isEmpty) return (done: 0, total: 0);
    final now = DateTime.now();
    var done = 0;
    for (final classId in classIds) {
      final records = await ref.watch(classAttendanceProvider(
        AttendanceParams(classId: classId, date: now),
      ).future);
      if (records.isNotEmpty) done++;
    }
    return (done: done, total: classIds.length);
  } catch (_) {
    return (done: 0, total: 0);
  }
});

// ─────────────────────────────────────────────────────────────
// Phase 7b — clerk / accountant / academic / library / exam data
//
// Same contract as above: every provider bails to an honest empty value
// when there is no tenant or a query fails. StateNotifier-backed sources
// (finance / library / darja) are loaded lazily INSIDE the provider and
// only after the tenant check, so widget tests (no tenant, no Supabase)
// never construct a notifier.
// ─────────────────────────────────────────────────────────────

/// New admissions: students whose `date_of_admit` is within the last 7
/// days. Real rows from [allStudentsProvider]; empty when none.
final newAdmissionsProvider = FutureProvider<List<Student>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  try {
    final students = await ref.watch(allStudentsProvider.future);
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return students.where((s) {
      final admitted = DateTime.tryParse(s.dateOfAdmit ?? '');
      return admitted != null && !admitted.isBefore(cutoff);
    }).toList();
  } catch (_) {
    return const [];
  }
});

bool _isSameDay(DateTime d) {
  final now = DateTime.now();
  return d.year == now.year && d.month == now.month && d.day == now.day;
}

/// Accountant's finance overview (Phase 7b, §§10–11).
///
/// * [todayExpenses] — posted ledger expenses with entry_date = today.
/// * [todayIncome] — posted ledger income with entry_date = today.
/// * [cashBalance] — active accounts whose name contains نقد/cash:
///   opening balance ± posted ledger amounts on that account.
///
/// Plain Urdu concepts only — no accounting jargon leaves this provider.
class FinanceOverview {
  final double todayExpenses;
  final double todayIncome;
  final double cashBalance;

  const FinanceOverview({
    required this.todayExpenses,
    required this.todayIncome,
    required this.cashBalance,
  });

  const FinanceOverview.zero()
      : todayExpenses = 0,
        todayIncome = 0,
        cashBalance = 0;
}

final financeOverviewProvider = FutureProvider<FinanceOverview>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const FinanceOverview.zero();
  try {
    await ref.watch(financeProvider.notifier).load();
    final state = ref.read(financeProvider);

    var expenses = 0.0;
    var income = 0.0;
    for (final t in state.ledger) {
      if (t.status != DocStatus.posted) continue;
      if (!_isSameDay(t.entryDate)) continue;
      if (t.isIncome) {
        income += t.amount;
      } else {
        expenses += t.amount;
      }
    }

    var cash = 0.0;
    for (final a in state.accounts) {
      if (!a.isActive || a.id == null) continue;
      final name = '${a.nameUrdu ?? ''} ${a.name}'.toLowerCase();
      if (!name.contains('نقد') && !name.contains('cash')) continue;
      var balance = a.openingBalance;
      for (final t in state.ledger) {
        if (t.status != DocStatus.posted || t.accountId != a.id) continue;
        balance += t.isIncome ? t.amount : -t.amount;
      }
      cash += balance;
    }

    return FinanceOverview(
      todayExpenses: expenses,
      todayIncome: income,
      cashBalance: cash,
    );
  } catch (_) {
    return const FinanceOverview.zero();
  }
});

/// Library overview (Phase 7b, §14): total books, currently issued,
/// and overdue returns (due date passed, not returned). Real rows from
/// the library notifier; honest zeros when the shelf is empty.
class LibraryOverview {
  final int totalBooks;
  final int issued;
  final int overdue;

  const LibraryOverview({
    required this.totalBooks,
    required this.issued,
    required this.overdue,
  });

  const LibraryOverview.zero()
      : totalBooks = 0,
        issued = 0,
        overdue = 0;
}

final libraryOverviewProvider = FutureProvider<LibraryOverview>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const LibraryOverview.zero();
  try {
    await ref.watch(libraryProvider.notifier).load();
    final state = ref.read(libraryProvider);
    final now = DateTime.now();
    final active = state.issues.where((i) => !i.isReturned).toList();
    final overdue = active.where((i) => i.dueAt.isBefore(now)).length;
    return LibraryOverview(
      totalBooks: state.books.length,
      issued: active.length,
      overdue: overdue,
    );
  } catch (_) {
    return const LibraryOverview.zero();
  }
});

/// Darja list for pickers — empty when logged out (never touches
/// Supabase without a tenant).
final safeDarjaListProvider = FutureProvider<List<Darja>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  try {
    await ref.watch(darjaProvider.notifier).loadAll();
    return ref.read(darjaProvider).darjas;
  } catch (_) {
    return const [];
  }
});

/// Academic overview (Phase 7b, §12): darjas, teachers, students, today's
/// attendance %, and exams still missing results. All real queries.
class AcademicOverview {
  final int darjas;
  final int teachers;
  final int students;

  /// null when today's attendance hasn't started.
  final double? attendancePct;
  final int pendingResults;

  const AcademicOverview({
    required this.darjas,
    required this.teachers,
    required this.students,
    required this.attendancePct,
    required this.pendingResults,
  });

  const AcademicOverview.zero()
      : darjas = 0,
        teachers = 0,
        students = 0,
        attendancePct = null,
        pendingResults = 0;
}

final academicOverviewProvider = FutureProvider<AcademicOverview>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const AcademicOverview.zero();
  try {
    final darjas = await ref.watch(safeDarjaListProvider.future);
    final stats = await ref.watch(dashboardStatsProvider.future);
    final pending = await ref.watch(examsWithoutResultsProvider.future);
    final marked = stats.todayPresent + stats.todayAbsent + stats.todayLeave;
    final pct = marked == 0 ? null : stats.todayPresent * 100 / marked;
    return AcademicOverview(
      darjas: darjas.length,
      teachers: stats.totalTeachers,
      students: stats.totalStudents,
      attendancePct: pct,
      pendingResults: pending.length,
    );
  } catch (_) {
    return const AcademicOverview.zero();
  }
});

/// Exam overview (Phase 7b, §15).
///
/// * [ongoing] — exams dated within the last 7 days or in the future.
/// * [pendingMarks] — exams with zero result rows (real query).
/// * [ready] — exams with at least one result row.
/// There is no publish flag in the schema, so "published" is honestly
/// NOT reported here (the dashboard shows an empty state for it).
class ExamSummary {
  final int ongoing;
  final int pendingMarks;
  final int ready;
  final int total;

  const ExamSummary({
    required this.ongoing,
    required this.pendingMarks,
    required this.ready,
    required this.total,
  });

  const ExamSummary.zero()
      : ongoing = 0,
        pendingMarks = 0,
        ready = 0,
        total = 0;
}

final examSummaryProvider = FutureProvider<ExamSummary>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const ExamSummary.zero();
  try {
    final exams = await ref.watch(allExamsProvider.future);
    final pending = await ref.watch(examsWithoutResultsProvider.future);
    final pendingIds = pending.map((e) => e.id).toSet();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekAgo = today.subtract(const Duration(days: 7));
    var ongoing = 0;
    for (final e in exams) {
      final d = DateTime.tryParse(e.examDate);
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      if (!day.isBefore(weekAgo)) ongoing++;
    }
    return ExamSummary(
      ongoing: ongoing,
      pendingMarks: pending.length,
      ready: exams.where((e) => !pendingIds.contains(e.id)).length,
      total: exams.length,
    );
  } catch (_) {
    return const ExamSummary.zero();
  }
});
