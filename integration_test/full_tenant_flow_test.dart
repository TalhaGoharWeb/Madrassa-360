/// Full tenant flow — end-to-end integration test.
///
/// Flow: login (real [LoginScreen]) → tenant selection (real
/// [TenantPickerScreen]) → create student → mark attendance → collect fee →
/// enter exam result (all through the REAL repository/notifier providers)
/// → offline phase (connectivity override at the sync-engine boundary) →
/// assert the 4 rows land in `sync_queue` with status `pending` → online
/// phase → assert the REAL [SyncEngine] drains the queue → logout.
///
/// Implementation files under test:
///   lib/presentation/screens/auth/login_screen.dart
///   lib/presentation/screens/auth/tenant_picker_screen.dart
///   lib/core/services/tenant_context.dart
///   lib/providers/auth_provider.dart
///   lib/data/repositories/student_repository.dart
///   lib/data/repositories/attendance_repository.dart
///   lib/data/repositories/fee_repository.dart
///   lib/data/repositories/result_repository.dart
///   lib/providers/student_provider.dart / attendance_provider.dart /
///     fee_provider.dart / result_provider.dart
///   lib/core/sync/sync_engine.dart      ← REAL: push/pull/conflict rules
///                                          are NOT mocked
///   lib/core/sync/sync_providers.dart
///   lib/data/local/app_database.dart / database_provider.dart
///
/// Seams — fakes live ONLY at the outermost boundaries:
///   * Supabase HTTP transport: `Supabase.initialize(..., httpClient:
///     MockClient)` intercepts every PostgREST/gotrue call. The engine's
///     push goes through the REAL `sync_apply` RPC path against this fake
///     transport (`{ok:true, new_revision: base+1}`); pull queries return
///     `[]` (no remote changes). Conflict branches are untouched — the
///     fake simply never triggers them.
///   * Connectivity: a method-channel mock for connectivity_plus
///     (`dev.fluttercommunity.plus/connectivity`, `checkConnectivity`)
///     toggles offline (`['none']`) / online (`['wifi']`). This is the
///     documented seam: `SyncEngine._isOnline()` reads it before every
///     push/pull, so the engine's offline gate is exercised for real.
///   * Auth: a fake [AuthRepository] (sign-in only) overrides
///     [authRepositoryProvider]; everything below it — permissions RPC,
///     memberships, tenant context, routing — is real.
///
/// Run on a device/emulator:
///   flutter test integration_test/full_tenant_flow_test.dart
/// (sqlite3 native libs come from sqlite3_flutter_libs.)

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:madrasa_360/core/constants/app_strings.dart';
import 'package:madrasa_360/core/errors/app_exceptions.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/core/sync/sync_providers.dart';
import 'package:madrasa_360/data/local/app_database.dart';
import 'package:madrasa_360/data/local/database_provider.dart';
import 'package:madrasa_360/data/models/attendance_record.dart';
import 'package:madrasa_360/data/models/attendance_status.dart';
import 'package:madrasa_360/data/models/fee.dart';
import 'package:madrasa_360/data/models/result.dart';
import 'package:madrasa_360/data/models/student.dart';
import 'package:madrasa_360/data/repositories/auth_repository.dart';
import 'package:madrasa_360/presentation/screens/auth/login_screen.dart';
import 'package:madrasa_360/presentation/screens/auth/tenant_picker_screen.dart';
import 'package:madrasa_360/presentation/screens/main_screen.dart';
import 'package:madrasa_360/providers/attendance_provider.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/fee_provider.dart';
import 'package:madrasa_360/providers/result_provider.dart';
import 'package:madrasa_360/providers/student_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────
// Fakes (outermost seams only)
// ─────────────────────────────────────────────

