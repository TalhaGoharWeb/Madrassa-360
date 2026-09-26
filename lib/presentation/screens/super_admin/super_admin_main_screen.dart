import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import 'super_admin_dashboard_screen.dart';
import 'madrasa_management_screen.dart';
import '../admin/user_management_screen.dart';
import '../common/about_screen.dart';

/// @deprecated Phase-3 replacement: the legacy Super Admin shell is
/// superseded by MasterAdminShell at
/// lib/presentation/screens/master_admin/master_admin_shell.dart (route
/// '/master', gated by MasterAdminGuard). Kept only because other code may
/// still reference it — do not build new features here.
@Deprecated('Use master_admin_shell.dart instead')
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
          indicatorColor: AppColors.primary.withValues(alpha: 0.12),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard, color: AppColors.primary),
              label: 'ڈیش بورڈ',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_outlined),
              selectedIcon:
                  Icon(Icons.account_balance, color: AppColors.primary),
              label: 'مدارس',
            ),
            NavigationDestination(
              icon: Icon(Icons.manage_accounts_outlined),
              selectedIcon:
                  Icon(Icons.manage_accounts, color: AppColors.primary),
              label: 'صارفین',
            ),
            NavigationDestination(
              icon: Icon(Icons.info_outline),
              selectedIcon: Icon(Icons.info, color: AppColors.primary),
              label: 'بارے میں',
            ),
          ],
        ),
      );
    });
  }
}
