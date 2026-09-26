/// امتحانات ڈیش بورڈ — §15 (Phase 7b)
/// Exam manager dashboard (mumtahin).
///
/// * Stats: جاری امتحانات، نمبر درج ہونا باقی، نتائج تیار — all from
///   real queries ([examSummaryProvider]). نتائج شائع شدہ is an honest
///   empty state: the schema has no publish flag, so nothing is
///   invented.
/// * "امتحان بنائیں" opens the step-by-step wizard
///   ([ExamWizardScreen]) — the workflow is guided one step at a time,
///   never shown all at once.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/services/role_service.dart';
import '../../widgets/dashboard/alert_card.dart';
import '../../widgets/dashboard/dashboard_scaffold.dart';
import '../../widgets/dashboard/schedule_slot.dart';
import '../../widgets/dashboard/quick_actions.dart';
import '../../widgets/dashboard/slot_heading.dart';
import '../../widgets/dashboard/stat_card.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/day_schedule_provider.dart';
import '../../../providers/dashboard_data_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../reports/reports_hub_screen.dart';
import '../teacher/results_screen.dart';
import 'exam_wizard_screen.dart';

class ExamDashboardScreen extends ConsumerWidget {
  const ExamDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'ممتحن';
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final madrasaName = branding?.displayName() ?? 'مدرسہ 360';

    final roleService = ref.watch(roleServiceProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);

    bool can(String permission) => ref.watch(hasPermissionProvider(permission));

    return FutureBuilder<String>(
      future: roleKeys.isEmpty
          ? Future.value('')
          : roleService.roleUrduLabel(roleKeys.first),
      builder: (context, snap) => DashboardScaffold(
        greeting: 'السلام علیکم ورحمۃ اللہ',
        userName: userName,
        roleLabel: snap.data?.isEmpty == true ? null : snap.data,
        madrasaName: madrasaName,
        schedule: ScheduleSlot(scheduleProvider: examDayScheduleProvider),
        stats: _ExamStats(can: can),
        alertsTitle: 'اہم امور',
        alerts: _ExamAlerts(can: can),
        quickActionsTitle: 'فوری عمل',
        quickActions: _ExamQuickActions(can: can),
      ),
    );
  }
}

/// Exam stat cards — every number from real queries.
class _ExamStats extends ConsumerWidget {
  final bool Function(String) can;

  const _ExamStats({required this.can});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!can(AppPermissions.viewExams)) {
      return const SizedBox.shrink();
    }

    final summary =
        ref.watch(examSummaryProvider).valueOrNull ?? const ExamSummary.zero();

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SlotHeading('امتحانات کا جائزہ'),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.assignment_outlined,
                label: 'جاری امتحانات',
                value: '${summary.ongoing}',
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                icon: Icons.edit_note_outlined,
                label: 'نمبر درج ہونا باقی',
                value: '${summary.pendingMarks}',
                color: summary.pendingMarks > 0
                    ? AppColors.warning
                    : AppColors.success,
                subtitle: summary.pendingMarks == 0 ? 'سب درج ہیں' : null,
                onTap: (summary.pendingMarks > 0 &&
                        can(AppPermissions.enterResults))
                    ? () => go(const ResultsScreen())
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.check_circle_outline,
                label: 'نتائج تیار',
                value: '${summary.ready}',
                color: AppColors.success,
                onTap: can(AppPermissions.viewResults)
                    ? () => go(const ResultsScreen())
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            // Honest empty state: no publish flag exists in the schema.
            Expanded(
              child: const StatCard(
                icon: Icons.publish_outlined,
                label: 'نتائج شائع شدہ',
                value: '—',
                color: AppColors.textSecondary,
                subtitle: 'ریکارڈ موجود نہیں',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Exam alerts — each with an action.
class _ExamAlerts extends ConsumerWidget {
  final bool Function(String) can;

  const _ExamAlerts({required this.can});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!can(AppPermissions.viewExams)) {
      return const SizedBox.shrink();
    }

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final summary = ref.watch(examSummaryProvider).valueOrNull;
    if (summary == null || summary.pendingMarks == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        AlertCard(
          icon: Icons.edit_note_outlined,
          message: summary.pendingMarks == 1
              ? '1 امتحان کے نمبر درج نہیں ہوئے'
              : '${summary.pendingMarks} امتحانات کے نمبر درج نہیں ہوئے',
          actionLabel: 'درج کریں',
          onAction: () => go(const ResultsScreen()),
        ),
      ],
    );
  }
}

/// Exam quick actions — each gated on its own permission.
class _ExamQuickActions extends ConsumerWidget {
  final bool Function(String) can;

  const _ExamQuickActions({required this.can});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final items = [
      if (can(AppPermissions.createExams))
        QuickActionItem(
          icon: Icons.add_circle_outline,
          label: 'امتحان بنائیں',
          color: AppColors.primary,
          onTap: () => go(const ExamWizardScreen()),
        ),
      if (can(AppPermissions.enterResults))
        QuickActionItem(
          icon: Icons.edit_note_outlined,
          label: 'نمبر درج کریں',
          color: AppColors.warning,
          onTap: () => go(const ResultsScreen()),
        ),
      if (can(AppPermissions.viewResults))
        QuickActionItem(
          icon: Icons.assessment_outlined,
          label: 'نتائج دیکھیں',
          color: AppColors.success,
          onTap: () => go(const ResultsScreen()),
        ),
      if (can(AppPermissions.viewReports))
        QuickActionItem(
          icon: Icons.bar_chart_outlined,
          label: 'رپورٹ',
          color: AppColors.info,
          onTap: () => go(const ReportsHubScreen()),
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();
    return QuickActionGrid(items: items);
  }
}
