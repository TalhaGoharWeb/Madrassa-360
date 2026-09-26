import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../providers/auth_provider.dart';
import '../main_screen.dart';
import 'login_screen.dart';
import 'no_access_screen.dart';
import 'tenant_picker_screen.dart';

/// Auth gate — the app's cold-start entry point.
///
/// On launch it asks the auth provider to restore any persisted Supabase
/// session (honoring the "remember me" choice), showing a branded splash
/// meanwhile. Once the restore settles it renders the same destination the
/// login screen would navigate to:
///
///   authenticated + home         → [MainScreen]
///   authenticated + tenantPicker → [TenantPickerScreen]
///   authenticated + noAccess     → [NoAccessScreen]
///   anything else                → [LoginScreen]
///
/// The gate only matters for cold start: after it renders [LoginScreen],
/// that screen's own pushReplacement flow takes over as before.
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
    // restoreSession() catches its own errors, but guard anyway: the gate
    // must never strand the user on the splash.
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
    switch (auth.route) {
      case AuthRoute.home:
        return const MainScreen();
      case AuthRoute.tenantPicker:
        return const TenantPickerScreen();
      case AuthRoute.noAccess:
        return const NoAccessScreen();
      case AuthRoute.login:
        return const LoginScreen();
    }
  }
}

/// Minimal branded splash shown while the session restore settles.
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
