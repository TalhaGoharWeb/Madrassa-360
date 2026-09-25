// TenantContext unit tests.
//
// Implementation file under test:
//   lib/core/services/tenant_context.dart
//
// Strategy: the REAL TenantContext class is driven through a real
// Riverpod ProviderContainer. The only faked boundary is the repository
// layer — tenantMembershipsProvider is overridden with canned membership
// lists (the real provider would hit Supabase), and SharedPreferences
// uses the standard test mechanism (setMockInitialValues), which is
// hermetic and in-memory.
//
// BEHAVIOUR NOTE (read from the implementation, not assumed): with N
// memberships and no valid saved choice, init() auto-selects the FIRST
// membership — it does not force an explicit selection. The UI may still
// present a picker; the context itself always resolves to something.

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
  // Resolve the async override so reads see data (not loading).
  await c.read(tenantMembershipsProvider.future);
  return c;
}

Future<String?> _savedPref() async =>
    (await SharedPreferences.getInstance()).getString(TenantContext.prefsKey);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Fresh hermetic prefs backend for every test.
    SharedPreferences.setMockInitialValues({});
  });

  group('TenantContext.init resolution', () {
    test('0 memberships -> null (no access), nothing persisted', () async {
      final c = await _container([]);
      await c.read(activeTenantIdProvider.notifier).init();
      expect(c.read(activeTenantIdProvider), isNull);
      expect(await _savedPref(), isNull);
    });

    test('1 membership -> auto-selected and persisted', () async {
      final c = await _container([_m('t1')]);
      await c.read(activeTenantIdProvider.notifier).init();
      expect(c.read(activeTenantIdProvider), 't1');
      expect(await _savedPref(), 't1');
    });

    test('N memberships, no saved choice -> first membership (documented)',
        () async {
      final c = await _container([_m('t1'), _m('t2'), _m('t3')]);
      await c.read(activeTenantIdProvider.notifier).init();
      expect(c.read(activeTenantIdProvider), 't1');
      expect(await _savedPref(), 't1');
    });

    test('saved valid choice is restored', () async {
      SharedPreferences.setMockInitialValues({TenantContext.prefsKey: 't2'});
      final c = await _container([_m('t1'), _m('t2')]);
      await c.read(activeTenantIdProvider.notifier).init();
      expect(c.read(activeTenantIdProvider), 't2');
    });

    test('saved STALE choice (revoked tenant) -> first membership, pref fixed',
        () async {
      SharedPreferences.setMockInitialValues(
          {TenantContext.prefsKey: 't-gone'});
      final c = await _container([_m('t1'), _m('t2')]);
      await c.read(activeTenantIdProvider.notifier).init();
      expect(c.read(activeTenantIdProvider), 't1');
      expect(await _savedPref(), 't1');
    });
  });

  group('TenantContext.switchTenant / clear (persistence round-trip)', () {
    test('switchTenant updates state and persists', () async {
      final c = await _container([_m('t1'), _m('t2')]);
      final notifier = c.read(activeTenantIdProvider.notifier);
      await notifier.init();
      await notifier.switchTenant('t2');
      expect(c.read(activeTenantIdProvider), 't2');
      expect(await _savedPref(), 't2');
    });

    test('persistence round-trips across a fresh context instance', () async {
      final c1 = await _container([_m('t1'), _m('t2')]);
      await c1.read(activeTenantIdProvider.notifier).init();
      await c1.read(activeTenantIdProvider.notifier).switchTenant('t2');

      // New container = "app restarted": init must restore t2 from prefs.
      final c2 = await _container([_m('t1'), _m('t2')]);
      await c2.read(activeTenantIdProvider.notifier).init();
      expect(c2.read(activeTenantIdProvider), 't2');
    });

    test('clear drops the state and removes the persisted choice', () async {
      final c = await _container([_m('t1')]);
      final notifier = c.read(activeTenantIdProvider.notifier);
      await notifier.init();
      expect(c.read(activeTenantIdProvider), 't1');
      await notifier.clear();
      expect(c.read(activeTenantIdProvider), isNull);
      expect(await _savedPref(), isNull);
    });
  });

  group('currentTenantIdProvider (effective tenant for queries)', () {
    test('active id valid in memberships -> active id', () async {
      final c = await _container([_m('t1'), _m('t2')]);
      await c.read(activeTenantIdProvider.notifier).init();
      await c.read(activeTenantIdProvider.notifier).switchTenant('t2');
      expect(c.read(currentTenantIdProvider), 't2');
    });

    test('active id revoked -> first membership', () async {
      final c = await _container([_m('t2')]);
      // Simulate a stale active id (e.g. membership removed server-side).
      c.read(activeTenantIdProvider.notifier).state = 't1';
      expect(c.read(currentTenantIdProvider), 't2');
    });

    test('no memberships -> null (callers must bail out unscoped)', () async {
      final c = await _container([]);
      expect(c.read(currentTenantIdProvider), isNull);
    });
  });

  group('TenantMembership.fromJson', () {
    test('parses the joined tenants row shape', () {
      final m = TenantMembership.fromJson({
        'tenant_id': 't9',
        'role': 'teacher',
        'is_active': true,
        'tenants': {
          'name': 'Jamia Test',
          'name_urdu': 'جامعہ ٹیسٹ',
          'logo_url': null,
        },
      });
      expect(m.tenantId, 't9');
      expect(m.role, 'teacher');
      expect(m.tenantName, 'Jamia Test');
      expect(m.tenantNameUrdu, 'جامعہ ٹیسٹ');
      expect(m.isActive, isTrue);
    });
  });
}
