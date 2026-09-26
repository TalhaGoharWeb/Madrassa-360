/// دفتر ڈیش بورڈ — §9 (Phase 7b)
/// Clerk dashboard (daftar_dar).
///
/// * Stats: نئے داخلے (real: students admitted in the last 7 days),
///   زیرِ تکمیل داخلے (honest empty — no admissions table exists),
///   آج کی فیس (real: today's fee collection),
///   دستاویزات باقی (honest empty — no documents table exists).
/// * Quick actions + today-tasks, each gated on its own permission.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/services/role_service.dart';
import '../../../core/utils/money_format.dart';
import '../../widgets/dashboard/alert_card.dart';
import '../../widgets/dashboard/dashboard_scaffold.dart';
import '../../widgets/dashboard/schedule_slot.dart';
import '../../widgets/dashboard/quick_actions.dart';
import '../../widgets/dashboard/slot_heading.dart';
import '../../widgets/dashboard/stat_card.dart';
import '../../widgets/dashboard/today_tasks.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/day_schedule_provider.dart';
import '../../../providers/dashboard_data_provider.dart';
import '../../../providers/fee_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../admin/fee_management_screen.dart';
import '../admin/student_list_screen.dart';

class ClerkDashboardScreen extends ConsumerStatefulWidget {
  const ClerkDashboardScreen({super.key});

  @override
  ConsumerState<ClerkDashboardScreen> createState() =>
      _ClerkDashboardScreenState();
}

class _ClerkDashboardScreenState extends ConsumerState<ClerkDashboardScreen> {
  final List<bool> _done = [false, false, false];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'دفتر دار';
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
        schedule: ScheduleSlot(scheduleProvider: clerkDayScheduleProvider),
        stats: _ClerkStats(can: can, moduleOk: moduleOk),
        alertsTitle: 'اہم امور',
        alerts: _ClerkAlerts(can: can, moduleOk: moduleOk),
        quickActionsTitle: 'فوری عمل',
        quickActions: _ClerkQuickActions(can: can, moduleOk: moduleOk),
        todayTasks: _ClerkTasks(
          can: can,
          moduleOk: moduleOk,
          done: _done,
          onToggle: (i, v) => setState(() => _done[i] = v),
        ),
      ),
    );
  }
}

