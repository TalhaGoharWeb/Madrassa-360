// ScopeService unit tests (Phase 5).
//
// Implementation file under test:
//   lib/core/services/scope_service.dart
//
// Only the pure parts are covered here: parsing a `permission_scopes` row
// and the Urdu scope descriptions. The live Supabase queries in
// classIdsInScope/studentIdsInScope/scopeAllows need a database and are
// NOT covered here (RLS `scope_allows()` remains the real enforcement;
// these helpers only pre-filter the UI).

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/scope_service.dart';

PermissionScope _row({
  String scopeType = 'all',
  Map<String, dynamic>? ref,
}) =>
    PermissionScope.fromRow(
      permission: 'students.view',
      row: {'scope_type': scopeType, 'scope_ref': ref},
    );

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

    test('missing scope_type defaults to all (unrestricted)', () {
      final s = PermissionScope.fromRow(
        permission: 'students.view',
        row: {'scope_ref': null},
      );
      expect(s.scopeType, 'all');
      expect(s.isUnrestricted, isTrue);
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
  });
}
