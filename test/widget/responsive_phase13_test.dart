/// Phase 13 — responsiveness validation (phone / tablet / desktop).
///
/// Pumps the Phase 8b (delegation), Phase 9 (scope manager) and audit-log
/// screens plus the profile screen (new tiles) at 360x740, 768x1024 and
/// 1280x800, forces RTL like the real app (`main.dart` wraps everything
/// in `Directionality(rtl)`), and fails on any layout overflow or
/// FlutterError. Test seams: [dtest.StubDelegationRepository] /
/// [dtest.StubRoleUxRepo] and [stest.StubScopeManagerRepository] from the
/// Phase 8b/9 widget tests; Supabase is initialized to a dummy URL.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/data/delegation_repository.dart';
import 'package:madrasa_360/data/role_ux_repository.dart';
import 'package:madrasa_360/data/scope_manager_repository.dart';
import 'package:madrasa_360/presentation/screens/common/profile_screen.dart';
import 'package:madrasa_360/presentation/screens/master_admin/audit_logs_screen.dart';
import 'package:madrasa_360/presentation/screens/settings/delegation_create_screen.dart';
import 'package:madrasa_360/presentation/screens/settings/delegation_screen.dart';
import 'package:madrasa_360/presentation/screens/settings/scope_manager_screen.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/delegation_provider.dart';
import 'package:madrasa_360/providers/role_ux_provider.dart';
import 'package:madrasa_360/providers/scope_manager_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'delegation_test.dart' as dtest;
import 'scope_manager_screen_test.dart' as stest;

// ─────────────────────────────────────────────────────────────
// Fixtures (long Urdu strings to stress narrow widths)
// ─────────────────────────────────────────────────────────────

const _selfUser = AppUser(
  id: 'u-self',
  email: 'mohtamim@madrassa.com',
  name: 'مہتمم صاحب',
  role: UserRole.madrasaAdmin,
);

const _users = [
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
    name: 'حافظ محمد احمد رضا قادری صاحب',
    email: 'ahmed@madrassa.com',
    roleKey: 'ustad',
    roleUrdu: 'استاد',
    isActive: true,
    banned: false,
  ),
  TenantUser(
    id: 'u3',
    name: 'مولانا مفتی بلال احمد صدیقی',
    email: 'bilal@madrassa.com',
    roleKey: 'nazim_taleem',
    roleUrdu: 'ناظم تعلیمات',
    isActive: true,
    banned: false,
  ),
];

const _catalog = [
  PermissionInfo(
    id: 'p1',
    code: 'fees.collect',
    labelUrdu: 'فیس وصول کرنا اور رسیدیں جاری کرنا',
    categoryUrdu: 'فیس کا انتظام',
    sortOrder: 1,
  ),
  PermissionInfo(
    id: 'p2',
    code: 'fees.edit',
    labelUrdu: 'فیس کے ریکارڈ میں ترمیم اور چھوٹ دینا',
    categoryUrdu: 'فیس کا انتظام',
    sortOrder: 2,
  ),
  PermissionInfo(
    id: 'p3',
    code: 'attendance.mark',
    labelUrdu: 'طلبہ کی روزانہ حاضری لگانا اور ترمیم کرنا',
    categoryUrdu: 'حاضری کا نظام',
    sortOrder: 3,
  ),
  PermissionInfo(
    id: 'p4',
    code: 'results.enter',
    labelUrdu: 'امتحانی نتائج درج کرنا اور شائع کرنا',
    categoryUrdu: 'نتائج کا نظام',
    sortOrder: 4,
  ),
];

const _classes = [
  ClassRef(id: 'c1', name: 'جماعت اول الف — ناظرہ قرآن کریم'),
  ClassRef(id: 'c2', name: 'جماعت دوم ب — حفظ قرآن کریم'),
  ClassRef(id: 'c3', name: 'جماعت سوم — اردو و دینیات'),
  ClassRef(id: 'c4', name: 'جماعت چہارم — عربی صرف و نحو'),
];

List<DelegationInfo> _delegations() => [
      DelegationInfo(
        id: 'd1',
        tenantId: 'tenant-test',
        delegatorId: 'u-self',
        delegateeId: 'u2',
        permissionId: 'p1',
        permissionCode: 'fees.collect',
        scopeType: 'all',
        startsAt: DateTime.utc(2026, 9, 1),
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        createdAt: DateTime.utc(2026, 9, 20),
      ),
      DelegationInfo(
        id: 'd2',
        tenantId: 'tenant-test',
        delegatorId: 'u-self',
        delegateeId: 'u3',
        permissionId: 'p3',
        permissionCode: 'attendance.mark',
        scopeType: 'classes',
        startsAt: DateTime.utc(2026, 9, 1),
        createdAt: DateTime.utc(2026, 9, 20),
      ),
    ];

