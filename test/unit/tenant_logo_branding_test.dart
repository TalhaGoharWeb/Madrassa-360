/// Tenant logo branding contract (2026-09-30).
///
/// Locks in:
///   1. `TenantBranding.fromRows` reads the per-madrassa
///      `use_logo_on_reports` toggle (migration 024), defaulting to true
///      when the column is absent (pre-024 databases).
///   2. `hasLogo` is true only for a non-empty logo URL.
///   3. `tenantLogoCacheFile` resolves to the tenant-scoped offline path
///      `<support>/Madrassa360/branding/<tenantId>/logo.png` — the single
///      path the report engine reads, so one tenant's logo can never leak
///      into another tenant's documents.
///
/// Implementation files under test:
///   lib/providers/tenant_branding_provider.dart
///   lib/core/reports/report_branding.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/reports/report_branding.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';

Map<String, dynamic> _tenantRow({bool? useLogoOnReports, String? logoUrl}) {
  return {
    'name': 'ٹیسٹ مدرسہ',
    'name_urdu': 'ٹیسٹ مدرسہ',
    'logo_url': logoUrl,
    if (useLogoOnReports != null) 'use_logo_on_reports': useLogoOnReports,
  };
}

void main() {
  group('TenantBranding.useLogoOnReports', () {
    test('defaults to true when the column is absent (pre-024 DB)', () {
      final b = TenantBranding.fromRows(_tenantRow(), null);
      expect(b.useLogoOnReports, isTrue);
    });

    test('reads false from the tenant row', () {
      final b =
          TenantBranding.fromRows(_tenantRow(useLogoOnReports: false), null);
      expect(b.useLogoOnReports, isFalse);
    });

    test('reads true from the tenant row', () {
      final b =
          TenantBranding.fromRows(_tenantRow(useLogoOnReports: true), null);
      expect(b.useLogoOnReports, isTrue);
    });

    test('fallback branding enables logo on reports', () {
      expect(TenantBranding.fallback().useLogoOnReports, isTrue);
    });
  });

  group('TenantBranding.hasLogo', () {
    test('false when logo_url is null', () {
      expect(TenantBranding.fromRows(_tenantRow(), null).hasLogo, isFalse);
    });

    test('false when logo_url is blank', () {
      expect(TenantBranding.fromRows(_tenantRow(logoUrl: '  '), null).hasLogo,
          isFalse);
    });

    test('true when logo_url is set', () {
      expect(
          TenantBranding.fromRows(
                  _tenantRow(logoUrl: 'https://x/logo.png'), null)
              .hasLogo,
          isTrue);
    });
  });

  group('tenantLogoCacheFile', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return '/tmp/m360-test-support';
          }
          return null;
        },
      );
    });

    test('is tenant-scoped under Madrassa360/branding', () async {
      final file = await tenantLogoCacheFile('tenant-abc');
      expect(file.path,
          '/tmp/m360-test-support/Madrassa360/branding/tenant-abc/logo.png');
    });

    test('different tenants resolve to different files', () async {
      final a = await tenantLogoCacheFile('tenant-a');
      final b = await tenantLogoCacheFile('tenant-b');
      expect(a.path, isNot(equals(b.path)));
    });
  });
}
