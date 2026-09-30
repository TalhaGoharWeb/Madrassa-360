/// منتظم ڈیش بورڈ — m360 redesign (Phase 10)
///
/// Admin Dashboard Screen with Statistics and Overview.
///
/// Every number comes from [dashboardStatsProvider] — live, tenant-scoped
/// queries. No hard-coded demo figures. Navigation cards are gated by BOTH
/// the user's permissions AND the tenant's enabled modules
/// ([tenantModulesProvider]). Institution identity (name/logo) comes from
/// [tenantBrandingProvider]. The one change vs the legacy screen: the
/// «عملہ» module card now opens the real [StaffListScreen] (it previously
/// opened an empty placeholder).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:madrasa_360/core/design/m360.dart';

import '../../../core/config/role_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/tenant_logo.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/admin_dashboard_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import 'user_management_screen.dart';
import 'darja_screen.dart';
import 'library_screen.dart';
import 'staff_list_screen.dart';
import '../finance/finance_hub_screen.dart'
    show FinanceHubScreen, FinanceSection;
import '../common/announcements_screen.dart';
import '../teacher/attendance_screen.dart';
import '../teacher/results_screen.dart';
import '../common/notifications_screen.dart';
import '../common/dashboard_guide_screen.dart';
import '../reports/reports_hub_screen.dart';
import 'backup_screen.dart';

