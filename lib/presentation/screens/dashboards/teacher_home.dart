/// استاد ہوم — ٹیب شیل
/// Teacher home shell (Phase 7a, §7 + §42 role-specific navigation).
///
/// Bottom-nav menu: ڈیش بورڈ، میری جماعتیں، میرے طلبہ، حاضری، تدریس،
/// امتحانات، نتائج. Each tab is included ONLY when the teacher holds the
/// relevant permission (via [hasPermissionProvider] — the same mechanism
/// [PermissionGuard] uses, i.e. guards, not mere omission).
///
/// Finance, payroll, settings, user management and master admin are NEVER
/// added here: there is no code path in this shell that can render them
/// for a teacher role.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_permissions.dart';
import '../../core/constants/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../teacher/attendance_screen.dart';
import '../teacher/results_screen.dart';
import 'my_classes_screen.dart';
import 'my_students_screen.dart';
import 'role_home.dart' show ComingSoonScreen;
import 'teacher_dashboard.dart';

class _TeacherTab {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget screen;

  const _TeacherTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.screen,
  });
}

class TeacherHomeScreen extends ConsumerStatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  ConsumerState<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends ConsumerState<TeacherHomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = _buildTabs();
    final index = _currentIndex.clamp(0, tabs.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [for (final t in tabs) t.screen],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: BottomNavigationBar(
            currentIndex: index,
            onTap: (i) => setState(() => _currentIndex = i),
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppColors.surface,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textSecondary,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            selectedLabelStyle: AppTypography.navLabel.copyWith(
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelStyle: AppTypography.navLabel,
            items: [
              for (final t in tabs)
                BottomNavigationBarItem(
                  icon: Icon(t.icon),
                  activeIcon: Icon(t.activeIcon),
                  label: t.label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Permission-gated tab list. Finance / users / settings / master-admin
  /// routes are deliberately absent — no tab can be constructed for them.
  List<_TeacherTab> _buildTabs() {
    bool can(String permission) =>
        ref.watch(hasPermissionProvider(permission));

    final canStudents = can(AppPermissions.viewStudents);
    final canAttendance = can(AppPermissions.viewAttendance) ||
        can(AppPermissions.markAttendance);
    final canExams = can(AppPermissions.viewExams);
    final canResults = can(AppPermissions.viewResults) ||
        can(AppPermissions.enterResults) ||
        can(AppPermissions.editResults);

    final tabs = <_TeacherTab>[];

    // Jump to a tab when it exists; otherwise push the screen directly so
    // the dashboard's quick actions never hit a dead end.
    void goTo(String label, Widget fallback) {
      final i = tabs.indexWhere((t) => t.label == label);
      if (i >= 0) {
        setState(() => _currentIndex = i);
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => fallback),
        );
      }
    }

    tabs.add(_TeacherTab(
      label: 'ڈیش بورڈ',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      screen: TeacherDashboardScreen(
        onMarkAttendance: () => goTo('حاضری', const AttendanceScreen()),
        onViewStudents: () => goTo('میرے طلبہ', const MyStudentsScreen()),
        onEnterResults: () => goTo('نتائج', const ResultsScreen()),
      ),
    ));

    if (canStudents) {
      tabs.add(const _TeacherTab(
        label: 'میری جماعتیں',
        icon: Icons.school_outlined,
        activeIcon: Icons.school,
        screen: MyClassesScreen(),
      ));
      tabs.add(const _TeacherTab(
        label: 'میرے طلبہ',
        icon: Icons.people_outlined,
        activeIcon: Icons.people,
        screen: MyStudentsScreen(),
      ));
    }

    if (canAttendance) {
      tabs.add(const _TeacherTab(
        label: 'حاضری',
        icon: Icons.fact_check_outlined,
        activeIcon: Icons.fact_check,
        screen: AttendanceScreen(),
      ));
    }

    // تدریس has no screen yet — clean placeholder, never a dead button.
    tabs.add(const _TeacherTab(
      label: 'تدریس',
      icon: Icons.menu_book_outlined,
      activeIcon: Icons.menu_book,
      screen: ComingSoonScreen(title: 'تدریس', showAppBar: false),
    ));

    if (canExams) {
      tabs.add(const _TeacherTab(
        label: 'امتحانات',
        icon: Icons.assignment_outlined,
        activeIcon: Icons.assignment,
        screen: ComingSoonScreen(title: 'امتحانات', showAppBar: false),
      ));
    }

    if (canResults) {
      tabs.add(const _TeacherTab(
        label: 'نتائج',
        icon: Icons.assessment_outlined,
        activeIcon: Icons.assessment,
        screen: ResultsScreen(),
      ));
    }

    return tabs;
  }
}
