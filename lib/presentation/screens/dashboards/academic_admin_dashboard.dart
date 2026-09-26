/// تعلیمی نظام ڈیش بورڈ — §12 (Phase 7b)
/// Academic admin dashboard (nazim_taleem, nazim_hifz).
///
/// * Stats: درجات، اساتذہ، طلبہ، آج حاضری، زیرِ تکمیل نتائج — all from
///   real queries ([academicOverviewProvider]).
/// * Quick actions: استاد مقرر کریں، جماعت بنائیں، نصاب ترتیب دیں،
///   امتحان بنائیں (step-by-step wizard)، نتائج دیکھیں — each gated on
///   its own permission.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/services/role_service.dart';
import '../../widgets/dashboard/alert_card.dart';
import '../../widgets/dashboard/dashboard_scaffold.dart';
import '../../widgets/dashboard/quick_actions.dart';
import '../../widgets/dashboard/slot_heading.dart';
import '../../widgets/dashboard/stat_card.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/dashboard_data_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../admin/darja_screen.dart';
import '../admin/staff_list_screen.dart';
import '../admin/student_list_screen.dart';
import '../teacher/attendance_screen.dart';
import '../teacher/results_screen.dart';
import 'exam_wizard_screen.dart';
import 'role_home.dart' show ComingSoonScreen;

class AcademicAdminDashboardScreen extends ConsumerWidget {
  const AcademicAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'ناظم تعلیم';
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final madrasaName = branding?.displayName() ?? 'مدرسہ 360';

    final roleService = ref.watch(roleServiceProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);

    final enabledModules = ref.watch(tenantModulesProvider).valueOrNull;
    bool moduleOk(String module) =>
        enabledModules == null || enabledModules.contains(module);

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
        stats: _AcademicStats(can: can, moduleOk: moduleOk),
        alertsTitle: 'اہم امور',
        alerts: _AcademicAlerts(can: can, moduleOk: moduleOk),
        quickActionsTitle: 'فوری عمل',
        quickActions: _AcademicQuickActions(can: can, moduleOk: moduleOk),
      ),
    );
  }
}

/// Academic stat cards — every number from real queries.
class _AcademicStats extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _AcademicStats({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(academicOverviewProvider).valueOrNull ??
        const AcademicOverview.zero();

    final canSeeDarjas =
        can(AppPermissions.viewDarjas) && moduleOk('academics');
    final canSeeTeachers = can(AppPermissions.viewTeachers);
    final canSeeStudents = can(AppPermissions.viewStudents);
    final canSeeAttendance = can(AppPermissions.viewAttendance) ||
        can(AppPermissions.markAttendance);
    final canSeeResults =
        can(AppPermissions.viewResults) || can(AppPermissions.enterResults);

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SlotHeading('تعلیمی جائزہ'),
        Row(
          children: [
            if (canSeeDarjas)
              Expanded(
                child: StatCard(
                  icon: Icons.school_outlined,
                  label: 'درجات',
                  value: '${overview.darjas}',
                  color: AppColors.primary,
                  onTap: () => go(const DarjaScreen()),
                ),
              ),
            if (canSeeDarjas) const SizedBox(width: 10),
            if (canSeeTeachers)
              Expanded(
                child: StatCard(
                  icon: Icons.person_outline,
                  label: 'اساتذہ',
                  value: '${overview.teachers}',
                  color: AppColors.info,
                  onTap: () => go(const StaffListScreen()),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (canSeeStudents)
              Expanded(
                child: StatCard(
                  icon: Icons.people_outline,
                  label: 'طلبہ',
                  value: '${overview.students}',
                  color: AppColors.primary,
                  onTap: () => go(const StudentListScreen()),
                ),
              ),
            if (canSeeStudents) const SizedBox(width: 10),
            if (canSeeAttendance)
              Expanded(
                child: StatCard(
                  icon: Icons.fact_check_outlined,
                  label: 'آج حاضری',
                  value: overview.attendancePct == null
                      ? '—'
                      : '${overview.attendancePct!.round()}٪',
                  color: AppColors.present,
                  subtitle: overview.attendancePct == null
                      ? 'ابھی شروع نہیں ہوئی'
                      : null,
                  onTap: overview.attendancePct == null
                      ? () => go(const AttendanceScreen())
                      : null,
                ),
              ),
          ],
        ),
        if (canSeeResults) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  icon: Icons.assessment_outlined,
                  label: 'زیرِ تکمیل نتائج',
                  value: '${overview.pendingResults}',
                  color: overview.pendingResults > 0
                      ? AppColors.warning
                      : AppColors.success,
                  subtitle: overview.pendingResults == 0
                      ? 'سب نتائج درج ہیں'
                      : 'امتحانات کے نتائج باقی',
                  onTap: overview.pendingResults > 0
                      ? () => go(const ResultsScreen())
                      : null,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Academic alerts — each with an action.
class _AcademicAlerts extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _AcademicAlerts({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = <Widget>[];

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final overview = ref.watch(academicOverviewProvider).valueOrNull;

    if ((can(AppPermissions.viewResults) || can(AppPermissions.enterResults)) &&
        overview != null &&
        overview.pendingResults > 0) {
      alerts.add(AlertCard(
        icon: Icons.assessment_outlined,
        message: overview.pendingResults == 1
            ? '1 امتحان کے نتائج درج نہیں ہوئے'
            : '${overview.pendingResults} امتحانات کے نتائج درج نہیں ہوئے',
        actionLabel: 'درج کریں',
        onAction: () => go(const ResultsScreen()),
      ));
    }

    if ((can(AppPermissions.viewAttendance) ||
            can(AppPermissions.markAttendance)) &&
        overview != null &&
        overview.attendancePct == null) {
      alerts.add(AlertCard(
        icon: Icons.fact_check_outlined,
        message: 'آج کی حاضری ابھی شروع نہیں ہوئی',
        actionLabel: 'حاضری لگائیں',
        onAction: () => go(const AttendanceScreen()),
        severity: AlertSeverity.info,
      ));
    }

    if (alerts.isEmpty) return const SizedBox.shrink();
    return Column(children: alerts);
  }
}

/// Academic quick actions — each gated on its own permission.
class _AcademicQuickActions extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _AcademicQuickActions({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final items = [
      if (can(AppPermissions.createTeachers))
        QuickActionItem(
          icon: Icons.group_add_outlined,
          label: 'استاد مقرر کریں',
          onTap: () => go(const StaffListScreen()),
        ),
      if (can(AppPermissions.manageDarjas) && moduleOk('academics'))
        QuickActionItem(
          icon: Icons.school_outlined,
          label: 'جماعت بنائیں',
          onTap: () => go(const DarjaScreen()),
        ),
      if (can(AppPermissions.manageDarjas) && moduleOk('academics'))
        QuickActionItem(
          icon: Icons.menu_book_outlined,
          label: 'نصاب ترتیب دیں',
          color: AppColors.info,
          onTap: () => go(const ComingSoonScreen(title: 'نصاب')),
        ),
      if (can(AppPermissions.createExams))
        QuickActionItem(
          icon: Icons.assignment_outlined,
          label: 'امتحان بنائیں',
          color: AppColors.warning,
          onTap: () => go(const ExamWizardScreen()),
        ),
      if (can(AppPermissions.viewResults))
        QuickActionItem(
          icon: Icons.assessment_outlined,
          label: 'نتائج دیکھیں',
          color: AppColors.success,
          onTap: () => go(const ResultsScreen()),
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();
    return QuickActionGrid(items: items);
  }
}
