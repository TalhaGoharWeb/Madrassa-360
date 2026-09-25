/// Widget tests for the tenant picker screen.
///
/// Implementation files under test:
///   lib/presentation/screens/auth/tenant_picker_screen.dart
///   lib/core/services/tenant_context.dart   (TenantContext, TenantMembership,
///                                            tenantMembershipsProvider,
///                                            activeTenantIdProvider)
///   lib/providers/auth_provider.dart        (selectTenant → route home)
///   lib/presentation/screens/main_screen.dart (post-selection destination)
///
/// Fakes: [FakeAuthRepository] overrides [authRepositoryProvider];
/// `tenantMembershipsProvider` is overridden with two fixture memberships;
/// `appDatabaseProvider` gets an in-memory Drift database because the
/// post-selection [MainScreen] build watches [pendingSyncCountProvider].

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/data/local/app_database.dart';
import 'package:madrasa_360/data/local/database_provider.dart';
import 'package:madrasa_360/presentation/screens/auth/tenant_picker_screen.dart';
import 'package:madrasa_360/presentation/screens/main_screen.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth_repository.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Dummy init: only needed so SupabaseService.client exists.
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'widget-test-anon-key',
    );
  });

  late FakeAuthRepository fakeAuth;
  late AppDatabase db;

  List<TenantMembership> memberships() => const [
        TenantMembership(
          tenantId: 'tenant-1',
          role: 'madrasa_admin',
          tenantName: 'Test Madrasa One',
          tenantNameUrdu: 'ٹیسٹ مدرسہ اول',
        ),
        TenantMembership(
          tenantId: 'tenant-2',
          role: 'teacher',
          tenantName: 'Test Madrasa Two',
        ),
      ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fakeAuth = FakeAuthRepository();
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    fakeAuth.dispose();
    await db.close();
  });

  Future<ProviderContainer> pumpPicker(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        tenantMembershipsProvider.overrideWith(
          (ref) async => memberships(),
        ),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TenantPickerScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('TenantPickerScreen', () {
    testWidgets('renders one tile per membership', (tester) async {
      await pumpPicker(tester);

      expect(find.text('ادارہ منتخب کریں'), findsOneWidget);
      expect(find.text('Test Madrasa One'), findsOneWidget);
      expect(find.text('Test Madrasa Two'), findsOneWidget);
      // Role chips use _roleLabel: 'منتظم (Madrasa admin)' and 'استاد (Teacher)'.
      expect(find.text('منتظم (Madrasa admin)'), findsOneWidget);
      expect(find.text('استاد (Teacher)'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));
    });

    testWidgets(
        'tapping a tile selects the tenant, persists it, and enters the app',
        (tester) async {
      final container = await pumpPicker(tester);

      await tester.tap(find.text('Test Madrasa Two'));
      await tester.pumpAndSettle();

      // TenantContext switched + persisted under 'active_tenant_id'.
      expect(container.read(activeTenantIdProvider), 'tenant-2');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(TenantContext.prefsKey), 'tenant-2');

      // Auth route moved home and the app shell was pushed.
      expect(container.read(authProvider).route, AuthRoute.home);
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(TenantPickerScreen), findsNothing);
    });

    testWidgets('empty memberships show the empty state', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          tenantMembershipsProvider.overrideWith(
            (ref) async => <TenantMembership>[],
          ),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: TenantPickerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('کوئی ادارہ دستیاب نہیں'), findsOneWidget);
    });
  });
}
