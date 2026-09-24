import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/role_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/student_provider.dart';
import '../../../providers/staff_provider.dart';
import '../../../providers/fee_provider.dart';
import '../../widgets/common/app_widgets.dart';
import 'user_management_screen.dart';
import 'darja_screen.dart';
import 'library_screen.dart';
import 'finance_screen.dart';
import '../common/announcements_screen.dart';
import '../teacher/attendance_screen.dart';
import '../teacher/results_screen.dart';

/// منتظم ڈیش بورڈ
/// Admin Dashboard Screen with Statistics and Overview
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  static const _activities = [
    {'icon': 'fee',        'title': 'فیس وصولی',    'subtitle': 'محمد احمد - 3000 روپے', 'time': 'ابھی'},
    {'icon': 'attendance', 'title': 'حاضری',      'subtitle': 'درجہ اولیٰ - مکمل',        'time': '10 منٹ پہلے'},
    {'icon': 'admission',  'title': 'نیا داخلہ',   'subtitle': 'سعد اللہ - درجہ دوم',         'time': '1 گھنٹہ پہلے'},
    {'icon': 'result',     'title': 'نتائج',        'subtitle': 'ماہانہ امتحان اپ لوڈ',    'time': 'کل'},
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
    final authState  = ref.watch(authProvider);
    final perms      = ref.watch(userPermissionsProvider);
    final role       = authState.user?.role ?? UserRole.teacher;
    final roleConfig = role.config;

    final adminName  = authState.user?.name ?? 'اسٹاف';
    final students   = ref.watch(allStudentsProvider).valueOrNull ?? [];
    final staffList  = ref.watch(allStaffProvider).valueOrNull ?? [];
    final feeSummary = ref.watch(feeSummaryProvider).valueOrNull;

    final teachers = staffList.where((s) => s.department == 'تعلیمی').length;
    final stats = {
      'totalStudents':  students.length,
      'totalTeachers':  teachers,
      'totalStaff':     staffList.length,
      'totalClasses':   8,
      'todayPresent':   142,
      'todayAbsent':    10,
      'todayLeave':     4,
      'pendingFees':    (feeSummary?.totalDue       ?? 45000).toInt(),
      'collectedFees':  (feeSummary?.totalCollected ?? 380000).toInt(),
      'monthlyTarget':  468000,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.dashboard),
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
            // Role-aware welcome header
            _buildWelcomeHeader(adminName, roleConfig),

            // Stats — shown only for permitted modules
            const SectionHeader(title: 'اہم اعداد و شمار'),
            _buildPermissionFilteredStats(stats, perms),

            // User Management card — only for managers
            if (perms.contains(AppPermissions.viewUsers))
              _buildUserManagementCard(context),

            // Module shortcuts — filtered by permissions
            _buildModulesSection(context, perms),

            // Fee progress — only if user can view fees
            if (perms.contains(AppPermissions.viewFees))
              _buildFeeProgress(stats),

            // Attendance overview — only if user can view attendance
            if (perms.contains(AppPermissions.viewAttendance))
              _buildAttendanceOverview(stats),

            // Recent activities
            const SectionHeader(
              title: 'حالیہ سرگرمیاں',
              actionText: 'سب دیکھیں',
            ),
            _buildRecentActivities(_filteredActivities(perms)),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
    });
  }

  Widget _buildWelcomeHeader(String userName, RoleConfig config) {
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
            child: Icon(
              config.icon,
              color: Colors.white,
              size: 36,
            ),
          ),
        ],
      ),
    );
  }

  /// Returns only the activity entries relevant to the current user's permissions.
  List<Map<String, dynamic>> _filteredActivities(Set<String> perms) {
    return _activities.where((a) {
      switch (a['icon']) {
        case 'fee':        return perms.contains(AppPermissions.viewFees);
        case 'attendance': return perms.contains(AppPermissions.viewAttendance);
        case 'admission':  return perms.contains(AppPermissions.viewStudents);
        case 'result':     return perms.contains(AppPermissions.viewResults);
        default:           return true;
      }
    }).toList();
  }

  /// Shows stat cards filtered to what the user is allowed to see.
  Widget _buildPermissionFilteredStats(
      Map<String, dynamic> stats, Set<String> perms) {
    final cards = <Widget>[];

    if (perms.contains(AppPermissions.viewStudents)) {
      cards.add(StatCard(
        icon: Icons.people,
        label: 'کل طلباء',
        value: '${stats['totalStudents']}',
        color: AppColors.primary,
        trend: '5%+',
        isUp: true,
      ));
    }
    if (perms.contains(AppPermissions.viewStaff)) {
      cards.add(StatCard(
        icon: Icons.school,
        label: 'اساتذہ',
        value: '${stats['totalTeachers']}',
        color: AppColors.info,
      ));
    }
    if (perms.contains(AppPermissions.viewDarjas)) {
      cards.add(StatCard(
        icon: Icons.class_,
        label: 'جماعتیں',
        value: '${stats['totalClasses']}',
        color: AppColors.warning,
      ));
    }
    if (perms.contains(AppPermissions.viewFees)) {
      cards.add(StatCard(
        icon: Icons.account_balance_wallet,
        label: 'واجب الادا',
        value: '${stats['pendingFees']}',
        color: AppColors.error,
      ));
    }
    if (perms.contains(AppPermissions.viewAttendance)) {
      cards.add(StatCard(
        icon: Icons.fact_check,
        label: 'آج حاضر',
        value: '${stats['todayPresent']}',
        color: AppColors.success,
      ));
    }
    if (perms.contains(AppPermissions.viewStaff) &&
        perms.contains(AppPermissions.createStaff)) {
      cards.add(StatCard(
        icon: Icons.person_add,
        label: 'کل عملہ',
        value: '${stats['totalStaff']}',
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

  Widget _buildModulesSection(BuildContext context, [Set<String>? perms]) {
    // All possible modules with their required permission
    final allModules = [
      _ModuleDef(
        label: 'درجات',
        subtitle: 'جماعتیں و سیکشن',
        icon: Icons.class_outlined,
        color: const Color(0xFF1565C0),
        screen: const DarjaScreen(),
        requiredPerm: AppPermissions.viewDarjas,
      ),
      _ModuleDef(
        label: 'اعلانات',
        subtitle: 'پیغامات نشر کریں',
        icon: Icons.campaign_outlined,
        color: const Color(0xFF2E7D32),
        screen: const AnnouncementsScreen(),
        requiredPerm: AppPermissions.viewAnnouncements,
      ),
      _ModuleDef(
        label: 'کتب خانہ',
        subtitle: 'کتابیں اور اجراء',
        icon: Icons.menu_book_outlined,
        color: const Color(0xFF6A1B9A),
        screen: const LibraryScreen(),
        requiredPerm: AppPermissions.viewLibrary,
      ),
      _ModuleDef(
        label: 'مالیات',
        subtitle: 'عطیات و اخراجات',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFFE65100),
        screen: const FinanceScreen(),
        requiredPerm: AppPermissions.viewFinance,
      ),
      _ModuleDef(
        label: 'حاضری',
        subtitle: 'حاضری لگائیں',
        icon: Icons.how_to_reg_outlined,
        color: const Color(0xFF00838F),
        screen: const AttendanceScreen(),
        requiredPerm: AppPermissions.markAttendance,
      ),
      _ModuleDef(
        label: 'نتائج',
        subtitle: 'امتحانی نتائج',
        icon: Icons.assessment_outlined,
        color: const Color(0xFF558B2F),
        screen: const ResultsScreen(),
        requiredPerm: AppPermissions.viewResults,
      ),
      _ModuleDef(
        label: 'عملہ',
        subtitle: 'اسٹاف انتظام',
        icon: Icons.badge_outlined,
        color: const Color(0xFF37474F),
        screen: const Placeholder(), // StaffListScreen imported in outer scope
        requiredPerm: AppPermissions.viewStaff,
      ),
    ];

    final visible = perms == null
        ? allModules
        : allModules
            .where((m) => perms.contains(m.requiredPerm))
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

  Widget _buildFeeProgress(Map<String, dynamic> stats) {
    final collected = stats['collectedFees'] as int;
    final target = stats['monthlyTarget'] as int;
    final progress = collected / target;

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
                      'جنوری 2026',
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
                '3,80,000',
                AppColors.success,
              ),
              _buildFeeStatItem(
                'واجب الادا',
                '45,000',
                AppColors.error,
              ),
              _buildFeeStatItem(
                'ہدف',
                '4,68,000',
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

  Widget _buildAttendanceOverview(Map<String, dynamic> stats) {
    final present = stats['todayPresent'] as int;
    final absent = stats['todayAbsent'] as int;
    final leave = stats['todayLeave'] as int;
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
          Row(
            children: [
              _buildAttendanceBar('حاضر', present, total, AppColors.present),
              const SizedBox(width: 8),
              _buildAttendanceBar('غیر حاضر', absent, total, AppColors.absent),
              const SizedBox(width: 8),
              _buildAttendanceBar('چھٹی', leave, total, AppColors.leave),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceBar(String label, int count, int total, Color color) {
    final percentage = (count / total * 100).toInt();
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
                  height: 80 * (count / total),
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
                      color: count / total > 0.5 ? Colors.white : color,
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

  Widget _buildRecentActivities(List<Map<String, dynamic>> activities) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: activities.length,
      itemBuilder: (context, index) {
        final activity = activities[index];
        return _buildActivityTile(
          icon: _getActivityIcon(activity['icon']),
          iconColor: _getActivityColor(activity['icon']),
          title: activity['title'],
          subtitle: activity['subtitle'],
          time: activity['time'],
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

/// Internal model for permission-gated module shortcuts on the dashboard.
class _ModuleDef {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget screen;
  final String requiredPerm;

  const _ModuleDef({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.screen,
    required this.requiredPerm,
  });
}
