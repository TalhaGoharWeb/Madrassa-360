import 'package:flutter/material.dart';

import '../../../core/widgets/master_admin_guard.dart';
import '../../../providers/auth_provider.dart';
import '../master_admin/master_admin_shell.dart';
import '../../shell/app_shell.dart';
import 'no_access_screen.dart';
import 'tenant_picker_screen.dart';

/// Post-authentication destination for a signed-in user.
///
/// Platform admins (a row in `platform_admins` OR in `super_admins`,
/// mirrored from [AuthState.isPlatformAdmin]) go DIRECTLY to the guarded
/// platform console — never to a tenant dashboard, the tenant picker, or
/// NoAccess, no matter how many tenant memberships they hold.
///
/// Returns null for [AuthRoute.login], which cannot occur for an
/// authenticated user; callers fall back to staying put.
Widget? postAuthDestination(AuthState auth) {
  // Super admin / platform admin: straight to the platform console.
  // MasterAdminGuard re-verifies against the server and fails closed.
  if (auth.isPlatformAdmin) {
    return const MasterAdminGuard(child: MasterAdminShell());
  }
  switch (auth.route) {
    case AuthRoute.home:
      return const AppShell();
    case AuthRoute.tenantPicker:
      return const TenantPickerScreen();
    case AuthRoute.noAccess:
      return const NoAccessScreen();
    case AuthRoute.login:
      return null;
  }
}
