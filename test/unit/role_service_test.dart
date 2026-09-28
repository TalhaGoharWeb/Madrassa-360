// RoleService unit tests (Phase 5).
//
// Implementation file under test:
//   lib/core/services/role_service.dart
//
// Capability helpers are derived from the EFFECTIVE PERMISSION SET
// (overridden here), never from role-name strings. Role-key helpers and the
// Urdu label fallback are covered with tenant memberships overridden per
// test. The live `tenant_roles` label query is NOT covered here (needs
// Supabase); the test asserts the static fallback path.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/providers/auth_provider.dart';

const _membership = TenantMembership(
  tenantId: 't1',
  role: 'tenant_admin',
  tenantName: 'مدرسہ',
);

ProviderContainer makeContainer({
  Set<String> permissions = const {},
  List<TenantMembership> memberships = const [_membership],
}) {
  final c = ProviderContainer(overrides: [
    userPermissionsProvider.overrideWithValue(permissions),
    tenantMembershipsProvider.overrideWith((ref) async => memberships),
  ]);
  c.read(activeTenantIdProvider.notifier).state = 't1';
  return c;
}

void main() {
  group('permission-derived capabilities (no role-name string checks)', () {
    test('canManageRoles follows roles.assign, not the role name', () {
      final c = makeContainer(permissions: {AppPermissions.assignRoles});
      addTearDown(c.dispose);
      expect(c.read(roleServiceProvider).canManageRoles(), isTrue);

      final c2 = makeContainer();
      addTearDown(c2.dispose);
      // tenant_admin role key but no roles.assign grant -> false
      expect(c2.read(roleServiceProvider).canManageRoles(), isFalse);
    });

    test('canCollectFees follows fees.collect', () {
      final c = makeContainer(permissions: {AppPermissions.collectFees});
      addTearDown(c.dispose);
      expect(c.read(roleServiceProvider).canCollectFees(), isTrue);
      expect(c.read(roleServiceProvider).canApproveFinance(), isFalse);
    });

    test('isPrincipal needs the full academic authority set', () {
      final full = makeContainer(permissions: {
        AppPermissions.manageDarjas,
        AppPermissions.publishExams,
        AppPermissions.publishResults,
      });
      addTearDown(full.dispose);
      expect(full.read(roleServiceProvider).isPrincipal(), isTrue);

      final partial = makeContainer(permissions: {
        AppPermissions.manageDarjas,
        AppPermissions.publishExams,
      });
      addTearDown(partial.dispose);
      expect(partial.read(roleServiceProvider).isPrincipal(), isFalse);
    });

    test('canSendAnnouncements follows notifications.send', () {
      final c = makeContainer(permissions: {AppPermissions.sendNotifications});
      addTearDown(c.dispose);
      expect(c.read(roleServiceProvider).canSendAnnouncements(), isTrue);
    });
  });

  group('role-key helpers (tenant administration only)', () {
    test('activeRoleKeys resolves from memberships for the active tenant',
        () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      await c.read(tenantMembershipsProvider.future);
      expect(c.read(activeRoleKeysProvider), ['tenant_admin']);
      expect(c.read(roleServiceProvider).isTenantAdmin(), isTrue);
      expect(c.read(roleServiceProvider).isTenantOwner(), isFalse);
    });

    test('isTenantOwner only for tenant_owner', () async {
      final c = makeContainer(memberships: const [
        TenantMembership(
            tenantId: 't1', role: 'tenant_owner', tenantName: 'مدرسہ'),
      ]);
      addTearDown(c.dispose);
      await c.read(tenantMembershipsProvider.future);
      expect(c.read(roleServiceProvider).isTenantOwner(), isTrue);
      expect(c.read(roleServiceProvider).isTenantAdmin(), isTrue);
    });

    test('no memberships -> no role keys', () async {
      final c = makeContainer(memberships: const []);
      addTearDown(c.dispose);
      await c.read(tenantMembershipsProvider.future);
      expect(c.read(roleServiceProvider).activeRoleKeys(), isEmpty);
      expect(c.read(roleServiceProvider).isTenantAdmin(), isFalse);
    });
  });

  group('roleUrduLabel static fallback', () {
    test('template role keys resolve to Urdu labels without the server',
        () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      // Supabase is not initialized in unit tests -> static fallback path.
      expect(
          await c.read(roleServiceProvider).roleUrduLabel('teacher'), 'استاد');
      expect(await c.read(roleServiceProvider).roleUrduLabel('tenant_owner'),
          'مالک');
      expect(
          await c.read(roleServiceProvider).roleUrduLabel('mohtamim'), 'مہتمم');
    });
  });
}
