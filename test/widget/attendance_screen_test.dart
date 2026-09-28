/// Widget tests for the teacher attendance screen.
///
/// Implementation files under test:
///   lib/presentation/screens/teacher/attendance_screen.dart
///   lib/providers/attendance_provider.dart    (classAttendanceProvider,
///                                             attendanceRecordNotifierProvider)
///   lib/providers/teacher_portal_provider.dart (teacherAssignedClassesProvider)
///   lib/core/services/tenant_context.dart     (currentTenantIdProvider)
///   lib/data/models/attendance_record.dart / attendance_status.dart
///
/// Fakes: [FakeAuthRepository] (auth), [FakeAttendanceRepository] below
/// (records the save call); roster/assignment data come from provider
/// overrides so the real widget tree, merge logic (_effective) and the
/// real [AttendanceRecordNotifier] are exercised.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:madrasa_360/core/constants/app_strings.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/core/sync/sync_providers.dart';
import 'package:madrasa_360/data/models/attendance_record.dart';
import 'package:madrasa_360/data/models/attendance_status.dart';
import 'package:madrasa_360/data/repositories/attendance_repository.dart';
import 'package:madrasa_360/presentation/screens/teacher/attendance_screen.dart';
import 'package:madrasa_360/providers/attendance_provider.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/teacher_portal_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth_repository.dart';

/// Records the save call; roster reads come from the
/// [classAttendanceProvider] override, not from here.
class FakeAttendanceRepository implements IAttendanceRepository {
  List<AttendanceRecord>? saved;

  @override
  Future<List<AttendanceRecord>> getClassAttendance({
    required String classId,
    required DateTime date,
    required String tenantId,
  }) async =>
      [];

  @override
  Future<void> saveAttendance(List<AttendanceRecord> records) async {
    saved = records;
  }

  @override
  Stream<List<AttendanceRecord>> subscribeToAttendance({
    required String classId,
    required DateTime date,
    required String tenantId,
  }) =>
      const Stream.empty();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ur');
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'widget-test-anon-key',
    );
  });

  late FakeAuthRepository fakeAuth;
  late FakeAttendanceRepository fakeAttendance;

  List<AttendanceRecord> roster() => [
        AttendanceRecord(
          id: 'att-1',
          tenantId: 't1',
          studentId: 's1',
          studentName: 'Ali Raza',
          studentRollNo: '101',
          classId: 'c1',
          teacherId: 'user-teacher-1',
          date: '2026-09-25',
          status: AttendanceStatus.present,
        ),
        AttendanceRecord(
          id: 'att-2',
          tenantId: 't1',
          studentId: 's2',
          studentName: 'Bilal Ahmed',
          studentRollNo: '102',
          classId: 'c1',
          teacherId: 'user-teacher-1',
          date: '2026-09-25',
          status: AttendanceStatus.absent,
        ),
      ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeAuth = FakeAuthRepository();
    fakeAttendance = FakeAttendanceRepository();
  });

  tearDown(() => fakeAuth.dispose());

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    required List<AssignedClass> classes,
    bool signedIn = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        currentTenantIdProvider.overrideWithValue('t1'),
        if (signedIn) currentUserProvider.overrideWithValue(fakeTeacherUser()),
        teacherAssignedClassesProvider.overrideWith(
          (ref) async => classes,
        ),
        classAttendanceProvider.overrideWith(
          (ref, AttendanceParams params) async => roster(),
        ),
        attendanceRepositoryProvider.overrideWithValue(fakeAttendance),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value(0)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AttendanceScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  const classOne = AssignedClass(id: 'c1', name: 'Class 1');

  group('AttendanceScreen bulk actions', () {
    testWidgets('mark-all-present flips every tile to present', (tester) async {
      await pumpScreen(tester, classes: const [classOne]);

      // Baseline: one present + one absent.
      expect(find.text('حاضر'), findsNWidgets(2)); // stat label + 1 badge
      expect(find.text('غیر حاضر'), findsNWidgets(2)); // stat label + 1 badge

      await tester.tap(find.text(AppStrings.markAllPresent));
      await tester.pump();

      // Both badges now present (plus the ever-present stat labels).
      expect(find.text('حاضر'), findsNWidgets(3));
      expect(find.text('غیر حاضر'), findsNWidgets(1));
    });

    testWidgets('mark-all-absent flips every tile to absent', (tester) async {
      await pumpScreen(tester, classes: const [classOne]);

      await tester.tap(find.text(AppStrings.markAllAbsent));
      await tester.pump();

      expect(find.text('غیر حاضر'), findsNWidgets(3));
      expect(find.text('حاضر'), findsNWidgets(1));
    });

    testWidgets('save stores the effective records and shows confirmation',
        (tester) async {
      final container = await pumpScreen(
        tester,
        classes: const [classOne],
        signedIn: true,
      );

      await tester.tap(find.text(AppStrings.markAllAbsent));
      await tester.pump();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // The real notifier merged the bulk edit and called the repository.
      expect(fakeAttendance.saved, isNotNull);
      expect(fakeAttendance.saved, hasLength(2));
      expect(
        fakeAttendance.saved!.map((r) => r.status).toSet(),
        {AttendanceStatus.absent},
      );
      expect(container.read(attendanceRecordNotifierProvider),
          isA<AsyncData<void>>());
      expect(find.text(AppStrings.attendanceSaved), findsOneWidget);
    });
  });

  group('AttendanceScreen fail-closed', () {
    testWidgets('save FAB is disabled when no class is assigned',
        (tester) async {
      await pumpScreen(tester, classes: const []);

      // Fail-closed placeholder, no roster, no save possible.
      expect(find.text(AppStrings.noClassAssigned), findsOneWidget);
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNull);
      expect(fakeAttendance.saved, isNull);
    });
  });
}
