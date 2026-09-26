// Guard widget tests (Phase 5).
//
// Widgets under test:
//   lib/core/widgets/permission_guard.dart
//   lib/core/widgets/role_guard.dart
//   lib/core/widgets/scope_guard.dart
//
// Guards are presentation-only (RLS remains the enforcement); these tests
// pin the show/hide behavior. ScopeGuard needs Supabase for scope rows, so
// only its fail-closed contracts are covered here: with no resolvable scope
// (no active tenant, or no signed-in session because Supabase is
// uninitialized in tests) the guard hides the child — mirroring migration
// 022, where `scope_allows()` denies when no `permission_scopes` row exists.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/core/widgets/permission_guard.dart';
import 'package:madrasa_360/core/widgets/role_guard.dart';
import 'package:madrasa_360/core/widgets/scope_guard.dart';
import 'package:madrasa_360/providers/auth_provider.dart';

Widget _harness(ProviderContainer c, Widget child) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('PermissionGuard', () {
    testWidgets('shows the child when the permission is held', (tester) async {
      final c = ProviderContainer(overrides: [
        userPermissionsProvider.overrideWithValue({AppPermissions.collectFees}),
      ]);
      addTearDown(c.dispose);

      await tester.pumpWidget(_harness(
        c,
        const PermissionGuard(
          permission: AppPermissions.collectFees,
          child: Text('فیس وصول کریں'),
        ),
      ));

      expect(find.text('فیس وصول کریں'), findsOneWidget);
    });

    testWidgets('hides the child when the permission is missing',
        (tester) async {
      final c = ProviderContainer(overrides: [
        userPermissionsProvider.overrideWithValue({}),
      ]);
      addTearDown(c.dispose);

      await tester.pumpWidget(_harness(
        c,
        const PermissionGuard(
          permission: AppPermissions.collectFees,
          child: Text('فیس وصول کریں'),
        ),
      ));

      expect(find.text('فیس وصول کریں'), findsNothing);
    });

    testWidgets('shows the fallback when the permission is missing',
        (tester) async {
      final c = ProviderContainer(overrides: [
        userPermissionsProvider.overrideWithValue({}),
      ]);
      addTearDown(c.dispose);

      await tester.pumpWidget(_harness(
        c,
        const PermissionGuard(
          permission: AppPermissions.collectFees,
          fallback: Text('رسائی نہیں'),
          child: Text('فیس وصول کریں'),
        ),
      ));

      expect(find.text('فیس وصول کریں'), findsNothing);
      expect(find.text('رسائی نہیں'), findsOneWidget);
    });
  });

  group('RoleGuard', () {
    Future<ProviderContainer> adminContainer() async {
      final c = ProviderContainer(overrides: [
        tenantMembershipsProvider.overrideWith((ref) async => [
              const TenantMembership(
                tenantId: 't1',
                role: 'tenant_admin',
                tenantName: 'مدرسہ',
              ),
            ]),
      ]);
      c.read(activeTenantIdProvider.notifier).state = 't1';
      await c.read(tenantMembershipsProvider.future);
      return c;
    }

    testWidgets('shows the child when a required role is held', (tester) async {
      final c = await adminContainer();
      addTearDown(c.dispose);

      await tester.pumpWidget(_harness(
        c,
        const RoleGuard(
          roleKeys: {'tenant_owner', 'tenant_admin'},
          child: Text('خطرناک حصہ'),
        ),
      ));

      expect(find.text('خطرناک حصہ'), findsOneWidget);
    });

    testWidgets('hides the child when no required role is held',
        (tester) async {
      final c = await adminContainer();
      addTearDown(c.dispose);

      await tester.pumpWidget(_harness(
        c,
        const RoleGuard(
          roleKeys: {'tenant_owner'},
          child: Text('خطرناک حصہ'),
        ),
      ));

      expect(find.text('خطرناک حصہ'), findsNothing);
    });
  });

  group('ScopeGuard', () {
    testWidgets('hides the child when no scope can be resolved (no tenant)',
        (tester) async {
      // No active tenant -> _ensureLoaded returns null -> fail closed.
      final c = ProviderContainer();
      addTearDown(c.dispose);

      await tester.pumpWidget(_harness(
        c,
        const ScopeGuard(
          permission: AppPermissions.markAttendance,
          classId: 'c1',
          child: Text('حاضری لگائیں'),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('حاضری لگائیں'), findsNothing);
    });

    testWidgets('hides the child when the session cannot be resolved',
        (tester) async {
      // Tenant active but Supabase uninitialized in tests -> no user id ->
      // fail closed (022: no row means deny).
      final c = ProviderContainer(overrides: [
        activeTenantIdProvider.overrideWith((ref) => TenantContext(ref)),
      ]);
      addTearDown(c.dispose);
      c.read(activeTenantIdProvider.notifier).state = 'tenant-1';

      await tester.pumpWidget(_harness(
        c,
        const ScopeGuard(
          permission: AppPermissions.markAttendance,
          classId: 'c1',
          fallback: Text('رسائی نہیں'),
          child: Text('حاضری لگائیں'),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('حاضری لگائیں'), findsNothing);
      expect(find.text('رسائی نہیں'), findsOneWidget);
    });
  });
}
