// Permission-authorization unit tests (Phase 5).
//
// Implementation files under test:
//   lib/core/constants/app_permissions.dart   (canonical catalog + Urdu labels)
//   lib/core/services/permission_service.dart (EffectivePermissions,
//     validateServerCodes, has/hasAll/hasAny, tenantRoleDefaults)
//
// The app uses the canonical DOTTED codes from supabase/migrations/019
// (e.g. 'students.view') plus the 56 still-live legacy underscore codes
// 019 also labels. Server rows are validated (unknown codes dropped
// fail-closed) but never re-mapped — there is no dotted-to-underscore
// translation step anymore.
//
// HONESTY NOTE: PermissionService.loadEffectivePermissions() calls the
// live `get_my_permissions_detailed` RPC and is NOT covered here (needs
// network + Supabase). Only the pure helpers, the server-code validator,
// the canonical catalog and the static offline role-default matrix are.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/services/permission_service.dart';

void main() {
  group('has / hasAll / hasAny (pure set helpers)', () {
    const perms = {'students.view', 'attendance.mark'};

    test('has is exact set membership', () {
      expect(PermissionService.has(perms, 'students.view'), isTrue);
      expect(PermissionService.has(perms, 'fees.collect'), isFalse);
      expect(PermissionService.has(const {}, 'students.view'), isFalse);
    });

    test('hasAll requires every permission', () {
      expect(
          PermissionService.hasAll(
              perms, ['students.view', 'attendance.mark']),
          isTrue);
      expect(
          PermissionService.hasAll(perms, ['students.view', 'fees.collect']),
          isFalse);
      expect(PermissionService.hasAll(perms, []), isTrue);
    });

    test('hasAny requires at least one', () {
      expect(
          PermissionService.hasAny(perms, ['fees.collect', 'attendance.mark']),
          isTrue);
      expect(PermissionService.hasAny(perms, ['fees.collect']), isFalse);
      expect(PermissionService.hasAny(perms, []), isFalse);
    });
  });

  group('validateServerCodes (server codes -> effective set)', () {
    test('known dotted codes pass through unchanged', () {
      final valid = PermissionService.validateServerCodes(
          {'students.view', 'attendance.mark'});
      expect(valid, {'students.view', 'attendance.mark'});
    });

    test('unknown / injected codes are dropped fail-closed', () {
      final valid = PermissionService.validateServerCodes({
        'students.view',
        'admin.superpowers',
        'DROP TABLE x;--',
        '',
      });
      expect(valid, {'students.view'});
    });

    test('legacy catalog codes pass through too (they are in the catalog)', () {
      final valid = PermissionService.validateServerCodes({'update_fees'});
      expect(valid, {'update_fees'});
    });

    test('empty input stays empty', () {
      expect(PermissionService.validateServerCodes({}), isEmpty);
    });

    // NOTE: rejecting rows whose tenant_id differs from the requested tenant
    // lives inside loadEffectivePermissions' RPC path and needs Supabase;
    // it is exercised in CI only via the widget/integration surface.
  });

  group('canonical catalog (019)', () {
    test('66 dotted codes + 56 legacy codes = 122 unique codes', () {
      expect(AppPermissions.allDottedCodes, hasLength(66));
      expect(AppPermissions.allCodes, hasLength(122));
      expect(AppPermissions.allCodes,
          containsAll(AppPermissions.allDottedCodes));
    });

    test('constants carry the canonical dotted values', () {
      expect(AppPermissions.viewStudents, 'students.view');
      expect(AppPermissions.markAttendance, 'attendance.mark');
      expect(AppPermissions.assignRoles, 'roles.assign');
      expect(AppPermissions.collectFees, 'fees.collect');
      expect(AppPermissions.sendNotifications, 'notifications.send');
      // Deliberate aliases (match RLS semantics — see file header):
      // fees have no separate update/delete grant server-side, and results
      // deletion is the results.edit grant.
      expect(AppPermissions.updateFees, 'fees.collect');
      expect(AppPermissions.deleteFees, 'fees.collect');
      expect(AppPermissions.deleteResults, 'results.edit');
      expect(AppPermissions.deleteUsers, 'users.deactivate');
    });

    test('Urdu label map covers every catalog code', () {
      for (final code in AppPermissions.allCodes) {
        expect(AppPermissions.urduLabelFor(code), isNotEmpty,
            reason: 'missing Urdu label for $code');
      }
    });
  });

  group('AppPermissions.fallbackFor (019 static offline fallback)', () {
    test('teacher: dotted attendance rights, NO fee/role rights', () {
      final p = AppPermissions.fallbackFor('teacher');
      expect(PermissionService.has(p, AppPermissions.markAttendance), isTrue);
      expect(PermissionService.has(p, AppPermissions.viewAttendance), isTrue);
      expect(PermissionService.has(p, AppPermissions.viewStudents), isTrue);
      expect(PermissionService.has(p, AppPermissions.enterResults), isTrue);
      // no fees.* and no admin rights for a teacher
      expect(PermissionService.has(p, AppPermissions.collectFees), isFalse);
      expect(PermissionService.has(p, AppPermissions.viewFees), isFalse);
      expect(PermissionService.has(p, AppPermissions.assignRoles), isFalse);
      // values are the canonical dotted codes, not legacy underscores
      expect(p, contains('attendance.mark'));
      expect(p, isNot(contains('mark_attendance')));
    });

    test('teacher: enter/edit results, but cannot publish them', () {
      final p = AppPermissions.fallbackFor('teacher');
      expect(PermissionService.has(p, AppPermissions.enterResults), isTrue);
      expect(PermissionService.has(p, AppPermissions.viewResults), isTrue);
      // deleteResults deliberately aliases results.edit (RLS semantics).
      expect(PermissionService.has(p, AppPermissions.deleteResults), isTrue);
      expect(PermissionService.has(p, AppPermissions.publishResults), isFalse);
    });

    test('accountant: collect/create fees yes; delete aliases collect', () {
      final p = AppPermissions.fallbackFor('accountant');
      expect(PermissionService.has(p, AppPermissions.collectFees), isTrue);
      expect(PermissionService.has(p, AppPermissions.createFees), isTrue);
      // deleteFees / updateFees deliberately alias fees.collect
      // (no separate server-side grant), so they resolve identically.
      expect(AppPermissions.deleteFees, AppPermissions.collectFees);
      expect(PermissionService.has(p, AppPermissions.deleteFees), isTrue);
      expect(PermissionService.has(p, AppPermissions.markAttendance), isFalse);
    });

    test('tenant_owner is a superset of teacher', () {
      final owner = AppPermissions.fallbackFor('tenant_owner');
      final teacher = AppPermissions.fallbackFor('teacher');
      expect(owner.containsAll(teacher), isTrue);
      expect(PermissionService.has(owner, AppPermissions.assignRoles), isTrue);
    });

    test('parent sees announcements only (read-only external role)', () {
      final p = AppPermissions.fallbackFor('parent');
      expect(PermissionService.has(p, AppPermissions.viewAnnouncements),
          isTrue);
      expect(PermissionService.has(p, AppPermissions.markAttendance), isFalse);
      expect(PermissionService.has(p, AppPermissions.createStudents), isFalse);
      expect(PermissionService.has(p, AppPermissions.collectFees), isFalse);
    });

    test('unknown role -> empty set (deny by default)', () {
      final p = AppPermissions.fallbackFor('definitely_not_a_role');
      expect(p, isEmpty);
      expect(PermissionService.has(p, AppPermissions.viewStudents), isFalse);
    });
  });
}
