/// پلیٹ فارم ایڈمن شیل
/// Master Admin shell — responsive platform-console navigation.
///
/// Desktop (width ≥ 1100px): persistent RIGHT-side [MasterAdminNavRail]
/// (same pattern as the tenant [AppNavRail] — ONE NAVIGATION SYSTEM).
/// Smaller screens: the same rail inside a drawer.
/// Mounted behind MasterAdminGuard on the '/master' route.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:madrasa_360/core/design/m360.dart';

import '../../../core/widgets/master_admin_guard.dart';
import '../../shell/app_shell.dart' show AppShell, kDesktopBreakpoint;
import '../common/dashboard_guide_screen.dart';
import 'audit_logs_screen.dart';
import 'console_profile_screen.dart';
import 'create_madrasa_wizard.dart';
import 'licenses_screen.dart';
import 'madrasa_detail_screen.dart';
import 'madrasa_list_screen.dart';
import 'master_admin_nav.dart';
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
  String _selectedId = 'dashboard';
  String? _role;

  @override
  void initState() {
    super.initState();
    fetchPlatformAdminRole().then((role) {
      if (mounted) setState(() => _role = role);
    });
  }

  MaNavDestination get _currentDestination {
    for (final group in kConsoleNavGroups) {
      for (final dest in group.destinations) {
        if (dest.id == _selectedId) return dest;
      }
    }
    return kConsoleNavGroups.first.destinations.first;
  }

  String? get _operatorEmail =>
      Supabase.instance.client.auth.currentUser?.email;

  Widget get _screen {
    switch (_selectedId) {
      case 'dashboard':
        return const MasterDashboardScreen();
      case 'madrasas':
        return MadrasaListScreen(
          onOpenDetail: (tenantId) => _openDetail(tenantId),
        );
      case 'plans':
        return const PlansScreen();
      case 'subscriptions':
        return const SubscriptionsScreen();
      case 'licenses':
        return const LicensesScreen();
      case 'modules':
        return const ModulesScreen();
      case 'audit-logs':
        return const AuditLogsScreen();
      case 'platform-users':
        return const PlatformUsersScreen();
      default:
        return const MasterDashboardScreen();
    }
  }

  /// Handles a rail selection. Action destinations push a route instead of
  /// swapping the inline screen; the selection stays where it was.
  void _handleSelect(String id) {
    if (id == 'create-madrasa') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CreateMadrasaWizard()),
      );
      return;
    }
    setState(() => _selectedId = id);
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

  /// Opens the operator's editable profile.
  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConsoleProfileScreen(role: _role),
      ),
    );
  }

  /// Leaves the platform console and returns to the normal app shell.
  /// A plain pop() is enough when the console was pushed on top of the app,
  /// but if the console is the only route in the stack (deep link, restored
  /// session), popping would close the app — so fall back to an explicit
  /// replacement with [AppShell]. Either way the operator is never
  /// stranded inside the console.
  void _backToApp() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Root console shell: the single Scaffold for the '/master' route.
    // Retained by design — the destinations inside use PageContainer /
    // PageHeader and must not add their own Scaffolds.
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    final rail = MasterAdminNavRail(
      selectedId: _selectedId,
      onSelect: _handleSelect,
      role: _role,
      operatorEmail: _operatorEmail,
      onOpenProfile: _openProfile,
    );

    return Scaffold(
      appBar: M360AppBar(
        // Section-aware title: the operator always knows where they are.
        title: _currentDestination.urduLabel,
        // The rail owns navigation here; a back arrow would wrongly
        // imply this console is a pushed deep screen.
        showBack: false,
        actions: [
          const DashboardGuideButton(roleKey: 'master'),
          // Always-visible exit back to the tenant app — the rail footer
          // now holds the profile button, so this is the way out.
          M360IconButton(
            icon: Icons.home_outlined,
            tooltip: 'Back to app',
            onPressed: _backToApp,
          ),
        ],
      ),
      drawer: isDesktop
          ? null
          : Drawer(
              child: Builder(
                builder: (drawerContext) => MasterAdminNavRail(
                  selectedId: _selectedId,
                  onSelect: (id) {
                    Navigator.of(drawerContext).pop();
                    _handleSelect(id);
                  },
                  inDrawer: true,
                  onCloseDrawer: () => Navigator.of(drawerContext).pop(),
                  role: _role,
                  operatorEmail: _operatorEmail,
                  onOpenProfile: () {
                    Navigator.of(drawerContext).pop();
                    _openProfile();
                  },
                ),
              ),
            ),
      body: isDesktop
          ? Row(
              children: [
                // First child in forced-RTL renders on the RIGHT.
                rail,
                const VerticalDivider(width: 1),
                Expanded(child: _screen),
              ],
            )
          : _screen,
    );
  }
}
