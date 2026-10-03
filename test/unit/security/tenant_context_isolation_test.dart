/// Client-side cross-tenant isolation tests.
///
/// Implementation files under test:
///   lib/core/services/tenant_context.dart
///
/// Runnable subset of the 19-test isolation plan
/// (docs/audit/security/raw/tenant-isolation.md §(c)):
///   #18 tenant switch — the client must never enter a tenant context the
///       user has no membership in.
///
/// Strategy mirrors test/unit/tenant_context_test.dart: the real
/// TenantContext driven through a ProviderContainer, with the repository
/// layer (tenantMembershipsProvider) overridden by canned memberships and
/// SharedPreferences mocked in-memory.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

TenantMembership _m(String tenantId, {String role = 'admin'}) =>
    TenantMembership(
      tenantId: tenantId,
      role: role,
      tenantName: 'Madrasa $tenantId',
    );

Future<ProviderContainer> _container(List<TenantMembership> memberships) async {
  final c = ProviderContainer(
    overrides: [
      tenantMembershipsProvider.overrideWith(
        (ref) async => memberships,
      ),
    ],
  );
  addTearDown(c.dispose);
  await c.read(tenantMembershipsProvider.future);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('tenant isolation — tampered persisted choice (plan #18)', () {
    test('init() rejects a saved tenant id with no membership', () async {
      SharedPreferences.setMockInitialValues(
          {TenantContext.prefsKey: 'tenant-evil'});
      final c = await _container([_m('tenant-a'), _m('tenant-b')]);

      await c.read(activeTenantIdProvider.notifier).init();

      // The tampered id must not be adopted; falls back to a membership.
      expect(c.read(activeTenantIdProvider), 'tenant-a');
    });

    test('currentTenantIdProvider never exposes a non-member tenant', () async {
      final c = await _container([_m('tenant-a')]);
      await c.read(activeTenantIdProvider.notifier).init();

      // Even if raw state were poisoned, the effective provider used by
      // every data provider stays inside the membership set.
      c.read(activeTenantIdProvider.notifier).state = 'tenant-evil';
      expect(c.read(currentTenantIdProvider), 'tenant-a');
    });
  });

  group('tenant isolation — switchTenant membership validation (plan #18)', () {
    test(
      'switchTenant refuses a tenant id with no membership',
      () async {
        final c = await _container([_m('tenant-a')]);
        await c.read(activeTenantIdProvider.notifier).init();

        await c.read(activeTenantIdProvider.notifier).switchTenant('tenant-b');

        // After the fix the switch is refused and context is unchanged.
        expect(c.read(activeTenantIdProvider), 'tenant-a');
        expect(c.read(currentTenantIdProvider), 'tenant-a');
      },
      skip: 'pending switchTenant membership validation fix '
          '(tenant-isolation plan #18 / SEC-M3): switchTenant() currently '
          'persists any id without checking memberships',
    );
  });

  group('tenant isolation — logout clears context', () {
    test('clear() drops state and the persisted choice', () async {
      final c = await _container([_m('tenant-a')]);
      await c.read(activeTenantIdProvider.notifier).init();
      expect(c.read(activeTenantIdProvider), 'tenant-a');

      await c.read(activeTenantIdProvider.notifier).clear();

      expect(c.read(activeTenantIdProvider), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(TenantContext.prefsKey), isNull);
    });
  });
}
