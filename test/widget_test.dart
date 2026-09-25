// Phase 4 — branding, module gating, and identity-purge tests.
//
// These tests are hermetic: they never touch Supabase or the network.
// Provider overrides supply tenant branding/modules directly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:madrasa_360/core/config/role_config.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/widgets/tenant_logo.dart';
import 'package:madrasa_360/providers/admin_dashboard_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';

TenantBranding _testBranding() => TenantBranding.fromRows(
      {
        'name': 'Test Madrassa',
        'name_urdu': 'ٹیسٹ مدرسہ',
        'logo_url': null,
        'phone': '0300-0000000',
        'email': 'info@test.pk',
        'website': null,
        'address': 'Test Road',
        'city': 'Lahore',
      },
      {
        'language': 'ur',
        'primary_color': '#123456',
        'secondary_color': null,
        'accent_color': 'ZZZ', // invalid → fallback
        'font': 'JameelNooriNastaleeq',
        'dark_mode_enabled': false,
      },
    );

void main() {
  // ── TenantBranding model ──────────────────────────────────────

  group('TenantBranding', () {
    test('fallback() carries no institution identity', () {
      final b = TenantBranding.fallback();
      expect(b.name, 'مدرسہ 360');
      expect(b.hasLogo, isFalse);
      expect(b.hasContact, isFalse);
      expect(b.phone, isNull);
      expect(b.email, isNull);
    });

    test('fromRows maps tenant + settings rows', () {
      final b = _testBranding();
      expect(b.name, 'Test Madrassa');
      expect(b.displayName(urdu: true), 'ٹیسٹ مدرسہ');
      expect(b.displayName(urdu: false), 'Test Madrassa');
      expect(b.phone, '0300-0000000');
      expect(b.email, 'info@test.pk');
      expect(b.locationLine, 'Test Road، Lahore');
      expect(b.hasContact, isTrue);
      expect(b.hasLogo, isFalse);
    });

    test('color parsing falls back on bad input', () {
      final b = _testBranding();
      expect(b.primaryColor, const Color(0xFF123456));
      // null secondary → default, invalid accent → default
      expect(b.secondaryColor, const Color(0xFF14532D));
      expect(b.accentColor, const Color(0xFFF59E0B));
    });

    test('displayName falls back to name when Urdu name missing', () {
      final b = TenantBranding.fromRows({'name': 'Only English'}, null);
      expect(b.displayName(urdu: true), 'Only English');
    });
  });

  // ── Module gating on navigation ───────────────────────────────

  group('buildNavTabs module gating', () {
    List<NavTab> tabs(Set<String> perms, Set<String>? modules) =>
        buildNavTabs(
          perms: perms,
          enabledModules: modules,
          dashboardBuilder: () => const SizedBox(),
          profileScreen: const SizedBox(),
          attendanceScreen: const SizedBox(),
          studentsScreen: const SizedBox(),
          staffScreen: const SizedBox(),
          feesScreen: const SizedBox(),
          usersScreen: const SizedBox(),
          resultsScreen: const SizedBox(),
        );

    List<String> labels(List<NavTab> t) => t.map((e) => e.label).toList();

    test('tenant with only students+attendance+fees never sees library UI',
        () {
      final perms = {
        AppPermissions.viewStudents,
        AppPermissions.markAttendance,
        AppPermissions.viewFees,
        AppPermissions.viewLibrary, // user permitted…
      };
      final got = tabs(perms, {'students', 'attendance', 'fees'});
      // …but the tenant has no library module: no library tab exists and
      // the middle slots only carry enabled modules.
      expect(labels(got), contains('طلباء'));
      expect(labels(got), contains('حاضری'));
      for (final t in got) {
        expect(t.module == 'library', isFalse);
      }
    });

    test('null module set does not filter (still resolving)', () {
      final got = tabs({AppPermissions.viewStudents}, null);
      expect(labels(got), contains('طلباء'));
    });

    test('disabled module hides its tab even when permitted', () {
      final withModule = tabs({AppPermissions.viewStudents}, {'students'});
      final withoutModule = tabs({AppPermissions.viewStudents}, <String>{});
      expect(labels(withModule), contains('طلباء'));
      expect(labels(withoutModule), isNot(contains('طلباء')));
      // dashboard + profile are core tabs — always present
      expect(labels(withoutModule), contains('ڈیش بورڈ'));
      expect(labels(withoutModule), contains('پروفائل'));
    });
  });

  // ── Dashboard helpers ─────────────────────────────────────────

  group('dashboard helpers', () {
    test('DashboardStats.zero is all zeros with empty feed', () {
      const s = DashboardStats.zero();
      expect(s.totalStudents, 0);
      expect(s.todayPresent, 0);
      expect(s.pendingFees, 0);
      expect(s.monthProgress, 0);
      expect(s.recentActivities, isEmpty);
    });

    test('formatPK uses Pakistani grouping', () {
      expect(formatPK(0), '0');
      expect(formatPK(999), '999');
      expect(formatPK(45000), '45,000');
      expect(formatPK(380000), '3,80,000');
      expect(formatPK(468000), '4,68,000');
    });

    test('urduTimeAgo labels', () {
      final now = DateTime.now();
      expect(urduTimeAgo(now), 'ابھی');
      expect(urduTimeAgo(now.subtract(const Duration(minutes: 10))),
          '10 منٹ پہلے');
      expect(urduTimeAgo(now.subtract(const Duration(hours: 3))),
          '3 گھنٹے پہلے');
      expect(urduTimeAgo(now.subtract(const Duration(days: 1))), 'کل');
    });
  });

  // ── Branding widgets ──────────────────────────────────────────

  group('branding widgets', () {
    testWidgets('TenantNameText shows the tenant name from the provider',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tenantBrandingProvider
                .overrideWith((ref) async => _testBranding()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: TenantNameText()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('ٹیسٹ مدرسہ'), findsOneWidget);
      expect(find.text('المرکز الاسلامی قصور'), findsNothing);
    });

    testWidgets('TenantLogo renders neutral mark when no logo configured',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tenantBrandingProvider
                .overrideWith((ref) async => _testBranding()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: TenantLogo()),
          ),
        ),
      );
      await tester.pump();
      // neutral placeholder: mosque glyph, no network image
      expect(find.byIcon(Icons.mosque), findsOneWidget);
    });
  });
}
