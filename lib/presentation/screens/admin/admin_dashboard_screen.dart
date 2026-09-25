import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/role_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/widgets/tenant_logo.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/admin_dashboard_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../../widgets/common/app_widgets.dart';
import 'user_management_screen.dart';
import 'darja_screen.dart';
import 'library_screen.dart';
import 'finance_screen.dart';
import '../common/announcements_screen.dart';
import '../teacher/attendance_screen.dart';
import '../teacher/results_screen.dart';

/// منتظم ڈیش بورڈ
/// Admin Dashboard Screen with Statistics and Overview.
///
/// Phase 4: every number comes from [dashboardStatsProvider] — live,
/// tenant-scoped Supabase queries. No hard-coded demo figures remain.
/// Navigation cards are gated by BOTH the user's permissions AND the
/// tenant's enabled modules ([tenantModulesProvider]): a tenant without
/// the library module never sees the library card, even for a permitted
/// user. Institution identity (name/logo) comes from
/// [tenantBrandingProvider].
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
    final authState  = ref.watch(authProvider);
    final perms      = ref.watch(userPermissionsProvider);
    final role       = authState.user?.role ?? UserRole.teacher;
    final roleConfig = role.config;

    final adminName  = authState.user?.name ?? 'اسٹاف';

    // Phase 4 — live tenant-scoped numbers (zeros while loading/offline).
    final stats =
        ref.watch(dashboardStatsProvider).valueOrNull ??
        const DashboardStats.zero();

    // Phase 4 — module gating. Null = modules not loaded yet → do not
    // filter, so cards don't flicker while the tenant resolves.
    final enabledModules = ref.watch(tenantModulesProvider).valueOrNull;
    bool moduleOk(String module) =>
        enabledModules == null || enabledModules.contains(module);

    final branding = ref.watch(tenantBrandingProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        // Phase 4 — the tenant's own name in the app bar.
        title: branding == null
            ? Text(AppStrings.dashboard)
            : TenantNameText(
                style: AppTypography.appBarTitle
                    .copyWith(color: Colors.white),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Role-aware welcome header (shows the tenant name)
            _buildWelcomeHeader(
                adminName, roleConfig, branding?.displayName()),

            // Stats — shown only for permitted AND enabled modules
            const SectionHeader(title: 'اہم اعداد و شمار'),
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
            const SectionHeader(
              title: 'حالیہ سرگرمیاں',
              actionText: 'سب دیکھیں',
            ),
            _buildRecentActivities(_filteredActivities(stats, perms)),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
    });
  }

  Widget _buildWelcomeHeader(
      String userName, RoleConfig config, String? tenantName) {
    return Container(
      margin: const EdgeInsets.all(16),
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
            color: config.gradient.first.withOpacity(0.35),
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
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userName,
                  style: AppTypography.headingSmall.copyWith(
                    color: Colors.white,
                  ),
                ),
                if (tenantName != null && tenantName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tenantName,
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.white70,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(config.icon,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        config.urduTitle,
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
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30, width: 2),
            ),
            // Phase 4 — tenant logo; neutral mark while loading/unset.
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

    if (perms.contains(AppPermissions.viewStudents) &&
        moduleOk('students')) {
      cards.add(StatCard(
        icon: Icons.people,
        label: 'کل طلباء',
        value: '${stats.totalStudents}',
        color: AppColors.primary,
      ));
    }
    if (perms.contains(AppPermissions.viewStaff) &&
        (moduleOk('teachers') || moduleOk('staff'))) {
      cards.add(StatCard(
        icon: Icons.school,
        label: 'اساتذہ',
        value: '${stats.totalTeachers}',
        color: AppColors.info,
      ));
    }
    if (perms.contains(AppPermissions.viewDarjas) &&
        moduleOk('academics')) {
      cards.add(StatCard(
        icon: Icons.class_,
        label: 'جماعتیں',
        value: '${stats.totalClasses}',
        color: AppColors.warning,
      ));
    }
    if (perms.contains(AppPermissions.viewFees) && moduleOk('fees')) {
      cards.add(StatCard(
        icon: Icons.account_balance_wallet,
        label: 'واجب الادا',
        value: formatPK(stats.pendingFees),
        color: AppColors.error,
      ));
    }
    if (perms.contains(AppPermissions.viewAttendance) &&
        moduleOk('attendance')) {
      cards.add(StatCard(
        icon: Icons.fact_check,
        label: 'آج حاضر',
        value: '${stats.todayPresent}',
        color: AppColors.success,
      ));
    }
    if (perms.contains(AppPermissions.viewStaff) &&
        perms.contains(AppPermissions.createStaff) &&
        moduleOk('staff')) {
      cards.add(StatCard(
        icon: Icons.person_add,
        label: 'کل عملہ',
        value: '${stats.totalStaff}',
        color: AppColors.success,
      ));
    }

    if (cards.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      rows.add(Row(children: [
        Expanded(child: cards[i]),
        const SizedBox(width: 12),
        Expanded(
            child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
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
        color: const Color(0xFF1565C0),
        screen: const DarjaScreen(),
        requiredPerm: AppPermissions.viewDarjas,
        module: 'academics',
      ),
      _ModuleDef(
        label: 'اعلانات',
        subtitle: 'پیغامات نشر کریں',
        icon: Icons.campaign_outlined,
        color: const Color(0xFF2E7D32),
        screen: const AnnouncementsScreen(),
        requiredPerm: AppPermissions.viewAnnouncements,
        module: 'notifications',
      ),
      _ModuleDef(
        label: 'کتب خانہ',
        subtitle: 'کتابیں اور اجراء',
        icon: Icons.menu_book_outlined,
        color: const Color(0xFF6A1B9A),
        screen: const LibraryScreen(),
        requiredPerm: AppPermissions.viewLibrary,
        module: 'library',
      ),
      _ModuleDef(
        label: 'مالیات',
        subtitle: 'عطیات و اخراجات',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFFE65100),
        screen: const FinanceScreen(),
        requiredPerm: AppPermissions.viewFinance,
        module: 'finance',
      ),
      _ModuleDef(
        label: 'حاضری',
        subtitle: 'حاضری لگائیں',
        icon: Icons.how_to_reg_outlined,
        color: const Color(0xFF00838F),
        screen: const AttendanceScreen(),
        requiredPerm: AppPermissions.markAttendance,
        module: 'attendance',
      ),
      _ModuleDef(
        label: 'نتائج',
        subtitle: 'امتحانی نتائج',
        icon: Icons.assessment_outlined,
        color: const Color(0xFF558B2F),
        screen: const ResultsScreen(),
        requiredPerm: AppPermissions.viewResults,
        module: 'results',
      ),
      _ModuleDef(
        label: 'عملہ',
        subtitle: 'اسٹاف انتظام',
        icon: Icons.badge_outlined,
        color: const Color(0xFF37474F),
        screen: const Placeholder(), // StaffListScreen imported in outer scope
        requiredPerm: AppPermissions.viewStaff,
        module: 'staff',
      ),
    ];

    // Phase 4 — a card shows only when the user is permitted AND the
    // tenant has the module enabled. A tenant with only
    // students+attendance+fees never sees library/hostel/finance cards.
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
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: visible
              .map((m) => _ModuleCard(
                    label: m.label,
                    subtitle: m.subtitle,
                    icon: m.icon,
                    color: m.color,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => m.screen)),
                  ))
              .toList(),
        ),
      ]),
    );
  }

  Widget _ModuleCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const Spacer(),
          Text(label,
              style: AppTypography.bodyLarge
                  .copyWith(fontWeight: FontWeight.w600)),
          Text(subtitle,
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  /// Monthly fee collection progress — real tenant numbers, dynamic month.
  Widget _buildFeeProgress(DashboardStats stats) {
    final progress = stats.monthProgress;

    return AppCard(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
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
                      style: AppTypography.titleMedium,
                    ),
                    Text(
                      stats.monthLabel.isNotEmpty ? stats.monthLabel : '—',
                      style: AppTypography.labelSmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
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
              _buildFeeStatItem(
                'وصول شدہ',
                formatPK(stats.collectedThisMonth),
                AppColors.success,
              ),
              _buildFeeStatItem(
                'واجب الادا',
                formatPK(stats.pendingFees),
                AppColors.error,
              ),
              _buildFeeStatItem(
                'ہدف',
                formatPK(stats.monthlyTarget),
                AppColors.primary,
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
            colors: [Color(0xFF5C6BC0), Color(0xFF3949AB)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3949AB).withOpacity(0.3),
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
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.manage_accounts, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'صارف انتظام',
                    style: AppTypography.titleMedium.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'صارفین بنائیں، کردار ترتیب دیں، اجازتیں دیں',
                    style: AppTypography.bodySmall.copyWith(color: Colors.white70),
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
      children: [
        Text(
          value,
          style: AppTypography.titleMedium.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: AppTypography.labelSmall,
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

    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
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
                      style: AppTypography.titleMedium,
                    ),
                    Text(
                      'کل طلباء: $total',
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
              color: color.withOpacity(0.1),
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
          Text(label, style: AppTypography.labelSmall),
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
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.textSecondary),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleSmall),
                Text(
                  subtitle,
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
