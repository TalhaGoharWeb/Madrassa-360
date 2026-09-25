/// Admin dashboard statistics — Phase 4 (SaaS transformation).
///
/// [dashboardStatsProvider] computes every number the admin dashboard shows
/// from live, tenant-scoped Supabase queries. It replaces the hard-coded
/// demo numbers the dashboard previously rendered (142 present, 8 classes,
/// fixed fee totals, a static "January 2026" label and a fake activity
/// feed with invented student names).
///
/// Behaviour contract:
/// * Bails out with [DashboardStats.zero] when logged out (`tenant_id`
///   null) — callers must never query unscoped.
/// * Every query carries an explicit `.eq('tenant_id', …)` filter.
///   (RLS is the server-side enforcement point; this is defence in depth
///   and keeps the numbers correct per tenant.)
/// * On any query failure (offline, etc.) it returns zeros rather than
///   throwing, so the dashboard degrades to honest "0" cards instead of
///   crashing. Numbers shown are always real or zero — never invented.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';
import '../core/utils/date_utils.dart' as app_date;

// ─────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────

/// One row of the "recent activities" feed.
class DashboardActivity {
  /// Icon key consumed by the dashboard: 'fee' | 'attendance' |
  /// 'admission' | 'result'. Unknown keys render a generic icon.
  final String iconKey;
  final String title;
  final String subtitle;
  final String timeLabel;
  final DateTime occurredAt;

  const DashboardActivity({
    required this.iconKey,
    required this.title,
    required this.subtitle,
    required this.timeLabel,
    required this.occurredAt,
  });
}

/// All live numbers for the admin dashboard.
class DashboardStats {
  final int totalStudents;
  final int totalTeachers;
  final int totalStaff;
  final int totalClasses;
  final int todayPresent;
  final int todayAbsent;
  final int todayLeave;
  final double pendingFees;
  final double collectedThisMonth;
  final double monthlyTarget;
  final String monthLabel;
  final List<DashboardActivity> recentActivities;

  const DashboardStats({
    required this.totalStudents,
    required this.totalTeachers,
    required this.totalStaff,
    required this.totalClasses,
    required this.todayPresent,
    required this.todayAbsent,
    required this.todayLeave,
    required this.pendingFees,
    required this.collectedThisMonth,
    required this.monthlyTarget,
    required this.monthLabel,
    required this.recentActivities,
  });

  /// Honest empty state — shown logged-out or when queries fail.
  /// All zeros, empty feed: never invented numbers.
  const DashboardStats.zero()
      : totalStudents = 0,
        totalTeachers = 0,
        totalStaff = 0,
        totalClasses = 0,
        todayPresent = 0,
        todayAbsent = 0,
        todayLeave = 0,
        pendingFees = 0,
        collectedThisMonth = 0,
        monthlyTarget = 0,
        monthLabel = '',
        recentActivities = const [];

  double get monthProgress => monthlyTarget <= 0
      ? 0
      : (collectedThisMonth / monthlyTarget).clamp(0.0, 1.0).toDouble();
}

// ─────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────

