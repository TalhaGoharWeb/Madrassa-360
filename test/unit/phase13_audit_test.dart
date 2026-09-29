// Phase 13 — regression audit (unit): dead-code absence, nav IA static
// invariants, permission gating, PKR formatting, offline fail-closed
// authorization, audit-export bytes.
//
// Units under test:
//   lib/presentation/shell/nav_destinations.dart (IA data)
//   lib/core/constants/app_permissions.dart (fallbackFor)
//   lib/core/services/permission_service.dart (offline fallback chain)
//   lib/core/services/authorization_service.dart (fail-closed reads)
//   lib/core/utils/money_format.dart (formatRs / formatPK)
//   lib/presentation/screens/master_admin/audit_export.dart
//   lib/core/reports/export/csv_export.dart + tabular_data.dart
//
// Hermetic: no widgets, no network, no Supabase. Filesystem reads are
// limited to the repo tree itself (dead-code + rupee-sign scans). The
// route table itself lives in test/widget/phase13_regression_test.dart
// (imported below); the builder-level checks live there too.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/reports/export/csv_export.dart';
import 'package:madrasa_360/core/reports/export/tabular_data.dart';
import 'package:madrasa_360/core/services/authorization_service.dart';
import 'package:madrasa_360/core/services/permission_service.dart';
import 'package:madrasa_360/core/utils/money_format.dart';
import 'package:madrasa_360/presentation/screens/master_admin/audit_export.dart';
import 'package:madrasa_360/presentation/shell/nav_destinations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget/phase13_regression_test.dart' as reg;

Widget _stubBuilder(BuildContext context) => const SizedBox();

