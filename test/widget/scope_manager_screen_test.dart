/// Phase 9 Data Scopes manager tests (plain Urdu, no mock data in lib/).
///
/// Unit:      [ScopeAssignment] JSON round-trip is in
///            test/unit/scope_assignment_test.dart; [ScopePolicy] in
///            test/unit/scope_policy_test.dart.
/// Widget:    scope directory (Urdu labels, stale banner, permission
///            gate, tenant isolation).
/// Controller:[ScopeManagerController] fail-closed + narrow-only wiring
///            via a stub [RoleUxRepository].
///
/// Supabase is initialized to a dummy URL; repository calls go through
/// [StubScopeManagerRepository] / [StubScopeRoleUxRepo] (test-only seams,
/// live in test/).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/data/role_ux_repository.dart';
import 'package:madrasa_360/data/scope_manager_repository.dart';
import 'package:madrasa_360/presentation/screens/settings/scope_manager_screen.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/role_ux_provider.dart';
import 'package:madrasa_360/providers/scope_manager_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────
// Test seams (test/ only — never shipped)
// ─────────────────────────────────────────────────────────────

class StubScopeManagerRepository implements ScopeManagerRepository {
  StubScopeManagerRepository({
    this.items = const [],
    this.fromCache = false,
    this.fetchedAt,
  });

  List<ScopeAssignment> items;
  bool fromCache;
  DateTime? fetchedAt;

  /// Every tenant id the list was requested for (tenant isolation).
  final List<String> listTenants = [];

  @override
  String? get currentUserId => 'u-self';

  @override
  Future<ScopeAssignmentListResult> listAssignments(
    String tenantId, {
    String? userId,
  }) async {
    listTenants.add(tenantId);
    return ScopeAssignmentListResult(
        items: items, fromCache: fromCache, fetchedAt: fetchedAt);
  }

  @override
  Future<Map<String, String>> studentNames(
          String tenantId, Set<String> ids) async =>
      {};

  @override
  Future<Map<String, String>> classIdOfStudents(
          String tenantId, Set<String> studentIds) async =>
      {};
}

ScopeAssignment _assignment({
  String id = 'row-1',
  String userId = 'u-teacher',
  String userName = 'استاد احمد',
  String roleUrdu = 'استاد',
  String code = 'attendance.mark',
  String label = 'حاضری لگانا',
  String type = 'classes',
  Set<String> classIds = const {'c1', 'c2'},
  Map<String, String> classNames = const {'c1': 'جماعت اول', 'c2': 'جماعت دوم'},
}) =>
    ScopeAssignment(
      id: id,
      tenantId: 'tenant-test',
      userId: userId,
      userName: userName,
      userRoleUrdu: roleUrdu,
      permissionCode: code,
      permissionLabelUrdu: label,
      scopeType: type,
      classIds: classIds,
      classNames: classNames,
      createdAt: DateTime.utc(2026, 9, 26, 10),
    );

/// Configurable RoleUx stub for controller tests.
class StubScopeRoleUxRepo implements RoleUxRepository {
  StubScopeRoleUxRepo({
    this.granterScopes = const {},
    this.throwOnUserScopes = false,
  });

  Map<String, ScopeSelection> granterScopes;
  bool throwOnUserScopes;

  /// Write log, e.g. 'write:tenant-test:u-2:attendance.mark:classes'.
  final List<String> writes = [];

  @override
  String? get currentUserId => 'u-self';

  @override
  Future<Map<String, ScopeSelection>> userScopes(
      {required String tenantId, required String userId}) async {
    if (throwOnUserScopes) throw Exception('db down');
    return granterScopes;
  }

  @override
  Future<void> writeScopes(
      {required String tenantId,
      required String userId,
      required Set<String> codes,
      required ScopeSelection selection}) async {
    writes.add('write:$tenantId:$userId:${codes.join(',')}:${selection.type}');
  }

  @override
  Future<List<TenantUser>> listUsers(String tenantId, {String? search}) =>
      throw UnimplementedError();
  @override
  Future<List<TenantRoleInfo>> listRoles(String tenantId) =>
      throw UnimplementedError();
  @override
  Future<List<PermissionInfo>> permissionCatalog() =>
      throw UnimplementedError();
  @override
  Future<Map<String, int>> roleMemberCounts(String tenantId) =>
      throw UnimplementedError();
  @override
  Future<String> createAuthUser(
          {required String name,
          required String phone,
          required String email,
          required String password}) =>
      throw UnimplementedError();
  @override
  Future<void> assignRole(
          {required String tenantId,
          required String userId,
          required String roleKey}) =>
      throw UnimplementedError();
  @override
  Future<void> setUserPermission(
          {required String tenantId,
          required String userId,
          required String code,
          required String? effect}) =>
      throw UnimplementedError();
  @override
  Future<void> syncUserPermissions(
          {required String tenantId,
          required String userId,
          required Set<String> templateCodes,
          required Set<String> selectedCodes}) =>
      throw UnimplementedError();
  @override
  Future<void> setActive({required String userId, required bool active}) =>
      throw UnimplementedError();
  @override
  Future<void> deleteAuthUser(String userId) => throw UnimplementedError();
  @override
  Future<Map<String, String>> userOverrides(
          {required String tenantId, required String userId}) =>
      throw UnimplementedError();
  @override
  Future<List<ClassRef>> listClasses(String tenantId) =>
      throw UnimplementedError();
  @override
  Future<List<StudentRef>> searchStudents(String tenantId, String query) =>
      throw UnimplementedError();
  @override
  Future<List<AssignedClassInfo>> assignedClasses(
          {required String tenantId, required String userId}) =>
      throw UnimplementedError();
  @override
  Future<List<AuditRow>> userActivity(
          {required String tenantId, required String userId}) =>
      throw UnimplementedError();
  @override
  Future<SafetyCheck?> safetyCheck(
          {required String tenantId, required String userId}) =>
      throw UnimplementedError();
}

