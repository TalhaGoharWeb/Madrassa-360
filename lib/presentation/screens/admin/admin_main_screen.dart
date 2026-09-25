/// منتظم مین اسکرین — کردار کی بنیاد پر متحرک نیویگیشن
/// Admin Main Screen — permission-driven bottom navigation.
/// All 11 staff roles land here; the nav tabs and home dashboard adapt
/// to each user's permission set automatically.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/role_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import 'admin_dashboard_screen.dart';
import 'student_list_screen.dart';
import 'staff_list_screen.dart';
import 'fee_management_screen.dart';
import 'user_management_screen.dart';
import '../teacher/attendance_screen.dart';
import '../teacher/results_screen.dart';
import '../common/profile_screen.dart';

class AdminMainScreen extends StatefulWidget {
  const AdminMainScreen({super.key});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  int _currentIndex = 0;
  List<NavTab> _tabs = [];

  // Phase 4 — module gating: [enabledModules] comes from
  // tenantModulesProvider. Null = not loaded yet → no filtering, so the
  // bar does not flicker while the tenant resolves.
  List<NavTab> _buildTabs(Set<String> perms, Set<String>? enabledModules) =>
      buildNavTabs(
        perms: perms,
        enabledModules: enabledModules,
        dashboardBuilder: () => const AdminDashboardScreen(),
        profileScreen: const ProfileScreen(),
        attendanceScreen: const AttendanceScreen(),
        studentsScreen: const StudentListScreen(),
        staffScreen: const StaffListScreen(),
        feesScreen: const FeeManagementScreen(),
        usersScreen: const UserManagementScreen(),
        resultsScreen: const ResultsScreen(),
      );

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final perms = ref.watch(userPermissionsProvider);
      final enabledModules = ref.watch(tenantModulesProvider).valueOrNull;
      final newTabs = _buildTabs(perms, enabledModules);

      // Reset to 0 when tab count changes (e.g. after session restore).
      if (newTabs.length != _tabs.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _currentIndex = 0);
        });
      }
      _tabs = newTabs;

      final safeIndex = _currentIndex.clamp(0, _tabs.length - 1);

      return Scaffold(
        body: IndexedStack(
          index: safeIndex,
          children: _tabs.map((t) => t.screen).toList(),
        ),
        bottomNavigationBar: _buildNavBar(safeIndex),
      );
    });
  }

  Widget _buildNavBar(int safeIndex) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
            children: List.generate(
              _tabs.length,
              (i) => _buildNavItem(i, safeIndex),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, int safeIndex) {
    final tab = _tabs[index];
    final isSelected = index == safeIndex;

    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? tab.activeIcon : tab.icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: AppTypography.navLabel.copyWith(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
