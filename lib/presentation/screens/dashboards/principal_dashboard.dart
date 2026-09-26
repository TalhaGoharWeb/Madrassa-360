/// پرنسپل ڈیش بورڈ — §§4–6
/// Principal dashboard (Phase 7a).
///
/// * "آج مدرسے کا حال": طلبہ، اساتذہ، آج حاضری ٪، آج کی وصولی — every
///   number from real providers ([dashboardStatsProvider],
///   [todayCollectionProvider]). Cards pair numbers with the actionable
///   alert (§31 smart dashboard).
/// * "اہم امور": فیس باقی، حاضری نامکمل، نتائج باقی، نئے اعلانات —
///   every alert carries an action (§32).
/// * Quick actions + sections render ONLY for held permissions AND
///   enabled modules ([hasPermissionProvider] / [tenantModulesProvider]).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_permissions.dart';
import '../../core/constants/app_typography.dart';
import '../../core/services/role_service.dart';
import '../../core/widgets/dashboard/alert_card.dart';
import '../../core/widgets/dashboard/dashboard_scaffold.dart';
import '../../core/widgets/dashboard/dashboard_section.dart';
import '../../core/widgets/dashboard/quick_actions.dart';
import '../../core/widgets/dashboard/stat_card.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../providers/announcement_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/fee_provider.dart';
import '../../providers/dashboard_data_provider.dart';
import '../../providers/tenant_branding_provider.dart';
import '../admin/darja_screen.dart';
import '../admin/fee_management_screen.dart';
import '../admin/finance_screen.dart';
import '../admin/library_screen.dart';
import '../admin/staff_list_screen.dart';
import '../admin/student_list_screen.dart';
import '../admin/user_management_screen.dart';
import '../common/announcements_screen.dart';
import '../reports/reports_hub_screen.dart';
import '../teacher/attendance_screen.dart';
import '../teacher/results_screen.dart';
import 'role_home.dart' show ComingSoonScreen;

class PrincipalDashboardScreen extends ConsumerWidget {
  const PrincipalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'مہتمم';
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final madrasaName = branding?.displayName() ?? 'مدرسہ 360';

    final roleService = ref.watch(roleServiceProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);

    // Module gating: null (still loading) → don't hide, avoid flicker.
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
        stats: _TodayOverview(can: can, moduleOk: moduleOk),
        alertsTitle: 'اہم امور',
        alerts: _Alerts(can: can, moduleOk: moduleOk),
        quickActionsTitle: 'فوری عمل',
        quickActions: _QuickActions(can: can, moduleOk: moduleOk),
        sections: _sections(context, can, moduleOk),
      ),
    );
  }

  /// Permission+module gated sections (§§4–6): مدرسے کا جائزہ، تعلیم،
  /// انتظامیہ، مالیات، دارالاقامہ، لائبریری.
  List<Widget> _sections(
    BuildContext context,
    bool Function(String) can,
    bool Function(String) moduleOk,
  ) {
    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final sections = <Widget>[];

    // مدرسے کا جائزہ
    final overviewTiles = [
      if (can(AppPermissions.viewStudents))
        SectionTile(
          icon: Icons.people_outline,
          label: 'طلبہ',
          onTap: () => go(const StudentListScreen()),
        ),
      if (can(AppPermissions.viewTeachers))
        SectionTile(
          icon: Icons.person_outline,
          label: 'اساتذہ',
          onTap: () => go(const StaffListScreen()),
        ),
      if (can(AppPermissions.viewAttendance))
        SectionTile(
          icon: Icons.fact_check_outlined,
          label: 'حاضری',
          onTap: () => go(const AttendanceScreen()),
        ),
      if (can(AppPermissions.viewDarjas) && moduleOk('academics'))
        SectionTile(
          icon: Icons.school_outlined,
          label: 'درجات',
          onTap: () => go(const DarjaScreen()),
        ),
    ];
    if (overviewTiles.isNotEmpty) {
      sections.add(DashboardSection(
        title: 'مدرسے کا جائزہ',
        icon: Icons.dashboard_outlined,
        tiles: overviewTiles,
      ));
    }

    // تعلیم
    final taleemTiles = [
      if (can(AppPermissions.viewExams))
        SectionTile(
          icon: Icons.assignment_outlined,
          label: 'امتحانات',
          onTap: () => go(const ComingSoonScreen(title: 'امتحانات')),
        ),
      if (can(AppPermissions.viewResults))
        SectionTile(
          icon: Icons.assessment_outlined,
          label: 'نتائج',
          onTap: () => go(const ResultsScreen()),
        ),
    ];
    if (taleemTiles.isNotEmpty) {
      sections.add(DashboardSection(
        title: 'تعلیم',
        icon: Icons.menu_book_outlined,
        tiles: taleemTiles,
      ));
    }

    // انتظامیہ
    final intizamiaTiles = [
      if (can(AppPermissions.viewStaff))
        SectionTile(
          icon: Icons.badge_outlined,
          label: 'عملہ',
          onTap: () => go(const StaffListScreen()),
        ),
      if (can(AppPermissions.viewUsers))
        SectionTile(
          icon: Icons.manage_accounts_outlined,
          label: 'صارفین',
          onTap: () => go(const UserManagementScreen()),
        ),
      if (can(AppPermissions.viewAnnouncements))
        SectionTile(
          icon: Icons.campaign_outlined,
          label: 'اعلانات',
          onTap: () => go(const AnnouncementsScreen()),
        ),
    ];
    if (intizamiaTiles.isNotEmpty) {
      sections.add(DashboardSection(
        title: 'انتظامیہ',
        icon: Icons.business_outlined,
        tiles: intizamiaTiles,
      ));
    }

    // مالیات
    final maliyatTiles = [
      if (can(AppPermissions.viewFees) && moduleOk('fees'))
        SectionTile(
          icon: Icons.payments_outlined,
          label: 'فیس',
          onTap: () => go(const FeeManagementScreen()),
        ),
      if (can(AppPermissions.viewFinance))
        SectionTile(
          icon: Icons.account_balance_outlined,
          label: 'مالی حساب',
          onTap: () => go(const FinanceScreen()),
        ),
      if (can(AppPermissions.viewReports))
        SectionTile(
          icon: Icons.bar_chart_outlined,
          label: 'رپورٹس',
          onTap: () => go(const ReportsHubScreen()),
        ),
    ];
    if (maliyatTiles.isNotEmpty) {
      sections.add(DashboardSection(
        title: 'مالیات',
        icon: Icons.account_balance_wallet_outlined,
        tiles: maliyatTiles,
      ));
    }

    // دارالاقامہ — module-gated; no hostel screen exists yet, so the tile
    // lands on a clean "جلد آ رہا ہے" placeholder (never a dead button).
    if (can(AppPermissions.viewHostel) && moduleOk('hostel')) {
      sections.add(DashboardSection(
        title: 'دارالاقامہ',
        icon: Icons.hotel_outlined,
        initiallyExpanded: false,
        tiles: [
          SectionTile(
            icon: Icons.hotel_outlined,
            label: 'دارالاقامہ',
            onTap: () => go(const ComingSoonScreen(title: 'دارالاقامہ')),
          ),
        ],
      ));
    }

    // لائبریری
    if (can(AppPermissions.viewLibrary) && moduleOk('library')) {
      sections.add(DashboardSection(
        title: 'لائبریری',
        icon: Icons.local_library_outlined,
        initiallyExpanded: false,
        tiles: [
          SectionTile(
            icon: Icons.local_library_outlined,
            label: 'کتب خانہ',
            onTap: () => go(const LibraryScreen()),
          ),
        ],
      ));
    }

    return sections;
  }
}

