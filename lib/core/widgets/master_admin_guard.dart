/// پلیٹ فارم ایڈمن گارڈ
/// Master Admin Guard — gates the /master route behind platform_admins.
///
/// A user is granted access iff a row exists in `public.platform_admins`
/// for their auth uid (role ∈ platform_owner | platform_support).
///
/// RLS NOTE (checked 2026-09-25 against supabase/migrations/004_memberships.sql):
/// platform_admins has ONE policy, "platform admins only" (FOR ALL USING
/// public.is_platform_admin()). There is NO dedicated self-read policy, but
/// the guard still works: a platform admin's own SELECT passes the policy
/// (is_platform_admin() is SECURITY DEFINER and returns true for them), while
/// everyone else gets zero rows — which is exactly the deny case. The guard
/// FAILS CLOSED: any error, null user, or missing row → access denied.
/// If Worker 4 ever replaces the policy set, this guard keeps denying until
/// a platform admin can read their own row again.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../presentation/screens/auth/login_screen.dart';
import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import 'loading_widget.dart';

/// Returns the caller's platform role ('platform_owner' | 'platform_support')
/// or null when the caller is not a platform admin. Fails closed on error.
Future<String?> fetchPlatformAdminRole() async {
  try {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return null;

    final row = await client
        .from('platform_admins')
        .select('role')
        .eq('user_id', uid)
        .maybeSingle();

    final role = row?['role'] as String?;
    if (role == 'platform_owner' || role == 'platform_support') {
      return role;
    }
    return null;
  } catch (_) {
    // Fail closed: any RLS/network/parse error means "not a platform admin".
    return null;
  }
}

/// Wraps the Master Admin section. Shows a loader, then either [child]
/// (platform admin) or an access-denied panel with sign-out.
class MasterAdminGuard extends StatefulWidget {
  final Widget child;

  const MasterAdminGuard({super.key, required this.child});

  @override
  State<MasterAdminGuard> createState() => _MasterAdminGuardState();
}

class _MasterAdminGuardState extends State<MasterAdminGuard> {
  late final Future<String?> _roleFuture;

  @override
  void initState() {
    super.initState();
    _roleFuture = fetchPlatformAdminRole();
  }

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _roleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: LoadingWidget(message: 'اجازت کی جانچ ہو رہی ہے…'),
          );
        }

        final role = snapshot.data;
        if (role == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Platform Admin')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.block,
                      size: 72,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Access denied',
                      style: AppTypography.headingMedium.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'یہ حصہ صرف پلیٹ فارم آپریٹرز کے لیے ہے۔\n'
                      'This section is restricted to platform operators only.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: () => _signOut(context),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return widget.child;
      },
    );
  }
}
