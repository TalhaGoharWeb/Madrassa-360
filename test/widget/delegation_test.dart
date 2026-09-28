/// Phase 8b delegation tests (plain Urdu, no mock data in lib/).
///
/// Unit:   [DelegationPolicy] ceiling validation; [DelegationInfo.isActiveAt]
///         expiry; [DelegationInfo] JSON round-trip (offline cache);
///         [delegationErrorMessage] mapping (never leaks server text).
/// Widget: delegation list (Urdu labels, revoke flow, tenant isolation);
///         create screen (ceiling-filtered picker, create wiring);
///         permission gate; offline cache fallback.
///
/// Supabase is initialized to a dummy URL; repository calls go through
/// [StubDelegationRepository] / [StubRoleUxRepo] (test-only seams, live in
/// test/). The offline test uses the REAL [SupabaseDelegationRepository]
/// against a seeded [StorageService] cache to prove the cache path.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/storage_service.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/data/delegation_policy.dart';
import 'package:madrasa_360/data/delegation_repository.dart';
import 'package:madrasa_360/data/role_ux_repository.dart';
import 'package:madrasa_360/presentation/screens/settings/delegation_create_screen.dart';
import 'package:madrasa_360/presentation/screens/settings/delegation_screen.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/delegation_provider.dart';
import 'package:madrasa_360/providers/role_ux_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────
// Test seams (test/ only — never shipped)
// ─────────────────────────────────────────────────────────────

class StubDelegationRepository implements DelegationRepository {
  StubDelegationRepository({this.delegations = const []});

  List<DelegationInfo> delegations;

  /// Write log, e.g. 'create:tenant-test:u2:fees.collect'.
  final List<String> calls = [];

  /// Every tenant id the list was requested for (tenant isolation).
  final List<String> listTenants = [];

  /// When set, createDelegation throws it (simulates a server refusal).
  Object? createError;

  @override
  String? get currentUserId => 'u-self';

  @override
  Future<DelegationListResult> listDelegations(
    String tenantId, {
    String? userId,
  }) async {
    listTenants.add(tenantId);
    return DelegationListResult(items: delegations, fromCache: false);
  }

  @override
  Future<void> createDelegation({
    required String tenantId,
    required String delegateeId,
    required String code,
    DelegationScope scope = const DelegationScope(),
    DateTime? expiresAt,
  }) async {
    if (createError != null) throw createError!;
    calls.add('create:$tenantId:$delegateeId:$code');
  }

  @override
  Future<void> revokeDelegation({
    required String tenantId,
    required String delegationId,
  }) async {
    calls.add('revoke:$tenantId:$delegationId');
    delegations = delegations.where((d) => d.id != delegationId).toList();
  }
}

/// Minimal RoleUxRepository stub: only what the delegation screens read
/// (users + permission catalog); everything else is out of scope here.
class StubRoleUxRepo implements RoleUxRepository {
  StubRoleUxRepo({required this.users, required this.catalog});

  final List<TenantUser> users;
  final List<PermissionInfo> catalog;

  @override
  String? get currentUserId => 'u-self';

  @override
  Future<List<TenantUser>> listUsers(String tenantId, {String? search}) async =>
      users;

  @override
  Future<List<PermissionInfo>> permissionCatalog() async => catalog;

