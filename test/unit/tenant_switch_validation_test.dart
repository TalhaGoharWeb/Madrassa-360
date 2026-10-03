// SEC-M24 regression tests — TenantContext.switchTenant must refuse tenant
// ids that are not in the user's server-derived membership list.
//
// What is real here: TenantContext.switchTenant with tenantMembershipsProvider
// overridden to a fixed membership list (no network). Previously any UUID was
// accepted and persisted; now an unknown id throws before any state changes.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

TenantMembership _member(String id, {bool active = true}) => TenantMembership(
      tenantId: id,
      role: 'teacher',
      tenantName: 'Test Madrasa',
      isActive: active,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer() {
    SharedPreferences.setMockInitialValues({});
    return ProviderContainer(
      overrides: [
        tenantMembershipsProvider.overrideWith(
          (ref) async => [_member('tenant-a'), _member('tenant-b')],
        ),
      ],
    );
  }

  test('switchTenant accepts a membership tenant', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(activeTenantIdProvider.notifier);

    await notifier.switchTenant('tenant-a');

    expect(container.read(activeTenantIdProvider), 'tenant-a');
  });

  test('switchTenant rejects an unknown tenant id', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(activeTenantIdProvider.notifier);

    await expectLater(
      notifier.switchTenant('attacker-tenant'),
      throwsA(isA<StateError>()),
    );
    // State is untouched by the rejected switch.
    expect(container.read(activeTenantIdProvider), isNull);
  });
}
