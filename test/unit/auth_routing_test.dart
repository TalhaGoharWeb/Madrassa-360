// Unit tests for postAuthDestination
// (lib/presentation/screens/auth/auth_routing.dart).
//
// Contract (user directive 2026-09-30): a super admin / platform admin goes
// DIRECTLY to the platform console — never to a tenant dashboard, the
// tenant picker, or NoAccess — no matter how many tenant memberships they
// hold. Everyone else follows AuthRoute.
//
// Background: the app used to detect platform admins via `platform_admins`
// only, so a super admin (row in `super_admins`, migration 023) was not
// recognised and landed on a tenant dashboard. The check now covers both
// tables; this test pins the routing half of that contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/widgets/master_admin_guard.dart';
import 'package:madrasa_360/presentation/screens/auth/auth_routing.dart';
import 'package:madrasa_360/presentation/screens/auth/no_access_screen.dart';
import 'package:madrasa_360/presentation/screens/auth/tenant_picker_screen.dart';
import 'package:madrasa_360/presentation/screens/master_admin/master_admin_shell.dart';
import 'package:madrasa_360/presentation/shell/app_shell.dart';
import 'package:madrasa_360/providers/auth_provider.dart';

const _adminUser = AppUser(
  id: 'admin-uid',
  email: 'muhaqqiqcreates@gmail.com',
  name: 'Platform Admin',
  role: UserRole.superAdmin,
);

AuthState _state({
  required bool isPlatformAdmin,
  AuthRoute route = AuthRoute.home,
}) =>
    AuthState.authenticated(
      _adminUser,
      const {},
      route: route,
      isPlatformAdmin: isPlatformAdmin,
    );

void main() {
  group('postAuthDestination — platform admin', () {
    test('goes to the guarded platform console, not the tenant shell', () {
      final dest = postAuthDestination(_state(isPlatformAdmin: true));

      expect(dest, isA<MasterAdminGuard>());
      final guard = dest as MasterAdminGuard;
      expect(guard.child, isA<MasterAdminShell>());
    });

    test('skips the tenant picker even with several memberships', () {
      final dest = postAuthDestination(
        _state(isPlatformAdmin: true, route: AuthRoute.tenantPicker),
      );

      expect(dest, isA<MasterAdminGuard>());
      expect(dest, isNot(isA<TenantPickerScreen>()));
    });

    test('never lands on NoAccess', () {
      final dest = postAuthDestination(
        _state(isPlatformAdmin: true, route: AuthRoute.noAccess),
      );

      expect(dest, isA<MasterAdminGuard>());
      expect(dest, isNot(isA<NoAccessScreen>()));
    });
  });

  group('postAuthDestination — regular users follow AuthRoute', () {
    test('home → AppShell', () {
      expect(
        postAuthDestination(
            _state(isPlatformAdmin: false, route: AuthRoute.home)),
        isA<AppShell>(),
      );
    });

    test('tenantPicker → TenantPickerScreen', () {
      expect(
        postAuthDestination(
            _state(isPlatformAdmin: false, route: AuthRoute.tenantPicker)),
        isA<TenantPickerScreen>(),
      );
    });

    test('noAccess → NoAccessScreen', () {
      expect(
        postAuthDestination(
            _state(isPlatformAdmin: false, route: AuthRoute.noAccess)),
        isA<NoAccessScreen>(),
      );
    });
  });
}