/// منتظم ڈیش بورڈ
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final authState = ref.watch(authProvider);
      final perms = ref.watch(userPermissionsProvider);
      final role = authState.user?.role ?? UserRole.teacher;
      final roleConfig = role.config;

      final adminName = authState.user?.name ?? 'اسٹاف';

      // Live tenant-scoped numbers (zeros while loading/offline).
      final stats = ref.watch(dashboardStatsProvider).valueOrNull ??
          const DashboardStats.zero();

      // Module gating. Null = modules not loaded yet → do not filter, so
      // cards don't flicker while the tenant resolves.
      final enabledModules = ref.watch(tenantModulesProvider).valueOrNull;
      bool moduleOk(String module) =>
          enabledModules == null || enabledModules.contains(module);

      final branding = ref.watch(tenantBrandingProvider).valueOrNull;

      return PageContainer(
        header: PageHeader(
          title:
              branding == null ? AppStrings.dashboard : branding.displayName(),
          breadcrumb: 'ہوم',
          description: 'آج کی صورتحال ایک نظر میں',
          actions: [
            const DashboardGuideButton(roleKey: 'admin'),
            M360IconButton(
              icon: Icons.notifications_outlined,
              tooltip: 'اطلاعات',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationsScreen(),
                ),
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Role-aware welcome header (shows the tenant name)
            _buildWelcomeHeader(adminName, roleConfig, branding?.displayName()),

            // Stats — shown only for permitted AND enabled modules
            const M360SectionHeader(title: 'اہم اعداد و شمار'),
            _buildPermissionFilteredStats(stats, perms, moduleOk),

            // User Management card — only for managers
            if (perms.contains(AppPermissions.viewUsers))
              _buildUserManagementCard(context),

            // Module shortcuts — filtered by permissions AND modules
            _buildModulesSection(context, perms, moduleOk),

            // Fee progress — only if user can view fees
            if (perms.contains(AppPermissions.viewFees))
              _buildFeeProgress(stats),

            // Attendance overview — only if user can view attendance
            if (perms.contains(AppPermissions.viewAttendance))
              _buildAttendanceOverview(stats),

            // Recent activities (real events from the tenant's data)
            const M360SectionHeader(title: 'حالیہ سرگرمیاں'),
            _buildRecentActivities(_filteredActivities(stats, perms)),
          ],
        ),
      );
    });
  }

  Widget _buildWelcomeHeader(
      String userName, RoleConfig config, String? tenantName) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: config.gradient,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: config.gradient.first.withValues(alpha: 0.35),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'السلام علیکم',
                  textDirection: TextDirection.rtl,
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userName,
                  textDirection: TextDirection.rtl,
                  style: AppTypography.headingSmall.copyWith(
                    color: Colors.white,
                  ),
                ),
                if (tenantName != null && tenantName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tenantName,
                    textDirection: TextDirection.rtl,
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.white70,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(config.icon, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        config.urduTitle,
                        textDirection: TextDirection.rtl,
                        style: AppTypography.labelMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30, width: 2),
            ),
            // Tenant logo; neutral mark while loading/unset.
            child: const TenantLogo(size: 66, circular: true),
          ),
        ],
      ),
    );
  }

  /// Returns only the real activity entries relevant to the current user's
  /// permissions. Empty feed renders as an empty section (never fake rows).
  List<DashboardActivity> _filteredActivities(
      DashboardStats stats, Set<String> perms) {
    return stats.recentActivities.where((a) {
      switch (a.iconKey) {
        case 'fee':
          return perms.contains(AppPermissions.viewFees);
        case 'attendance':
          return perms.contains(AppPermissions.viewAttendance);
        case 'admission':
          return perms.contains(AppPermissions.viewStudents);
        case 'result':
          return perms.contains(AppPermissions.viewResults);
        default:
          return true;
      }
    }).toList();
  }

  /// Shows stat cards filtered to what the user is allowed to see AND what
  /// the tenant has enabled. All values are live tenant-scoped counts.
  Widget _buildPermissionFilteredStats(
    DashboardStats stats,
    Set<String> perms,
    bool Function(String) moduleOk,
  ) {
    final cards = <Widget>[];

    if (perms.contains(AppPermissions.viewStudents) && moduleOk('students')) {
      cards.add(M360StatCard(
        icon: Icons.people,
        label: 'کل طلباء',
        value: '${stats.totalStudents}',
        iconBackground: AppColors.primary.withValues(alpha: 0.12),
      ));
    }
    if (perms.contains(AppPermissions.viewStaff) &&
        (moduleOk('teachers') || moduleOk('staff'))) {
      cards.add(M360StatCard(
        icon: Icons.school,
        label: 'اساتذہ',
        value: '${stats.totalTeachers}',
        iconBackground: AppColors.info.withValues(alpha: 0.12),
      ));
    }
    if (perms.contains(AppPermissions.viewDarjas) && moduleOk('academics')) {
      cards.add(M360StatCard(
        icon: Icons.class_,
        label: 'جماعتیں',
        value: '${stats.totalClasses}',
        iconBackground: AppColors.warning.withValues(alpha: 0.12),
      ));
    }
    if (perms.contains(AppPermissions.viewFees) && moduleOk('fees')) {
      cards.add(M360StatCard(
        icon: Icons.account_balance_wallet,
        label: 'واجب الادا',
        value: formatPK(stats.pendingFees),
        iconBackground: AppColors.error.withValues(alpha: 0.12),
        valueColor: AppColors.error,
      ));
    }
    if (perms.contains(AppPermissions.viewAttendance) &&
        moduleOk('attendance')) {
      cards.add(M360StatCard(
        icon: Icons.fact_check,
        label: 'آج حاضر',
        value: '${stats.todayPresent}',
        iconBackground: AppColors.success.withValues(alpha: 0.12),
      ));
    }
    if (perms.contains(AppPermissions.viewStaff) &&
        perms.contains(AppPermissions.createStaff) &&
        moduleOk('staff')) {
      cards.add(M360StatCard(
        icon: Icons.person_add,
        label: 'کل عملہ',
        value: '${stats.totalStaff}',
        iconBackground: AppColors.success.withValues(alpha: 0.12),
      ));
    }

    if (cards.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      rows.add(Row(children: [
        Expanded(child: cards[i]),
        const SizedBox(width: 12),
        Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
      ]));
      if (i + 2 < cards.length) rows.add(const SizedBox(height: 12));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: rows),
    );
  }

  Widget _buildModulesSection(
    BuildContext context,
    Set<String> perms,
    bool Function(String) moduleOk,
  ) {
    // All possible modules with their required permission AND tenant module.
    final allModules = [
      _ModuleDef(
        label: 'درجات',
        subtitle: 'جماعتیں و سیکشن',
        icon: Icons.class_outlined,
        color: AppColors.primary,
        screen: const DarjaScreen(),
        requiredPerm: AppPermissions.viewDarjas,
        module: 'academics',
      ),
      _ModuleDef(
        label: 'اعلانات',
        subtitle: 'پیغامات نشر کریں',
        icon: Icons.campaign_outlined,
        color: AppColors.success,
        screen: const AnnouncementsScreen(),
        requiredPerm: AppPermissions.viewAnnouncements,
        module: 'notifications',
      ),
      _ModuleDef(
        label: 'کتب خانہ',
        subtitle: 'کتابیں اور اجراء',
        icon: Icons.menu_book_outlined,
        color: AppColors.info,
        screen: const LibraryScreen(),
        requiredPerm: AppPermissions.viewLibrary,
        module: 'library',
      ),
      _ModuleDef(
        label: 'مالیات',
        subtitle: 'عطیات و اخراجات',
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.warning,
        screen: const FinanceHubScreen(section: FinanceSection.dashboard),
        requiredPerm: AppPermissions.viewFinance,
        module: 'finance',
      ),
      _ModuleDef(
        label: 'حاضری',
        subtitle: 'حاضری لگائیں',
        icon: Icons.how_to_reg_outlined,
        color: AppColors.primaryDark,
        screen: const AttendanceScreen(),
        requiredPerm: AppPermissions.markAttendance,
        module: 'attendance',
      ),
      _ModuleDef(
        label: 'نتائج',
        subtitle: 'امتحانی نتائج',
        icon: Icons.assessment_outlined,
        color: AppColors.success,
        screen: const ResultsScreen(),
        requiredPerm: AppPermissions.viewResults,
        module: 'results',
      ),
      _ModuleDef(
        label: 'عملہ',
        subtitle: 'اسٹاف انتظام',
        icon: Icons.badge_outlined,
        color: AppColors.textSecondary,
        screen: const StaffListScreen(),
        requiredPerm: AppPermissions.viewStaff,
        module: 'staff',
      ),
      // Offline-first reporting, one-file backup, notifications inbox.
      // Reports are tenant-module-gated; backup is a core admin function
      // (never module-gated); the inbox follows the notifications module
      // like announcements do.
      _ModuleDef(
        label: 'رپورٹس',
        subtitle: 'رپورٹیں بنائیں اور پرنٹ کریں',
        icon: Icons.bar_chart_outlined,
        color: AppColors.info,
        screen: const ReportsHubScreen(),
        requiredPerm: AppPermissions.viewReports,
        module: 'reports',
      ),
      _ModuleDef(
        label: 'بیک اپ',
        subtitle: 'مکمل ڈیٹا ایک فائل میں',
        icon: Icons.backup_outlined,
        color: AppColors.warning,
        screen: const BackupScreen(),
        requiredPerm: AppPermissions.manageSettings,
      ),
      _ModuleDef(
        label: 'اطلاعات',
        subtitle: 'پیغامات دیکھیں',
        icon: Icons.notifications_outlined,
        color: AppColors.primary,
        screen: const NotificationsScreen(),
        requiredPerm: AppPermissions.viewAnnouncements,
        module: 'notifications',
      ),
    ];

    // A card shows only when the user is permitted AND the tenant has the
    // module enabled. A tenant with only students+attendance+fees never
    // sees library/hostel/finance cards.
    final visible = allModules
        .where((m) =>
            perms.contains(m.requiredPerm) &&
            (m.module == null || moduleOk(m.module!)))
        .toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('ماڈیولز', style: AppTypography.titleMedium),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // Breakpoint columns keep cards a sane width on desktop; the
            // extent grows with the text scale so label + subtitle never
            // clip inside the fixed cell.
            final width = constraints.maxWidth;
            final cols = width >= 1100
                ? 4
                : width >= 720
                    ? 3
                    : 2;
            final scale =
                MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
            return GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 132 + 48 * (scale - 1),
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final m = visible[i];
                return _moduleCard(
                  label: m.label,
                  subtitle: m.subtitle,
                  icon: m.icon,
                  color: m.color,
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => m.screen)),
                );
              },
            );
          },
        ),
      ]),
    );
  }

  Widget _moduleCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: M360Card(
        margin: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const Spacer(),
          Text(label,
              textDirection: TextDirection.rtl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyLarge
                  .copyWith(fontWeight: FontWeight.w600)),
          Text(subtitle,
              textDirection: TextDirection.rtl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  /// Monthly fee collection progress — real tenant numbers, dynamic month.
  Widget _buildFeeProgress(DashboardStats stats) {
    final progress = stats.monthProgress;

    return M360Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ماہانہ فیس وصولی',
                      textDirection: TextDirection.rtl,
                      style: AppTypography.titleMedium,
                    ),
                    Text(
                      stats.monthLabel.isNotEmpty ? stats.monthLabel : '—',
                      textDirection: TextDirection.rtl,
                      style: AppTypography.labelSmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(progress * 100).toInt()}%',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.background,
              color: AppColors.success,
              minHeight: 12,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _buildFeeStatItem(
                  'وصول شدہ',
                  formatPK(stats.collectedThisMonth),
                  AppColors.success,
                ),
              ),
              Expanded(
                child: _buildFeeStatItem(
                  'واجب الادا',
                  formatPK(stats.pendingFees),
                  AppColors.error,
                ),
              ),
              Expanded(
                child: _buildFeeStatItem(
                  'ہدف',
                  formatPK(stats.monthlyTarget),
                  AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserManagementCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UserManagementScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.manage_accounts,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'صارف انتظام',
                    textDirection: TextDirection.rtl,
                    style:
                        AppTypography.titleMedium.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'صارفین بنائیں، کردار ترتیب دیں، اجازتیں دیں',
                    textDirection: TextDirection.rtl,
                    style:
                        AppTypography.bodySmall.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_back_ios, color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFeeStatItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.titleMedium.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          textDirection: TextDirection.rtl,
          style: AppTypography.labelSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// Today's attendance from live tenant data.
  Widget _buildAttendanceOverview(DashboardStats stats) {
    final present = stats.todayPresent;
    final absent = stats.todayAbsent;
    final leave = stats.todayLeave;
    final total = present + absent + leave;

    return M360Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.fact_check,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'آج کی حاضری',
                      textDirection: TextDirection.rtl,
                      style: AppTypography.titleMedium,
                    ),
                    Text(
                      'کل طلباء: $total',
                      textDirection: TextDirection.rtl,
                      style: AppTypography.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'آج کی حاضری ابھی درج نہیں ہوئی',
                textDirection: TextDirection.rtl,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
            )
          else
            Row(
              children: [
                _buildAttendanceBar('حاضر', present, total, AppColors.present),
                const SizedBox(width: 8),
                _buildAttendanceBar(
                    'غیر حاضر', absent, total, AppColors.absent),
                const SizedBox(width: 8),
                _buildAttendanceBar('چھٹی', leave, total, AppColors.leave),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAttendanceBar(String label, int count, int total, Color color) {
    final percentage = total == 0 ? 0 : (count / total * 100).toInt();
    final ratio = total == 0 ? 0.0 : count / total;
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  height: 80 * ratio,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                Positioned(
                  top: 8,
                  child: Text(
                    '$count',
                    style: AppTypography.titleLarge.copyWith(
                      color: ratio > 0.5 ? Colors.white : color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              textDirection: TextDirection.rtl,
              style: AppTypography.labelSmall),
          Text(
            '٪$percentage',
            style: AppTypography.labelSmall.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivities(List<DashboardActivity> activities) {
    if (activities.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'ابھی کوئی سرگرمی نہیں',
          textDirection: TextDirection.rtl,
          style:
              AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: activities.length,
      itemBuilder: (context, index) {
        final activity = activities[index];
        return _buildActivityTile(
          icon: _getActivityIcon(activity.iconKey),
          iconColor: _getActivityColor(activity.iconKey),
          title: activity.title,
          subtitle: activity.subtitle,
          time: activity.timeLabel,
        );
      },
    );
  }

  IconData _getActivityIcon(String type) {
    switch (type) {
      case 'fee':
        return Icons.payments;
      case 'attendance':
        return Icons.fact_check;
      case 'admission':
        return Icons.person_add;
      case 'result':
        return Icons.assessment;
      default:
        return Icons.info;
    }
  }

  Color _getActivityColor(String type) {
    switch (type) {
      case 'fee':
        return AppColors.success;
      case 'attendance':
        return AppColors.primary;
      case 'admission':
        return AppColors.info;
      case 'result':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildActivityTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String time,
  }) {
    return M360Card(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    textDirection: TextDirection.rtl,
                    style: AppTypography.titleSmall),
                Text(
                  subtitle,
                  textDirection: TextDirection.rtl,
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            time,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal model for permission- AND module-gated module shortcuts.
class _ModuleDef {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget screen;
  final String requiredPerm;

  /// Module key from `modules_catalog`; null = never module-gated.
  final String? module;

  const _ModuleDef({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.screen,
    required this.requiredPerm,
    this.module,
  });
}
