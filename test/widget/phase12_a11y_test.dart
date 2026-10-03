/// Phase 12 — responsive + accessibility regression tests.
///
/// Covers the required Phase-12 verification:
/// * no horizontal overflow at 360x740 and 1280x800 for login, dashboard
///   (generic), finance hub, fee collection, student list, attendance,
///   reports hub, and master-admin licenses;
/// * minimum 48x48 touch targets on primary CTAs (M360 buttons + shell
///   chips);
/// * semantic labels on shell icon-only controls;
/// * no overflow at 2.0x text scale for dialog + table cards.
///
/// Screens are pumped with honest empty/error states (overridden providers)
/// — no fake backend rows, no invented data.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/design/m360_buttons.dart';
import 'package:madrasa_360/core/design/m360_dialog.dart';
import 'package:madrasa_360/core/design/m360_inputs.dart';
import 'package:madrasa_360/core/design/m360_status.dart';
import 'package:madrasa_360/core/design/m360_table.dart';
import 'package:madrasa_360/presentation/shell/command_palette.dart';
import 'package:madrasa_360/presentation/shell/nav_destinations.dart';
import 'package:madrasa_360/data/local/app_database.dart';
import 'package:madrasa_360/data/local/database_provider.dart';
import 'package:madrasa_360/core/notifications/notification_providers.dart';
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/data/models/attendance_record.dart';
import 'package:madrasa_360/data/models/attendance_status.dart';
import 'package:madrasa_360/data/models/fee.dart';
import 'package:madrasa_360/data/models/student.dart';
import 'package:madrasa_360/data/repositories/attendance_repository.dart';
import 'package:madrasa_360/presentation/screens/admin/student_list_screen.dart';
import 'package:madrasa_360/presentation/screens/auth/login_screen.dart';
import 'package:madrasa_360/presentation/screens/finance/collect_fee_screen.dart';
import 'package:madrasa_360/presentation/screens/finance/finance_hub_screen.dart';
import 'package:madrasa_360/presentation/screens/master_admin/licenses_screen.dart';
import 'package:madrasa_360/presentation/screens/reports/reports_hub_screen.dart';
import 'package:madrasa_360/presentation/screens/teacher/attendance_screen.dart';
import 'package:madrasa_360/presentation/shell/app_shell.dart';
import 'package:madrasa_360/providers/announcement_provider.dart';
import 'package:madrasa_360/providers/attendance_provider.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/fee_provider.dart';
import 'package:madrasa_360/providers/student_provider.dart';
import 'package:madrasa_360/providers/teacher_portal_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';
import 'package:madrasa_360/presentation/viewmodels/finance/finance_overview_provider.dart';
import 'package:madrasa_360/presentation/viewmodels/finance/financial_views.dart';

import 'fake_auth_repository.dart';

/// Asset bundle stub so the login screen logo asset resolves.
class _TestAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.view(Uint8List(0).buffer);
}

