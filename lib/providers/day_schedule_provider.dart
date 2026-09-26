/// آج کا شیڈول — role day-schedule data (v3).
///
/// Pure-data providers mapping REAL provider rows to [DayScheduleEvent]s
/// for the [DayTimeline] widget. An empty list means the role genuinely has
/// no schedule data today — the dashboard then shows the honest empty
/// state. Nothing here invents rows.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/tenant_context.dart';
import '../core/utils/date_utils.dart' as app_date;
import '../core/utils/money_format.dart';
import 'announcement_provider.dart';
import 'attendance_provider.dart';
import 'dashboard_data_provider.dart';
import 'fee_provider.dart';
import 'result_provider.dart';
import 'teacher_portal_provider.dart';

/// Schedule state of one event: done (✓), now (● pulsing), upcoming (○).
enum DayScheduleState { done, now, upcoming }

/// One schedule event — pure data, rendered by [DayTimeline].
class DayScheduleEvent {
  /// Urdu title, e.g. 'حاضری — جماعت پنجم'.
  final String title;

  /// Optional supporting line.
  final String? subtitle;

  /// Optional time label. Null when the source data carries no real time —
  /// callers must never fabricate one.
  final String? timeLabel;

  final DayScheduleState state;

  const DayScheduleEvent({
    required this.title,
    this.subtitle,
    this.timeLabel,
    this.state = DayScheduleState.upcoming,
  });
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Orders events done → now → upcoming, and promotes the first pending
/// event to [DayScheduleState.now] so the timeline always has a focal
/// "happening now" row when anything is still open.
List<DayScheduleEvent> _orderEvents(List<DayScheduleEvent> events) {
  final done = events.where((e) => e.state == DayScheduleState.done).toList();
  final pending =
      events.where((e) => e.state != DayScheduleState.done).toList();
  final ordered = <DayScheduleEvent>[...done];
  for (var i = 0; i < pending.length; i++) {
    final e = pending[i];
    ordered.add(i == 0
        ? DayScheduleEvent(
            title: e.title,
            subtitle: e.subtitle,
            timeLabel: e.timeLabel,
            state: DayScheduleState.now,
          )
        : e);
  }
  return ordered;
}

// ─────────────────────────────────────────────────────────────
// Teacher: today's attendance per assigned class.
// ─────────────────────────────────────────────────────────────

/// One event per assigned class: attendance marked today → done,
/// otherwise upcoming. Real rows from [teacherAssignmentsProvider] ×
/// [classAttendanceProvider].
final teacherDayScheduleProvider =
    FutureProvider<List<DayScheduleEvent>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  try {
    final assignments = await ref.watch(teacherAssignmentsProvider.future);
    if (assignments.isEmpty) return const [];
    final today = DateTime.now();
    final events = <DayScheduleEvent>[];
    for (final a in assignments) {
      final records = await ref.watch(
        classAttendanceProvider(
                AttendanceParams(classId: a.classId, date: today))
            .future,
      );
      final done = records.isNotEmpty;
      events.add(DayScheduleEvent(
        title: 'حاضری — ${a.className}',
        subtitle: done
            ? '${records.length} طلبہ کی حاضری درج ہو گئی'
            : 'حاضری درج کرنا باقی ہے',
        state: done ? DayScheduleState.done : DayScheduleState.upcoming,
      ));
    }
    return _orderEvents(events);
  } catch (_) {
    return const [];
  }
});

// ─────────────────────────────────────────────────────────────
// Accountant: today's collection + outstanding dues.
// ─────────────────────────────────────────────────────────────

/// Today's fee collection (done when > 0) plus outstanding dues
/// (upcoming). Real rows from [todayCollectionProvider] and
/// [feeSummaryProvider].
final accountantDayScheduleProvider =
    FutureProvider<List<DayScheduleEvent>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  try {
    final collected = await ref.watch(todayCollectionProvider.future);
    final summary = await ref.watch(feeSummaryProvider.future);
    final events = <DayScheduleEvent>[
      DayScheduleEvent(
        title: 'آج کی وصولی',
        subtitle: collected > 0
            ? '${formatRs(collected)} وصول ہو چکے'
            : 'ابھی کوئی وصولی نہیں ہوئی',
        state:
            collected > 0 ? DayScheduleState.done : DayScheduleState.upcoming,
      ),
    ];
    if (summary.pendingCount > 0) {
      events.add(DayScheduleEvent(
        title: 'بقایا فیس کی وصولی',
        subtitle:
            '${summary.pendingCount} فیس بقایا ہے — ${formatRs(summary.totalDue)}',
        state: DayScheduleState.upcoming,
      ));
    }
    return _orderEvents(events);
  } catch (_) {
    return const [];
  }
});

