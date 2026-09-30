/// دارالاقامہ ڈیش بورڈ — §13 (Phase 7b)
/// Hostel dashboard (nazim_darul_iqama, warden, hostel_manager).
///
/// HONEST EMPTY STATE: there is no hostel data source in the app yet
/// (no hostel tables, no residents, no rooms). The cards say so plainly
/// ('—' + 'ابھی دستیاب نہیں') instead of inventing numbers. Quick
/// actions point only at real screens (حاضری، رپورٹ); hostel-specific
/// actions are omitted entirely — never "coming soon" buttons.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/services/role_service.dart';
import '../../widgets/dashboard/dashboard_scaffold.dart';
import '../../widgets/dashboard/day_timeline.dart';
import '../../widgets/dashboard/quick_actions.dart';
import '../common/dashboard_guide_screen.dart';
import '../../widgets/dashboard/dashboard_stat_card.dart';
import '../../../core/design/m360.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../reports/reports_hub_screen.dart';
import '../teacher/attendance_screen.dart';

class HostelDashboardScreen extends ConsumerWidget {
  const HostelDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Display name contract: local profile edit wins; never an email.
    final userName = ref.watch(displayNameProvider('وارڈن'));

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
        actions: const [DashboardGuideButton(roleKey: 'hostel')],
        schedule: const DayTimeline(),
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
      children: const [
        M360SectionHeader(title: 'دارالاقامہ کا جائزہ'),
        Row(
          children: [
            Expanded(
              child: DashboardStatCard(
                icon: Icons.people_outline,
                label: 'رہائشی طلبہ',
                value: '—',
                color: AppColors.textSecondary,
                subtitle: 'ابھی دستیاب نہیں',
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: DashboardStatCard(
                icon: Icons.check_circle_outline,
                label: 'آج حاضر',
                value: '—',
                color: AppColors.textSecondary,
                subtitle: 'ابھی دستیاب نہیں',
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DashboardStatCard(
                icon: Icons.time_to_leave_outlined,
                label: 'چھٹی پر',
                value: '—',
                color: AppColors.textSecondary,
                subtitle: 'ابھی دستیاب نہیں',
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: DashboardStatCard(
                icon: Icons.cancel_outlined,
                label: 'غیر حاضر',
                value: '—',
                color: AppColors.textSecondary,
                subtitle: 'ابھی دستیاب نہیں',
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        // Honest backend-unavailable state (BackendUnavailableScreen
        // pattern): no hostel tables exist yet — never a "جلد آرہا ہے"
        // marketing placeholder.
        M360EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'دارالاقامہ کا ریکارڈ دستیاب نہیں',
          description:
              'طلبہ، کمرے اور چھٹی کا ریکارڈ ابھی بیک اینڈ سے منسلک نہیں ہے',
        ),
      ],
    );
  }
}

/// Hostel quick actions. حاضری and رپورٹ reuse real screens;
/// hostel-specific actions (رہائشی طلبہ، کمرے، چھٹی، وارڈن) have no data
/// source, so they are omitted — never "coming soon" buttons.
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

    final items = [
      if (can(AppPermissions.viewAttendance) ||
          can(AppPermissions.markAttendance))
        QuickActionItem(
          icon: Icons.fact_check_outlined,
          label: 'حاضری',
          onTap: () => go(const AttendanceScreen()),
        ),
      if (can(AppPermissions.viewReports))
        QuickActionItem(
          icon: Icons.bar_chart_outlined,
          label: 'رپورٹ',
          onTap: () => go(const ReportsHubScreen()),
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();
    return QuickActionGrid(items: items);
  }
}
