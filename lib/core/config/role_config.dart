/// کردار کی بصری ترتیب
/// Role Visual Config — display metadata for each UserRole
/// Used by dashboard welcome headers, nav bars, and badges.

import 'package:flutter/material.dart';
import '../../data/repositories/auth_repository.dart';
import '../constants/app_colors.dart';
import '../constants/app_permissions.dart';

// ─────────────────────────────────────────────────────────────
// RoleConfig
// ─────────────────────────────────────────────────────────────

class RoleConfig {
  final String urduTitle;       // Shown in welcome header badge
  final String urduGreeting;    // e.g. 'منتظمِ اعلیٰ'
  final IconData icon;
  final List<Color> gradient;   // 2-colour gradient for welcome card
  final Color accentColor;      // For badges, icons, stats

  const RoleConfig({
    required this.urduTitle,
    required this.urduGreeting,
    required this.icon,
    required this.gradient,
    required this.accentColor,
  });
}

// ─────────────────────────────────────────────────────────────
// Config map
// ─────────────────────────────────────────────────────────────

const Map<UserRole, RoleConfig> _configs = {

  // ── Platform ──────────────────────────────────────────────
  UserRole.superAdmin: RoleConfig(
    urduTitle:    'سپر ایڈمن',
    urduGreeting: 'پلیٹ فارم منتظم',
    icon:         Icons.admin_panel_settings,
    gradient:     [Color(0xFF4527A0), Color(0xFF1A237E)],
    accentColor:  Color(0xFF7C4DFF),
  ),
  UserRole.franchiseManager: RoleConfig(
    urduTitle:    'فرنچائز مینیجر',
    urduGreeting: 'نیٹ ورک ناظر',
    icon:         Icons.account_tree,
    gradient:     [Color(0xFF283593), Color(0xFF0D47A1)],
    accentColor:  Color(0xFF448AFF),
  ),

  // ── Madrasa ────────────────────────────────────────────────
  UserRole.madrasaAdmin: RoleConfig(
    urduTitle:    'ناظمِ مدرسہ',
    urduGreeting: 'مدرسہ انتظامیہ',
    icon:         Icons.mosque_outlined,
    gradient:     [AppColors.primary, AppColors.primaryDark],
    accentColor:  AppColors.primary,
  ),
  UserRole.admin: RoleConfig(
    urduTitle:    'منتظم',
    urduGreeting: 'مدرسہ انتظامیہ',
    icon:         Icons.mosque_outlined,
    gradient:     [AppColors.primary, AppColors.primaryDark],
    accentColor:  AppColors.primary,
  ),
  UserRole.editor: RoleConfig(
    urduTitle:    'ایڈیٹر',
    urduGreeting: 'ڈیٹا مینیجر',
    icon:         Icons.edit_note,
    gradient:     [Color(0xFF00695C), Color(0xFF004D40)],
    accentColor:  Color(0xFF1DE9B6),
  ),

  // ── Academic ───────────────────────────────────────────────
  UserRole.academicManager: RoleConfig(
    urduTitle:    'تعلیمی مینیجر',
    urduGreeting: 'علمی نظام',
    icon:         Icons.school_outlined,
    gradient:     [Color(0xFF1565C0), Color(0xFF0D47A1)],
    accentColor:  Color(0xFF2979FF),
  ),
  UserRole.teacher: RoleConfig(
    urduTitle:    'استاذ',
    urduGreeting: 'معلّم',
    icon:         Icons.menu_book_outlined,
    gradient:     [Color(0xFF1976D2), Color(0xFF0288D1)],
    accentColor:  Color(0xFF40C4FF),
  ),
  UserRole.attendanceOfficer: RoleConfig(
    urduTitle:    'حاضری افسر',
    urduGreeting: 'حاضری رجسٹر',
    icon:         Icons.how_to_reg_outlined,
    gradient:     [Color(0xFF00838F), Color(0xFF006064)],
    accentColor:  Color(0xFF18FFFF),
  ),

  // ── Finance ────────────────────────────────────────────────
  UserRole.accountant: RoleConfig(
    urduTitle:    'محاسب',
    urduGreeting: 'فیس و مالیات',
    icon:         Icons.calculate_outlined,
    gradient:     [Color(0xFFE65100), Color(0xFFBF360C)],
    accentColor:  Color(0xFFFF6D00),
  ),
  UserRole.financeManager: RoleConfig(
    urduTitle:    'مالیاتی مینیجر',
    urduGreeting: 'مالی انتظام',
    icon:         Icons.account_balance_outlined,
    gradient:     [Color(0xFFEF6C00), Color(0xFFE64A19)],
    accentColor:  Color(0xFFFF9100),
  ),

  // ── Departments ────────────────────────────────────────────
  UserRole.libraryManager: RoleConfig(
    urduTitle:    'لائبریری مینیجر',
    urduGreeting: 'کتب خانہ',
    icon:         Icons.local_library_outlined,
    gradient:     [Color(0xFF6A1B9A), Color(0xFF4A148C)],
    accentColor:  Color(0xFFEA80FC),
  ),
  UserRole.hostelManager: RoleConfig(
    urduTitle:    'ہاسٹل مینیجر',
    urduGreeting: 'رہائش انتظام',
    icon:         Icons.home_outlined,
    gradient:     [Color(0xFF4E342E), Color(0xFF3E2723)],
    accentColor:  Color(0xFFBCAAA4),
  ),
  UserRole.announcementManager: RoleConfig(
    urduTitle:    'اعلان مینیجر',
    urduGreeting: 'اطلاعات و پیغامات',
    icon:         Icons.campaign_outlined,
    gradient:     [Color(0xFF2E7D32), Color(0xFF1B5E20)],
    accentColor:  Color(0xFF69F0AE),
  ),
  UserRole.admissionOfficer: RoleConfig(
    urduTitle:    'داخلہ افسر',
    urduGreeting: 'داخلہ و اندراج',
    icon:         Icons.person_add_outlined,
    gradient:     [Color(0xFF00695C), Color(0xFF00838F)],
    accentColor:  Color(0xFF64FFDA),
  ),
  UserRole.itManager: RoleConfig(
    urduTitle:    'آئی ٹی مینیجر',
    urduGreeting: 'نظام انتظام',
    icon:         Icons.settings_outlined,
    gradient:     [Color(0xFF37474F), Color(0xFF263238)],
    accentColor:  Color(0xFF78909C),
  ),

  // ── External ───────────────────────────────────────────────
  UserRole.parent: RoleConfig(
    urduTitle:    'والدین',
    urduGreeting: 'بچے کی پیشرفت',
    icon:         Icons.family_restroom,
    gradient:     [Color(0xFF558B2F), Color(0xFF33691E)],
    accentColor:  Color(0xFFCCFF90),
  ),
  UserRole.student: RoleConfig(
    urduTitle:    'طالب علم',
    urduGreeting: 'میری تعلیم',
    icon:         Icons.school,
    gradient:     [Color(0xFF00838F), Color(0xFF006064)],
    accentColor:  Color(0xFF84FFFF),
  ),
};