// ─────────────────────────────────────────────────────────────
// Exam: upcoming exams by date.
// ─────────────────────────────────────────────────────────────

/// Next exams sorted by [Exam.examDate]: past → done, today → now,
/// future → upcoming. Real rows from [allExamsProvider].
final examDayScheduleProvider =
    FutureProvider<List<DayScheduleEvent>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  try {
    final exams = await ref.watch(allExamsProvider.future);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dated = <({DateTime date, String name})>[];
    for (final exam in exams) {
      final d = DateTime.tryParse(exam.examDate);
      if (d == null) continue;
      dated.add((date: DateTime(d.year, d.month, d.day), name: exam.name));
    }
    dated.sort((a, b) => a.date.compareTo(b.date));
    final events = <DayScheduleEvent>[];
    for (final e in dated.take(6)) {
      final label = app_date.DateUtils.formatDateUrdu(e.date);
      if (e.date.isBefore(today)) {
        events.add(DayScheduleEvent(
          title: e.name,
          subtitle: label,
          timeLabel: label,
          state: DayScheduleState.done,
        ));
      } else {
        events.add(DayScheduleEvent(
          title: e.name,
          subtitle: label,
          timeLabel: label,
          state: DayScheduleState.upcoming,
        ));
      }
    }
    return _orderEvents(events);
  } catch (_) {
    return const [];
  }
});

// ─────────────────────────────────────────────────────────────
// Principal: today's announcements + today's new admissions.
// ─────────────────────────────────────────────────────────────

/// Announcements scheduled for today plus students admitted today.
/// Real rows from [announcementListProvider] and [newAdmissionsProvider].
final principalDayScheduleProvider =
    FutureProvider<List<DayScheduleEvent>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  try {
    final now = DateTime.now();
    final events = <DayScheduleEvent>[];

    final announcements = ref.watch(announcementListProvider);
    for (final a in announcements) {
      final scheduled = a.scheduledAt;
      if (scheduled != null && _isSameDay(scheduled, now)) {
        events.add(DayScheduleEvent(
          title: a.title,
          subtitle: 'آج کا اعلان',
          timeLabel: app_date.DateUtils.formatTime(scheduled),
          state: DayScheduleState.upcoming,
        ));
      }
    }

    final admissions = await ref.watch(newAdmissionsProvider.future);
    final todayCount = admissions.where((s) {
      final d = DateTime.tryParse(s.dateOfAdmit ?? '');
      return d != null && _isSameDay(d, now);
    }).length;
    if (todayCount > 0) {
      events.add(DayScheduleEvent(
        title: 'نئے داخلے',
        subtitle:
            '$todayCount ${todayCount == 1 ? 'طالب علم' : 'طلبہ'} کا آج داخلہ ہوا',
        state: DayScheduleState.done,
      ));
    }

    return _orderEvents(events);
  } catch (_) {
    return const [];
  }
});

// ─────────────────────────────────────────────────────────────
// Clerk: today's admissions + outstanding dues.
// ─────────────────────────────────────────────────────────────

/// Students admitted today (done) plus outstanding fee dues (upcoming).
/// Real rows from [newAdmissionsProvider] and [feeSummaryProvider].
final clerkDayScheduleProvider =
    FutureProvider<List<DayScheduleEvent>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  try {
    final now = DateTime.now();
    final events = <DayScheduleEvent>[];

    final admissions = await ref.watch(newAdmissionsProvider.future);
    final todayCount = admissions.where((s) {
      final d = DateTime.tryParse(s.dateOfAdmit ?? '');
      return d != null && _isSameDay(d, now);
    }).length;
    if (todayCount > 0) {
      events.add(DayScheduleEvent(
        title: 'آج کے نئے داخلے',
        subtitle:
            '$todayCount ${todayCount == 1 ? 'طالب علم' : 'طلبہ'} کا داخلہ مکمل',
        state: DayScheduleState.done,
      ));
    }

    final summary = await ref.watch(feeSummaryProvider.future);
    if (summary.pendingCount > 0) {
      events.add(DayScheduleEvent(
        title: 'بقایا فیس کی وصولی',
        subtitle: '${summary.pendingCount} فیس بقایا ہے',
        state: DayScheduleState.upcoming,
      ));
    }

    return _orderEvents(events);
  } catch (_) {
    return const [];
  }
});