List<ScopeAssignment> _assignments() => [
      ScopeAssignment(
        id: 's1',
        tenantId: 'tenant-test',
        userId: 'u2',
        userName: 'حافظ محمد احمد رضا قادری صاحب',
        userRoleUrdu: 'استاد',
        permissionCode: 'attendance.mark',
        permissionLabelUrdu: 'طلبہ کی روزانہ حاضری لگانا اور ترمیم کرنا',
        scopeType: 'classes',
        classIds: const {'c1', 'c2'},
        classNames: const {
          'c1': 'جماعت اول الف — ناظرہ قرآن کریم',
          'c2': 'جماعت دوم ب — حفظ قرآن کریم',
        },
        createdAt: DateTime.utc(2026, 9, 1),
      ),
      ScopeAssignment(
        id: 's2',
        tenantId: 'tenant-test',
        userId: 'u3',
        userName: 'مولانا مفتی بلال احمد صدیقی',
        userRoleUrdu: 'ناظم تعلیمات',
        permissionCode: 'results.enter',
        permissionLabelUrdu: 'امتحانی نتائج درج کرنا اور شائع کرنا',
        scopeType: 'all',
        createdAt: DateTime.utc(2026, 9, 2),
      ),
    ];

/// RoleUxRepository seam: the Phase 8b stub plus class/student pickers and
/// an empty granter-scope map (fail-closed notice still renders).
class _RoleUxRepo extends dtest.StubRoleUxRepo {
  _RoleUxRepo({required super.users, required super.catalog});

  @override
  Future<List<ClassRef>> listClasses(String tenantId) async => _classes;

  @override
  Future<List<StudentRef>> searchStudents(
          String tenantId, String query) async =>
      const [];

  @override
  Future<Map<String, ScopeSelection>> userScopes(
          {required String tenantId, required String userId}) async =>
      const {};
}

// ─────────────────────────────────────────────────────────────
// Harness
// ─────────────────────────────────────────────────────────────

const _sizes = <String, Size>{
  'phone 360x740': Size(360, 740),
  'tablet 768x1024': Size(768, 1024),
  'desktop 1280x800': Size(1280, 800),
};

/// Mirrors the app shell: forced RTL like `main.dart`.
Widget _rtlApp(Widget child) => MaterialApp(
      home: child,
      builder: (context, c) => Directionality(
        textDirection: TextDirection.rtl,
        child: c!,
      ),
    );

ProviderScope _delegationScope({
  required dtest.StubDelegationRepository repo,
  required _RoleUxRepo roleRepo,
  required Widget child,
}) =>
    ProviderScope(
      overrides: [
        currentTenantIdProvider.overrideWithValue('tenant-test'),
        userPermissionsProvider.overrideWithValue(const {
          'roles.assign',
          'users.view',
          'fees.collect',
          'fees.edit',
          'attendance.mark',
          'results.enter',
        }),
        currentUserProvider.overrideWithValue(_selfUser),
        delegationRepositoryProvider.overrideWithValue(repo),
        roleUxRepositoryProvider.overrideWithValue(roleRepo),
      ],
      child: _rtlApp(child),
    );

ProviderScope _scopeDirScope({
  required stest.StubScopeManagerRepository repo,
  required Widget child,
}) =>
    ProviderScope(
      overrides: [
        currentTenantIdProvider.overrideWithValue('tenant-test'),
        userPermissionsProvider.overrideWithValue(const {
          'roles.assign',
          'users.view',
        }),
        currentUserProvider.overrideWithValue(_selfUser),
        scopeManagerRepositoryProvider.overrideWithValue(repo),
      ],
      child: _rtlApp(child),
    );

ProviderScope _scopeEditorScope({
  required _RoleUxRepo roleRepo,
  required Widget child,
}) =>
    ProviderScope(
      overrides: [
        currentTenantIdProvider.overrideWithValue('tenant-test'),
        userPermissionsProvider.overrideWithValue(const {
          'roles.assign',
          'users.view',
        }),
        currentUserProvider.overrideWithValue(_selfUser),
        roleUxRepositoryProvider.overrideWithValue(roleRepo),
        scopeManagerRepositoryProvider
            .overrideWithValue(stest.StubScopeManagerRepository()),
      ],
      child: _rtlApp(child),
    );