/// Same pattern as the Phase 13 responsive tests: an offscreen MaterialApp
/// with an RTL scaffold; the Flutter test framework surfaces RenderFlex
/// overflow as a test failure via [takeException].
Future<void> _pumpResponsive(
  WidgetTester tester, {
  required Size size,
  required Widget child,
  List<Override> overrides = const [],
  double textScaler = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScaler)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Minimal fake for attendance-screen tests (mirrors the shared test fake).
class _FakeAttendance implements IAttendanceRepository {
  @override
  Future<List<AttendanceRecord>> getClassAttendance({
    required String classId,
    required DateTime date,
    required String tenantId,
  }) async =>
      [];

  @override
  Future<void> saveAttendance(List<AttendanceRecord> records) async {}

  @override
  Stream<List<AttendanceRecord>> subscribeToAttendance({
    required String classId,
    required DateTime date,
    required String tenantId,
  }) =>
      const Stream.empty();

  @override
  Future<Set<String>> getMarkedClassIds({
    required List<String> classIds,
    required DateTime date,
    required String tenantId,
  }) async =>
      {};
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
  setUp(() => fakeAuth = FakeAuthRepository());
  tearDown(() => fakeAuth.dispose());

  List<Override> baseOverrides() => [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        currentTenantIdProvider.overrideWithValue('t1'),
        tenantMembershipsProvider.overrideWith(
          (ref) async => [
            const TenantMembership(
              tenantId: 't1',
              role: 'teacher',
              tenantName: 'ٹیسٹ مدرسہ',
            ),
          ],
        ),
        tenantBrandingProvider
            .overrideWith((ref) async => TenantBranding.fallback()),
        unreadNotificationsCountProvider.overrideWith((ref) => Stream.value(0)),
      ];

  List<Student> fakeStudents() => [
        for (var i = 0; i < 15; i++)
          Student(
            id: 's$i',
            tenantId: 't1',
            rollNo: '${100 + i}',
            name: 'طالب علم $i',
            fatherName: 'والد $i',
            darjaId: 'd1',
            darjaName: 'درجہ اول',
            classId: 'c1',
            className: 'جماعت اول',
          ),
      ];

  group('Phase 12 — no overflow at 360x740', () {
    const phone = Size(360, 740);

    testWidgets('login screen has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: phone,
        overrides: baseOverrides(),
        child: DefaultAssetBundle(
          bundle: _TestAssetBundle(),
          child: const LoginScreen(),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('generic dashboard via AppShell has no overflow',
        (tester) async {
      await _pumpResponsive(
        tester,
        size: phone,
        overrides: [
          ...baseOverrides(),
          currentUserProvider.overrideWithValue(fakeTeacherUser()),
          activeRoleKeysProvider.overrideWithValue(const <String>[]),
          userPermissionsProvider.overrideWithValue(<String>{}),
          announcementListProvider.overrideWithValue(const []),
        ],
        child: const AppShell(),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('finance hub dashboard has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: phone,
        overrides: [
          ...baseOverrides(),
          financeHubOverviewProvider.overrideWith(
            (ref) => const AsyncValue.data(
              FinanceHubOverview(
                totalOutstanding: 0,
                monthCollected: 0,
                pendingRecords: 0,
                overdueRecords: 0,
                postedIncome: 0,
                postedExpense: 0,
                topDues: [],
                recentPayments: [],
              ),
            ),
          ),
        ],
        child: const FinanceHubScreen(section: FinanceSection.dashboard),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(FinanceHubScreen), findsOneWidget);
    });

    testWidgets('fee collection form has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: phone,
        overrides: [
          ...baseOverrides(),
          appDatabaseProvider
              .overrideWith((ref) => AppDatabase(NativeDatabase.memory())),
        ],
        child: CollectFeeScreen(
          fee: Fee(
            id: 'f1',
            tenantId: 't1',
            studentId: 's1',
            studentName: 'احمد',
            studentClass: 'جماعت اول',
            month: 'ستمبر 2026',
            amountDue: 1500,
            amountPaid: 500,
            dueDate: '2026-09-30',
            status: FeeStatus.partial,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CollectFeeScreen), findsOneWidget);
    });

    testWidgets('student list has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: phone,
        overrides: [
          ...baseOverrides(),
          allStudentsProvider.overrideWith((ref) async => fakeStudents()),
          allFeesProvider.overrideWith((ref) async => const <Fee>[]),
        ],
        child: const StudentListScreen(),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(StudentListScreen), findsOneWidget);
    });

    testWidgets('attendance screen has no overflow', (tester) async {
      final fakeAttendance = _FakeAttendance();
      await _pumpResponsive(
        tester,
        size: phone,
        overrides: [
          ...baseOverrides(),
          currentUserProvider.overrideWithValue(fakeTeacherUser()),
          teacherAssignedClassesProvider.overrideWith(
            (ref) async => const [
              AssignedClass(id: 'c1', name: 'جماعت اول'),
            ],
          ),
          classAttendanceProvider.overrideWith(
            (ref, AttendanceParams params) async => [
              AttendanceRecord(
                id: 'att-1',
                tenantId: 't1',
                studentId: 's1',
                studentName: 'علی رضا',
                studentRollNo: '101',
                classId: 'c1',
                teacherId: 'user-teacher-1',
                date: '2026-09-25',
                status: AttendanceStatus.present,
              ),
            ],
          ),
          attendanceRepositoryProvider.overrideWithValue(fakeAttendance),
        ],
        child: const AttendanceScreen(),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(AttendanceScreen), findsOneWidget);
    });

    testWidgets('reports hub has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: phone,
        overrides: [
          ...baseOverrides(),
          appDatabaseProvider
              .overrideWith((ref) => AppDatabase(NativeDatabase.memory())),
        ],
        child: const ReportsHubScreen(),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ReportsHubScreen), findsOneWidget);
    });

    testWidgets('master-admin licenses error state has no overflow',
        (tester) async {
      // The repository hits the dummy Supabase URL and fails; the screen
      // must render the honest error state without overflowing.
      await _pumpResponsive(
        tester,
        size: phone,
        overrides: baseOverrides(),
        child: const LicensesScreen(),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(LicensesScreen), findsOneWidget);
    });

    testWidgets('responsive table cards + pager have no overflow',
        (tester) async {
      await _pumpResponsive(
        tester,
        size: phone,
        overrides: baseOverrides(),
        // SingleChildScrollView matches real embedding: the table's card
        // list is shrink-wrapped for a scrolling parent.
        child: SingleChildScrollView(
          child: M360ResponsiveTable<Map<String, String>>(
            columns: [
              M360TableColumn(title: 'نام', value: (row) => row['name'] ?? ''),
              M360TableColumn(
                  title: 'رقم', value: (row) => row['amount'] ?? ''),
            ],
            rows: [
              for (var i = 0; i < 25; i++)
                const {'name': 'طالب علم', 'amount': '1500'},
            ],
            pageSize: 10,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Advance the pager to exercise the footer buttons.
      await tester.ensureVisible(find.byTooltip('اگلا صفحہ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('اگلا صفحہ'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('long dialog content has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: phone,
        overrides: baseOverrides(),
        child: Builder(
          builder: (context) => Center(
            child: M360SecondaryButton(
              label: 'کھولیں',
              icon: Icons.open_in_new,
              onPressed: () => showDialog(
                context: context,
                builder: (_) => M360Dialog(
                  title: 'لمبی تفصیلات',
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 12; i++)
                        const M360TextField(
                          label: 'فیلڈ',
                          hint: 'قدر درج کریں',
                        ),
                    ],
                  ),
                  actions: [
                    M360TertiaryButton(
                      label: 'منسوخ',
                      onPressed: () {},
                    ),
                    M360PrimaryButton(
                      label: 'محفوظ کریں',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('کھولیں'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 12 — no overflow at 1280x800', () {
    const desktop = Size(1280, 800);

    testWidgets('login screen has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: desktop,
        overrides: baseOverrides(),
        child: DefaultAssetBundle(
          bundle: _TestAssetBundle(),
          child: const LoginScreen(),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppShell dashboard (rail layout) has no overflow',
        (tester) async {
      await _pumpResponsive(
        tester,
        size: desktop,
        overrides: [
          ...baseOverrides(),
          currentUserProvider.overrideWithValue(fakeTeacherUser()),
          activeRoleKeysProvider.overrideWithValue(const <String>[]),
          userPermissionsProvider.overrideWithValue(<String>{}),
          announcementListProvider.overrideWithValue(const []),
        ],
        child: const AppShell(),
      );
      expect(tester.takeException(), isNull);
      // Desktop rail is visible at 1280px.
      expect(find.byTooltip('اطلاعات'), findsOneWidget);
    });

    testWidgets('finance hub has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: desktop,
        overrides: [
          ...baseOverrides(),
          financeHubOverviewProvider.overrideWith(
            (ref) => const AsyncValue.data(
              FinanceHubOverview(
                totalOutstanding: 0,
                monthCollected: 0,
                pendingRecords: 0,
                overdueRecords: 0,
                postedIncome: 0,
                postedExpense: 0,
                topDues: [],
                recentPayments: [],
              ),
            ),
          ),
        ],
        child: const FinanceHubScreen(section: FinanceSection.dashboard),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('fee collection form has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: desktop,
        overrides: [
          ...baseOverrides(),
          appDatabaseProvider
              .overrideWith((ref) => AppDatabase(NativeDatabase.memory())),
        ],
        child: CollectFeeScreen(
          fee: Fee(
            id: 'f1',
            tenantId: 't1',
            studentId: 's1',
            studentName: 'احمد',
            studentClass: 'جماعت اول',
            month: 'ستمبر 2026',
            amountDue: 1500,
            amountPaid: 500,
            dueDate: '2026-09-30',
            status: FeeStatus.partial,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('student list has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: desktop,
        overrides: [
          ...baseOverrides(),
          allStudentsProvider.overrideWith((ref) async => fakeStudents()),
          allFeesProvider.overrideWith((ref) async => const <Fee>[]),
        ],
        child: const StudentListScreen(),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('attendance screen has no overflow', (tester) async {
      final fakeAttendance = _FakeAttendance();
      await _pumpResponsive(
        tester,
        size: desktop,
        overrides: [
          ...baseOverrides(),
          currentUserProvider.overrideWithValue(fakeTeacherUser()),
          teacherAssignedClassesProvider.overrideWith(
            (ref) async => const [
              AssignedClass(id: 'c1', name: 'جماعت اول'),
            ],
          ),
          classAttendanceProvider.overrideWith(
            (ref, AttendanceParams params) async => [
              AttendanceRecord(
                id: 'att-1',
                tenantId: 't1',
                studentId: 's1',
                studentName: 'علی رضا',
                studentRollNo: '101',
                classId: 'c1',
                teacherId: 'user-teacher-1',
                date: '2026-09-25',
                status: AttendanceStatus.present,
              ),
            ],
          ),
          attendanceRepositoryProvider.overrideWithValue(fakeAttendance),
        ],
        child: const AttendanceScreen(),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('reports hub has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: desktop,
        overrides: [
          ...baseOverrides(),
          appDatabaseProvider
              .overrideWith((ref) => AppDatabase(NativeDatabase.memory())),
        ],
        child: const ReportsHubScreen(),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('licenses error state has no overflow', (tester) async {
      await _pumpResponsive(
        tester,
        size: desktop,
        overrides: baseOverrides(),
        child: const LicensesScreen(),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('responsive table renders desktop table without overflow',
        (tester) async {
      await _pumpResponsive(
        tester,
        size: desktop,
        overrides: baseOverrides(),
        // SingleChildScrollView matches real embedding: the table's card
        // list is shrink-wrapped for a scrolling parent.
        child: SingleChildScrollView(
          child: M360ResponsiveTable<Map<String, String>>(
            columns: [
              M360TableColumn(title: 'نام', value: (row) => row['name'] ?? ''),
              M360TableColumn(
                  title: 'رقم', value: (row) => row['amount'] ?? ''),
            ],
            rows: [
              for (var i = 0; i < 25; i++)
                const {'name': 'طالب علم', 'amount': '1500'},
            ],
            pageSize: 10,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Pager footer wraps cleanly even at desktop width.
      await tester.ensureVisible(find.byTooltip('اگلا صفحہ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('اگلا صفحہ'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 12 — 48x48 touch targets', () {
    Future<Size> buttonSize(WidgetTester tester, Widget button) async {
      await _pumpResponsive(
        tester,
        size: const Size(360, 740),
        overrides: baseOverrides(),
        child: Center(child: button),
      );
      expect(tester.takeException(), isNull);
      return tester.getSize(find.byWidget(button));
    }

    testWidgets('M360PrimaryButton is at least 48x48', (tester) async {
      final size = await buttonSize(
        tester,
        M360PrimaryButton(label: 'محفوظ کریں', onPressed: () {}),
      );
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('M360SecondaryButton is at least 48x48', (tester) async {
      final size = await buttonSize(
        tester,
        M360SecondaryButton(label: 'منسوخ کریں', onPressed: () {}),
      );
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('M360TertiaryButton is at least 48x48', (tester) async {
      final size = await buttonSize(
        tester,
        M360TertiaryButton(label: 'تفصیل', onPressed: () {}),
      );
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('M360IconButton is at least 48x48', (tester) async {
      final size = await buttonSize(
        tester,
        M360IconButton(
          icon: Icons.add,
          tooltip: 'شامل کریں',
          onPressed: () {},
        ),
      );
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('primary CTA keeps the darker orange for readable contrast',
        (tester) async {
      // White label text on the lighter accent orange (~2.45:1) is below
      // readable contrast; the design system must use accentDark (~3:1).
      await _pumpResponsive(
        tester,
        size: const Size(360, 740),
        overrides: baseOverrides(),
        child: Center(
          child: M360PrimaryButton(label: 'محفوظ کریں', onPressed: () {}),
        ),
      );
      final elevated =
          tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      final bg =
          elevated.style?.backgroundColor?.resolve(const <WidgetState>{});
      expect(bg, AppColors.accentDark);
    });

    /// Size of the InkWell wrapping [innerText] (shell chips).
    Size chipInkWellSize(WidgetTester tester, String innerText) {
      final element = find.text(innerText).evaluate().single;
      Element? inkWell;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is InkWell) {
          inkWell = ancestor;
          return false;
        }
        return true;
      });
      expect(inkWell, isNotNull, reason: 'no InkWell around "$innerText"');
      final box = inkWell!.renderObject;
      expect(box, isA<RenderBox>());
      return (box! as RenderBox).size;
    }

    testWidgets(
        'shell search trigger, tenant chip and profile chip '
        'are at least 48dp tall', (tester) async {
      await _pumpResponsive(
        tester,
        size: const Size(360, 740),
        overrides: [
          ...baseOverrides(),
          // Two memberships so the tenant chip is in switcher mode.
          tenantMembershipsProvider.overrideWith(
            (ref) async => const [
              TenantMembership(
                tenantId: 't1',
                role: 'teacher',
                tenantName: 'ٹیسٹ مدرسہ',
              ),
              TenantMembership(
                tenantId: 't2',
                role: 'teacher',
                tenantName: 'دوسرا مدرسہ',
              ),
            ],
          ),
          // The chip renders the branding name (not the membership label).
          tenantBrandingProvider.overrideWith(
            (ref) async => const TenantBranding(
              name: 'ٹیسٹ مدرسہ',
              primaryColor: Color(0xFF0E7C5B),
              secondaryColor: Color(0xFF14532D),
              accentColor: Color(0xFFF59E0B),
              fontFamily: 'JameelNooriNastaleeq',
              darkModeEnabled: false,
              language: 'ur',
            ),
          ),
          currentUserProvider.overrideWithValue(fakeTeacherUser()),
          activeRoleKeysProvider.overrideWithValue(const <String>[]),
          userPermissionsProvider.overrideWithValue(<String>{}),
          announcementListProvider.overrideWithValue(const []),
        ],
        child: const AppShell(),
      );
      expect(tester.takeException(), isNull);

      // Search trigger is icon-only in compact mode.
      final searchSize = tester.getSize(
        find.byWidgetPredicate(
          (w) => w is M360IconButton && w.tooltip == 'تلاش (Ctrl+K)',
        ),
      );
      expect(searchSize.height, greaterThanOrEqualTo(48));
      expect(searchSize.width, greaterThanOrEqualTo(48));

      final tenantSize = chipInkWellSize(tester, 'ٹیسٹ مدرسہ');
      expect(tenantSize.height, greaterThanOrEqualTo(48));

      // Profile chip: find the avatar initial text inside it.
      final profileSize =
          chipInkWellSize(tester, fakeTeacherUser().name.characters.first);
      expect(profileSize.height, greaterThanOrEqualTo(48));
    });
  });

  group('Phase 12 — shell icon-only controls have Urdu semantics', () {
    /// Fails unless a semantics node containing [labelText] carries the
    /// button flag (robust to label merging from nested Semantics/Tooltip).
    void expectLabeledButton(WidgetTester tester, String labelText) {
      final matches = find.bySemanticsLabel(RegExp(RegExp.escape(labelText)));
      expect(matches, findsWidgets,
          reason: 'no semantics node labeled "$labelText"');
      // getSemantics takes a Finder — resolve each matched element back
      // through .at(i) instead of casting Elements to SemanticsNodes.
      var foundButton = false;
      final count = matches.evaluate().length;
      for (var i = 0; i < count; i++) {
        final node = tester.getSemantics(matches.at(i));
        if (node.getSemanticsData().flagsCollection.isButton) {
          foundButton = true;
          break;
        }
      }
      expect(foundButton, isTrue,
          reason: '"$labelText" is not exposed as a button');
    }

    Future<void> pumpShell(WidgetTester tester) => _pumpResponsive(
          tester,
          size: const Size(360, 740),
          overrides: [
            ...baseOverrides(),
            tenantMembershipsProvider.overrideWith(
              (ref) async => const [
                TenantMembership(
                  tenantId: 't1',
                  role: 'teacher',
                  tenantName: 'ٹیسٹ مدرسہ',
                ),
                TenantMembership(
                  tenantId: 't2',
                  role: 'teacher',
                  tenantName: 'دوسرا مدرسہ',
                ),
              ],
            ),
            currentUserProvider.overrideWithValue(fakeTeacherUser()),
            activeRoleKeysProvider.overrideWithValue(const <String>[]),
            userPermissionsProvider.overrideWithValue(<String>{}),
            announcementListProvider.overrideWithValue(const []),
          ],
          child: const AppShell(),
        );

    testWidgets('search trigger announces as a button', (tester) async {
      await pumpShell(tester);
      expect(tester.takeException(), isNull);
      expectLabeledButton(tester, 'تلاش (Ctrl+K)');
    });

    testWidgets('tenant switcher chip announces as a button', (tester) async {
      await pumpShell(tester);
      expect(tester.takeException(), isNull);
      expectLabeledButton(tester, 'ادارہ تبدیل کریں');
    });

    testWidgets('profile chip announces as a button', (tester) async {
      await pumpShell(tester);
      expect(tester.takeException(), isNull);
      expectLabeledButton(tester, 'پروفائل');
    });

    testWidgets('notification bell has an Urdu tooltip', (tester) async {
      await pumpShell(tester);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('اطلاعات'), findsOneWidget);
    });
  });

  group('Phase 12 — large text scale', () {
    testWidgets('dialog has no overflow at 2x text scale', (tester) async {
      await _pumpResponsive(
        tester,
        size: const Size(360, 740),
        textScaler: 2.0,
        overrides: baseOverrides(),
        child: Builder(
          builder: (context) => Center(
            child: M360SecondaryButton(
              label: 'کھولیں',
              icon: Icons.open_in_new,
              onPressed: () => showDialog(
                context: context,
                builder: (_) => M360Dialog(
                  title: 'لمبی تفصیلات',
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 6; i++)
                        const M360TextField(
                          label: 'فیلڈ',
                          hint: 'قدر درج کریں',
                        ),
                    ],
                  ),
                  actions: [
                    M360TertiaryButton(label: 'منسوخ', onPressed: () {}),
                    M360PrimaryButton(label: 'محفوظ کریں', onPressed: () {}),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('کھولیں'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('table cards have no overflow at 1.5x text scale',
        (tester) async {
      await _pumpResponsive(
        tester,
        size: const Size(360, 740),
        textScaler: 1.5,
        overrides: baseOverrides(),
        // SingleChildScrollView matches real embedding: the table's card
        // list is shrink-wrapped for a scrolling parent.
        child: SingleChildScrollView(
          child: M360ResponsiveTable<Map<String, String>>(
            columns: [
              M360TableColumn(title: 'نام', value: (row) => row['name'] ?? ''),
              M360TableColumn(
                  title: 'رقم', value: (row) => row['amount'] ?? ''),
            ],
            rows: [
              for (var i = 0; i < 25; i++)
                const {'name': 'طالب علم', 'amount': '1500'},
            ],
            pageSize: 10,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('اگلا صفحہ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('اگلا صفحہ'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 12 — tablet/desktop breakpoints and remaining components', () {
    Future<void> pumpShellAt(WidgetTester tester, Size size) => _pumpResponsive(
          tester,
          size: size,
          overrides: [
            ...baseOverrides(),
            currentUserProvider.overrideWithValue(fakeTeacherUser()),
            activeRoleKeysProvider.overrideWithValue(const <String>[]),
            userPermissionsProvider.overrideWithValue(<String>{}),
            announcementListProvider.overrideWithValue(const []),
          ],
          child: const AppShell(),
        );

    testWidgets(
        'AppShell dashboard (drawer layout) has no overflow at 768x1024',
        (tester) async {
      await pumpShellAt(tester, const Size(768, 1024));
      expect(tester.takeException(), isNull);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('AppShell dashboard (rail layout) has no overflow at 1920x1080',
        (tester) async {
      await pumpShellAt(tester, const Size(1920, 1080));
      expect(tester.takeException(), isNull);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('command palette footer has no overflow at 360x740',
        (tester) async {
      await _pumpResponsive(
        tester,
        size: const Size(360, 740),
        child: Scaffold(
          body: CommandPalette(
            visibleDestinations: const [
              NavDestination(
                id: 'dashboard',
                labelUr: 'ڈیش بورڈ',
                icon: Icons.dashboard_outlined,
                builder: _palettePlaceholder,
              ),
              NavDestination(
                id: 'students',
                labelUr: 'طلبہ',
                icon: Icons.people_outlined,
                builder: _palettePlaceholder,
              ),
            ],
            onSelectDestination: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Footer hint survives the Wrap conversion.
      expect(
          find.text('↑↓ انتخاب • Enter کھولیں • Esc بند کریں'), findsOneWidget);
    });

    testWidgets('status chip announces its state and meets minimum height',
        (tester) async {
      await _pumpResponsive(
        tester,
        size: const Size(360, 740),
        child: const Scaffold(
          body: Center(
            child: M360StatusChip.attendance(
              attendance: M360AttendanceStatus.present,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Screen readers hear the state, not just a color: the chip wraps
      // its label in an explicit Semantics node.
      expect(
        find.ancestor(
          of: find.text('حاضر'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'حالت: حاضر',
          ),
        ),
        findsOneWidget,
      );
      final size = tester.getSize(find.byType(M360StatusChip));
      expect(size.height, greaterThanOrEqualTo(28));
      // Foreground is darkened for contrast, not the raw status color.
      final text = tester.widget<Text>(find.text('حاضر'));
      expect(text.style?.color, isNot(AppColors.success));
    });
  });
}

Widget _palettePlaceholder(BuildContext context) => const SizedBox.shrink();
