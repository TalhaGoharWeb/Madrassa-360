/// Phase 8a user-management tests (plain Urdu, no mock data in lib/).
///
/// Unit:   [roleUxErrorMessage] maps technical failures to plain Urdu and
///         never leaks PostgREST/JWT/RLS text.
/// Widget: permission-gated settings entry; user list/search/status;
///         bulk-action confirmation; wizard step headings, defaults,
///         summary and exclusions; last-owner UI refusal.
///
/// Supabase is initialized to a dummy URL; every repository call goes
/// through [StubRoleUxRepository] (a test-only seam, lives in test/).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/data/role_ux_repository.dart';
import 'package:madrasa_360/presentation/screens/common/profile_screen.dart';
import 'package:madrasa_360/presentation/screens/settings/user_management_hub.dart';
import 'package:madrasa_360/presentation/screens/settings/user_wizard_screen.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/role_ux_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────
// Test seam: in-memory repository (test/ only — never shipped)
// ─────────────────────────────────────────────────────────────

class StubRoleUxRepository implements RoleUxRepository {
  StubRoleUxRepository({
    required this.users,
    required this.roles,
    required this.catalog,
    this.classes = const [],
    this.safety,
  });

  List<TenantUser> users;
  List<TenantRoleInfo> roles;
  List<PermissionInfo> catalog;
  List<ClassRef> classes;
  SafetyCheck? safety;

  /// Write log: e.g. 'setActive:<id>:false', 'assignRole:<id>:ustad'.
  final List<String> calls = [];

  @override
  String? get currentUserId => 'self-user';

  @override
  Future<List<TenantUser>> listUsers(String tenantId, {String? search}) async {
    final q = (search ?? '').trim();
    if (q.isEmpty) return users;
    return users
        .where((u) => u.name.contains(q) || u.roleUrdu.contains(q))
        .toList();
  }

  @override
  Future<List<TenantRoleInfo>> listRoles(String tenantId) async => roles;

  @override
  Future<List<PermissionInfo>> permissionCatalog() async => catalog;

