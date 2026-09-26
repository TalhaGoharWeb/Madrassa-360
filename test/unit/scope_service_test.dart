// ScopeService unit tests (Phase 5; fail-closed contract from Phase 11).
//
// Implementation file under test:
//   lib/core/services/scope_service.dart
//
// Covered here without a database:
//   * PermissionScope.fromRow parsing (incl. the 022 fail-closed defaults:
//     a missing or unrecognized scope_type parses to `unknown`, never `all`).
//   * descriptionUrdu for every scope type.
//   * The service-level fail-closed contract: when the scope rows cannot be
//     resolved (no signed-in user here — Supabase is uninitialized in tests,
//     and when no tenant is active), scopeFor returns null, scopeAllows
//     denies, the *InScope helpers return empty sets, and
//     scopeDescriptionUrdu reports an unknown scope — never "unrestricted".
//
// The live Supabase row-loading path needs a database and is NOT covered
// here (RLS `scope_allows()` remains the real enforcement; these helpers
// only pre-filter the UI).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/scope_service.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';

PermissionScope _row({
  String? scopeType = 'all',
  Map<String, dynamic>? ref,
}) =>
    PermissionScope.fromRow(
      permission: 'students.view',
      row: {'scope_type': scopeType, 'scope_ref': ref},
    );

/// A ScopeService whose tenant is fixed; Supabase stays uninitialized, so
/// every auth/session lookup fails and the service must fail closed.
ScopeService _serviceWithTenant(String? tenantId) {
  final container = ProviderContainer(
    overrides: [
      activeTenantIdProvider.overrideWith((ref) => TenantContext(ref)),
    ],
  );
  addTearDown(container.dispose);
  container.read(activeTenantIdProvider.notifier).state = tenantId;
  return container.read(scopeServiceProvider);
}

void main() {
  group('PermissionScope.fromRow', () {
    test('parses classes scope with class ids', () {
      final s = _row(
        scopeType: 'classes',
        ref: {
          'class_ids': ['c1', 'c2'],
        },
      );
      expect(s.scopeType, 'classes');
      expect(s.classIds, {'c1', 'c2'});
      expect(s.studentIds, isEmpty);
      expect(s.isUnrestricted, isFalse);
    });

    test('parses students scope with student ids', () {
      final s = _row(
        scopeType: 'students',
        ref: {
          'student_ids': ['s1'],
        },
      );
      expect(s.studentIds, {'s1'});
      expect(s.classIds, isEmpty);
    });

    test('missing scope_type parses to unknown (fail-closed, never all)', () {
      final s = PermissionScope.fromRow(
        permission: 'students.view',
        row: {'scope_ref': null},
      );
      expect(s.scopeType, 'unknown');
      expect(s.isUnrestricted, isFalse);
    });

    test('unrecognized scope_type parses to unknown (fail-closed)', () {
      final s = _row(scopeType: 'zone');
      expect(s.scopeType, 'unknown');
      expect(s.isUnrestricted, isFalse);
    });

    test('null scope_ref parses to empty id sets', () {
      final s = _row(scopeType: 'classes', ref: null);
      expect(s.classIds, isEmpty);
      expect(s.studentIds, isEmpty);
    });

    test('non-string ids are stringified defensively', () {
      final s = _row(
        scopeType: 'classes',
        ref: {
          'class_ids': [1, 2],
        },
      );
      expect(s.classIds, {'1', '2'});
    });

    test('isUnrestricted is true only for an explicit all row', () {
      expect(_row(scopeType: 'all').isUnrestricted, isTrue);
      expect(_row(scopeType: 'classes').isUnrestricted, isFalse);
      expect(_row(scopeType: 'department').isUnrestricted, isFalse);
      expect(_row(scopeType: 'students').isUnrestricted, isFalse);
      expect(_row(scopeType: 'zone').isUnrestricted, isFalse);
    });
  });

  group('descriptionUrdu (plain-language scope descriptions)', () {
    test('all -> پورا مدرسہ', () {
      expect(_row(scopeType: 'all').descriptionUrdu, 'پورا مدرسہ');
    });

    test('department -> صرف میرے شعبے کے افراد', () {
      expect(_row(scopeType: 'department').descriptionUrdu,
          'صرف میرے شعبے کے افراد');
    });

    test('classes -> صرف میری مقرر کردہ جماعتوں کے طلبہ', () {
      expect(_row(scopeType: 'classes').descriptionUrdu,
          'صرف میری مقرر کردہ جماعتوں کے طلبہ');
    });

    test('students -> صرف میرے طلبہ', () {
      expect(_row(scopeType: 'students').descriptionUrdu, 'صرف میرے طلبہ');
    });

    test('unknown -> نامعلوم دائرہ (never "whole madrasa")', () {
      expect(_row(scopeType: 'zone').descriptionUrdu, 'نامعلوم دائرہ');
    });
  });

  group('fail-closed when scopes cannot be resolved (022)', () {
    test('no signed-in session: everything denies / hides', () async {
      final svc = _serviceWithTenant('tenant-1');
      expect(await svc.scopeFor('students.view'), isNull);
      expect(await svc.scopeAllows('students.view'), isFalse);
      expect(await svc.scopeAllows('students.view', classId: 'c1'), isFalse);
      expect(await svc.classIdsInScope('students.view'), isEmpty);
      expect(await svc.studentIdsInScope('students.view'), isEmpty);
      expect(await svc.scopeDescriptionUrdu('students.view'), 'نامعلوم دائرہ');
    });

    test('no active tenant: everything denies / hides', () async {
      final svc = _serviceWithTenant(null);
      expect(await svc.scopeFor('students.view'), isNull);
      expect(await svc.scopeAllows('students.view'), isFalse);
      expect(await svc.classIdsInScope('students.view'), isEmpty);
      expect(await svc.studentIdsInScope('students.view'), isEmpty);
    });

    test('clearCache keeps the fail-closed behavior', () async {
      final svc = _serviceWithTenant('tenant-1');
      svc.clearCache();
      expect(await svc.scopeAllows('students.view'), isFalse);
      expect(await svc.classIdsInScope('students.view'), isEmpty);
    });
  });
}
