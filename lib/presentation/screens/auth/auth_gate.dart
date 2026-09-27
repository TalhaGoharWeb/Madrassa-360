// Fixed AuthGate — super admins go to SuperAdminDashboard, NOT RoleHomeScreen
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/super_admin_service.dart';
import '../dashboards/role_home.dart';
import '../super_admin/super_admin_dashboard.dart';
import '../super_admin/tenant_access_guard.dart';
import 'login_screen.dart';
import 'no_access_screen.dart';
import 'tenant_picker_screen.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _restoreDone = false;

  @override
  void initState() {
    super.initState();
    ref.read(authProvider.notifier).restoreSession().then((_) {
      if (mounted) setState(() => _restoreDone = true);
    }).catchError((_) {
      if (mounted) setState(() => _restoreDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_restoreDone) return const _Splash();

    final auth = ref.watch(authProvider);
    if (!auth.isAuthenticated) return const LoginScreen();

    // SUPER ADMIN CHECK FIRST: super admins see ONLY the super admin
    // dashboard, never a tenant/mohtamim dashboard.
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final isSuperAdminAsync = ref.watch(isSuperAdminProvider(userId));
    
    return isSuperAdminAsync.when(
      data: (isSuperAdmin) {
        if (isSuperAdmin) {
          // Super admin: dedicated dashboard, no tenant context
          return const SuperAdminDashboard();
        }
        // Regular user: normal tenant flow
        switch (auth.route) {
          case AuthRoute.home:
            return const TenantAccessGuard(child: RoleHomeScreen());
          case AuthRoute.tenantPicker:
            return const TenantPickerScreen();
          case AuthRoute.noAccess:
            return const NoAccessScreen();
          case AuthRoute.login:
            return const LoginScreen();
        }
      },
      loading: () => const _Splash(),
      error: (_, __) {
        // Fail closed for super admin check, fall through to normal flow
        // which will handle via tenant memberships
        switch (auth.route) {
          case AuthRoute.home:
            return const TenantAccessGuard(child: RoleHomeScreen());
          case AuthRoute.tenantPicker:
            return const TenantPickerScreen();
          case AuthRoute.noAccess:
            return const NoAccessScreen();
          case AuthRoute.login:
            return const LoginScreen();
        }
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'مدرسہ 360',
                style: AppTypography.headingLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