ProviderScope _profileScope({required Widget child}) => ProviderScope(
      overrides: [
        currentTenantIdProvider.overrideWithValue('tenant-test'),
        userPermissionsProvider.overrideWithValue(const {
          'roles.assign',
          'users.view',
        }),
        currentUserProvider.overrideWithValue(_selfUser),
        activeRoleKeysProvider.overrideWithValue(const ['mohtamim']),
        tenantBrandingProvider
            .overrideWith((ref) => Future.value(TenantBranding.fallback())),
      ],
      child: _rtlApp(child),
    );

/// Pumps [app] at [size], runs [interact], then fails on any thrown
/// exception or reported layout overflow. Also asserts the screen subtree
/// sits under an RTL [Directionality].
Future<void> _pumpResponsive(
  WidgetTester tester, {
  required Size size,
  required Widget app,
  required Type screenType,
  Future<void> Function()? interact,
}) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details);
    previous?.call(details);
  };
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  try {
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await interact?.call();
    await tester.pumpAndSettle();
  } finally {
    FlutterError.onError = previous;
  }
  final thrown = tester.takeException();
  expect(thrown, isNull,
      reason: '$screenType threw at ${size.width}x${size.height}: $thrown');
  final overflows =
      errors.where((e) => e.toString().contains('overflowed')).toList();
  expect(overflows, isEmpty,
      reason: '$screenType overflowed at ${size.width}x${size.height}: '
          '${overflows.map((e) => e.summary).join(' | ')}');
  // RTL holds: the nearest Directionality above the screen is RTL.
  final dirs = find
      .ancestor(
        of: find.byType(screenType),
        matching: find.byType(Directionality),
      )
      .evaluate();
  expect(dirs, isNotEmpty, reason: 'no Directionality above $screenType');
  expect((dirs.first.widget as Directionality).textDirection, TextDirection.rtl,
      reason: '$screenType is not under RTL directionality');
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'widget-test-anon-key',
    );
  });

  group('DelegationScreen responsive', () {
    for (final entry in _sizes.entries) {
      testWidgets('no overflow at ${entry.key}', (tester) async {
        final repo =
            dtest.StubDelegationRepository(delegations: _delegations());
        final roleRepo = _RoleUxRepo(users: _users, catalog: _catalog);
        await _pumpResponsive(
          tester,
          size: entry.value,
          app: _delegationScope(
              repo: repo, roleRepo: roleRepo, child: const DelegationScreen()),
          screenType: DelegationScreen,
        );
        expect(find.text('حافظ محمد احمد رضا قادری صاحب'), findsWidgets);
      });
    }

    testWidgets('revoke confirm dialog fits at 360px', (tester) async {
      final repo = dtest.StubDelegationRepository(delegations: _delegations());
      final roleRepo = _RoleUxRepo(users: _users, catalog: _catalog);
      await _pumpResponsive(
        tester,
        size: const Size(360, 740),
        app: _delegationScope(
            repo: repo, roleRepo: roleRepo, child: const DelegationScreen()),
        screenType: DelegationScreen,
        interact: () async {
          await tester.tap(find.byIcon(Icons.undo_outlined).first);
          await tester.pumpAndSettle();
          expect(find.text('اختیار واپس لیں'), findsWidgets);
          // Cancel — no state change, just layout proof.
          await tester.tap(find.text('منسوخ'));
          await tester.pumpAndSettle();
        },
      );
    });
  });

  group('DelegationCreateScreen responsive', () {
    for (final entry in _sizes.entries) {
      testWidgets('no overflow at ${entry.key}', (tester) async {
        final repo = dtest.StubDelegationRepository();
        final roleRepo = _RoleUxRepo(users: _users, catalog: _catalog);
        await _pumpResponsive(
          tester,
          size: entry.value,
          app: _delegationScope(
              repo: repo,
              roleRepo: roleRepo,
              child: const DelegationCreateScreen()),
          screenType: DelegationCreateScreen,
        );
        expect(find.text('اختیارات منتخب کریں'), findsOneWidget);
      });
    }

    testWidgets('user picker bottom sheet fits at 360px', (tester) async {
      final repo = dtest.StubDelegationRepository();
      final roleRepo = _RoleUxRepo(users: _users, catalog: _catalog);
      await _pumpResponsive(
        tester,
        size: const Size(360, 740),
        app: _delegationScope(
            repo: repo,
            roleRepo: roleRepo,
            child: const DelegationCreateScreen()),
        screenType: DelegationCreateScreen,
        interact: () async {
          await tester.tap(find.text('صارف منتخب کریں…'));
          await tester.pumpAndSettle();
          expect(find.text('نام سے تلاش کریں'), findsOneWidget);
          await tester.tap(find.text('حافظ محمد احمد رضا قادری صاحب'));
          await tester.pumpAndSettle();
        },
      );
    });
  });

  group('ScopeManagerScreen responsive', () {
    for (final entry in _sizes.entries) {
      testWidgets('no overflow at ${entry.key}', (tester) async {
        // fromCache: true exercises the stale/offline banner too.
        final repo = stest.StubScopeManagerRepository(
          items: _assignments(),
          fromCache: true,
          fetchedAt: DateTime.utc(2026, 9, 25, 8),
        );
        await _pumpResponsive(
          tester,
          size: entry.value,
          app: _scopeDirScope(repo: repo, child: const ScopeManagerScreen()),
          screenType: ScopeManagerScreen,
        );
        expect(find.text('حافظ محمد احمد رضا قادری صاحب'), findsOneWidget);
      });
    }
  });

  group('ScopeEditorScreen responsive', () {
    for (final entry in _sizes.entries) {
      testWidgets('edit flow (fixed user) no overflow at ${entry.key}',
          (tester) async {
        final roleRepo = _RoleUxRepo(users: _users, catalog: _catalog);
        await _pumpResponsive(
          tester,
          size: entry.value,
          app: _scopeEditorScope(
            roleRepo: roleRepo,
            child: ScopeEditorScreen(
              initialUser: _users[1],
              initialCodes: const {'attendance.mark'},
              initialSelection: const ScopeSelection(
                type: 'classes',
                classIds: {'c1', 'c2'},
              ),
            ),
          ),
          screenType: ScopeEditorScreen,
          // The scope-type section sits below the fold: scroll it into
          // view so the class chips actually build (and are measured).
          interact: () async {
            await tester.scrollUntilVisible(
              find.text('دائرہ کار منتخب کریں'),
              400,
            );
            await tester.pumpAndSettle();
          },
        );
        expect(find.text('جماعت اول الف — ناظرہ قرآن کریم'), findsOneWidget);
      });

      testWidgets('create flow (user picker) no overflow at ${entry.key}',
          (tester) async {
        final roleRepo = _RoleUxRepo(users: _users, catalog: _catalog);
        await _pumpResponsive(
          tester,
          size: entry.value,
          app: _scopeEditorScope(
              roleRepo: roleRepo, child: const ScopeEditorScreen()),
          screenType: ScopeEditorScreen,
        );
        expect(find.text('صارف منتخب کریں'), findsOneWidget);
      });

      testWidgets('class picker section fits at ${entry.key}', (tester) async {
        final roleRepo = _RoleUxRepo(users: _users, catalog: _catalog);
        await _pumpResponsive(
          tester,
          size: entry.value,
          app: _scopeEditorScope(
            roleRepo: roleRepo,
            child: ScopeEditorScreen(initialUser: _users[1]),
          ),
          screenType: ScopeEditorScreen,
          interact: () async {
            // Scroll the scope-type options into view, then switch scope
            // type to 'classes' to reveal the class chips (tap the whole
            // option card — more reliable than the small radio target).
            final classesRadio = find.byWidgetPredicate(
              (w) => w is Radio<String> && w.value == 'classes',
            );
            final classesCard = find.ancestor(
              of: classesRadio,
              matching: find.byType(InkWell),
            );
            await tester.scrollUntilVisible(classesCard, 400);
            // Let the scroll motion fully settle: a tap issued while the
            // list is still moving loses the gesture arena to scrolling.
            await tester.pumpAndSettle();
            await tester.tap(classesCard);
            await tester.pumpAndSettle();
            expect(
                find.text('جماعت اول الف — ناظرہ قرآن کریم'), findsOneWidget);
          },
        );
      });
    }
  });

  group('AuditLogsScreen responsive', () {
    for (final entry in _sizes.entries) {
      testWidgets('no overflow at ${entry.key}', (tester) async {
        // Supabase points at a dummy URL: every query fails into the
        // honest error/empty states — the filters bar always renders.
        await _pumpResponsive(
          tester,
          size: entry.value,
          app: _rtlApp(const Scaffold(body: AuditLogsScreen())),
          screenType: AuditLogsScreen,
        );
        expect(find.text('از تاریخ'), findsOneWidget);
      });
    }
  });

  group('ProfileScreen responsive (with new tiles)', () {
    for (final entry in _sizes.entries) {
      testWidgets('no overflow at ${entry.key}', (tester) async {
        await _pumpResponsive(
          tester,
          size: entry.value,
          app: _profileScope(child: const ProfileScreen()),
          screenType: ProfileScreen,
        );
        // The new Phase 8b tile is gated by `roles.assign` — present here.
        expect(find.text('اختیار سونپنا'), findsOneWidget);
      });
    }
  });
}