final dashboardStatsProvider =
    FutureProvider<DashboardStats>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const DashboardStats.zero();

  try {
    final client = SupabaseService.client;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final results = await Future.wait([
      // 0 — active students
      client
          .from('students')
          .select('id')
          .eq('tenant_id', tenantId)
          .eq('is_active', true),
      // 1 — active staff (id + department to derive teacher count)
      client
          .from('staff')
          .select('id, department')
          .eq('tenant_id', tenantId)
          .eq('is_active', true),
      // 2 — darjas (classes)
      client.from('darjas').select('id').eq('tenant_id', tenantId),
      // 3 — today's attendance marks
      client
          .from('attendance')
          .select('status')
          .eq('tenant_id', tenantId)
          .eq('date', todayStr),
      // 4 — fees (for dues, monthly progress, recent collections)
      client
          .from('fees')
          .select(
              'amount_due, amount_paid, status, month, paid_date, updated_at, students(name)')
          .eq('tenant_id', tenantId),
      // 5 — recent admissions
      client
          .from('students')
          .select('name, created_at')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false)
          .limit(3),
    ]);

    final studentRows = results[0] as List;
    final staffRows = results[1] as List;
    final darjaRows = results[2] as List;
    final attendanceRows = results[3] as List;
    final feeRows = results[4] as List;
    final admissionRows = results[5] as List;

    // ── Headcounts ──
    final totalStudents = studentRows.length;
    final totalStaff = staffRows.length;
    // 'تعلیمی' (teaching) department marks teaching staff — the same
    // convention the dashboard used before Phase 4.
    final totalTeachers = staffRows
        .where((r) =>
            (r as Map<String, dynamic>)['department'] == 'تعلیمی')
        .length;
    final totalClasses = darjaRows.length;

    // ── Today's attendance ──
    var present = 0, absent = 0, leave = 0;
    for (final r in attendanceRows) {
      switch ((r as Map<String, dynamic>)['status'] as String?) {
        case 'present':
          present++;
          break;
        case 'absent':
          absent++;
          break;
        case 'leave':
          leave++;
          break;
      }
    }

    // ── Fees ──
    var pending = 0.0;
    var monthTarget = 0.0;
    var monthCollected = 0.0;
    final paidFees = <Map<String, dynamic>>[];
    for (final r in feeRows) {
      final row = r as Map<String, dynamic>;
      final due = (row['amount_due'] as num?)?.toDouble() ?? 0;
      final paid = (row['amount_paid'] as num?)?.toDouble() ?? 0;
      final status = row['status'] as String?;
      if (status == 'pending' ||
          status == 'past_due' ||
          status == 'partial') {
        pending += (due - paid);
      }
      if (status == 'paid') paidFees.add(row);
      if (row['month'] == monthKey) {
        monthTarget += due;
        monthCollected += paid;
      }
    }

    // ── Recent activity feed (real events, newest first) ──
    final activities = <DashboardActivity>[];

    paidFees.sort((a, b) => _activityTime(b).compareTo(_activityTime(a)));
    for (final row in paidFees.take(3)) {
      final at = _activityTime(row);
      final student =
          (row['students'] as Map<String, dynamic>?)?['name'] as String? ??
              'طالب علم';
      final amount = (row['amount_paid'] as num?)?.toDouble() ?? 0;
      activities.add(DashboardActivity(
        iconKey: 'fee',
        title: 'فیس وصولی',
        subtitle: '$student - ${formatPK(amount)} روپے',
        timeLabel: urduTimeAgo(at),
        occurredAt: at,
      ));
    }

    for (final r in admissionRows) {
      final row = r as Map<String, dynamic>;
      final at = DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      activities.add(DashboardActivity(
        iconKey: 'admission',
        title: 'نیا داخلہ',
        subtitle: (row['name'] as String?) ?? 'طالب علم',
        timeLabel: urduTimeAgo(at),
        occurredAt: at,
      ));
    }

    activities.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    return DashboardStats(
      totalStudents: totalStudents,
      totalTeachers: totalTeachers,
      totalStaff: totalStaff,
      totalClasses: totalClasses,
      todayPresent: present,
      todayAbsent: absent,
      todayLeave: leave,
      pendingFees: pending,
      collectedThisMonth: monthCollected,
      monthlyTarget: monthTarget,
      monthLabel:
          '${app_date.DateUtils.formatMonthName(now)} ${now.year}',
      recentActivities: activities.take(5).toList(),
    );
  } catch (_) {
    // Offline or query failure: honest zeros, never invented numbers.
    return const DashboardStats.zero();
  }
});

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

/// Best available timestamp for a fee row (paid date, else last update).
DateTime _activityTime(Map<String, dynamic> row) {
  return DateTime.tryParse(row['paid_date'] as String? ?? '') ??
      DateTime.tryParse(row['updated_at'] as String? ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// Relative Urdu timestamp: 'ابھی' | 'X منٹ پہلے' | 'X گھنٹے پہلے' |
/// 'کل' | '<day> <month> <year>'.
String urduTimeAgo(DateTime at) {
  if (at.millisecondsSinceEpoch == 0) return '';
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'ابھی';
  if (diff.inMinutes < 60) return '${diff.inMinutes} منٹ پہلے';
  if (diff.inHours < 24) {
    return diff.inHours == 1 ? '1 گھنٹہ پہلے' : '${diff.inHours} گھنٹے پہلے';
  }
  final now = DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));
  if (at.year == yesterday.year &&
      at.month == yesterday.month &&
      at.day == yesterday.day) {
    return 'کل';
  }
  return app_date.DateUtils.formatDateUrdu(at);
}

/// Pakistani digit grouping: 380000 → '3,80,000'.
String formatPK(num value) {
  final n = value.round();
  final digits = n.abs().toString();
  if (digits.length <= 3) return (n < 0 ? '-' : '') + digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.add(rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  groups.add(rest);
  return (n < 0 ? '-' : '') + groups.reversed.join(',') + ',' + last3;
}