// ─────────────────────────────────────────────────────────────
// Public accessor
// ─────────────────────────────────────────────────────────────

extension UserRoleConfig on UserRole {
  RoleConfig get config => _configs[this] ?? _configs[UserRole.teacher]!;
}

// ─────────────────────────────────────────────────────────────
// Nav-tab definition
// ─────────────────────────────────────────────────────────────

class NavTab {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget screen;

  /// Module key from `modules_catalog` (e.g. 'students', 'attendance').
  /// Null = core tab (dashboard/profile) that is never module-gated.
  final String? module;

  const NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.screen,
    this.module,
  });
}

// ─────────────────────────────────────────────────────────────
// Dashboard module card definition
// ─────────────────────────────────────────────────────────────

class DashboardModule {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String requiredPermission;
  final Widget screen;

  const DashboardModule({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.requiredPermission,
    required this.screen,
  });
}

// ─────────────────────────────────────────────────────────────
// Permission → nav-tab builder
// Builds a priority-ordered list; Dashboard first, Profile last.
// Middle slots capped at 3 to keep the bar at max 5 items.
//
// Phase 4 — module gating: pass [enabledModules] (from
// tenantModulesProvider) to hide tabs whose module the tenant has not
// enabled. A null set means "not loaded yet" — no filtering is applied
// so navigation does not flicker while the tenant resolves.
// ─────────────────────────────────────────────────────────────

List<NavTab> buildNavTabs({
  required Set<String> perms,
  required Widget Function() dashboardBuilder,
  required Widget profileScreen,
  required Widget attendanceScreen,
  required Widget studentsScreen,
  required Widget staffScreen,
  required Widget feesScreen,
  required Widget usersScreen,
  required Widget resultsScreen,
  Set<String>? enabledModules,
}) {
  bool moduleOk(String? module) =>
      enabledModules == null ||
      module == null ||
      enabledModules.contains(module);

  final middle = <NavTab>[];

  // Priority order for middle slots (max 3)
  if (perms.contains(AppPermissions.viewStudents) &&
      moduleOk('students') &&
      middle.length < 3) {
    middle.add(NavTab(
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      label: 'طلباء',
      screen: studentsScreen,
      module: 'students',
    ));
  }
  if (perms.contains(AppPermissions.markAttendance) &&
      moduleOk('attendance') &&
      middle.length < 3) {
    middle.add(NavTab(
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check,
      label: 'حاضری',
      screen: attendanceScreen,
      module: 'attendance',
    ));
  }
  if (perms.contains(AppPermissions.viewResults) &&
      perms.contains(AppPermissions.enterResults) &&
      moduleOk('results') &&
      middle.length < 3) {
    middle.add(NavTab(
      icon: Icons.assessment_outlined,
      activeIcon: Icons.assessment,
      label: 'نتائج',
      screen: resultsScreen,
      module: 'results',
    ));
  }
  if (perms.contains(AppPermissions.viewStaff) &&
      !perms.contains(AppPermissions.viewStudents) &&
      moduleOk('staff') &&
      middle.length < 3) {
    middle.add(NavTab(
      icon: Icons.badge_outlined,
      activeIcon: Icons.badge,
      label: 'عملہ',
      screen: staffScreen,
      module: 'staff',
    ));
  }
  if (perms.contains(AppPermissions.viewFees) &&
      !perms.contains(AppPermissions.viewStudents) &&
      moduleOk('fees') &&
      middle.length < 3) {
    middle.add(NavTab(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      label: 'فیس',
      screen: feesScreen,
      module: 'fees',
    ));
  }
  if (perms.contains(AppPermissions.viewUsers) &&
      middle.length < 3) {
    middle.add(NavTab(
      icon: Icons.manage_accounts_outlined,
      activeIcon: Icons.manage_accounts,
      label: 'صارفین',
      screen: usersScreen,
    ));
  }

  return [
    NavTab(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'ڈیش بورڈ',
      screen: dashboardBuilder(),
    ),
    ...middle,
    NavTab(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'پروفائل',
      screen: profileScreen,
    ),
  ];
}