/// Clerk stat cards. Admissions come from real student rows; the two
/// '—' cards are honest empty states (no admissions/documents tables).
class _ClerkStats extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _ClerkStats({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admissions = ref.watch(newAdmissionsProvider).valueOrNull ?? const [];
    final todayCollection =
        ref.watch(todayCollectionProvider).valueOrNull ?? 0.0;

    final canSeeStudents = can(AppPermissions.viewStudents);
    final canSeeFees =
        (can(AppPermissions.viewFees) || can(AppPermissions.collectFees)) &&
            moduleOk('fees');

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SlotHeading('دفتر کا جائزہ'),
        Row(
          children: [
            if (canSeeStudents)
              Expanded(
                child: StatCard(
                  icon: Icons.person_add_outlined,
                  label: 'نئے داخلے',
                  value: '${admissions.length}',
                  color: AppColors.primary,
                  subtitle: admissions.isEmpty
                      ? 'اس ہفتے کوئی نیا داخلہ نہیں'
                      : 'اس ہفتے',
                  onTap: () => go(const StudentListScreen()),
                ),
              ),
            if (canSeeStudents) const SizedBox(width: 10),
            Expanded(
              child: const StatCard(
                icon: Icons.pending_actions_outlined,
                label: 'زیرِ تکمیل داخلے',
                value: '—',
                color: AppColors.textSecondary,
                subtitle: 'ریکارڈ موجود نہیں',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (canSeeFees)
              Expanded(
                child: StatCard(
                  icon: Icons.payments_outlined,
                  label: 'آج کی فیس',
                  value: formatRs(todayCollection),
                  color: AppColors.success,
                  onTap: () => go(const FeeManagementScreen()),
                ),
              ),
            if (canSeeFees) const SizedBox(width: 10),
            Expanded(
              child: const StatCard(
                icon: Icons.folder_outlined,
                label: 'دستاویزات باقی',
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

/// Clerk alerts — each with an action.
class _ClerkAlerts extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _ClerkAlerts({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = <Widget>[];

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    if ((can(AppPermissions.viewFees) || can(AppPermissions.collectFees)) &&
        moduleOk('fees')) {
      final summary = ref.watch(feeSummaryProvider).valueOrNull;
      if (summary != null && summary.pendingCount > 0) {
        alerts.add(AlertCard(
          icon: Icons.payments_outlined,
          message: '${summary.pendingCount} طلبہ کی فیس باقی ہے '
              '(${formatRs(summary.totalDue)})',
          actionLabel: 'دیکھیں',
          onAction: () => go(const FeeManagementScreen()),
        ));
      }
    }

    if (can(AppPermissions.viewStudents)) {
      final admissions =
          ref.watch(newAdmissionsProvider).valueOrNull ?? const [];
      if (admissions.isNotEmpty) {
        alerts.add(AlertCard(
          icon: Icons.person_add_outlined,
          message: 'اس ہفتے ${admissions.length} نئے داخلے ہوئے',
          actionLabel: 'دیکھیں',
          onAction: () => go(const StudentListScreen()),
          severity: AlertSeverity.info,
        ));
      }
    }

    if (alerts.isEmpty) return const SizedBox.shrink();
    return Column(children: alerts);
  }
}

/// Clerk quick actions — each gated on its own permission.
class _ClerkQuickActions extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _ClerkQuickActions({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final items = [
      if (can(AppPermissions.createStudents))
        QuickActionItem(
          icon: Icons.person_add_outlined,
          label: 'نیا داخلہ',
          onTap: () => go(const StudentListScreen()),
        ),
      if (can(AppPermissions.viewStudents))
        QuickActionItem(
          icon: Icons.people_outline,
          label: 'طلبہ کی فہرست',
          onTap: () => go(const StudentListScreen()),
        ),
      if (can(AppPermissions.collectFees) && moduleOk('fees'))
        QuickActionItem(
          icon: Icons.payments_outlined,
          label: 'فیس وصول کریں',
          color: AppColors.success,
          onTap: () => go(const FeeManagementScreen()),
        ),
      if (can(AppPermissions.collectFees) && moduleOk('fees'))
        QuickActionItem(
          icon: Icons.receipt_outlined,
          label: 'رسید بنائیں',
          color: AppColors.success,
          onTap: () => go(const FeeManagementScreen()),
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();
    return QuickActionGrid(items: items);
  }
}

/// "میرا آج کا کام" — داخلے مکمل کریں، رسیدیں تیار کریں. (دستاویزات کا
/// کوئی ڈیٹا سورس نہیں، اس لیے وہ ٹاسک ہٹا دیا گیا ہے۔)
class _ClerkTasks extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;
  final List<bool> done;
  final void Function(int, bool) onToggle;

  const _ClerkTasks({
    required this.can,
    required this.moduleOk,
    required this.done,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final admissions = ref.watch(newAdmissionsProvider).valueOrNull ?? const [];

    // (task, row action, slot in the caller's done-state list) — the slot
    // keeps toggle state aligned even when a permission hides a row.
    final entries = <({TodayTask task, VoidCallback? action, int slot})>[];

    if (can(AppPermissions.createStudents)) {
      entries.add((
        task: TodayTask(
          label: 'داخلے مکمل کریں',
          subtitle: admissions.isEmpty
              ? 'اس ہفتے کوئی نیا داخلہ نہیں'
              : 'اس ہفتے ${admissions.length} نئے داخلے',
          done: done[0],
        ),
        action: () => go(const StudentListScreen()),
        slot: 0,
      ));
    }
    if (can(AppPermissions.collectFees) && moduleOk('fees')) {
      entries.add((
        task: const TodayTask(
          label: 'رسیدیں تیار کریں',
          done: false,
        ),
        action: () => go(const FeeManagementScreen()),
        slot: 2,
      ));
    }

    if (entries.isEmpty) return const SizedBox.shrink();
    return TodayTasks(
      tasks: [
        for (final e in entries) e.task.copyWith(done: done[e.slot]),
      ],
      onToggle: (i, v) => onToggle(entries[i].slot, v),
      rowActions: [for (final e in entries) e.action],
    );
  }
}
