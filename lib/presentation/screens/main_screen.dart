import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_typography.dart';
import '../../core/widgets/master_admin_guard.dart';
import 'teacher/teacher_dashboard_screen.dart';
import 'teacher/attendance_screen.dart';
import 'teacher/results_screen.dart';
import 'common/profile_screen.dart';

/// مین اسکرین
/// Main Screen with Bottom Navigation Bar
/// This serves as the navigation wrapper for the Teacher role (Phase 1)
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  /// True when the signed-in user is a platform operator (platform_owner or
  /// platform_support). Drives the conditional "Platform Admin" entry.
  bool _isPlatformAdmin = false;

  @override
  void initState() {
    super.initState();
    // Lightweight platform_admins lookup (fails closed → entry stays hidden).
    fetchPlatformAdminRole().then((role) {
      if (mounted && role != null) {
        setState(() => _isPlatformAdmin = true);
      }
    });
  }

  // List of screens for each tab
  final List<Widget> _screens = const [
    TeacherDashboardScreen(), // ہوم
    AttendanceScreen(), // حاضری
    ResultsScreen(), // نتائج
    ProfileScreen(), // پروفائل
  ];

  // Navigation items for Teacher role
  final List<_NavItem> _navItems = const [
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: AppStrings.home,
    ),
    _NavItem(
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check,
      label: AppStrings.attendance,
    ),
    _NavItem(
      icon: Icons.assessment_outlined,
      activeIcon: Icons.assessment,
      label: AppStrings.results,
    ),
    _NavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: AppStrings.profile,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ...List.generate(
                  _navItems.length,
                  (index) => _buildNavItem(index),
                ),
                // Platform Admin entry — visible only to platform operators.
                // Opens the guarded '/master' route (the guard re-verifies).
                if (_isPlatformAdmin) _buildPlatformAdminItem(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final item = _navItems[index];
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? item.activeIcon : item.icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: AppTypography.navLabel.copyWith(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Conditional "Platform Admin" entry (platform operators only).
  /// Pushes the guarded '/master' route — MasterAdminGuard re-verifies.
  Widget _buildPlatformAdminItem() {
    return InkWell(
      onTap: () => Navigator.of(context).pushNamed('/master'),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.admin_panel_settings_outlined,
              color: AppColors.warning,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              'پلیٹ فارم',
              style: AppTypography.navLabel.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper class for navigation items
class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