const _self = AppUser(
  id: 'u-self',
  email: 'mohtamim@madrassa.com',
  name: 'مہتمم صاحب',
  role: UserRole.madrasaAdmin,
);

ProviderScope _scope({
  required StubScopeManagerRepository repo,
  Set<String> permissions = const {'roles.assign', 'users.view'},
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      currentTenantIdProvider.overrideWithValue('tenant-test'),
      userPermissionsProvider.overrideWithValue(permissions),
      currentUserProvider.overrideWithValue(_self),
      scopeManagerRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'widget-test-anon-key',
    );
  });

  group('ScopeManagerScreen directory', () {
    testWidgets('renders assignments with Urdu labels', (tester) async {
      final repo = StubScopeManagerRepository(items: [_assignment()]);
      await tester
          .pumpWidget(_scope(repo: repo, child: const ScopeManagerScreen()));
      await tester.pumpAndSettle();

      expect(find.text('ڈیٹا حدود'), findsWidgets);
      expect(find.text('استاد احمد'), findsOneWidget);
      expect(find.text('حاضری لگانا'), findsOneWidget);
      expect(find.text('مقرر کردہ جماعتیں (2)'), findsOneWidget);
      expect(find.textContaining('جماعت اول'), findsOneWidget);
      expect(find.textContaining('لاگو از'), findsOneWidget);
      // Tenant isolation: the stub saw exactly the active tenant.
      expect(repo.listTenants, ['tenant-test']);
    });

    testWidgets('shows the stale banner for cached data', (tester) async {
      final repo = StubScopeManagerRepository(
        items: [_assignment()],
        fromCache: true,
        fetchedAt: DateTime.utc(2026, 9, 25, 5),
      );
      await tester
          .pumpWidget(_scope(repo: repo, child: const ScopeManagerScreen()));
      await tester.pumpAndSettle();

      expect(find.text('آف لائن ڈیٹا دکھایا جا رہا ہے'), findsOneWidget);
      expect(find.textContaining('آخری تازہ کاری'), findsOneWidget);
    });

    testWidgets('empty directory explains the default plainly', (tester) async {
      final repo = StubScopeManagerRepository(items: const []);
      await tester
          .pumpWidget(_scope(repo: repo, child: const ScopeManagerScreen()));
      await tester.pumpAndSettle();

      expect(find.text('ابھی کوئی محدود دائرہ کار مقرر نہیں'), findsOneWidget);
    });

    testWidgets('locked without roles.assign', (tester) async {
      final repo = StubScopeManagerRepository(items: [_assignment()]);
      await tester.pumpWidget(_scope(
          repo: repo,
          permissions: const {'users.view'},
          child: const ScopeManagerScreen()));
      await tester.pumpAndSettle();

      expect(
          find.text('آپ کو یہ صفحہ دیکھنے کی اجازت نہیں ہے'), findsOneWidget);
      expect(find.text('استاد احمد'), findsNothing);
    });
  });

  group('ScopeManagerController', () {
    ProviderContainer makeContainer(StubScopeRoleUxRepo roleUx) {
      return ProviderContainer(
        overrides: [
          currentTenantIdProvider.overrideWithValue('tenant-test'),
          currentUserProvider.overrideWithValue(_self),
          roleUxRepositoryProvider.overrideWithValue(roleUx),
          scopeManagerRepositoryProvider
              .overrideWithValue(StubScopeManagerRepository()),
        ],
      );
    }

    test('fail-closed when granter scopes cannot load', () async {
      final roleUx = StubScopeRoleUxRepo(throwOnUserScopes: true);
      final container = makeContainer(roleUx);
      addTearDown(container.dispose);

      final err = await container
          .read(scopeManagerControllerProvider.notifier)
          .saveScope(
            targetUserId: 'u-2',
            codes: const {'attendance.mark'},
            selection: const ScopeSelection(type: 'classes', classIds: {'c1'}),
          );
      expect(err, contains('معلوم نہیں'));
      expect(roleUx.writes, isEmpty);
    });

    test('narrow-only refusal surfaces before any write', () async {
      final roleUx = StubScopeRoleUxRepo(granterScopes: {
        'attendance.mark':
            const ScopeSelection(type: 'classes', classIds: {'c1'}),
      });
      final container = makeContainer(roleUx);
      addTearDown(container.dispose);

      final err = await container
          .read(scopeManagerControllerProvider.notifier)
          .saveScope(
            targetUserId: 'u-2',
            codes: const {'attendance.mark'},
            selection:
                const ScopeSelection(type: 'classes', classIds: {'c1', 'c2'}),
          );
      expect(err, isNotNull);
      expect(err, contains('اپنے دائرہ کار'));
      expect(roleUx.writes, isEmpty);
    });

    test('allowed grant writes through', () async {
      final roleUx = StubScopeRoleUxRepo(); // no rows = unrestricted
      final container = makeContainer(roleUx);
      addTearDown(container.dispose);

      final err = await container
          .read(scopeManagerControllerProvider.notifier)
          .saveScope(
            targetUserId: 'u-2',
            codes: const {'attendance.mark'},
            selection: const ScopeSelection(type: 'classes', classIds: {'c1'}),
          );
      expect(err, isNull);
      expect(roleUx.writes, ['write:tenant-test:u-2:attendance.mark:classes']);
    });
  });
}
