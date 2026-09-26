// Phase 9: ScopeAssignment model tests (offline cache round-trip).
//
// Implementation file under test:
//   lib/data/scope_manager_repository.dart (ScopeAssignment only — the
//   Supabase queries need a database and are NOT covered here).

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/data/scope_manager_repository.dart';

ScopeAssignment _assignment() => ScopeAssignment(
      id: 'row-1',
      tenantId: 'tenant-test',
      userId: 'u-1',
      userName: 'استاد احمد',
      userRoleUrdu: 'استاد',
      permissionCode: 'attendance.mark',
      permissionLabelUrdu: 'حاضری لگانا',
      scopeType: 'classes',
      classIds: const {'c1', 'c2'},
      studentIds: const {},
      classNames: const {'c1': 'جماعت اول', 'c2': 'جماعت دوم'},
      studentNames: const {},
      createdAt: DateTime.utc(2026, 9, 26, 10, 0),
    );

void main() {
  group('ScopeAssignment JSON round-trip', () {
    test('toJson/fromJson preserves every field', () {
      final a = _assignment();
      final back = ScopeAssignment.fromJson(a.toJson());
      expect(back.id, a.id);
      expect(back.tenantId, a.tenantId);
      expect(back.userId, a.userId);
      expect(back.userName, a.userName);
      expect(back.userRoleUrdu, a.userRoleUrdu);
      expect(back.permissionCode, a.permissionCode);
      expect(back.permissionLabelUrdu, a.permissionLabelUrdu);
      expect(back.scopeType, a.scopeType);
      expect(back.classIds, a.classIds);
      expect(back.studentIds, a.studentIds);
      expect(back.classNames, a.classNames);
      expect(back.studentNames, a.studentNames);
      expect(back.createdAt, a.createdAt);
    });

    test('fromJson tolerates corrupt / partial rows', () {
      final a = ScopeAssignment.fromJson(const {});
      expect(a.id, isEmpty);
      expect(a.scopeType, 'all');
      expect(a.classIds, isEmpty);
      expect(a.createdAt, isNotNull);
    });

    test('ScopeAssignmentListResult carries the stale-cache signal', () {
      const r = ScopeAssignmentListResult(items: [], fromCache: true);
      expect(r.fromCache, isTrue);
      expect(r.fetchedAt, isNull);
      expect(r.items, isEmpty);
    });
  });
}