  @override
  Future<List<TenantRoleInfo>> listRoles(String tenantId) =>
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
  Future<void> writeScopes(
          {required String tenantId,
          required String userId,
          required Set<String> codes,
          required ScopeSelection selection}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, String>> userOverrides(
          {required String tenantId, required String userId}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, ScopeSelection>> userScopes(
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

// ─────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────

List<TenantUser> _users() => const [
      TenantUser(
        id: 'u-self',
        name: 'مہتمم صاحب',
        email: 'mohtamim@madrassa.com',
        roleKey: 'mohtamim',
        roleUrdu: 'مہتمم',
        isActive: true,
        banned: false,
      ),
      TenantUser(
        id: 'u2',
        name: 'احمد رضا',
        email: 'ahmed@madrassa.com',
        roleKey: 'ustad',
        roleUrdu: 'استاد',
        isActive: true,
        banned: false,
      ),
      TenantUser(
        id: 'u3',
        name: 'بلال احمد',
        email: 'bilal@madrassa.com',
        roleKey: 'daftar_dar',
        roleUrdu: 'دفتر دار',
        isActive: true,
        banned: false,
      ),
    ];

List<PermissionInfo> _catalog() => const [
      PermissionInfo(
          id: 'p1',
          code: 'fees.collect',
          labelUrdu: 'فیس وصول کرنا',
          categoryUrdu: 'مالیات',
          sortOrder: 1),
      PermissionInfo(
          id: 'p2',
          code: 'students.view',
          labelUrdu: 'طلبہ دیکھنا',
          categoryUrdu: 'طلبہ',
          sortOrder: 2),
      PermissionInfo(
          id: 'p3',
          code: 'users.create',
          labelUrdu: 'نیا صارف بنانا',
          categoryUrdu: 'انتظام',
          sortOrder: 3),
    ];

DelegationInfo _delegation({
  required String id,
  required String delegateeId,
  required String code,
  DateTime? expiresAt,
}) =>
    DelegationInfo(
      id: id,
      tenantId: 'tenant-test',
      delegatorId: 'u-self',
      delegateeId: delegateeId,
      permissionId: 'p-$code',
      permissionCode: code,
      scopeType: 'all',
      startsAt: DateTime.utc(2026, 9, 1),
      expiresAt: expiresAt,
      createdAt: DateTime.utc(2026, 9, 20),
    );

ProviderScope _scope({
  required StubDelegationRepository repo,
  required StubRoleUxRepo roleRepo,
  Set<String> permissions = const {
    'users.view',
    'roles.assign',
    'fees.collect'
  },
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      currentTenantIdProvider.overrideWithValue('tenant-test'),
      userPermissionsProvider.overrideWithValue(permissions),
      currentUserProvider.overrideWithValue(const AppUser(
        id: 'u-self',
        email: 'mohtamim@madrassa.com',
        name: 'مہتمم صاحب',
        role: UserRole.madrasaAdmin,
      )),
      delegationRepositoryProvider.overrideWithValue(repo),
      roleUxRepositoryProvider.overrideWithValue(roleRepo),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'widget-test-anon-key',
    );
  });

  // ── unit: DelegationPolicy (client-side ceiling) ─────────────

  group('DelegationPolicy.validateCreate', () {
    final now = DateTime(2026, 9, 26, 12);

    test('delegating an unheld permission is refused (the ceiling)', () {
      final msg = DelegationPolicy.validateCreate(
        selfId: 'u-self',
        delegateeId: 'u2',
        codes: {'fees.collect'},
        myCodes: {'roles.assign'},
        now: now,
      );
      expect(msg, isNotNull);
      expect(msg, contains('آپ کے پاس خود موجود نہیں'));
      expect(msg, isNot(contains('fees.collect')));
    });

    test('delegating to yourself is refused', () {
      final msg = DelegationPolicy.validateCreate(
        selfId: 'u-self',
        delegateeId: 'u-self',
        codes: {'fees.collect'},
        myCodes: {'fees.collect', 'roles.assign'},
        now: now,
      );
      expect(msg, contains('خود کو اختیار نہیں سونپ سکتے'));
    });

    test('a past expiry date is refused', () {
      final msg = DelegationPolicy.validateCreate(
        selfId: 'u-self',
        delegateeId: 'u2',
        codes: {'fees.collect'},
        myCodes: {'fees.collect'},
        expiresAt: DateTime(2026, 9, 25),
        now: now,
      );
      expect(msg, contains('آج سے آگے'));
    });

    test('empty permission set is refused', () {
      final msg = DelegationPolicy.validateCreate(
        selfId: 'u-self',
        delegateeId: 'u2',
        codes: const {},
        myCodes: {'fees.collect'},
        now: now,
      );
      expect(msg, contains('کم از کم ایک اختیار'));
    });

    test('a held permission with future expiry passes', () {
      final msg = DelegationPolicy.validateCreate(
        selfId: 'u-self',
        delegateeId: 'u2',
        codes: {'fees.collect'},
        myCodes: {'fees.collect', 'roles.assign'},
        expiresAt: DateTime(2026, 10, 26),
        now: now,
      );
      expect(msg, isNull);
    });
  });

  group('DelegationPolicy.delegatableCatalog', () {
    test('only the delegator-held codes are offered', () {
      final offered = DelegationPolicy.delegatableCatalog(
          _catalog(), {'fees.collect', 'roles.assign'});
      expect(offered.map((p) => p.code), ['fees.collect']);
    });

    test('empty own set offers nothing (fail-closed)', () {
      expect(
          DelegationPolicy.delegatableCatalog(_catalog(), const {}), isEmpty);
    });
  });

  // ── unit: expiry + JSON round-trip ───────────────────────────

  group('DelegationInfo', () {
    test('isActiveAt honors expiry', () {
      final now = DateTime(2026, 9, 26, 12);
      expect(
          _delegation(id: 'a', delegateeId: 'u2', code: 'fees.collect')
              .isActiveAt(now),
          isTrue);
      expect(
          _delegation(
                  id: 'b',
                  delegateeId: 'u2',
                  code: 'fees.collect',
                  expiresAt: DateTime(2026, 10, 1))
              .isActiveAt(now),
          isTrue);
      expect(
          _delegation(
                  id: 'c',
                  delegateeId: 'u2',
                  code: 'fees.collect',
                  expiresAt: DateTime(2026, 9, 25))
              .isActiveAt(now),
          isFalse);
    });

    test('expired rows are filtered out of the active list', () {
      final now = DateTime(2026, 9, 26, 12);
      final rows = [
        _delegation(id: 'a', delegateeId: 'u2', code: 'fees.collect'),
        _delegation(
            id: 'b',
            delegateeId: 'u2',
            code: 'fees.collect',
            expiresAt: DateTime(2026, 9, 1)),
      ];
      final active = rows.where((d) => d.isActiveAt(now)).toList();
      expect(active.map((d) => d.id), ['a']);
    });

    test('JSON round-trip preserves every field (offline cache)', () {
      final d = _delegation(
          id: 'd1',
          delegateeId: 'u2',
          code: 'fees.collect',
          expiresAt: DateTime.utc(2026, 12, 31, 10));
      final back = DelegationInfo.fromJson(
          jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(back.id, 'd1');
      expect(back.tenantId, 'tenant-test');
      expect(back.delegatorId, 'u-self');
      expect(back.delegateeId, 'u2');
      expect(back.permissionCode, 'fees.collect');
      expect(back.expiresAt?.toUtc(), DateTime.utc(2026, 12, 31, 10));
      expect(back.isActiveAt(DateTime(2026, 9, 26)), isTrue);
    });
  });

  // ── unit: error mapping ──────────────────────────────────────

  group('delegationErrorMessage', () {
    test('server ceiling refusal is mapped, code hidden', () {
      final msg = delegationErrorMessage(Exception(
          'permission_delegations: delegator u-self does not effectively '
          'hold permission "fees.collect" in tenant tenant-test'));
      expect(msg, contains('آپ کے پاس خود موجود نہیں'));
      expect(msg, isNot(contains('fees.collect')));
      expect(msg, isNot(contains('permission_delegations')));
    });

    test('lacks roles.assign is mapped', () {
      final msg = delegationErrorMessage(Exception(
          'permission_delegations: delegator u-self lacks roles.assign '
          '(or owner/admin) in tenant tenant-test'));
      expect(msg, contains('اختیار سونپنے کی اجازت نہیں'));
    });

    test('non-member delegatee is explained', () {
      final msg = delegationErrorMessage(Exception(
          'permission_delegations: delegatee u9 is not a member of tenant '
          'tenant-test'));
      expect(msg, contains('اس مدرسے کا رکن نہیں'));
    });

    test('network failure falls back to the shared Urdu mapping', () {
      final msg =
          delegationErrorMessage(const SocketException('connection refused'));
      expect(msg, contains('انٹرنیٹ سے رابطہ نہیں'));
    });
  });

  // ── widget: list screen ──────────────────────────────────────

  group('DelegationScreen', () {
    testWidgets('shows active delegations with Urdu labels, hides expired',
        (tester) async {
      final repo = StubDelegationRepository(delegations: [
        _delegation(
            id: 'd1',
            delegateeId: 'u2',
            code: 'fees.collect',
            expiresAt: DateTime.now().add(const Duration(days: 10))),
        _delegation(id: 'd2', delegateeId: 'u3', code: 'students.view'),
        _delegation(
            id: 'd3',
            delegateeId: 'u2',
            code: 'fees.collect',
            expiresAt: DateTime.now().subtract(const Duration(days: 1))),
      ]);
      await tester.pumpWidget(_scope(
        repo: repo,
        roleRepo: StubRoleUxRepo(users: _users(), catalog: _catalog()),
        child: const DelegationScreen(),
      ));
      await tester.pumpAndSettle();

      // Tenant isolation: every query carried the active tenant id.
      expect(repo.listTenants, ['tenant-test']);

      // Active rows render with human Urdu labels — never raw codes.
      expect(find.text('احمد رضا'), findsOneWidget);
      expect(find.text('فیس وصول کرنا'), findsOneWidget);
      expect(find.text('بلال احمد'), findsOneWidget);
      expect(find.text('طلبہ دیکھنا'), findsOneWidget);
      expect(find.text('fees.collect'), findsNothing);
      expect(find.textContaining('سونپنے والا:'), findsNWidgets(2));
      expect(find.textContaining('میعاد:'), findsOneWidget);
      expect(find.text('بغیر میعاد'), findsOneWidget);
      // The expired delegation (d3) is not listed.
      expect(find.byTooltip('اختیار واپس لیں'), findsNWidgets(2));
    });

    testWidgets('revoke asks for confirmation then calls the repository',
        (tester) async {
      final repo = StubDelegationRepository(delegations: [
        _delegation(id: 'd1', delegateeId: 'u2', code: 'fees.collect'),
      ]);
      await tester.pumpWidget(_scope(
        repo: repo,
        roleRepo: StubRoleUxRepo(users: _users(), catalog: _catalog()),
        child: const DelegationScreen(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('اختیار واپس لیں'));
      await tester.pumpAndSettle();
      expect(find.text('اختیار واپس لیں'), findsWidgets);
      expect(
          find.textContaining('فوری طور پر واپس لیا جائے گا'), findsOneWidget);

      await tester.tap(find.text('جی ہاں، واپس لیں'));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('revoke:tenant-test:d1'));
      expect(find.text('اختیار واپس لے لیا گیا'), findsOneWidget);
      // The revoked row is gone from the list.
      expect(find.text('احمد رضا'), findsNothing);
    });

    testWidgets('without roles.assign the screen stays locked', (tester) async {
      final repo = StubDelegationRepository();
      await tester.pumpWidget(_scope(
        repo: repo,
        roleRepo: StubRoleUxRepo(users: _users(), catalog: _catalog()),
        permissions: const {'users.view'},
        child: const DelegationScreen(),
      ));
      await tester.pumpAndSettle();
      expect(
          find.text('آپ کو یہ صفحہ دیکھنے کی اجازت نہیں ہے'), findsOneWidget);
      expect(repo.listTenants, isEmpty);
    });
  });

  // ── widget: create screen ────────────────────────────────────

  group('DelegationCreateScreen', () {
    testWidgets('picker offers only the delegator-held permissions',
        (tester) async {
      final repo = StubDelegationRepository();
      await tester.pumpWidget(_scope(
        repo: repo,
        roleRepo: StubRoleUxRepo(users: _users(), catalog: _catalog()),
        child: const DelegationCreateScreen(),
      ));
      await tester.pumpAndSettle();

      // fees.collect is held -> offered; the rest are hidden (ceiling).
      expect(find.text('فیس وصول کرنا'), findsOneWidget);
      expect(find.text('طلبہ دیکھنا'), findsNothing);
      expect(find.text('نیا صارف بنانا'), findsNothing);
      expect(find.textContaining('جو آپ کے پاس خود موجود ہیں'), findsOneWidget);
    });

    testWidgets('full create flow calls the repository once per code',
        (tester) async {
      final repo = StubDelegationRepository();
      await tester.pumpWidget(_scope(
        repo: repo,
        roleRepo: StubRoleUxRepo(users: _users(), catalog: _catalog()),
        permissions: const {
          'users.view',
          'roles.assign',
          'fees.collect',
          'students.view'
        },
        child: const DelegationCreateScreen(),
      ));
      await tester.pumpAndSettle();

      // 1. pick the target user.
      await tester.tap(find.text('صارف منتخب کریں…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('احمد رضا'));
      await tester.pumpAndSettle();
      expect(find.text('احمد رضا'), findsWidgets);

      // 2. pick permissions (both held codes are offered now).
      await tester.tap(find.text('فیس وصول کرنا'));
      await tester.pump();
      await tester.tap(find.text('طلبہ دیکھنا'));
      await tester.pump();

      // 3. confirm.
      await tester.tap(find.text('اختیار سونپیں'));
      await tester.pumpAndSettle();

      expect(
          repo.calls,
          containsAll([
            'create:tenant-test:u2:fees.collect',
            'create:tenant-test:u2:students.view',
          ]));
      expect(repo.calls.length, 2);
    });

    testWidgets('server ceiling refusal surfaces as plain Urdu',
        (tester) async {
      final repo = StubDelegationRepository()
        ..createError = Exception('permission_delegations: delegator u-self '
            'does not effectively hold permission "fees.collect" in tenant '
            'tenant-test');
      final container = ProviderContainer(overrides: [
        currentTenantIdProvider.overrideWithValue('tenant-test'),
        userPermissionsProvider
            .overrideWithValue(const {'roles.assign', 'fees.collect'}),
        currentUserProvider.overrideWithValue(const AppUser(
          id: 'u-self',
          email: 'mohtamim@madrassa.com',
          name: 'مہتمم صاحب',
          role: UserRole.madrasaAdmin,
        )),
        delegationRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final err = await container
          .read(delegationControllerProvider.notifier)
          .createDelegations(
        delegateeId: 'u2',
        codes: {'fees.collect'},
        scopesByCode: const {},
      );
      expect(err, isNotNull);
      expect(err, contains('آپ کے پاس خود موجود نہیں'));
      expect(err, isNot(contains('fees.collect')));
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ── widget: offline cache fallback ───────────────────────────

  group('offline delegation list', () {
    testWidgets('reads the last-known cache when the network fails',
        (tester) async {
      const userId = 'u-test';
      const cacheKey = 'delegations.v1.$userId.tenant-test';
      final cached = _delegation(
          id: 'd-cached',
          delegateeId: 'u2',
          code: 'fees.collect',
          expiresAt: DateTime.now().add(const Duration(days: 5)));
      await StorageService.saveStringList(
          cacheKey, [jsonEncode(cached.toJson())]);

      // The REAL repository: the dummy Supabase URL fails, so the
      // offline cache path is exercised for real.
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentTenantIdProvider.overrideWithValue('tenant-test'),
          userPermissionsProvider
              .overrideWithValue(const {'roles.assign', 'fees.collect'}),
          currentUserProvider.overrideWithValue(const AppUser(
            id: userId,
            email: 't@example.com',
            name: 'ٹیسٹ',
            role: UserRole.madrasaAdmin,
          )),
          delegationRepositoryProvider
              .overrideWithValue(SupabaseDelegationRepository()),
          roleUxRepositoryProvider.overrideWithValue(
              StubRoleUxRepo(users: _users(), catalog: _catalog())),
        ],
        child: const MaterialApp(home: DelegationScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('فیس وصول کرنا'), findsOneWidget);
      expect(find.textContaining('آف لائن — آخری محفوظ فہرست'), findsOneWidget);

      await StorageService.remove(cacheKey);
    });
  });
}
