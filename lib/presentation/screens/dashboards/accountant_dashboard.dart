/// مالیات ڈیش بورڈ — §§10–11 (Phase 7b)
/// Accountant dashboard (accountant, nazim_maliyat).
///
/// "آج کا مالی خلاصہ": آج کی وصولی، آج کے اخراجات، بقایا فیس، نقد رقم —
/// every number from real queries ([todayCollectionProvider],
/// [financeOverviewProvider], [feeSummaryProvider]) and every one guarded
/// by its own permission. Plain Urdu only: آمدن/خرچ/وصولی/ادائیگی/حساب/
/// بقایا — no Debit/Credit/Ledger/Journal anywhere. The detailed
/// accounting screen lives behind "تفصیلی حسابات".

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
import '../common/dashboard_guide_screen.dart';
import '../../widgets/dashboard/slot_heading.dart';
import '../../widgets/dashboard/stat_card.dart';
import '../../widgets/dashboard/today_tasks.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/day_schedule_provider.dart';
import '../../../providers/dashboard_data_provider.dart';
import '../../../providers/fee_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../admin/fee_management_screen.dart';
import '../admin/finance_screen.dart';
import '../reports/reports_hub_screen.dart';

class AccountantDashboardScreen extends ConsumerStatefulWidget {
  const AccountantDashboardScreen({super.key});

  @override
  ConsumerState<AccountantDashboardScreen> createState() =>
      _AccountantDashboardScreenState();
}

class _AccountantDashboardScreenState
    extends ConsumerState<AccountantDashboardScreen> {
  final List<bool> _done = [false, false, false];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'محاسب';
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
        actions: const [DashboardGuideButton(roleKey: 'accountant')],
        schedule: ScheduleSlot(scheduleProvider: accountantDayScheduleProvider),
        stats: _FinanceSummary(can: can, moduleOk: moduleOk),
        alertsTitle: 'اہم امور',
        alerts: _FinanceAlerts(can: can, moduleOk: moduleOk),
        quickActionsTitle: 'فوری عمل',
        quickActions: _FinanceQuickActions(can: can, moduleOk: moduleOk),
        todayTasks: _FinanceTasks(
          can: can,
          moduleOk: moduleOk,
          done: _done,
          onToggle: (i, v) => setState(() => _done[i] = v),
        ),
      ),
    );
  }
}

/// "آج کا مالی خلاصہ" — four live cards, each permission-guarded.
class _FinanceSummary extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _FinanceSummary({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayCollection =
        ref.watch(todayCollectionProvider).valueOrNull ?? 0.0;
    final overview = ref.watch(financeOverviewProvider).valueOrNull ??
        const FinanceOverview.zero();
    final feeSummary = ref.watch(feeSummaryProvider).valueOrNull;

    final canSeeFees =
        (can(AppPermissions.viewFees) || can(AppPermissions.collectFees)) &&
            moduleOk('fees');
    final canSeeFinance = can(AppPermissions.viewFinance);

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SlotHeading('آج کا مالی خلاصہ'),
        Row(
          children: [
            if (canSeeFees)
              Expanded(
                child: StatCard(
                  icon: Icons.payments_outlined,
                  label: 'آج کی وصولی',
                  value: formatRs(todayCollection),
                  color: AppColors.success,
                  subtitle:
                      todayCollection == 0 ? 'ابھی کوئی وصولی نہیں' : null,
                  onTap: () => go(const FeeManagementScreen()),
                ),
              ),
            if (canSeeFees) const SizedBox(width: 10),
            if (canSeeFinance)
              Expanded(
                child: StatCard(
                  icon: Icons.shopping_cart_outlined,
                  label: 'آج کے اخراجات',
                  value: formatRs(overview.todayExpenses),
                  color: AppColors.warning,
                  subtitle:
                      overview.todayExpenses == 0 ? 'ابھی کوئی خرچ نہیں' : null,
                  onTap: () => go(const FinanceScreen()),
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
                  icon: Icons.hourglass_empty_outlined,
                  label: 'بقایا فیس',
                  value: formatRs(feeSummary?.totalDue ?? 0),
                  color: AppColors.error,
                  subtitle: (feeSummary != null && feeSummary.pendingCount > 0)
                      ? '${feeSummary.pendingCount} طلبہ کی باقی'
                      : 'کوئی بقایا نہیں',
                  onTap: (feeSummary != null && feeSummary.pendingCount > 0)
                      ? () => go(const FeeManagementScreen())
                      : null,
                ),
              ),
            if (canSeeFees) const SizedBox(width: 10),
            if (canSeeFinance)
              Expanded(
                child: StatCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'نقد رقم',
                  value: formatRs(overview.cashBalance),
                  color: AppColors.primary,
                  onTap: () => go(const FinanceScreen()),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Finance alerts — each with an action.
class _FinanceAlerts extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _FinanceAlerts({required this.can, required this.moduleOk});

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
          icon: Icons.hourglass_empty_outlined,
          message: '${summary.pendingCount} طلبہ کی فیس باقی ہے '
              '(${formatRs(summary.totalDue)})',
          actionLabel: 'وصول کریں',
          onAction: () => go(const FeeManagementScreen()),
        ));
      }
    }

    if (can(AppPermissions.viewFinance)) {
      final overview = ref.watch(financeOverviewProvider).valueOrNull;
      if (overview != null && overview.todayExpenses > 0) {
        alerts.add(AlertCard(
          icon: Icons.shopping_cart_outlined,
          message: 'آج ${formatRs(overview.todayExpenses)} خرچ ہوئے',
          actionLabel: 'دیکھیں',
          onAction: () => go(const FinanceScreen()),
          severity: AlertSeverity.info,
        ));
      }
    }

    if (alerts.isEmpty) return const SizedBox.shrink();
    return Column(children: alerts);
  }
}

