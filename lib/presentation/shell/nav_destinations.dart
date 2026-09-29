/// مدرسہ 360 — نئی معلوماتی ساخت (Information Architecture)
///
/// This file is the SINGLE SOURCE OF TRUTH for the new navigation shell's
/// information architecture. It contains no layout code — only data:
/// navigation groups (مرکزی، طلبہ، تعلیمی نظام، حاضری، مالیات، ادارہ),
/// destinations with Urdu (Nastaleeq) labels, icons, screen builders,
/// permission/role visibility rules, and badge-count provider hooks.
///
/// RULES
/// -----
/// * A destination may only point at a screen class that EXISTS in the repo.
///   Anything whose screen does not exist yet is listed with `planned: true`
///   and an honest backend-unavailable state — never a "جلد آرہا ہے"
///   marketing placeholder.
/// * Visibility is permission-first ([requiredPermissions], OR semantics —
///   the user needs ANY of them), matching the app's RoleService contract
///   ("permission-derived capabilities, never role-name string matching for
///   feature gating"). [visibleForRoleKeys] is only an additional narrowing
///   filter for role-specific portals (e.g. the parent fee record).
/// * Badge counts hook into REAL existing providers only; see [NavBadges].
///
/// Drop-in usage: `import 'package:madrasa_360/presentation/shell/nav_destinations.dart';`

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Existing providers (badge hooks) ────────────────────────────────────────
import 'package:madrasa_360/core/notifications/notification_providers.dart'
    show unreadNotificationsCountProvider;
import 'package:madrasa_360/providers/announcement_provider.dart'
    show announcementListProvider;

import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';

// ── Existing screens — every builder target verified present in the repo ───
// مرکزی
import 'package:madrasa_360/presentation/screens/admin/backup_screen.dart'
    show BackupScreen;
import 'package:madrasa_360/presentation/screens/common/about_screen.dart'
    show AboutScreen;
import 'package:madrasa_360/presentation/screens/common/profile_screen.dart'
    show ProfileScreen;
import 'package:madrasa_360/presentation/screens/hostel/hostel_screen.dart'
    show HostelScreen;
import 'package:madrasa_360/presentation/screens/transport/transport_screen.dart'
    show TransportScreen;
import 'package:madrasa_360/presentation/screens/certificates/certificates_screen.dart'
    show CertificatesScreen;
import 'package:madrasa_360/presentation/screens/common/announcements_screen.dart'
    show AnnouncementsScreen;
import 'package:madrasa_360/presentation/screens/common/notifications_screen.dart'
    show NotificationsScreen;
import 'package:madrasa_360/presentation/screens/common/dashboard_guide_screen.dart'
    show DashboardGuideScreen;
import 'package:madrasa_360/presentation/screens/dashboards/role_home.dart'
    show RoleHomeScreen;
// طلبہ
import 'package:madrasa_360/presentation/screens/admin/student_list_screen.dart'
    show StudentListScreen;
import 'package:madrasa_360/presentation/screens/dashboards/my_classes_screen.dart'
    show MyClassesScreen;
import 'package:madrasa_360/presentation/screens/dashboards/my_students_screen.dart'
    show MyStudentsScreen;
import 'package:madrasa_360/presentation/screens/parent/fee_history_screen.dart'
    show FeeHistoryScreen;
// تعلیمی نظام
import 'package:madrasa_360/presentation/screens/admin/darja_screen.dart'
    show DarjaScreen;
import 'package:madrasa_360/presentation/screens/dashboards/exam_dashboard.dart'
    show ExamDashboardScreen;
import 'package:madrasa_360/presentation/screens/teacher/results_screen.dart'
    show ResultsScreen;
// حاضری
import 'package:madrasa_360/presentation/screens/teacher/attendance_screen.dart'
    show AttendanceScreen;
// مالیات
import 'package:madrasa_360/presentation/screens/admin/fee_management_screen.dart'
    show FeeManagementScreen;
import 'package:madrasa_360/presentation/screens/finance/finance_hub_screen.dart'
    show FinanceHubScreen, FinanceSection;
// ادارہ
import 'package:madrasa_360/presentation/screens/admin/library_screen.dart'
    show LibraryScreen;
import 'package:madrasa_360/presentation/screens/admin/staff_list_screen.dart'
    show StaffListScreen;
import 'package:madrasa_360/presentation/screens/settings/user_management_hub.dart'
    show UserManagementHubScreen;