/// "آج مدرسے کا حال" — four live stat cards. Numbers pair with their
/// actionable alert (§31): e.g. the طلبہ card links to pending fees.
class _TodayOverview extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _TodayOverview({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider).valueOrNull ??
        const DashboardStats.zero();
    final feeSummary = ref.watch(feeSummaryProvider).valueOrNull;
    final todayCollection = ref.watch(todayCollectionProvider).valueOrNull ?? 0.0;

    final marked = stats.todayPresent + stats.todayAbsent + stats.todayLeave;
    final attendancePct =
        marked == 0 ? null : (stats.todayPresent * 100 / marked);

    final canSeeFees = (can(AppPermissions.viewFees) ||
            can(AppPermissions.collectFees)) &&
        moduleOk('fees');
    final canSeeAttendance = can(AppPermissions.viewAttendance) ||
        can(AppPermissions.markAttendance);

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'آج مدرسے کا حال',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.people_outline,
                label: 'طلبہ',
                value: '${stats.totalStudents}',
                color: AppColors.primary,
                // §31: number paired with its actionable alert.
                subtitle: (feeSummary != null &&
                        feeSummary.pendingCount > 0 &&
                        canSeeFees)
                    ? '${feeSummary.pendingCount} کی فیس باقی — دیکھیں'
                    : null,
                onTap: (feeSummary != null &&
                        feeSummary.pendingCount > 0 &&
                        canSeeFees)
                    ? () => go(const FeeManagementScreen())
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                icon: Icons.person_outline,
                label: 'اساتذہ',
                value: '${stats.totalTeachers}',
                color: AppColors.info,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (canSeeAttendance)
              Expanded(
                child: StatCard(
                  icon: Icons.fact_check_outlined,
                  label: 'آج حاضری',
                  value: attendancePct == null
                      ? '—'
                      : '${attendancePct.round()}٪',
                  color: AppColors.present,
                  subtitle: attendancePct == null ? 'ابھی شروع نہیں ہوئی' : null,
                  onTap: attendancePct == null
                      ? () => go(const AttendanceScreen())
                      : null,
                ),
              ),
            if (canSeeAttendance) const SizedBox(width: 10),
            if (canSeeFees)
              Expanded(
                child: StatCard(
                  icon: Icons.payments_outlined,
                  label: 'آج کی وصولی',
                  value: _formatRs(todayCollection),
                  color: AppColors.success,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// "اہم امور" — clickable alerts, each with an action (§32).
class _Alerts extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _Alerts({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = <Widget>[];

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    // فیس باقی
    if ((can(AppPermissions.viewFees) || can(AppPermissions.collectFees)) &&
        moduleOk('fees')) {
      final summary = ref.watch(feeSummaryProvider).valueOrNull;
      if (summary != null && summary.pendingCount > 0) {
        alerts.add(AlertCard(
          icon: Icons.payments_outlined,
          message:
              '${summary.pendingCount} طلبہ کی فیس باقی ہے (${_formatRs(summary.totalDue)})',
          actionLabel: 'دیکھیں',
          onAction: () => go(const FeeManagementScreen()),
        ));
      }
    }

    // حاضری نامکمل
    if (can(AppPermissions.viewAttendance) ||
        can(AppPermissions.markAttendance)) {
      final stats = ref.watch(dashboardStatsProvider).valueOrNull;
      final marked = stats == null
          ? -1
          : (stats.todayPresent + stats.todayAbsent + stats.todayLeave);
      if (marked == 0) {
        alerts.add(AlertCard(
          icon: Icons.fact_check_outlined,
          message: 'آج کی حاضری ابھی شروع نہیں ہوئی',
          actionLabel: 'حاضری لگائیں',
          onAction: () => go(const AttendanceScreen()),
        ));
      }
    }

    // نتائج باقی
    if (can(AppPermissions.viewResults) || can(AppPermissions.enterResults)) {
      final pending = ref.watch(examsWithoutResultsProvider).valueOrNull;
      if (pending != null && pending.isNotEmpty) {
        alerts.add(AlertCard(
          icon: Icons.assessment_outlined,
          message: pending.length == 1
              ? '«${pending.first.name}» کے نتائج درج نہیں ہوئے'
              : '${pending.length} امتحانات کے نتائج درج نہیں ہوئے',
          actionLabel: 'درج کریں',
          onAction: () => go(const ResultsScreen()),
          severity: AlertSeverity.info,
        ));
      }
    }

    // نئے اعلانات (last 7 days — the app tracks no read state, so "new"
    // honestly means "recently posted").
    if (can(AppPermissions.viewAnnouncements)) {
      final announcements = ref.watch(announcementListProvider);
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final recent = announcements
          .where((a) => a.createdAt != null && a.createdAt!.isAfter(cutoff))
          .length;
      if (recent > 0) {
        alerts.add(AlertCard(
          icon: Icons.campaign_outlined,
          message: 'پچھلے 7 دنوں میں $recent نئے اعلانات',
          actionLabel: 'پڑھیں',
          onAction: () => go(const AnnouncementsScreen()),
          severity: AlertSeverity.info,
        ));
      }
    }

    if (alerts.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'سب امور مکمل ہیں — کوئی زیر التواء کام نہیں',
                style: AppTypography.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return Column(children: alerts);
  }
}

/// Quick actions — each gated on its own permission.
class _QuickActions extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _QuickActions({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final items = [
      if (can(AppPermissions.createStudents))
        QuickActionItem(
          icon: Icons.person_add_outlined,
          label: 'طالب علم داخل کریں',
          onTap: () => go(const StudentListScreen()),
        ),
      if (can(AppPermissions.createTeachers))
        QuickActionItem(
          icon: Icons.group_add_outlined,
          label: 'استاد شامل کریں',
          onTap: () => go(const StaffListScreen()),
        ),
      if (can(AppPermissions.sendNotifications))
        QuickActionItem(
          icon: Icons.campaign_outlined,
          label: 'اعلان کریں',
          color: AppColors.info,
          onTap: () => go(const AnnouncementsScreen()),
        ),
      if (can(AppPermissions.collectFees) && moduleOk('fees'))
        QuickActionItem(
          icon: Icons.payments_outlined,
          label: 'فیس وصول کریں',
          color: AppColors.success,
          onTap: () => go(const FeeManagementScreen()),
        ),
      if (can(AppPermissions.createExams))
        QuickActionItem(
          icon: Icons.assignment_outlined,
          label: 'امتحان بنائیں',
          color: AppColors.warning,
          onTap: () => go(const ComingSoonScreen(title: 'امتحانات')),
        ),
      if (can(AppPermissions.viewReports))
        QuickActionItem(
          icon: Icons.bar_chart_outlined,
          label: 'رپورٹ بنائیں',
          color: AppColors.info,
          onTap: () => go(const ReportsHubScreen()),
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();
    return QuickActionGrid(items: items);
  }
}

/// Rs formatting with Pakistani digit grouping (1,25,000).
String _formatRs(double amount) {
  final s = amount.round().toString();
  if (s.length <= 3) return 'Rs $s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return 'Rs ${parts.join(',')},$last3';
}
