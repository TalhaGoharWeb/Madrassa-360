import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import 'super_admin_dashboard_screen.dart';
import 'madrasa_management_screen.dart';
import '../admin/user_management_screen.dart';
import '../common/about_screen.dart';

class SuperAdminMainScreen extends StatefulWidget {
  const SuperAdminMainScreen({super.key});
  @override
  State<SuperAdminMainScreen> createState() => _SuperAdminMainScreenState();
}

class _SuperAdminMainScreenState extends State<SuperAdminMainScreen> {
  int _index = 0;

  final _screens = const [
    SuperAdminDashboardScreen(),
    MadrasaManagementScreen(),
    UserManagementScreen(),
    AboutScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, ref, _) {
      return Scaffold(
        body: _screens[_index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: Colors.white,
          indicatorColor: AppColors.primary.withOpacity(0.12),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: const Icon(Icons.dashboard, color: AppColors.primary),
              label: 'ڈیش بورڈ',
            ),
            NavigationDestination(
              icon: const Icon(Icons.account_balance_outlined),
              selectedIcon: const Icon(Icons.account_balance, color: AppColors.primary),
              label: 'مدارس',
            ),
            NavigationDestination(
              icon: const Icon(Icons.manage_accounts_outlined),
              selectedIcon: const Icon(Icons.manage_accounts, color: AppColors.primary),
              label: 'صارفین',
            ),
            NavigationDestination(
              icon: const Icon(Icons.info_outline),
              selectedIcon: const Icon(Icons.info, color: AppColors.primary),
              label: 'بارے میں',
            ),
          ],
        ),
      );
    });
  }
}
