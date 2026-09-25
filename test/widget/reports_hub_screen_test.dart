/// Widget tests for the reports hub and its permission gating.
///
/// Implementation files under test:
///   lib/presentation/screens/reports/reports_hub_screen.dart
///   lib/core/reports/report_catalog.dart / report_params.dart
///   lib/core/services/tenant_context.dart        (currentTenantIdProvider)
///   lib/presentation/screens/admin/admin_dashboard_screen.dart
///        (the REAL permission gate for the reports module card:
///         `perms.contains(AppPermissions.viewReports) && moduleOk('reports')`)
///   lib/core/constants/app_permissions.dart
///
/// IMPORTANT — read before extending: [ReportsHubScreen] itself renders the
/// full static [ReportCatalog] for the active tab with NO per-report
/// permission filter (`ReportDefinition` has no permission field). The
/// permission gate lives one level up, on the admin dashboard's module
/// grid ('رپورٹس' card). The gating tests below therefore target
/// [AdminDashboardScreen], the actual fail-closed gate.
///
/// Fakes: [FakeAuthRepository] (auth); `appDatabaseProvider` gets an
/// in-memory Drift DB for the filter sheet's lookups; dashboard data
/// providers are overridden with zero/fallback values.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/reports/report_catalog.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/data/local/app_database.dart';
import 'package:madrasa_360/data/local/database_provider.dart';
import 'package:madrasa_360/presentation/screens/admin/admin_dashboard_screen.dart';
import 'package:madrasa_360/presentation/screens/reports/reports_hub_screen.dart';
import 'package:madrasa_360/providers/admin_dashboard_provider.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth_repository.dart';

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'widget-test-anon-key',
    );
  });

  late FakeAuthRepository fakeAuth;
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fakeAuth = FakeAuthRepository();
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    fakeAuth.dispose();
    await db.close();
  });

  Future<ProviderContainer> pumpHub(
    WidgetTester tester, {
    String? tenantId,
  }) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        currentTenantIdProvider.overrideWithValue(tenantId),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReportsHubScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('ReportsHubScreen', () {
    testWidgets('no tenant → login prompt (empty state)', (tester) async {
      await pumpHub(tester, tenantId: null);

      expect(find.text('براہ کرم پہلے لاگ اِن کریں۔'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget); // tabs still render
    });

    testWidgets('student tab lists the student report catalog', (tester) async {
      await pumpHub(tester, tenantId: 't1');

      final studentReports =
          ReportCatalog.byCategory(ReportCategory.student);
      expect(studentReports, isNotEmpty);
      // First catalog entry renders with its Urdu title.
      expect(find.text(studentReports.first.titleUr), findsOneWidget);
      // Admin-category reports are not on this tab.
      final adminReports = ReportCatalog.byCategory(ReportCategory.admin);
      if (adminReports.isNotEmpty) {
        expect(find.text(adminReports.first.titleUr), findsNothing);
      }
    });

    testWidgets('admin tab lists the admin report catalog', (tester) async {
      await pumpHub(tester, tenantId: 't1');

      await tester.tap(find.text('انتظامیہ'));
      await tester.pumpAndSettle();

      final adminReports = ReportCatalog.byCategory(ReportCategory.admin);
      expect(adminReports, isNotEmpty);
      expect(find.text(adminReports.first.titleUr), findsOneWidget);
    });

    testWidgets('filter sheet validates required student before preview',
        (tester) async {
      await pumpHub(tester, tenantId: 't1');

      // 'داخلہ فارم' needs a student (ReportCatalog).
      await tester.tap(find.text('داخلہ فارم'));
      await tester.pumpAndSettle();

      // No student selected → preview is rejected with the validation message.
      await tester.tap(find.text('پیش نظارہ'));
      await tester.pumpAndSettle();

      expect(find.text('براہ کرم طالب علم منتخب کریں۔'), findsOneWidget);
    });
  });

  group('Reports module permission gate (AdminDashboardScreen)', () {
    Future<ProviderContainer> pumpDashboard(
      WidgetTester tester, {
      required Set<String> permissions,
    }) async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          userPermissionsProvider.overrideWithValue(permissions),
          tenantModulesProvider.overrideWith((ref) async => {'reports'}),
          dashboardStatsProvider
              .overrideWith((ref) async => const DashboardStats.zero()),
          tenantBrandingProvider
              .overrideWith((ref) async => TenantBranding.fallback()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AdminDashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('reports card visible with view_reports permission',
        (tester) async {
      await pumpDashboard(
        tester,
        permissions: {AppPermissions.viewReports},
      );

      expect(find.text('رپورٹس'), findsOneWidget);
    });

    testWidgets('reports card hidden without view_reports permission',
        (tester) async {
      await pumpDashboard(
        tester,
        permissions: {AppPermissions.viewStudents},
      );

      expect(find.text('رپورٹس'), findsNothing);
    });
  });
}