/// Controllable sign-in; everything below the repository is real.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository();

  final _events = StreamController<sb.AuthState>.broadcast();
  AppUser? _user;

  @override
  Stream<sb.AuthState> get authStateChanges => _events.stream;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    if (email == 'teacher@test.local' && password == 'secret123') {
      _user = const AppUser(
        id: 'user-teacher-1',
        email: 'teacher@test.local',
        name: 'Test Teacher',
        role: UserRole.teacher,
      );
      _events.add(sb.AuthState(sb.AuthChangeEvent.signedIn, null));
      return _user!;
    }
    throw const AuthenticationException('غلط ای میل یا پاس ورڈ');
  }

  @override
  Future<AppUser?> getSessionUser() async => _user;

  @override
  Future<void> signOut() async {
    _user = null;
    _events.add(sb.AuthState(sb.AuthChangeEvent.signedOut, null));
  }
}

/// Fake Supabase HTTP transport. Handles, in order:
///   POST /rest/v1/rpc/sync_apply      → success (new_revision = base + 1)
///   POST /rest/v1/rpc/get_my_permissions → no permissions
///   GET  /rest/v1/tenant_memberships  → two fixture memberships
///   GET  /rest/v1/platform_admins     → no rows (not a platform admin)
///   GET  /rest/v1/<table>             → [] (pull: no remote changes)
Future<http.Response> _fakeSupabase(http.Request request) async {
  http.Response json(Object? body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
  final path = request.url.path;

  if (path.endsWith('/rpc/sync_apply') && request.method == 'POST') {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final base = (body['p_base_revision'] as num?)?.toInt() ?? 0;
    return json({'ok': true, 'new_revision': base + 1});
  }
  if (path.endsWith('/rpc/get_my_permissions')) {
    return json([]);
  }
  if (path.contains('/rest/v1/tenant_memberships')) {
    return json([
      {
        'tenant_id': 'tenant-1',
        'role': 'teacher',
        'is_active': true,
        'tenants': {
          'name': 'Test Madrasa One',
          'name_urdu': 'ٹیسٹ مدرسہ اول',
          'logo_url': null,
        },
      },
      {
        'tenant_id': 'tenant-2',
        'role': 'teacher',
        'is_active': true,
        'tenants': {
          'name': 'Test Madrasa Two',
          'name_urdu': null,
          'logo_url': null,
        },
      },
    ]);
  }
  if (path.contains('/rest/v1/platform_admins')) {
    return json([]);
  }
  if (path.contains('/rest/v1/')) {
    return json([]); // pull queries: no remote changes
  }
  return json({'message': 'not mocked: $path'}, 404);
}

// ─────────────────────────────────────────────
// Connectivity seam (the sync-engine boundary)
// ─────────────────────────────────────────────

const _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

/// Flipped by the test to simulate offline/online. Read by the
/// `checkConnectivity` mock that [SyncEngine._isOnline] consults.
bool _online = true;

void _installConnectivityMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivityChannel, (call) async {
    if (call.method == 'checkConnectivity') {
      return _online ? ['wifi'] : ['none'];
    }
    return null;
  });
}