  @override
  Future<Map<String, int>> roleMemberCounts(String tenantId) async {
    final counts = <String, int>{};
    for (final u in users) {
      if (u.isActive) counts[u.roleKey] = (counts[u.roleKey] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Future<String> createAuthUser({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    calls.add('createAuthUser:$email');
    return 'new-user-id';
  }

  @override
  Future<void> assignRole({
    required String tenantId,
    required String userId,
    required String roleKey,
  }) async {
    calls.add('assignRole:$userId:$roleKey');
  }

  @override
  Future<void> setUserPermission({
    required String tenantId,
    required String userId,
    required String code,
    required String? effect,
  }) async {
    calls.add('setUserPermission:$userId:$code:$effect');
  }

  @override
  Future<void> syncUserPermissions({
    required String tenantId,
    required String userId,
    required Set<String> templateCodes,
    required Set<String> selectedCodes,
  }) async {
    calls.add('syncUserPermissions:$userId');
  }

  @override
  Future<void> setActive({required String userId, required bool active}) async {
    calls.add('setActive:$userId:$active');
    users = [
      for (final u in users)
        if (u.id == userId)
          TenantUser(
            id: u.id,
            name: u.name,
            email: u.email,
            phone: u.phone,
            roleKey: u.roleKey,
            roleUrdu: u.roleUrdu,
            isActive: active,
            banned: u.banned,
            lastSignInAt: u.lastSignInAt,
            createdAt: u.createdAt,
          )
        else
          u,
    ];
  }

  @override
  Future<void> deleteAuthUser(String userId) async {
    calls.add('deleteAuthUser:$userId');
  }

  @override
  Future<void> writeScopes({
    required String tenantId,
    required String userId,
    required Set<String> codes,
    required ScopeSelection selection,
  }) async {
    calls.add('writeScopes:$userId:${selection.type}');
  }

  @override
  Future<Map<String, String>> userOverrides({
    required String tenantId,
    required String userId,
  }) async =>
      const {};

  @override
  Future<Map<String, ScopeSelection>> userScopes({
    required String tenantId,
    required String userId,
  }) async =>
      const {};

  @override
  Future<List<ClassRef>> listClasses(String tenantId) async => classes;

  @override
  Future<List<StudentRef>> searchStudents(
          String tenantId, String query) async =>
      const [];

  @override
  Future<List<AssignedClassInfo>> assignedClasses({
    required String tenantId,
    required String userId,
  }) async =>
      const [];

  @override
  Future<List<AuditRow>> userActivity({
    required String tenantId,
    required String userId,
  }) async =>
      const [];

  @override
  Future<SafetyCheck?> safetyCheck({
    required String tenantId,
    required String userId,
  }) async =>
      safety;
}

// ─────────────────────────────────────────────────────────────
// Fixtures (plain Urdu labels, as the DB seeds them)
// ─────────────────────────────────────────────────────────────

List<TenantUser> _users() => [
      const TenantUser(
        id: 'u-ahmad',
        name: 'محمد احمد',
        email: 'ahmad@madrassa.com',
        roleKey: 'ustad',
        roleUrdu: 'استاد',
        isActive: true,
        banned: false,
      ),
      const TenantUser(
        id: 'u-bilal',
        name: 'بلال حسین',
        email: 'bilal@madrassa.com',
        roleKey: 'daftar_dar',
        roleUrdu: 'دفتر دار',
        isActive: false,
        banned: false,
      ),
    ];

List<TenantRoleInfo> _roles() => [
      const TenantRoleInfo(
        id: 'r-ustad',
        key: 'ustad',
        displayUrdu: 'استاد',
        displayName: 'Ustad',
        description: 'جماعت کا مدرس',
        permissionCodes: {'attendance.mark', 'results.enter'},
      ),
      const TenantRoleInfo(
        id: 'r-daftar',
        key: 'daftar_dar',
        displayUrdu: 'دفتر دار',
        displayName: 'Daftar Dar',
        description: 'دفتری امور',
        permissionCodes: {'students.view'},
      ),
    ];

List<PermissionInfo> _catalog() => [
      const PermissionInfo(
          id: 'p1',
          code: 'attendance.mark',
          labelUrdu: 'حاضری درج کر سکتا ہے',
          categoryUrdu: 'حاضری',
          sortOrder: 1),
      const PermissionInfo(
          id: 'p2',
          code: 'results.enter',
          labelUrdu: 'نتائج درج کر سکتا ہے',
          categoryUrdu: 'نتائج',
          sortOrder: 2),
      const PermissionInfo(
          id: 'p3',
          code: 'fees.view',
          labelUrdu: 'فیس دیکھ سکتا ہے',
          categoryUrdu: 'مالیات',
          sortOrder: 3),
      const PermissionInfo(
          id: 'p4',
          code: 'fees.collect',
          labelUrdu: 'فیس وصول کر سکتا ہے',
          categoryUrdu: 'مالیات',
          sortOrder: 4),
      const PermissionInfo(
          id: 'p5',
          code: 'users.view',
          labelUrdu: 'صارفین دیکھ سکتا ہے',
          categoryUrdu: 'انتظام',
          sortOrder: 5),
      const PermissionInfo(
          id: 'p6',
          code: 'students.create',
          labelUrdu: 'نیا طالب علم درج کر سکتا ہے',
          categoryUrdu: 'طلبہ',
          sortOrder: 6),
    ];

List<ClassRef> _classes() => [
      const ClassRef(id: 'c1', name: 'جماعت اول'),
      const ClassRef(id: 'c2', name: 'جماعت دوم'),
    ];

ProviderScope _scope({
  required StubRoleUxRepository repo,
  Set<String> permissions = const {'users.view', 'roles.assign'},
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      currentTenantIdProvider.overrideWithValue('tenant-test'),
      userPermissionsProvider.overrideWithValue(permissions),
      roleUxRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(home: child),
  );
}

/// Host page so the wizard can be pushed (and popped) as a real route.
class _WizardHost extends StatelessWidget {
  const _WizardHost({required this.wizard});
  final Widget wizard;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => wizard)),
          child: const Text('open-wizard'),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'widget-test-anon-key',
    );
  });

  // ── unit: plain-Urdu error mapping ─────────────────────────

  group('roleUxErrorMessage', () {
    test('permission denied (RLS/42501) is mapped, jargon hidden', () {
      final msg = roleUxErrorMessage(
          Exception('permission denied for table user_permissions (PG 42501)'));
      expect(msg, 'آپ کے پاس اس عمل کی اجازت نہیں ہے۔');
    });

    test('last owner is explained plainly', () {
      final msg = roleUxErrorMessage(
          Exception('protect_last_owner: last active tenant_owner'));
      expect(msg, contains('واحد مالک'));
      expect(msg, isNot(contains('protect_last_owner')));
    });

    test('duplicate email is explained plainly', () {
      final msg = roleUxErrorMessage(
          Exception('duplicate key value violates unique constraint (email)'));
      expect(msg, contains('ای میل پہلے سے درج ہے'));
    });

    test('network failure is explained plainly', () {
      final msg =
          roleUxErrorMessage(Exception('SocketException: Failed host lookup'));
      expect(msg, contains('انٹرنیٹ سے رابطہ نہیں ہو سکا'));
    });

    test('weak password is explained plainly', () {
      final msg = roleUxErrorMessage(Exception(
          'AuthApiException: Password should be at least 6 characters'));
      expect(msg, contains('کم از کم 6 حروف'));
    });

    test('never leaks technical jargon', () {
      const technical = [
        'permission denied for table x (42501)',
        'JWT expired: invalid or expired token',
        'PostgREST error PGRST116',
        'RLS policy violation on user_permissions',
        'duplicate key value violates unique constraint',
      ];
      const banned = [
        '42501',
        'permission denied',
        'RLS',
        'JWT',
        'PostgREST',
        'duplicate',
        'PGRST',
      ];
      for (final t in technical) {
        final msg = roleUxErrorMessage(Exception(t));
        for (final b in banned) {
          expect(msg, isNot(contains(b)),
              reason: 'jargon "$b" leaked for input "$t"');
        }
      }
    });
  });

  // ── widget: permission-gated settings entry ─────────────────

  group('settings entry', () {
    testWidgets('visible with users.view, hidden without', (tester) async {
      final repo = StubRoleUxRepository(
        users: _users(),
        roles: _roles(),
        catalog: _catalog(),
      );
      await tester.pumpWidget(_scope(
        repo: repo,
        permissions: const {'users.view'},
        child: const ProfileScreen(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('صارفین اور ذمہ داریاں'), findsOneWidget);

      await tester.pumpWidget(_scope(
        repo: repo,
        permissions: const {},
        child: const ProfileScreen(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('صارفین اور ذمہ داریاں'), findsNothing);
    });
  });

  // ── widget: user list / search / status ─────────────────────

  group('user hub', () {
    testWidgets('lists users with Urdu role and active badges', (tester) async {
      final repo = StubRoleUxRepository(
        users: _users(),
        roles: _roles(),
        catalog: _catalog(),
      );
      await tester.pumpWidget(_scope(
        repo: repo,
        child: const UserManagementHubScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('محمد احمد'), findsOneWidget);
      expect(find.text('بلال حسین'), findsOneWidget);
      expect(find.text('فعال'), findsOneWidget);
      expect(find.text('غیر فعال'), findsOneWidget);
      expect(find.text('صارفین'), findsOneWidget);
      expect(find.text('ذمہ داریاں'), findsOneWidget);
    });

    testWidgets('search filters by name', (tester) async {
      final repo = StubRoleUxRepository(
        users: _users(),
        roles: _roles(),
        catalog: _catalog(),
      );
      await tester.pumpWidget(_scope(
        repo: repo,
        child: const UserManagementHubScreen(),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'نام یا ذمہ داری سے تلاش کریں'),
          'احمد');
      await tester.pumpAndSettle();

      expect(find.text('محمد احمد'), findsOneWidget);
      expect(find.text('بلال حسین'), findsNothing);
    });

    testWidgets('bulk deactivate asks for confirmation, then writes',
        (tester) async {
      final repo = StubRoleUxRepository(
        users: _users(),
        roles: _roles(),
        catalog: _catalog(),
      );
      await tester.pumpWidget(_scope(
        repo: repo,
        child: const UserManagementHubScreen(),
      ));
      await tester.pumpAndSettle();

      // enter selection mode and pick the active user
      await tester.tap(find.byIcon(Icons.checklist_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('محمد احمد'));
      await tester.pumpAndSettle();
      expect(find.text('1 منتخب'), findsOneWidget);

      // destructive action must ask first
      await tester.tap(find.byType(PopupMenuButton<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('غیر فعال کریں'));
      await tester.pumpAndSettle();
      expect(find.text('صارفین غیر فعال کریں'), findsOneWidget);

      await tester
          .tap(find.widgetWithText(ElevatedButton, 'جی ہاں، جاری رکھیں'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('setActive:u-ahmad:false'));
      expect(find.text('عمل مکمل ہو گیا'), findsOneWidget);
    });

    testWidgets('last-owner deactivation is refused in plain Urdu',
        (tester) async {
      final repo = StubRoleUxRepository(
        users: _users(),
        roles: _roles(),
        catalog: _catalog(),
        safety: const SafetyCheck(
          ownerCount: 1,
          isLastOwner: true,
          assignHolderCount: 2,
          isLastAssignHolder: false,
          targetRole: 'tenant_owner',
        ),
      );
      await tester.pumpWidget(_scope(
        repo: repo,
        child: const UserManagementHubScreen(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.checklist_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('محمد احمد'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('غیر فعال کریں'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(ElevatedButton, 'جی ہاں، جاری رکھیں'));
      await tester.pumpAndSettle();

      // refused before any write
      expect(repo.calls.where((c) => c.startsWith('setActive')), isEmpty);
      expect(find.textContaining('واحد مالک'), findsOneWidget);
    });

    testWidgets('roles tab: member counts and check/cross permission preview',
        (tester) async {
      final repo = StubRoleUxRepository(
        users: _users(),
        roles: _roles(),
        catalog: _catalog(),
      );
      await tester.pumpWidget(_scope(
        repo: repo,
        child: const UserManagementHubScreen(),
      ));
      await tester.pumpAndSettle();

      // switch to the roles tab
      await tester.tap(find.text('ذمہ داریاں'));
      await tester.pumpAndSettle();

      // real list: Urdu name, description, permission + member counts —
      // no "coming soon" placeholder anywhere
      expect(find.text('استاد'), findsOneWidget);
      expect(find.text('جماعت کا مدرس'), findsOneWidget);
      expect(find.text('2 اختیارات'), findsOneWidget);
      expect(find.text('1 ارکان'), findsOneWidget);
      expect(find.textContaining('جلد'), findsNothing);

      // preview sheet: granted and not-granted across the whole catalog
      await tester.tap(find.text('استاد'));
      await tester.pumpAndSettle();
      expect(find.text('اختیارات کا جائزہ (2/6)'), findsOneWidget);
      expect(find.text('حاضری درج کر سکتا ہے'), findsOneWidget);
      expect(find.text('فیس دیکھ سکتا ہے'), findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is Icon && w.icon == Icons.check_circle_outline),
          findsWidgets);
      expect(
          find.byWidgetPredicate(
              (w) => w is Icon && w.icon == Icons.cancel_outlined),
          findsWidgets);
    });
  });

  // ── widget: wizard ──────────────────────────────────────────

  group('user wizard', () {
    Future<void> pumpWizard(WidgetTester tester, StubRoleUxRepository repo,
        {bool edit = false}) async {
      await tester.pumpWidget(_scope(
        repo: repo,
        child: _WizardHost(
          wizard: edit
              ? UserWizardScreen.edit(user: _users().first)
              : const UserWizardScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-wizard'));
      await tester.pumpAndSettle();
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'آگے'));
      await tester.pumpAndSettle();
    }

    testWidgets('step 0 validates required fields', (tester) async {
      final repo = StubRoleUxRepository(
        users: _users(),
        roles: _roles(),
        catalog: _catalog(),
        classes: _classes(),
      );
      await pumpWizard(tester, repo);
      expect(find.text('بنیادی معلومات'), findsOneWidget);

      await next(tester); // empty form must not advance
      expect(find.text('بنیادی معلومات'), findsOneWidget);
      expect(find.text('نام درج کرنا ضروری ہے۔'), findsOneWidget);
    });

    testWidgets('five steps, teacher defaults, summary and exclusions',
        (tester) async {
      final repo = StubRoleUxRepository(
        users: _users(),
        roles: _roles(),
        catalog: _catalog(),
        classes: _classes(),
      );
      await pumpWizard(tester, repo);

      // step 1: identity
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'کریم بخش');
      await tester.enterText(fields.at(2), 'karim@madrassa.com');
      await tester.enterText(fields.at(3), 'secret123');
      await next(tester);

      // step 2: role — teacher-like default pre-selected
      expect(find.text('یہ صاحب کیا ذمہ داری سنبھالیں گے؟'), findsOneWidget);
      expect(find.text('استاد'), findsOneWidget);
      await next(tester);

      // step 3: permissions — template grants pre-checked
      expect(find.text('ان کو یہ اختیارات حاصل ہوں گے'), findsOneWidget);
      expect(find.text('حاضری درج کر سکتا ہے'), findsOneWidget);
      expect(find.text('مزید اختیارات'), findsOneWidget);
      await tester.tap(find.text('مزید اختیارات'));
      await tester.pumpAndSettle();
      expect(find.text('فیس دیکھ سکتا ہے'), findsOneWidget);
      await next(tester);

      // step 4: scope — teacher-like default is classes
      expect(find.text('یہ اختیارات کن لوگوں پر لاگو ہوں گے؟'), findsOneWidget);
      expect(find.text('صرف میری مقرر کردہ جماعتیں'), findsOneWidget);
      expect(find.text('جماعت اول'), findsOneWidget);
      await tester.tap(find.text('جماعت اول'));
      await tester.pumpAndSettle();
      await next(tester);

      // step 5: summary — grants + honest exclusions
      expect(find.text('اس صارف کو یہ اختیارات حاصل ہوں گے:'), findsOneWidget);
      expect(find.text('حاضری درج کر سکتا ہے'), findsOneWidget);
      expect(find.textContaining('مالی لین دین تک رسائی نہیں'), findsOneWidget);

      // save runs the real write sequence
      await tester.tap(find.widgetWithText(ElevatedButton, 'محفوظ کریں'));
      await tester.pumpAndSettle();
      expect(repo.calls.any((c) => c.startsWith('createAuthUser:')), isTrue);
      expect(repo.calls, contains('assignRole:new-user-id:ustad'));
      expect(repo.calls, contains('syncUserPermissions:new-user-id'));
      expect(
          repo.calls
              .any((c) => c.startsWith('writeScopes:new-user-id:classes')),
          isTrue);
    });
  });
}