// ════════════════════════════════════════════════════════════════════════════
// Badge hooks
// ════════════════════════════════════════════════════════════════════════════

/// Badge-count provider hooks for destinations.
///
/// The shell normalises the watched value to an `int?`:
/// * `AsyncValue<int>` (e.g. a StreamProvider) → its value
/// * `int` / `List` → itself / its length
///
/// These are static METHODS (not getters) on purpose: a static method
/// tear-off (e.g. `NavBadges.unreadNotifications`) is a compile-time
/// constant, so it can be used inside the `const` [kNavGroups] list,
/// whereas a getter cannot.
///
/// Add future hooks here (e.g. today's unpaid-fee count from
/// `fee_provider.dart` once a canonical dues counter exists) and assign
/// them to the destination's [NavDestination.badgeProvider].
class NavBadges {
  NavBadges._();

  /// Unread in-app notifications (verified: StreamProvider<int> in
  /// `lib/core/notifications/notification_providers.dart`).
  static ProviderListenable<Object?> unreadNotifications() =>
      unreadNotificationsCountProvider;

  /// Published announcements in the active tenant (verified:
  /// `announcementListProvider`, Provider<List<Announcement>>).
  static ProviderListenable<Object?> announcements() =>
      announcementListProvider;
}

// ════════════════════════════════════════════════════════════════════════════
// Data model
// ════════════════════════════════════════════════════════════════════════════

/// One selectable destination in the new navigation shell.
///
/// Visibility rule (evaluated by the shell):
/// `visible = badgeOK && (requiredPermissions.isEmpty || permissions ∩ requiredPermissions ≠ ∅)`
/// `&& (visibleForRoleKeys.isEmpty || roleKeys ∩ visibleForRoleKeys ≠ ∅)`
class NavDestination {
  const NavDestination({
    required this.id,
    required this.labelUr,
    required this.icon,
    required this.builder,
    this.requiredPermissions = const [],
    this.visibleForRoleKeys = const [],
    this.badgeProvider,
  });

  /// Stable machine id, e.g. 'dashboard', 'students'.
  final String id;

  /// Urdu label, always rendered in Nastaleeq ([AppTypography.navLabel]).
  final String labelUr;

  final IconData icon;

  /// Screen builder. Must be a real screen — never an invented one.
  final WidgetBuilder builder;

  /// Permission codes from [AppPermissions]; the user needs ANY of them.
  /// Empty = visible to every authenticated user.
  final List<String> requiredPermissions;

  /// Extra role-key narrowing (role_home.dart template keys). Empty = no
  /// role filtering.
  final List<String> visibleForRoleKeys;

  /// Optional badge-count provider hook (see [NavBadges]). Stored as a
  /// static-method tear-off so it stays a compile-time constant inside the
  /// const [kNavGroups] list; the shell calls it to obtain the provider.
  final ProviderListenable<Object?> Function()? badgeProvider;

  /// True when the current user may see this destination.
  bool isVisible(Set<String> permissions, List<String> roleKeys) {
    if (requiredPermissions.isNotEmpty &&
        !requiredPermissions.any(permissions.contains)) {
      return false;
    }
    if (visibleForRoleKeys.isNotEmpty &&
        !visibleForRoleKeys.any(roleKeys.contains)) {
      return false;
    }
    return true;
  }
}

/// A collapsible section of the rail/drawer.
class NavGroup {
  const NavGroup({
    required this.id,
    required this.labelUr,
    required this.destinations,
  });

  final String id;
  final String labelUr;
  final List<NavDestination> destinations;