// ─────────────────────────────────────────────
// The flow
// ─────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeAuthRepository fakeAuth;

  setUpAll(() async {
    _installConnectivityMock();
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'integration-test-anon-key',
      httpClient: MockClient(_fakeSupabase),
    );
    db = AppDatabase(NativeDatabase.memory());
    fakeAuth = _FakeAuthRepository();
  });

  tearDownAll(() async {
    await db.close();
  });

  Future<List<Map<String, dynamic>>> queueRows(
      String tenantId, String status) async {
    final rows = await db.customSelect(
      'SELECT entity, sync_status FROM sync_queue '
      'WHERE tenant_id = ? AND sync_status = ?',
      variables: [
        Variable.withString(tenantId),
        Variable.withString(status),
      ],
    ).get();
    return rows.map((r) => r.data).toList();
  }

  testWidgets('full tenant flow: login → data → offline queue → drain → logout',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // ── 1. Login via the real screen ──────────────────────────
    await tester.enterText(
      find.widgetWithText(TextFormField, 'اپنا ای میل درج کریں'),
      'teacher@test.local',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'اپنا پاس ورڈ درج کریں'),
      'secret123',
    );
    await tester.tap(
      find.widgetWithText(ElevatedButton, AppStrings.loginButton),
    );
    await tester.pumpAndSettle();

    expect(container.read(authProvider).isAuthenticated, isTrue);
    expect(container.read(authProvider).route, AuthRoute.tenantPicker);
    expect(find.byType(TenantPickerScreen), findsOneWidget);

    // ── 2. Tenant selection via the real screen ───────────────
    await tester.tap(find.text('Test Madrasa One'));
    await tester.pumpAndSettle();

    expect(container.read(activeTenantIdProvider), 'tenant-1');
    expect(find.byType(MainScreen), findsOneWidget);
    final tenantId = container.read(currentTenantIdProvider);
    expect(tenantId, 'tenant-1');

    // ── 3. Go offline at the sync-engine boundary ─────────────
    _online = false;

    // ── 4. Local-first writes through the real providers ──────
    final student =
        await container.read(studentRepositoryProvider).upsertStudent(
              const Student(
                id: 'student-1',
                tenantId: 'tenant-1',
                rollNo: '101',
                name: 'Ali Raza',
                fatherName: 'Raza Ahmed',
                darjaId: 'darja-1',
                darjaName: 'Darja 1',
                classId: 'class-1',
                className: 'Class 1',
              ),
              tenantId: tenantId!,
            );

    await container
        .read(attendanceRecordNotifierProvider.notifier)
        .save([
      AttendanceRecord(
        tenantId: tenantId,
        studentId: student.id,
        studentName: student.name,
        studentRollNo: student.rollNo,
        classId: 'class-1',
        teacherId: 'user-teacher-1',
        date: '2026-09-25',
        status: AttendanceStatus.present,
      ),
    ]);

    await container.read(feeRepositoryProvider).upsertFee(
          const Fee(
            id: 'fee-1',
            tenantId: 'tenant-1',
            studentId: 'student-1',
            studentName: 'Ali Raza',
            studentClass: 'Class 1',
            month: '2026-09',
            amountDue: 1000.0,
            amountPaid: 1000.0,
            dueDate: '2026-09-30',
            status: FeeStatus.paid,
          ),
          tenantId: tenantId,
        );

    await container.read(resultRepositoryProvider).upsertResult(
          const SubjectResult(
            id: 'result-1',
            tenantId: 'tenant-1',
            examId: 'exam-1',
            studentId: 'student-1',
            subject: 'Quran',
            marksObtained: 85.0,
            totalMarks: 100.0,
          ),
          tenantId: tenantId,
        );

    // Local-first: rows are readable locally even while offline.
    final localStudents = await container
        .read(studentRepositoryProvider)
        .getAllStudents(tenantId: tenantId);
    expect(localStudents.map((s) => s.id), contains('student-1'));

    // ── 5. Offline → all four ops sit in sync_queue as pending ─
    final pending = await queueRows(tenantId, 'pending');
    expect(
      pending.map((r) => r['entity']).toSet(),
      {'students', 'attendance', 'fees', 'results'},
    );
    expect(pending, hasLength(4));

    // ── 6. Go online → the REAL engine drains the queue ────────
    _online = true;
    final engine = container.read(syncEngineProvider);
    expect(engine, isNotNull);
    await engine!.syncNow();

    expect(await queueRows(tenantId, 'pending'), isEmpty);
    final done = await queueRows(tenantId, 'done');
    expect(done.map((r) => r['entity']).toSet(),
        {'students', 'attendance', 'fees', 'results'});
    expect(done, hasLength(4));

    // ── 7. Logout ─────────────────────────────────────────────
    await container.read(authProvider.notifier).logout();
    await tester.pumpAndSettle();

    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(container.read(authProvider).route, AuthRoute.login);
    expect(container.read(activeTenantIdProvider), isNull);
  });
}
