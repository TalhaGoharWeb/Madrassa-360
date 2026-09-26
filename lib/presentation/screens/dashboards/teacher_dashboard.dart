/// استاد ڈیش بورڈ — §7
/// Teacher dashboard (Phase 7a) — radically simple.
///
/// Greeting (السلام علیکم استاد محترم / آج کی تدریس), four cards
/// (میری جماعتیں، میرے طلبہ، آج کی حاضری، آج کے اسباق), quick actions
/// (حاضری لگائیں، طلبہ دیکھیں، نمبر درج کریں), "میرا آج کا کام"
/// checklist, and the latest announcements.
///
/// Every number comes from the teacher's assignment-scoped providers —
/// never global lists, never hard-coded. "آج کے اسباق" has no data
/// source yet, so it renders an honest empty state (§37), not a number.
///
/// Finance / payroll / settings / user management / master admin appear
/// NOWHERE here — and the tab shell ([TeacherHomeScreen]) never adds
/// those routes for teacher roles either.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_typography.dart';
import '../../widgets/dashboard/alert_card.dart';
import '../../widgets/dashboard/dashboard_scaffold.dart';
import '../../widgets/dashboard/schedule_slot.dart';
import '../../widgets/dashboard/quick_actions.dart';
import '../../widgets/dashboard/stat_card.dart';
import '../../widgets/dashboard/today_tasks.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/day_schedule_provider.dart';
import '../../../providers/dashboard_data_provider.dart';
import '../../../providers/teacher_portal_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../common/announcements_screen.dart';

class TeacherDashboardScreen extends ConsumerStatefulWidget {
  final VoidCallback onMarkAttendance;
  final VoidCallback onViewStudents;
  final VoidCallback onEnterResults;

  const TeacherDashboardScreen({
    super.key,
    required this.onMarkAttendance,
    required this.onViewStudents,
    required this.onEnterResults,
  });

  @override
  ConsumerState<TeacherDashboardScreen> createState() =>
      _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState
    extends ConsumerState<TeacherDashboardScreen> {
  /// Manual checkbox overrides (task index → done). Absent = derive from
  /// real data; toggling back to the derived value clears the override.
  final Map<int, bool> _overrides = {};

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final teacherName = user?.name ?? 'استاد';
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final madrasaName = branding?.displayName() ?? 'مدرسہ 360';

    bool can(String permission) => ref.watch(hasPermissionProvider(permission));
    final canAttendance = can(AppPermissions.viewAttendance) ||
        can(AppPermissions.markAttendance);
    final canStudents = can(AppPermissions.viewStudents);
    final canResults = can(AppPermissions.viewResults) ||
        can(AppPermissions.enterResults) ||
        can(AppPermissions.editResults);

    final quickActionItems = [
      if (canAttendance)
        QuickActionItem(
          icon: Icons.fact_check_outlined,
          label: 'حاضری لگائیں',
          color: AppColors.present,
          onTap: widget.onMarkAttendance,
        ),
      // سبق درج کریں: no lesson-logging source exists, so the action is
      // omitted entirely (the 'آج کے اسباق' card below keeps its honest
      // empty state).
      if (canStudents)
        QuickActionItem(
          icon: Icons.people_outline,
          label: 'طلبہ دیکھیں',
          onTap: widget.onViewStudents,
        ),
      if (canResults)
        QuickActionItem(
          icon: Icons.edit_outlined,
          label: 'نمبر درج کریں',
          color: AppColors.info,
          onTap: widget.onEnterResults,
        ),
    ];

    return DashboardScaffold(
      greeting: 'السلام علیکم استاد محترم',
      userName: teacherName,
      roleLabel: 'آج کی تدریس',
      madrasaName: madrasaName,
      schedule: ScheduleSlot(scheduleProvider: teacherDayScheduleProvider),
      stats: _Cards(
        onMarkAttendance: widget.onMarkAttendance,
        onViewStudents: widget.onViewStudents,
      ),
      quickActionsTitle: 'فوری عمل',
      quickActions: QuickActionGrid(items: quickActionItems),
      todayTasks: _TodayTasks(
        overrides: _overrides,
        onToggle: (i, derived, v) => setState(() {
          if (v == derived) {
            _overrides.remove(i);
          } else {
            _overrides[i] = v;
          }
        }),
        onMarkAttendance: widget.onMarkAttendance,
        onEnterResults: widget.onEnterResults,
      ),
      alertsTitle: 'تازہ اعلانات',
      alerts: _LatestAnnouncements(),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: 'اعلانات',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
          ),
        ),
      ],
    );
  }
}

