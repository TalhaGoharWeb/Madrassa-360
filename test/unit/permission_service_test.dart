// Permission-evaluation unit tests.
//
// Implementation files under test:
//   lib/core/services/permission_service.dart     (has/hasAll/hasAny + role classifiers)
//   lib/core/constants/app_permissions.dart       (offline roleDefaults fallback matrix)
//
// The Dart side uses the legacy underscore codes (mark_attendance,
// create_fees, ...), which are the client mirror of the canonical dotted
// codes seeded by supabase/migrations/005_rbac.sql:
//   SQL 005 'teacher' row set: students.view, attendance.view,
//     attendance.mark, attendance.edit, exams.view, results.view,
//     results.enter, results.edit, notifications.view
//   -> notably NO fees.* and NO results.delete / exams.create.
// The tests below assert the same grants/denies on the Dart fallback,
// e.g. a teacher HAS attendance.mark (mark_attendance) but NOT
// fees.collect (create_fees/update_fees).
//
// HONESTY NOTE: PermissionService.loadForUser() calls the Supabase RPC
// get_my_permissions() and is NOT covered here (needs network). Only the
// pure evaluation helpers and the static fallback matrix are.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/services/permission_service.dart';

void main() {
  group('PermissionService.has / hasAll / hasAny', () {
    final perms = <String>{'a', 'b', 'c'};

    test('has is exact set membership', () {
      expect(PermissionService.has(perms, 'a'), isTrue);
      expect(PermissionService.has(perms, 'z'), isFalse);
      expect(PermissionService.has(const {}, 'a'), isFalse);
    });

    test('hasAll requires every permission', () {
      expect(PermissionService.hasAll(perms, ['a', 'b']), isTrue);
      expect(PermissionService.hasAll(perms, ['a', 'z']), isFalse);
      expect(PermissionService.hasAll(perms, []), isTrue);
    });

    test('hasAny requires at least one', () {
      expect(PermissionService.hasAny(perms, ['z', 'b']), isTrue);
      expect(PermissionService.hasAny(perms, ['x', 'y']), isFalse);
      expect(PermissionService.hasAny(perms, []), isFalse);
    });
  });

  group('teacher role (005 matrix: attendance.mark yes, fees.collect no)',
      () {
    final teacher = AppPermissions.fallbackFor('teacher');

    test('teacher can mark attendance (SQL: attendance.mark)', () {
      expect(
          PermissionService.has(teacher, AppPermissions.markAttendance),
          isTrue);
      expect(PermissionService.has(teacher, AppPermissions.viewAttendance),
          isTrue);
    });

    test('teacher CANNOT collect/refund fees (SQL: no fees.* for teacher)',
        () {
      expect(PermissionService.has(teacher, AppPermissions.createFees),
          isFalse);
      expect(PermissionService.has(teacher, AppPermissions.updateFees),
          isFalse);
      expect(PermissionService.has(teacher, AppPermissions.deleteFees),
          isFalse);
      // viewing fee records is allowed
      expect(PermissionService.has(teacher, AppPermissions.viewFees),
          isTrue);
    });

    test('teacher can enter results but not delete them', () {
      expect(PermissionService.has(teacher, AppPermissions.enterResults),
          isTrue);
      expect(PermissionService.has(teacher, AppPermissions.viewResults),
          isTrue);
      expect(PermissionService.has(teacher, AppPermissions.deleteResults),
          isFalse);
    });

    test('teacher cannot manage users, roles or settings', () {
      expect(
          PermissionService.hasAny(teacher, [
            AppPermissions.createUsers,
            AppPermissions.manageRoles,
            AppPermissions.managePermissions,
            AppPermissions.manageSettings,
          ]),
          isFalse);
    });
  });

  group('finance roles', () {
    test('accountant can create/update fees but not delete them', () {
      final p = AppPermissions.fallbackFor('accountant');
      expect(PermissionService.has(p, AppPermissions.createFees), isTrue);
      expect(PermissionService.has(p, AppPermissions.updateFees), isTrue);
      expect(PermissionService.has(p, AppPermissions.deleteFees), isFalse);
      expect(
          PermissionService.has(p, AppPermissions.markAttendance), isFalse);
    });

    test('financeManager has the full finance set', () {
      final p = AppPermissions.fallbackFor('financeManager');
      expect(
          PermissionService.hasAll(p, [
            AppPermissions.viewFinance,
            AppPermissions.createFinance,
            AppPermissions.approveFinance,
            AppPermissions.deleteFinance,
            AppPermissions.deleteFees,
          ]),
          isTrue);
    });
  });

  group('fallbackFor edge cases', () {
    test('unknown role -> empty set (deny by default)', () {
      final p = AppPermissions.fallbackFor('definitely_not_a_role');
      expect(p, isEmpty);
      expect(PermissionService.has(p, AppPermissions.viewStudents), isFalse);
    });

    test('parent is read-only on attendance/fees/results', () {
      final p = AppPermissions.fallbackFor('parent');
      expect(
          PermissionService.hasAll(p, [
            AppPermissions.viewAttendance,
            AppPermissions.viewFees,
            AppPermissions.viewResults,
          ]),
          isTrue);
      expect(PermissionService.has(p, AppPermissions.markAttendance),
          isFalse);
      expect(PermissionService.has(p, AppPermissions.createStudents),
          isFalse);
    });

    test('madrasaAdmin is a superset of teacher', () {
      final admin = AppPermissions.fallbackFor('madrasaAdmin');
      final teacher = AppPermissions.fallbackFor('teacher');
      expect(admin.containsAll(teacher), isTrue);
      expect(PermissionService.has(admin, AppPermissions.deleteFees),
          isTrue);
    });
  });

  group('role classifiers', () {
    test('isPlatformRole', () {
      expect(PermissionService.isPlatformRole('superAdmin'), isTrue);
      expect(PermissionService.isPlatformRole('franchiseManager'), isTrue);
      expect(PermissionService.isPlatformRole('madrasaAdmin'), isFalse);
      expect(PermissionService.isPlatformRole('teacher'), isFalse);
    });

    test('isMadrasaAdmin', () {
      expect(PermissionService.isMadrasaAdmin('madrasaAdmin'), isTrue);
      expect(PermissionService.isMadrasaAdmin('admin'), isTrue);
      expect(PermissionService.isMadrasaAdmin('editor'), isTrue);
      expect(PermissionService.isMadrasaAdmin('itManager'), isTrue);
      expect(PermissionService.isMadrasaAdmin('teacher'), isFalse);
    });

    test('isStaffRole covers operational staff, not externals', () {
      expect(PermissionService.isStaffRole('teacher'), isTrue);
      expect(PermissionService.isStaffRole('accountant'), isTrue);
      expect(PermissionService.isStaffRole('parent'), isFalse);
      expect(PermissionService.isStaffRole('student'), isFalse);
    });

    test('isExternalRole is exactly parent/student', () {
      expect(PermissionService.isExternalRole('parent'), isTrue);
      expect(PermissionService.isExternalRole('student'), isTrue);
      expect(PermissionService.isExternalRole('teacher'), isFalse);
    });
  });

  // ── Server-code normalization (Phase-8 fix) ────────────────────────
  // The server returns dotted codes (005_rbac.sql); the UI checks underscore
  // constants. Without normalizeServerCodes every online check was false.

  group('normalizeServerCodes', () {
    test('teacher dotted set maps to working underscore permissions', () {
      final server = {
        'students.view',
        'attendance.view',
        'attendance.mark',
        'attendance.edit',
        'exams.view',
        'results.view',
        'results.enter',
        'results.edit',
        'notifications.view',
      };
      final perms = PermissionService.normalizeServerCodes(server);
      expect(PermissionService.has(perms, AppPermissions.markAttendance),
          isTrue);
      expect(
          PermissionService.has(perms, AppPermissions.viewStudents), isTrue);
      expect(PermissionService.has(perms, AppPermissions.enterResults),
          isTrue);
      // teacher has no fee rights anywhere in the matrix
      expect(PermissionService.has(perms, AppPermissions.viewFees), isFalse);
      expect(PermissionService.has(perms, AppPermissions.createFees), isFalse);
    });

    test('unmapped dotted codes are dropped fail-closed', () {
      final perms = PermissionService.normalizeServerCodes({
        'fees.collect', // no Dart counterpart
        'audit.view', // no Dart counterpart
        'roles.assign', // intentionally unmapped (would over-grant)
        'students.view',
      });
      expect(perms, {AppPermissions.viewStudents});
    });

    test('legacy underscore codes pass through untouched', () {
      final perms = PermissionService.normalizeServerCodes(
          {AppPermissions.viewStudents, 'custom_code'});
      expect(perms, {AppPermissions.viewStudents, 'custom_code'});
    });

    test('empty set stays empty; update maps to edit_* family', () {
      expect(PermissionService.normalizeServerCodes({}), isEmpty);
      final perms =
          PermissionService.normalizeServerCodes({'students.update'});
      expect(perms, {AppPermissions.editStudents});
    });
  });
}