/// Finance quick actions in plain Urdu — the detailed accounting screen
/// sits behind "تفصیلی حسابات" (§10).
class _FinanceQuickActions extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _FinanceQuickActions({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final items = [
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
      if (can(AppPermissions.createFinance))
        QuickActionItem(
          icon: Icons.remove_circle_outline,
          label: 'خرچ درج کریں',
          color: AppColors.warning,
          onTap: () => go(const FinanceScreen()),
        ),
      if (can(AppPermissions.createFinance))
        QuickActionItem(
          icon: Icons.add_circle_outline,
          label: 'آمدن درج کریں',
          color: AppColors.success,
          onTap: () => go(const FinanceScreen()),
        ),
      if (can(AppPermissions.viewFinance))
        QuickActionItem(
          icon: Icons.account_balance_wallet_outlined,
          label: 'حساب دیکھیں',
          onTap: () => go(const FinanceScreen()),
        ),
      if (can(AppPermissions.viewReports))
        QuickActionItem(
          icon: Icons.bar_chart_outlined,
          label: 'مالی رپورٹ',
          color: AppColors.info,
          onTap: () => go(const ReportsHubScreen()),
        ),
      if (can(AppPermissions.viewFinance))
        QuickActionItem(
          icon: Icons.account_balance_outlined,
          label: 'تفصیلی حسابات',
          color: AppColors.primary,
          onTap: () => go(const FinanceScreen()),
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();
    return QuickActionGrid(items: items);
  }
}

/// "میرا آج کا کام" for the accountant.
class _FinanceTasks extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;
  final List<bool> done;
  final void Function(int, bool) onToggle;

  const _FinanceTasks({
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

    final todayCollection =
        ref.watch(todayCollectionProvider).valueOrNull ?? 0.0;
    final overview = ref.watch(financeOverviewProvider).valueOrNull;
    final feeSummary = ref.watch(feeSummaryProvider).valueOrNull;

    final entries = <({TodayTask task, VoidCallback? action, int slot})>[];

    if (can(AppPermissions.collectFees) && moduleOk('fees')) {
      entries.add((
        task: TodayTask(
          label: 'آج کی وصولی مکمل کریں',
          subtitle: todayCollection > 0
              ? '${formatRs(todayCollection)} وصول ہو چکے'
              : 'ابھی کوئی وصولی نہیں',
          done: false,
        ),
        action: () => go(const FeeManagementScreen()),
        slot: 0,
      ));
    }
    if (can(AppPermissions.createFinance)) {
      entries.add((
        task: TodayTask(
          label: 'آج کے اخراجات درج کریں',
          subtitle: (overview != null && overview.todayExpenses > 0)
              ? '${formatRs(overview.todayExpenses)} درج ہیں'
              : 'ابھی کوئی خرچ درج نہیں',
          done: false,
        ),
        action: () => go(const FinanceScreen()),
        slot: 1,
      ));
    }
    if (can(AppPermissions.viewFees) && moduleOk('fees')) {
      entries.add((
        task: TodayTask(
          label: 'بقایا فیس کا جائزہ لیں',
          subtitle: feeSummary == null
              ? null
              : '${formatRs(feeSummary.totalDue)} باقی',
          done: false,
        ),
        action: () => go(const FeeManagementScreen()),
        slot: 2,
      ));
    }

    if (entries.isEmpty) return const SizedBox.shrink();
    return TodayTasks(
      tasks: [
        for (final e in entries)
          e.task.copyWith(
            done: e.slot == 0
                ? (todayCollection > 0 || done[e.slot])
                : e.slot == 1
                    ? ((overview?.todayExpenses ?? 0) > 0 || done[e.slot])
                    : done[e.slot],
          ),
      ],
      onToggle: (i, v) => onToggle(entries[i].slot, v),
      rowActions: [for (final e in entries) e.action],
    );
  }
}