  /// Destinations the current user may see.
  List<NavDestination> visibleDestinations(
      Set<String> permissions, List<String> roleKeys) {
    return destinations
        .where((d) => d.isVisible(permissions, roleKeys))
        .toList(growable: false);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// The information architecture
// ════════════════════════════════════════════════════════════════════════════

/// Complete IA: six groups. Order is intentional — daily workflows first,
/// administration last. Max 2–3 taps to any common workflow.
const List<NavGroup> kNavGroups = [
  // ── مرکزی ───────────────────────────────────────────────────────────────
  NavGroup(
    id: 'markazi',
    labelUr: 'مرکزی',
    destinations: [
      NavDestination(
        id: 'dashboard',
        labelUr: 'ڈیش بورڈ',
        icon: Icons.dashboard_outlined,
        builder: _dashboardBuilder,
      ),
      NavDestination(
        id: 'announcements',
        labelUr: 'اعلانات',
        icon: Icons.campaign_outlined,
        builder: _announcementsBuilder,
        badgeProvider: NavBadges.announcements,
      ),
      NavDestination(
        id: 'guide',
        labelUr: 'رہنمائی',
        icon: Icons.help_outline,
        builder: _guideBuilder,
      ),
    ],
  ),

  // ── طلبہ ────────────────────────────────────────────────────────────────
  NavGroup(
    id: 'students',
    labelUr: 'طلبہ',
    destinations: [
      NavDestination(
        id: 'student-list',
        labelUr: 'طلبہ کی فہرست',
        icon: Icons.school_outlined,
        builder: _studentListBuilder,
        requiredPermissions: [
          AppPermissions.viewStudents,
          AppPermissions.createStudents,
          AppPermissions.editStudents,
        ],
      ),
      NavDestination(
        id: 'my-classes',
        labelUr: 'میری جماعتیں',
        icon: Icons.class_outlined,
        builder: _myClassesBuilder,
        requiredPermissions: [
          AppPermissions.viewTeachers,
          AppPermissions.viewDarjas,
          AppPermissions.viewStudents,
        ],
      ),
      NavDestination(
        id: 'my-students',
        labelUr: 'میرے طلبہ',
        icon: Icons.groups_outlined,
        builder: _myStudentsBuilder,
        visibleForRoleKeys: ['teacher', 'ustad', 'ustad_hifz'],
      ),
      NavDestination(
        id: 'parent-fees',
        labelUr: 'فیس کا ریکارڈ',
        icon: Icons.receipt_long_outlined,
        builder: _feeHistoryBuilder,
        visibleForRoleKeys: ['parent'],
      ),
    ],
  ),

  // ── تعلیمی نظام ──────────────────────────────────────────────────────────
  NavGroup(
    id: 'academics',
    labelUr: 'تعلیمی نظام',
    destinations: [
      NavDestination(
        id: 'darjas',
        labelUr: 'درجات',
        icon: Icons.layers_outlined,
        builder: _darjaBuilder,
        requiredPermissions: [
          AppPermissions.viewDarjas,
          AppPermissions.manageDarjas,
        ],
      ),
      NavDestination(
        id: 'exams',
        labelUr: 'امتحانات',
        icon: Icons.assignment_outlined,
        builder: _examsBuilder,
        requiredPermissions: [
          AppPermissions.viewExams,
          AppPermissions.createExams,
          AppPermissions.manageExams,
        ],
      ),
      NavDestination(
        id: 'results',
        labelUr: 'نتائج',
        icon: Icons.grade_outlined,
        builder: _resultsBuilder,
        requiredPermissions: [
          AppPermissions.viewResults,
          AppPermissions.enterResults,
          AppPermissions.editResults,
          AppPermissions.publishResults,
        ],
      ),
    ],
  ),

  // ── حاضری ────────────────────────────────────────────────────────────────
  NavGroup(
    id: 'attendance',
    labelUr: 'حاضری',
    destinations: [
      NavDestination(
        id: 'attendance',
        labelUr: 'حاضری لگائیں',
        icon: Icons.fact_check_outlined,
        builder: _attendanceBuilder,
        requiredPermissions: [
          AppPermissions.markAttendance,
          AppPermissions.viewAttendance,
        ],
      ),
    ],
  ),

  // ── مالی ─────────────────────────────────────────────────────────────────
  NavGroup(
    id: 'finance',
    labelUr: 'مالی',
    destinations: [
      NavDestination(
        id: 'finance_dashboard',
        labelUr: 'مالی ڈیش بورڈ',
        icon: Icons.dashboard_outlined,
        builder: _financeDashboardBuilder,
        requiredPermissions: [
          AppPermissions.viewFinance,
          AppPermissions.viewFees,
        ],
      ),
      NavDestination(
        id: 'student_fees',
        labelUr: 'طلبہ کی فیس',
        icon: Icons.payments_outlined,
        builder: _feesBuilder,
        requiredPermissions: [
          AppPermissions.collectFees,
          AppPermissions.viewFees,
        ],
      ),
      NavDestination(
        id: 'finance_dues',
        labelUr: 'واجبات',
        icon: Icons.pending_actions_outlined,
        builder: _financeDuesBuilder,
        requiredPermissions: [
          AppPermissions.collectFees,
          AppPermissions.viewFees,
        ],
      ),
      NavDestination(
        id: 'finance_invoices',
        labelUr: 'انوائسز',
        icon: Icons.receipt_long_outlined,
        builder: _financeInvoicesBuilder,
        requiredPermissions: [
          AppPermissions.viewFinance,
          AppPermissions.approveFinance,
        ],
      ),
      NavDestination(
        id: 'finance_payments',
        labelUr: 'ادائیگیاں',
        icon: Icons.account_balance_wallet_outlined,
        builder: _financePaymentsBuilder,
        requiredPermissions: [
          AppPermissions.viewFinance,
          AppPermissions.approveFinance,
        ],
      ),
      NavDestination(
        id: 'finance_ledger',
        labelUr: 'لیجر',
        icon: Icons.book_outlined,
        builder: _financeLedgerBuilder,
        requiredPermissions: [
          AppPermissions.viewFinance,
          AppPermissions.approveFinance,
        ],
      ),
      NavDestination(
        id: 'finance_expenses',
        labelUr: 'اخراجات',
        icon: Icons.shopping_cart_outlined,
        builder: _financeExpensesBuilder,
        requiredPermissions: [
          AppPermissions.viewFinance,
          AppPermissions.approveFinance,
        ],
      ),
      NavDestination(
        id: 'finance_reports',
        labelUr: 'مالی رپورٹس',
        icon: Icons.bar_chart_outlined,
        builder: _reportsBuilder,
        requiredPermissions: [
          AppPermissions.viewReports,
          AppPermissions.exportReports,
        ],
      ),
    ],
  ),

  // ── ادارہ ────────────────────────────────────────────────────────────────
  NavGroup(
    id: 'institution',
    labelUr: 'ادارہ',
    destinations: [
      NavDestination(
        id: 'staff',
        labelUr: 'عملہ',
        icon: Icons.badge_outlined,
        builder: _staffBuilder,
        requiredPermissions: [
          AppPermissions.viewStaff,
          AppPermissions.viewTeachers,
        ],
      ),
      NavDestination(
        id: 'library',
        labelUr: 'کتب خانہ',
        icon: Icons.local_library_outlined,
        builder: _libraryBuilder,
        requiredPermissions: [
          AppPermissions.viewLibrary,
          AppPermissions.manageLibrary,
        ],
      ),
      NavDestination(
        id: 'users-roles',
        labelUr: 'صارفین و کردار',
        icon: Icons.manage_accounts_outlined,
        builder: _userMgmtBuilder,
        requiredPermissions: [
          AppPermissions.viewUsers,
          AppPermissions.assignRoles,
        ],
      ),
      NavDestination(
        id: 'hostel',
        labelUr: 'دارالاقامہ',
        icon: Icons.hotel_outlined,
        builder: _hostelBuilder,
        requiredPermissions: [
          AppPermissions.viewHostel,
          AppPermissions.manageHostel,
        ],
      ),
      NavDestination(
        id: 'transport',
        labelUr: 'ٹرانسپورٹ',
        icon: Icons.directions_bus_outlined,
        builder: _transportBuilder,
        requiredPermissions: [
          AppPermissions.viewTransport,
          AppPermissions.manageTransport,
        ],
      ),
      NavDestination(
        id: 'certificates',
        labelUr: 'اسناد',
        icon: Icons.workspace_premium_outlined,
        builder: _certificatesBuilder,
        requiredPermissions: [
          AppPermissions.viewCertificates,
          AppPermissions.issueCertificates,
        ],
      ),
    ],
  ),

  // ── ترتیبات ─────────────────────────────────────────────────────────────
  NavGroup(
    id: 'settings',
    labelUr: 'ترتیبات',
    destinations: [
      NavDestination(
        id: 'profile',
        labelUr: 'پروفائل',
        icon: Icons.person_outline,
        builder: _profileBuilder,
      ),
      NavDestination(
        id: 'notifications',
        labelUr: 'اطلاعات',
        icon: Icons.notifications_outlined,
        builder: _notificationsBuilder,
        badgeProvider: NavBadges.unreadNotifications,
      ),
      NavDestination(
        id: 'backup',
        labelUr: 'بیک اپ',
        icon: Icons.backup_outlined,
        builder: _backupBuilder,
        requiredPermissions: [
          AppPermissions.manageSettings,
        ],
      ),
      NavDestination(
        id: 'about',
        labelUr: 'ادارے کے بارے میں',
        icon: Icons.info_outline,
        builder: _aboutBuilder,
      ),
      NavDestination(
        id: 'logout',
        labelUr: 'لاگ آؤٹ',
        icon: Icons.logout_outlined,
        builder: _logoutStubBuilder,
      ),
    ],
  ),
];

// ── Builders (kept as top-level functions so the const IA list stays clean) ─

Widget _dashboardBuilder(BuildContext context) => const RoleHomeScreen();
Widget _announcementsBuilder(BuildContext context) =>
    const AnnouncementsScreen();
Widget _notificationsBuilder(BuildContext context) =>
    const NotificationsScreen();
Widget _guideBuilder(BuildContext context) =>
    const DashboardGuideScreen(roleKey: 'generic');
Widget _studentListBuilder(BuildContext context) => const StudentListScreen();
Widget _myClassesBuilder(BuildContext context) => const MyClassesScreen();
Widget _myStudentsBuilder(BuildContext context) => const MyStudentsScreen();
Widget _feeHistoryBuilder(BuildContext context) => const FeeHistoryScreen();
Widget _darjaBuilder(BuildContext context) => const DarjaScreen();
Widget _examsBuilder(BuildContext context) => const ExamDashboardScreen();
Widget _resultsBuilder(BuildContext context) => const ResultsScreen();
Widget _attendanceBuilder(BuildContext context) => const AttendanceScreen();
Widget _feesBuilder(BuildContext context) => const FeeManagementScreen();
Widget _financeDashboardBuilder(BuildContext context) =>
    const FinanceHubScreen(section: FinanceSection.dashboard);
Widget _financeDuesBuilder(BuildContext context) =>
    const FinanceHubScreen(section: FinanceSection.dues);
Widget _financeInvoicesBuilder(BuildContext context) =>
    const FinanceHubScreen(section: FinanceSection.invoices);
Widget _financePaymentsBuilder(BuildContext context) =>
    const FinanceHubScreen(section: FinanceSection.payments);
Widget _financeLedgerBuilder(BuildContext context) =>
    const FinanceHubScreen(section: FinanceSection.ledger);
Widget _financeExpensesBuilder(BuildContext context) =>
    const FinanceHubScreen(section: FinanceSection.expenses);
Widget _reportsBuilder(BuildContext context) =>
    const FinanceHubScreen(section: FinanceSection.reports);
Widget _staffBuilder(BuildContext context) => const StaffListScreen();
Widget _libraryBuilder(BuildContext context) => const LibraryScreen();
Widget _userMgmtBuilder(BuildContext context) =>
    const UserManagementHubScreen();
Widget _aboutBuilder(BuildContext context) => const AboutScreen();
Widget _profileBuilder(BuildContext context) => const ProfileScreen();
Widget _backupBuilder(BuildContext context) => const BackupScreen();

/// Hostel opens the Phase 8 module hub (buildings → rooms → beds →
/// allocations). Its data layer is backend-pending, so the hub renders
/// honest unavailable states until the tables exist.
Widget _hostelBuilder(BuildContext context) => const HostelScreen();

/// Transport opens the Phase 8 module hub (vehicles, drivers, routes,
/// assignments) against the isolated repository interface.
Widget _transportBuilder(BuildContext context) => const TransportScreen();

/// Certificates opens the Phase 8 module: real PDF generation through the
/// reporting engine + issuance history behind the isolated repository.
Widget _certificatesBuilder(BuildContext context) => const CertificatesScreen();

/// The shell intercepts the 'logout' id (confirmation + sign-out) — this
/// builder is never rendered.
Widget _logoutStubBuilder(BuildContext context) => const SizedBox.shrink();

/// Flattened list of all destinations (handy for deep-link resolution and
/// the mobile bottom nav's "primary" lookup).
List<NavDestination> get kAllDestinations =>
    [for (final g in kNavGroups) ...g.destinations];

/// Find a destination by id, or null.
NavDestination? findDestination(String id) {
  for (final d in kAllDestinations) {
    if (d.id == id) return d;
  }
  return null;
}

/// Find the group a destination belongs to, or null.
NavGroup? findGroupOf(String destinationId) {
  for (final g in kNavGroups) {
    if (g.destinations.any((d) => d.id == destinationId)) return g;
  }
  return null;
}

/// The four primary destinations for the mobile bottom navigation bar.
/// "مزید" (more) is handled by [MobileNavBar] itself and is not in this list.
const List<String> kMobilePrimaryIds = [
  'dashboard',
  'student-list',
  'attendance',
  'student_fees',
];
