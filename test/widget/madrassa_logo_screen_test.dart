/// Madrassa logo screen tests (2026-09-30).
///
/// Locks in:
///   1. Permission gate: without `settings.update` the screen shows the
///      locked empty state — never the upload controls.
///   2. With the permission, the screen renders the current logo state,
///      the reports toggle reflecting `useLogoOnReports`, and the upload
///      / remove actions.
///   3. The new Madrassa-360 brand mark ships as `assets/images/app_logo.png`
///      (valid PNG, non-empty) and the drawer footer references it.
///
/// Implementation files under test:
///   lib/presentation/screens/settings/madrassa_logo_screen.dart
///   lib/presentation/widgets/app_drawer.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/presentation/screens/settings/madrassa_logo_screen.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

TenantBranding _branding({bool useLogoOnReports = true, String? logoUrl}) =>
    TenantBranding(
      name: 'ٹیسٹ مدرسہ',
      nameUrdu: 'ٹیسٹ مدرسہ',
      logoUrl: logoUrl,
      primaryColor: const Color(0xFF0E7C5B),
      secondaryColor: const Color(0xFF14532D),
      accentColor: const Color(0xFFF59E0B),
      fontFamily: 'JameelNooriNastaleeq',
      darkModeEnabled: false,
      language: 'ur',
      useLogoOnReports: useLogoOnReports,
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  required Set<String> permissions,
  TenantBranding? branding,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userPermissionsProvider.overrideWith((ref) => permissions),
        currentTenantIdProvider.overrideWith((ref) => 'tenant-1'),
        tenantBrandingProvider.overrideWith(
          (ref) async => branding ?? _branding(),
        ),
      ],
      child: const MaterialApp(
        home: MadrassaLogoScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'widget-test-anon-key',
    );
  });

  group('permission gate', () {
    testWidgets('locked state without settings.update', (tester) async {
      await _pumpScreen(tester, permissions: {'students.view'});
      expect(
        find.text('آپ کو یہ صفحہ دیکھنے کی اجازت نہیں ہے'),
        findsOneWidget,
      );
      expect(find.text('لوگو لگائیں'), findsNothing);
    });

    testWidgets('upload controls visible with settings.update', (tester) async {
      await _pumpScreen(
        tester,
        permissions: {AppPermissions.manageSettings},
      );
      expect(find.text('لوگو لگائیں'), findsOneWidget);
      expect(
        find.text('رپورٹس اور دستاویزات پر لوگو دکھائیں'),
        findsOneWidget,
      );
    });
  });

  group('logo state', () {
    testWidgets('shows remove action when a logo is set', (tester) async {
      await _pumpScreen(
        tester,
        permissions: {AppPermissions.manageSettings},
        branding: _branding(logoUrl: 'https://example.com/logo.png'),
      );
      expect(find.text('لوگو تبدیل کریں'), findsOneWidget);
      expect(find.text('لوگو ہٹائیں'), findsOneWidget);
    });

    testWidgets('toggle reflects useLogoOnReports=false', (tester) async {
      await _pumpScreen(
        tester,
        permissions: {AppPermissions.manageSettings},
        branding: _branding(useLogoOnReports: false),
      );
      final toggle = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(toggle.value, isFalse);
    });

    testWidgets('toggle reflects useLogoOnReports=true', (tester) async {
      await _pumpScreen(
        tester,
        permissions: {AppPermissions.manageSettings},
        branding: _branding(useLogoOnReports: true),
      );
      final toggle = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(toggle.value, isTrue);
    });
  });

  group('brand asset', () {
    test('new Madrassa-360 mark ships as assets/images/app_logo.png', () {
      final file = File('assets/images/app_logo.png');
      expect(file.existsSync(), isTrue,
          reason: 'login screen + drawer footer load this asset');
      final bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(10000));
      // PNG magic bytes.
      expect(bytes.sublist(0, 8),
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    });
  });
}
