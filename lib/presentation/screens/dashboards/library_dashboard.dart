/// کتب خانہ ڈیش بورڈ — §14 (Phase 7b)
/// Library dashboard (librarian).
///
/// * Stats: کل کتب، جاری شدہ، واپسی باقی — all from real queries
///   ([libraryOverviewProvider]).
/// * Quick actions: کتب، کتاب جاری کریں، کتاب واپس لیں، تلاش کریں،
///   رپورٹ — issue/return actions reuse the real LibraryScreen.

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
import '../admin/library_screen.dart';
import '../reports/reports_hub_screen.dart';

class LibraryDashboardScreen extends ConsumerWidget {
  const LibraryDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'لائبریرین';
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final madrasaName = branding?.displayName() ?? 'مدرسہ 360';

    final roleService = ref.watch(roleServiceProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);

    final enabledModules = ref.watch(tenantModulesProvider).valueOrNull;
    bool moduleOk(String module) =>
        enabledModules == null || enabledModules.contains(module);

    bool can(String permission) =>
        ref.watch(hasPermissionProvider(permission));

    return FutureBuilder<String>(
      future: roleKeys.isEmpty
          ? Future.value('')
          : roleService.roleUrduLabel(roleKeys.first),
      builder: (context, snap) => DashboardScaffold(
        greeting: 'السلام علیکم ورحمۃ اللہ',
        userName: userName,
        roleLabel: snap.data?.isEmpty == true ? null : snap.data,
        madrasaName: madrasaName,
        stats: _LibraryStats(can: can, moduleOk: moduleOk),
        alertsTitle: 'اہم امور',
        alerts: _LibraryAlerts(can: can, moduleOk: moduleOk),
        quickActionsTitle: 'فوری عمل',
        quickActions: _LibraryQuickActions(can: can, moduleOk: moduleOk),
      ),
    );
  }
}

/// Library stat cards — every number from real book/issue rows.
class _LibraryStats extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _LibraryStats({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!can(AppPermissions.viewLibrary) || !moduleOk('library')) {
      return const SizedBox.shrink();
    }

    final overview = ref.watch(libraryOverviewProvider).valueOrNull ??
        const LibraryOverview.zero();

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SlotHeading('کتب خانے کا جائزہ'),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.menu_book_outlined,
                label: 'کل کتب',
                value: '${overview.totalBooks}',
                color: AppColors.primary,
                subtitle: overview.totalBooks == 0
                    ? 'ابھی کوئی کتاب درج نہیں'
                    : null,
                onTap: () => go(const LibraryScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                icon: Icons.outbox_outlined,
                label: 'جاری شدہ',
                value: '${overview.issued}',
                color: AppColors.info,
                onTap: () => go(const LibraryScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.assignment_return_outlined,
                label: 'واپسی باقی',
                value: '${overview.overdue}',
                color: overview.overdue > 0
                    ? AppColors.warning
                    : AppColors.success,
                subtitle: overview.overdue == 0
                    ? 'کوئی تاخیر نہیں'
                    : 'تاخیر سے واپسی',
                onTap: overview.overdue > 0
                    ? () => go(const LibraryScreen())
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Library alerts — each with an action.
class _LibraryAlerts extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _LibraryAlerts({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!can(AppPermissions.viewLibrary) || !moduleOk('library')) {
      return const SizedBox.shrink();
    }

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final overview = ref.watch(libraryOverviewProvider).valueOrNull;
    if (overview == null || overview.overdue == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        AlertCard(
          icon: Icons.assignment_return_outlined,
          message: overview.overdue == 1
              ? '1 کتاب کی واپسی میں تاخیر ہے'
              : '${overview.overdue} کتابوں کی واپسی میں تاخیر ہے',
          actionLabel: 'دیکھیں',
          onAction: () => go(const LibraryScreen()),
        ),
      ],
    );
  }
}

/// Library quick actions — each gated on its own permission.
class _LibraryQuickActions extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _LibraryQuickActions({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!can(AppPermissions.viewLibrary) || !moduleOk('library')) {
      return const SizedBox.shrink();
    }

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final canManage = can(AppPermissions.manageLibrary);

    final items = [
      QuickActionItem(
        icon: Icons.menu_book_outlined,
        label: 'کتب',
        onTap: () => go(const LibraryScreen()),
      ),
      if (canManage)
        QuickActionItem(
          icon: Icons.outbox_outlined,
          label: 'کتاب جاری کریں',
          color: AppColors.success,
          onTap: () => go(const LibraryScreen()),
        ),
      if (canManage)
        QuickActionItem(
          icon: Icons.inbox_outlined,
          label: 'کتاب واپس لیں',
          color: AppColors.info,
          onTap: () => go(const LibraryScreen()),
        ),
      QuickActionItem(
        icon: Icons.search_outlined,
        label: 'تلاش کریں',
        onTap: () => go(const LibraryScreen()),
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
