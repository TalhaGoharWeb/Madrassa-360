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
import '../data/models/result.dart';
import 'attendance_provider.dart';
import 'fee_provider.dart';
import 'result_provider.dart';
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
        .fold(0.0, (sum, f) => sum + f.amountPaid);
  } catch (_) {
    return 0.0;
  }
});

/// Exams that have no results entered yet (drives the "نتائج باقی" alert).
/// Empty when logged out or on failure — the alert simply doesn't render.
final examsWithoutResultsProvider =
    FutureProvider<List<Exam>>((ref) async {
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
      final records = await ref
          .watch(classAttendanceProvider(
            AttendanceParams(classId: classId, date: now),
          ).future);
      if (records.isNotEmpty) done++;
    }
    return (done: done, total: classIds.length);
  } catch (_) {
    return (done: 0, total: 0);
  }
});
