/// دارالاقامہ ڈیش بورڈ — §13 (Phase 7b)
/// Hostel dashboard (nazim_darul_iqama, warden, hostel_manager).
///
/// HONEST EMPTY STATE: there is no hostel data source in the app yet
/// (no hostel tables, no residents, no rooms). The cards say so plainly
/// ('—' + 'ابھی دستیاب نہیں') instead of inventing numbers, and every
/// action lands on a titled "جلد آ رہا ہے" screen — except حاضری and
/// رپورٹ, which have real screens (AttendanceScreen, ReportsHubScreen).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/role_service.dart';
import '../../widgets/dashboard/dashboard_scaffold.dart';
import '../../widgets/dashboard/quick_actions.dart';
import '../../widgets/dashboard/slot_heading.dart';
import '../../widgets/dashboard/stat_card.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../reports/reports_hub_screen.dart';
import '../teacher/attendance_screen.dart';
import 'role_home.dart' show ComingSoonScreen;

class HostelDashboardScreen extends ConsumerWidget {
  const HostelDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'وارڈن';
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
        stats: _HostelStats(can: can, moduleOk: moduleOk),
        quickActionsTitle: 'فوری عمل',
        quickActions: _HostelQuickActions(can: can, moduleOk: moduleOk),
      ),
    );
  }
}

/// Hostel stat cards — honest empty states until a hostel module exists.
class _HostelStats extends StatelessWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _HostelStats({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context) {
    if (!can(AppPermissions.viewHostel) || !moduleOk('hostel')) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SlotHeading('دارالاقامہ کا جائزہ'),
        const Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.people_outline,
                label: 'رہائشی طلبہ',
                value: '—',
                color: AppColors.textSecondary,
                subtitle: 'ابھی دستیاب نہیں',
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: StatCard(
                icon: Icons.check_circle_outline,
                label: 'آج حاضر',
                value: '—',
                color: AppColors.textSecondary,
                subtitle: 'ابھی دستیاب نہیں',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.time_to_leave_outlined,
                label: 'چھٹی پر',
                value: '—',
                color: AppColors.textSecondary,
                subtitle: 'ابھی دستیاب نہیں',
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: StatCard(
                icon: Icons.cancel_outlined,
                label: 'غیر حاضر',
                value: '—',
                color: AppColors.textSecondary,
                subtitle: 'ابھی دستیاب نہیں',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.info),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'دارالاقامہ کا ریکارڈ (طلبہ، کمرے، چھٹی) ابھی اس ایپ '
                  'میں موجود نہیں — یہ حصہ جلد مکمل ہوگا',
                  style: AppTypography.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hostel quick actions. حاضری and رپورٹ reuse real screens; the rest
/// are clean "جلد آ رہا ہے" placeholders (never dead buttons).
class _HostelQuickActions extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _HostelQuickActions({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!can(AppPermissions.viewHostel) || !moduleOk('hostel')) {
      return const SizedBox.shrink();
    }

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final canManage = can(AppPermissions.manageHostel);

    final items = [
      QuickActionItem(
        icon: Icons.people_outline,
        label: 'رہائشی طلبہ',
        onTap: () => go(const ComingSoonScreen(title: 'رہائشی طلبہ')),
      ),
      QuickActionItem(
        icon: Icons.meeting_room_outlined,
        label: 'کمرے',
        onTap: () => go(const ComingSoonScreen(title: 'کمرے')),
      ),
      if (canManage)
        QuickActionItem(
          icon: Icons.time_to_leave_outlined,
          label: 'چھٹی',
          onTap: () => go(const ComingSoonScreen(title: 'چھٹی')),
        ),
      if (can(AppPermissions.viewAttendance) ||
          can(AppPermissions.markAttendance))
        QuickActionItem(
          icon: Icons.fact_check_outlined,
          label: 'حاضری',
          color: AppColors.success,
          onTap: () => go(const AttendanceScreen()),
        ),
      if (canManage)
        QuickActionItem(
          icon: Icons.shield_outlined,
          label: 'وارڈن',
          onTap: () => go(const ComingSoonScreen(title: 'وارڈن')),
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