/// Four cards: میری جماعتیں، میرے طلبہ، آج کی حاضری، آج کے اسباق.
class _Cards extends ConsumerWidget {
  final VoidCallback onMarkAttendance;
  final VoidCallback onViewStudents;

  const _Cards({
    required this.onMarkAttendance,
    required this.onViewStudents,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classCount = ref.watch(teacherAssignedClassIdsProvider).length;
    final studentCount = ref.watch(teacherStudentCountProvider).valueOrNull;
    final attendance =
        ref.watch(teacherTodayAttendanceStatusProvider).valueOrNull;

    final attDone = attendance?.done ?? 0;
    final attTotal = attendance?.total ?? 0;
    final attComplete = attTotal > 0 && attDone == attTotal;

    Widget card(Widget child) => Expanded(child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'آج کی تدریس',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Row(
          children: [
            card(StatCard(
              icon: Icons.school_outlined,
              label: 'میری جماعتیں',
              value: '$classCount',
              color: AppColors.primary,
            )),
            const SizedBox(width: 10),
            card(StatCard(
              icon: Icons.people_outline,
              label: 'میرے طلبہ',
              value: studentCount == null ? '—' : '$studentCount',
              color: AppColors.info,
              onTap: studentCount == null ? null : onViewStudents,
            )),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            card(StatCard(
              icon: Icons.fact_check_outlined,
              label: 'آج کی حاضری',
              value: attTotal == 0
                  ? '—'
                  : attComplete
                      ? 'مکمل'
                      : 'باقی',
              subtitle: attTotal == 0
                  ? 'کوئی جماعت نہیں'
                  : '$attDone میں سے $attTotal جماعتیں',
              color: attComplete ? AppColors.present : AppColors.warning,
              onTap: attTotal == 0 ? null : onMarkAttendance,
            )),
            const SizedBox(width: 10),
            // No lesson-logging source exists yet — honest empty state
            // (§37), never an invented number.
            card(const StatCard(
              icon: Icons.menu_book_outlined,
              label: 'آج کے اسباق',
              value: '—',
              subtitle: 'ابھی کوئی سبق درج نہیں',
              color: AppColors.textSecondary,
            )),
          ],
        ),
      ],
    );
  }
}

/// "میرا آج کا کام" — attendance derived from real data, the rest are
/// caller-owned manual checkboxes.
class _TodayTasks extends ConsumerWidget {
  final Map<int, bool> overrides;
  final void Function(int index, bool derived, bool value) onToggle;
  final VoidCallback onMarkAttendance;
  final VoidCallback onEnterResults;

  const _TodayTasks({
    required this.overrides,
    required this.onToggle,
    required this.onMarkAttendance,
    required this.onEnterResults,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendance =
        ref.watch(teacherTodayAttendanceStatusProvider).valueOrNull;
    final attDone = attendance?.done ?? 0;
    final attTotal = attendance?.total ?? 0;
    final attComplete = attTotal > 0 && attDone == attTotal;

    final derived = [attComplete, false, false];
    final labels = [
      (
        'آج کی حاضری مکمل کریں',
        attTotal == 0
            ? 'کوئی جماعت تفویض نہیں'
            : '$attDone میں سے $attTotal جماعتیں مکمل'
      ),
      ('آج کے اسباق درج کریں', ''),
      ('نمبرات درج کریں', ''),
    ];

    // 'آج کے اسباق درج کریں' stays a manual checklist item: no
    // lesson-logging source exists, so it has no navigation action.
    return TodayTasks(
      tasks: List.generate(
        3,
        (i) => TodayTask(
          label: labels[i].$1,
          subtitle: labels[i].$2.isEmpty ? null : labels[i].$2,
          done: overrides[i] ?? derived[i],
        ),
      ),
      onToggle: (i, v) => onToggle(i, derived[i], v),
      rowActions: [onMarkAttendance, null, onEnterResults],
    );
  }
}

/// Latest 3 announcements (real, tenant-scoped).
class _LatestAnnouncements extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcements = ref.watch(announcementListProvider).take(3).toList();
    if (announcements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'ابھی کوئی اعلان نہیں',
          style: AppTypography.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      children: announcements
          .map((a) => AlertCard(
                icon: Icons.campaign_outlined,
                message: a.title,
                actionLabel: 'پڑھیں',
                onAction: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AnnouncementsScreen(),
                  ),
                ),
                severity: AlertSeverity.info,
              ))
          .toList(),
    );
  }
}