void main() {
  group('dead code stays deleted (Phase 13 cleanup)', () {
    // The exact 14 files deleted in the Phase 13 cleanup. Re-adding any of
    // them fails this test — resurrection is a conscious, reviewed act.
    const deleted = <String>[
      'lib/core/widgets/confirm_dialog.dart',
      'lib/core/widgets/custom_buttons.dart',
      'lib/core/widgets/loading_overlay.dart',
      'lib/presentation/screens/admin/admin_main_screen.dart',
      'lib/presentation/screens/dashboards/teacher_home.dart',
      'lib/presentation/screens/main_screen.dart',
      'lib/presentation/screens/parent/parent_dashboard_screen.dart',
      'lib/presentation/screens/parent/parent_main_screen.dart',
      'lib/presentation/screens/super_admin/madrasa_management_screen.dart',
      'lib/presentation/screens/super_admin/super_admin_dashboard_screen.dart',
      'lib/presentation/screens/super_admin/super_admin_main_screen.dart',
      'lib/presentation/screens/teacher/teacher_dashboard_screen.dart',
      'lib/presentation/widgets/app_drawer.dart',
      'lib/presentation/widgets/profile_avatar_button.dart',
    ];

    test('all 14 deleted files are still absent', () {
      expect(deleted, hasLength(14));
      for (final path in deleted) {
        expect(File(path).existsSync(), isFalse,
            reason: 'resurrected dead file: $path');
      }
      // The whole legacy super_admin portal went with its screens.
      expect(
        Directory('lib/presentation/screens/super_admin').existsSync(),
        isFalse,
        reason: 'legacy super_admin portal directory is back',
      );
    });
  });

  group('license destructive actions require typed confirmation', () {
    // Source-contract test: _LicenseDetailDialog is private and the
    // license repository has no hermetic seam (with the dummy Supabase
    // URL the screen only renders its honest error state), so the
    // requirement "revoke AND extend both require typed confirmation"
    // is pinned at the source level instead.
    String methodBody(String src, String marker) {
      final start = src.indexOf(marker);
      expect(start, isNot(-1), reason: 'method not found: $marker');
      final open = src.indexOf('{', start);
      var depth = 0;
      for (var i = open; i < src.length; i++) {
        if (src[i] == '{') depth++;
        if (src[i] == '}') {
          depth--;
          if (depth == 0) return src.substring(open, i + 1);
        }
      }
      fail('unbalanced braces in $marker');
    }

    test('revoke and extend both request typed confirmation', () {
      final src = File(
        'lib/presentation/screens/master_admin/licenses_screen.dart',
      ).readAsStringSync();
      // Collapse whitespace so formatting can never dodge the check.
      String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
      final revoke = norm(methodBody(src, 'Future<void> _revoke()'));
      final extend = norm(methodBody(src, 'Future<void> _extend()'));
      expect(revoke, contains('requireTypedConfirmation: true'),
          reason: '_revoke lost its typed confirmation');
      // REGRESSION (Phase 13): _extend currently shows a plain confirm
      // dialog — no requireTypedConfirmation, no expectedText. This
      // assertion fails until lib/ is fixed (reported, not fixed here).
      expect(extend, contains('requireTypedConfirmation: true'),
          reason: '_extend must require typed confirmation like _revoke');
      expect(extend, contains('expectedText:'),
          reason: '_extend must pass the tenant name as expectedText');
    });
  });

  group('route checklist — static invariants', () {
    test('destination ids are unique', () {
      final ids = kAllDestinations.map((d) => d.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every mobile primary id resolves (student_fees, not fees)', () {
      // Regression for the Phase 13 fix: the mobile bottom nav referenced
      // the stale 'fees' id, so the fees tab silently never appeared.
      expect(
        kMobilePrimaryIds,
        ['dashboard', 'student-list', 'attendance', 'student_fees'],
      );
      for (final id in kMobilePrimaryIds) {
        expect(findDestination(id), isNotNull, reason: 'unresolved: $id');
      }
      expect(findDestination('fees'), isNull,
          reason: "stale 'fees' id must not resolve");
    });

    test('destination set matches the checked-in contract exactly', () {
      final ids = kAllDestinations.map((d) => d.id).toSet();
      final expected = reg.kPhase13ExpectedRoutes.map((r) => r.id).toSet();
      expect(
        ids,
        expected,
        reason: 'a destination was added/removed/renamed without updating '
            'kPhase13ExpectedRoutes',
      );
      expect(kAllDestinations.length, reg.kPhase13ExpectedRoutes.length);
    });
  });

  group('NavDestination.isVisible permission gating', () {
    const gated = NavDestination(
      id: 'x',
      labelUr: 'x',
      icon: Icons.school,
      builder: _stubBuilder,
      requiredPermissions: ['a.view', 'a.edit'],
    );

    test('hidden when the user lacks every required permission', () {
      expect(gated.isVisible({'other.perm'}, []), isFalse);
      expect(gated.isVisible({}, []), isFalse);
    });

    test('OR semantics: any one required permission grants visibility', () {
      expect(gated.isVisible({'a.edit'}, []), isTrue);
      expect(gated.isVisible({'a.view', 'unrelated'}, []), isTrue);
    });

    test('visibleForRoleKeys narrows beyond permissions', () {
      const roleNarrowed = NavDestination(
        id: 'y',
        labelUr: 'y',
        icon: Icons.school,
        builder: _stubBuilder,
        visibleForRoleKeys: ['parent'],
      );
      expect(roleNarrowed.isVisible({}, ['teacher']), isFalse);
      expect(roleNarrowed.isVisible({}, ['parent']), isTrue);
      // Both filters must pass together.
      const both = NavDestination(
        id: 'w',
        labelUr: 'w',
        icon: Icons.school,
        builder: _stubBuilder,
        requiredPermissions: ['a.view'],
        visibleForRoleKeys: ['parent'],
      );
      expect(both.isVisible({'a.view'}, ['teacher']), isFalse);
      expect(both.isVisible({}, ['parent']), isFalse);
      expect(both.isVisible({'a.view'}, ['parent']), isTrue);
    });

    test('empty permissions and role keys mean visible to everyone', () {
      const open = NavDestination(
        id: 'z',
        labelUr: 'z',
        icon: Icons.school,
        builder: _stubBuilder,
      );
      expect(open.isVisible({}, []), isTrue);
      expect(open.isVisible({'anything'}, ['any-role']), isTrue);
    });

    test('NavGroup.visibleDestinations filters as a whole', () {
      const open = NavDestination(
        id: 'z',
        labelUr: 'z',
        icon: Icons.school,
        builder: _stubBuilder,
      );
      const group = NavGroup(
        id: 'g',
        labelUr: 'g',
        destinations: [gated, open],
      );
      expect(
        group.visibleDestinations({'a.view'}, []).map((d) => d.id),
        ['x', 'z'],
      );
      expect(
        group.visibleDestinations({}, []).map((d) => d.id),
        ['z'],
      );
    });
  });

  group('PKR formatting consistency', () {
    test('formatRs prefixes Rs with Pakistani grouping', () {
      expect(formatRs(125000), 'Rs 1,25,000');
      expect(formatRs(380000), 'Rs 3,80,000');
      expect(formatRs(999), 'Rs 999');
      expect(formatRs(-2500), '-Rs 2,500');
      for (final v in [0.0, 500.0, 99999.0, 10000000.0]) {
        final out = formatRs(v);
        expect(out, contains('Rs'), reason: 'formatRs($v)');
        expect(out, isNot(contains('₹')), reason: 'formatRs($v)');
      }
    });

    test('formatPK groups digits Pakistani-style and never emits ₹', () {
      // REQUIRED contract: formatPK must carry an Rs/روپے marker like
      // formatRs does. The current implementation returns bare grouped
      // digits (lib/core/utils/money_format.dart, formatPK) — this
      // assertion intentionally fails until the library is fixed; the
      // bug is reported, not worked around here.
      expect(formatPK(380000), contains('Rs'));
      expect(formatPK(380000), 'Rs 3,80,000');
      expect(formatPK(10000000), 'Rs 1,00,00,000');
      expect(formatPK(500), 'Rs 500');
      expect(formatPK(-1500), '-Rs 1,500');
      for (final v in [0, 42, 999, 1000, 125000, 987654321]) {
        expect(formatPK(v), isNot(contains('₹')), reason: 'formatPK($v)');
      }
    });

    test('no Indian rupee sign anywhere under lib/', () {
      // The app is PKR-only; a stray ₹ pasted from a snippet must never
      // ship. Scans every Dart file in the repo tree.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains('₹')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty, reason: offenders.join(', '));
    });
  });

  group('offline fail-closed authorization', () {
    test('static fallback is empty for unknown and empty role keys', () {
      // Unknown keys yield the empty set (fail-closed) — see
      // AppPermissions.fallbackFor. This is the last resort when the RPC
      // fails AND no persisted cache exists.
      expect(AppPermissions.fallbackFor(''), isEmpty);
      expect(AppPermissions.fallbackFor('no_such_role'), isEmpty);
    });

    test('fresh AuthorizationService denies everything', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(authorizationServiceProvider);
      expect(service.loadedTenantId, isNull);
      expect(service.effectivePermissions, isEmpty);
      expect(service.has(AppPermissions.viewStudents), isFalse);
      expect(service.hasAll([AppPermissions.viewStudents]), isFalse);
      expect(service.hasAny([AppPermissions.viewStudents]), isFalse);
      expect(service.sourceOf(AppPermissions.viewStudents), isNull);
    });

    test('loadEffectivePermissions falls back to empty when offline', () async {
      SharedPreferences.setMockInitialValues({});
      // No Supabase.init(): touching the client throws inside the method,
      // which must land in the offline fallback — never escape, and with
      // an empty role key the fallback grants nothing.
      final perms = await PermissionService.loadEffectivePermissions(
        tenantId: 't-offline',
        roleKey: '',
      );
      expect(perms.codes, isEmpty);
    });
  });

  group('audit export produces bytes', () {
    test('headers + rows encode to non-empty UTF-8 CSV with BOM', () {
      final networkColumns = ['ip'];
      final headers = buildAuditExportHeaders(networkColumns);
      final row = buildAuditExportRow(
        {
          'created_at': '2026-09-29T10:00:00Z',
          'action': 'license.revoked',
          'entity': 'license',
          'entity_id': 'abc',
          'tenants': {'name': 'ڈیمو مدرسہ'},
          'metadata': {'ip': '1.2.3.4'},
        },
        actorName: 'منتظم',
        networkColumns: networkColumns,
      );
      expect(row, hasLength(headers.length));
      final csv = CsvExport.build([
        ReportTable(
          sheetName: 'audit',
          titleUr: 'آڈٹ لاگ',
          headers: headers,
          rows: [row],
        ),
      ]);
      final bytes = utf8.encode(csv);
      expect(bytes, isNotEmpty);
      expect(csv.codeUnitAt(0), 0xFEFF, reason: 'Excel-readable BOM');
      expect(csv, contains('1.2.3.4'));
    });
  });
}
