/// پلیٹ فارم ایڈمن شیل
/// Master Admin shell — drawer navigation for all platform-operator sections.
/// Mounted behind MasterAdminGuard on the '/master' route.

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/widgets/master_admin_guard.dart';
import '../common/dashboard_guide_screen.dart';
import '../main_screen.dart';
import 'audit_logs_screen.dart';
import 'licenses_screen.dart';
import 'madrasa_detail_screen.dart';
import 'madrasa_list_screen.dart';
import 'master_dashboard_screen.dart';
import 'modules_screen.dart';
import 'plans_screen.dart';
import 'platform_users_screen.dart';
import 'subscriptions_screen.dart';

class MasterAdminShell extends StatefulWidget {
  const MasterAdminShell({super.key});

  @override
  State<MasterAdminShell> createState() => _MasterAdminShellState();
}

class _MasterAdminShellState extends State<MasterAdminShell> {
  int _index = 0;
  String? _role;

  @override
  void initState() {
    super.initState();
    fetchPlatformAdminRole().then((role) {
      if (mounted) setState(() => _role = role);
    });
  }

  static const _items = [
    _MaNavItem('Dashboard', Icons.dashboard_outlined),
    _MaNavItem('Madrasas', Icons.account_balance_outlined),
    _MaNavItem('Plans', Icons.card_membership_outlined),
    _MaNavItem('Subscriptions', Icons.autorenew_outlined),
    _MaNavItem('Licenses', Icons.verified_outlined),
    _MaNavItem('Modules', Icons.extension_outlined),
    _MaNavItem('Audit Logs', Icons.receipt_long_outlined),
    _MaNavItem('Platform Users', Icons.admin_panel_settings_outlined),
  ];

  Widget get _screen {
    switch (_index) {
      case 0:
        return const MasterDashboardScreen();
      case 1:
        return MadrasaListScreen(
          onOpenDetail: (tenantId) => _openDetail(tenantId),
        );
      case 2:
        return const PlansScreen();
      case 3:
        return const SubscriptionsScreen();
      case 4:
        return const LicensesScreen();
      case 5:
        return const ModulesScreen();
      case 6:
        return const AuditLogsScreen();
      case 7:
        return const PlatformUsersScreen();
      default:
        return const MasterDashboardScreen();
    }
  }

  void _openDetail(String tenantId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MasterAdminGuard(
          child: MadrasaDetailScreen(tenantId: tenantId),
        ),
      ),
    );
  }

  /// Leaves the platform console and returns to the normal app shell.
  /// A plain pop() is enough when the console was pushed on top of the app,
  /// but if the console is the only route in the stack (deep link, restored
  /// session), popping would close the app — so fall back to an explicit
  /// replacement with [MainScreen]. Either way the operator is never
  /// stranded inside the console.
  void _backToApp() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _role == 'platform_owner'
              ? 'Platform Owner Console'
              : 'Platform Admin Console',
        ),
        actions: [
          const DashboardGuideButton(roleKey: 'master'),
          // Always-visible exit: the drawer also has "Back to app", but an
          // operator should never have to hunt for the way out.
          TextButton.icon(
            onPressed: _backToApp,
            icon: const Icon(
              Icons.home_outlined,
              color: Colors.white,
              size: 20,
            ),
            label: Text(
              'Back to app',
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _role ?? '…',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                color: AppColors.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_outlined,
                        color: Colors.white, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      'Madrassa-360',
                      style: AppTypography.titleLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'پلیٹ فارم انتظامیہ',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    final selected = i == _index;
                    return ListTile(
                      leading: Icon(
                        item.icon,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      title: Text(
                        item.label,
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                      ),
                      selected: selected,
                      selectedTileColor:
                          AppColors.primary.withValues(alpha: 0.08),
                      onTap: () {
                        setState(() => _index = i);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.arrow_back,
                    color: AppColors.textSecondary),
                title: const Text('Back to app'),
                onTap: () {
                  Navigator.of(context).pop(); // close the drawer first
                  _backToApp();
                },
              ),
            ],
          ),
        ),
      ),
      body: _screen,
    );
  }
}

class _MaNavItem {
  final String label;
  final IconData icon;
  const _MaNavItem(this.label, this.icon);
}
