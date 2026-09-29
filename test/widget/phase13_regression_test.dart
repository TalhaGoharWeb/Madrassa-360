// Phase 13 — regression suite: nav IA lock-in, teacher single shell,
// honest unavailable states, breakpoints, command palette, typed-confirm
// barrier guard.
//
// Widgets under test:
//   lib/presentation/shell/nav_destinations.dart (IA data + every builder)
//   lib/presentation/screens/dashboards/role_home.dart (teacher routing)
//   lib/presentation/screens/dashboards/teacher_dashboard.dart
//     (TeacherDashboardScreen: single shell, quick actions → shell nav)
//   lib/presentation/shell/app_shell.dart (Ctrl+K binding, bottom-nav ids)
//   lib/presentation/shell/command_palette.dart (open / Esc / barrier)
//   lib/presentation/screens/hostel/hostel_screen.dart (via nav builder)
//   lib/presentation/screens/transport/transport_screen.dart (via nav builder)
//   lib/presentation/screens/certificates/certificates_screen.dart
//     (via nav builder)
//   lib/presentation/screens/finance/finance_hub_screen.dart (breakpoints)
//   lib/presentation/screens/admin/student_list_screen.dart (breakpoints)
//   lib/core/design/m360_dialog.dart (typed-confirmation barrier guard)
//
// Hermetic: Supabase points at a dummy URL and every Supabase-backed
// provider a screen needs is overridden with empty data — no network is
// ever touched.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/design/m360_dialog.dart';
import 'package:madrasa_360/core/notifications/notification_providers.dart';
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/data/models/fee.dart';
import 'package:madrasa_360/data/models/student.dart';
import 'package:madrasa_360/presentation/screens/admin/student_list_screen.dart';
import 'package:madrasa_360/presentation/screens/dashboards/role_home.dart';
import 'package:madrasa_360/presentation/screens/dashboards/teacher_dashboard.dart';
import 'package:madrasa_360/presentation/screens/finance/finance_hub_screen.dart';
import 'package:madrasa_360/presentation/shell/app_shell.dart';
import 'package:madrasa_360/presentation/shell/command_palette.dart';
import 'package:madrasa_360/presentation/shell/nav_destinations.dart';
import 'package:madrasa_360/presentation/shell/shell_nav.dart';
import 'package:madrasa_360/presentation/viewmodels/finance/finance_overview_provider.dart';
import 'package:madrasa_360/presentation/viewmodels/finance/financial_views.dart';
import 'package:madrasa_360/providers/announcement_provider.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/fee_provider.dart';
import 'package:madrasa_360/providers/student_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth_repository.dart';

// ─────────────────────────────────────────────────────────────
// Checked-in route → screen → permission contract
// ─────────────────────────────────────────────────────────────

/// One row of the checked-in contract.
///
/// [screenType] is the [Widget.runtimeType] string the destination's
/// builder must produce. [permissions] / [roleKeys] lock the visibility
/// contract. Adding, renaming or re-permissioning a destination without
/// updating this table fails the checklist tests — that is the point:
/// new routes must arrive with test coverage.
class Phase13RouteExpectation {
  const Phase13RouteExpectation(
    this.id,
    this.screenType,
    this.permissions, [
    this.roleKeys = const <String>[],
  ]);

  final String id;
  final String screenType;
  final List<String> permissions;
  final List<String> roleKeys;
}

/// The full IA contract: 30 destinations. Keep in lock-step with
/// lib/presentation/shell/nav_destinations.dart.
const kPhase13ExpectedRoutes = <Phase13RouteExpectation>[
  // ── مرکزی ──
  Phase13RouteExpectation('dashboard', 'RoleHomeScreen', []),
  Phase13RouteExpectation('announcements', 'AnnouncementsScreen', []),
  Phase13RouteExpectation('guide', 'DashboardGuideScreen', []),
  // ── طلبہ ──
  Phase13RouteExpectation('student-list', 'StudentListScreen', [
    AppPermissions.viewStudents,
    AppPermissions.createStudents,
    AppPermissions.editStudents,
  ]),
  Phase13RouteExpectation('my-classes', 'MyClassesScreen', [
    AppPermissions.viewTeachers,
    AppPermissions.viewDarjas,
    AppPermissions.viewStudents,
  ]),
  Phase13RouteExpectation('my-students', 'MyStudentsScreen', [], [
    'teacher',
    'ustad',
    'ustad_hifz',
  ]),
  Phase13RouteExpectation('parent-fees', 'FeeHistoryScreen', [], ['parent']),
  // ── تعلیمی نظام ──
  Phase13RouteExpectation('darjas', 'DarjaScreen', [
    AppPermissions.viewDarjas,
    AppPermissions.manageDarjas,
  ]),
  Phase13RouteExpectation('exams', 'ExamDashboardScreen', [
    AppPermissions.viewExams,
    AppPermissions.createExams,
    AppPermissions.manageExams,
  ]),
  Phase13RouteExpectation('results', 'ResultsScreen', [
    AppPermissions.viewResults,
    AppPermissions.enterResults,
    AppPermissions.publishResults,
  ]),
  // ── حاضری ──
  Phase13RouteExpectation('attendance', 'AttendanceScreen', [
    AppPermissions.markAttendance,
    AppPermissions.viewAttendance,
  ]),
  // ── مالی ──
  Phase13RouteExpectation('finance_dashboard', 'FinanceHubScreen', [
    AppPermissions.viewFinance,
    AppPermissions.viewFees,
  ]),
  // Phase 13 fix: the mobile bottom nav used the stale 'fees' id and
  // silently dropped the fees tab — the canonical id is 'student_fees'.
  Phase13RouteExpectation('student_fees', 'FeeManagementScreen', [
    AppPermissions.collectFees,
    AppPermissions.viewFees,
  ]),
  Phase13RouteExpectation('finance_dues', 'FinanceHubScreen', [
    AppPermissions.collectFees,
    AppPermissions.viewFees,
  ]),
  Phase13RouteExpectation('finance_invoices', 'FinanceHubScreen', [
    AppPermissions.viewFinance,
    AppPermissions.approveFinance,
  ]),
  Phase13RouteExpectation('finance_payments', 'FinanceHubScreen', [
    AppPermissions.viewFinance,
    AppPermissions.approveFinance,
  ]),
  Phase13RouteExpectation('finance_ledger', 'FinanceHubScreen', [
    AppPermissions.viewFinance,
    AppPermissions.approveFinance,
  ]),
  Phase13RouteExpectation('finance_expenses', 'FinanceHubScreen', [
    AppPermissions.viewFinance,
    AppPermissions.approveFinance,
  ]),
  Phase13RouteExpectation('finance_reports', 'FinanceHubScreen', [
    AppPermissions.viewReports,
    AppPermissions.exportReports,
  ]),
  // ── ادارہ ──
  Phase13RouteExpectation('staff', 'StaffListScreen', [
    AppPermissions.viewStaff,
    AppPermissions.viewTeachers,
  ]),
  Phase13RouteExpectation('library', 'LibraryScreen', [
    AppPermissions.viewLibrary,
    AppPermissions.manageLibrary,
  ]),
  Phase13RouteExpectation('users-roles', 'UserManagementHubScreen', [
    AppPermissions.viewUsers,
    AppPermissions.assignRoles,
  ]),
  Phase13RouteExpectation('hostel', 'HostelScreen', [
    AppPermissions.viewHostel,
    AppPermissions.manageHostel,
  ]),
  Phase13RouteExpectation('transport', 'TransportScreen', [
    AppPermissions.viewTransport,
    AppPermissions.manageTransport,
  ]),
  Phase13RouteExpectation('certificates', 'CertificatesScreen', [
    AppPermissions.viewCertificates,
    AppPermissions.issueCertificates,
  ]),
  // ── ترتیبات ──
  Phase13RouteExpectation('profile', 'ProfileScreen', []),
  Phase13RouteExpectation('notifications', 'NotificationsScreen', []),
  Phase13RouteExpectation('backup', 'BackupScreen', [
    AppPermissions.manageSettings,
  ]),
  Phase13RouteExpectation('about', 'AboutScreen', []),
  // The shell intercepts 'logout' (confirm + sign out); the builder is a
  // stub that is never rendered.
  Phase13RouteExpectation('logout', 'SizedBox', []),
];

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

  group('route checklist — destination builders', () {
    testWidgets('every builder returns its contracted screen widget',
        (tester) async {
      // Grab a real BuildContext once; invoking a builder only constructs
      // the widget (no build(), no provider reads), so one context serves
      // all 30 destinations.
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      for (final expected in kPhase13ExpectedRoutes) {
        final destination = findDestination(expected.id);
        expect(destination, isNotNull,
            reason: 'destination missing: ${expected.id}');
        final built = destination!.builder(context);
        expect(
          built.runtimeType.toString(),
          expected.screenType,
          reason:
              'destination ${expected.id} built ${built.runtimeType}, expected ${expected.screenType}',
        );
        expect(
          destination.requiredPermissions.toSet(),
          expected.permissions.toSet(),
          reason: 'destination ${expected.id}: requiredPermissions changed',
        );
        expect(
          destination.visibleForRoleKeys,
          expected.roleKeys,
          reason: 'destination ${expected.id}: visibleForRoleKeys changed',
        );
      }
    });

    test('destination count matches the checked-in contract', () {
      // Trips first when a destination is added, removed or renamed —
      // update kPhase13ExpectedRoutes (and the builder test above) with it.
      expect(kAllDestinations.length, kPhase13ExpectedRoutes.length);
    });
  });

  group('teacher single shell (Phase 13)', () {
    ProviderContainer teacherContainer() {
      final c = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(fakeTeacherUser()),
        userPermissionsProvider.overrideWithValue({
          AppPermissions.markAttendance,
          AppPermissions.viewStudents,
          AppPermissions.enterResults,
        }),
        activeRoleKeysProvider.overrideWithValue(const ['teacher']),
        announcementListProvider.overrideWithValue(const []),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> pumpRoleHome(WidgetTester tester, ProviderContainer c) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: Scaffold(body: RoleHomeScreen())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('teacher role renders TeacherDashboardScreen directly',
        (tester) async {
      await pumpRoleHome(tester, teacherContainer());
      expect(find.byType(TeacherDashboardScreen), findsOneWidget);
      expect(find.text('السلام علیکم استاد محترم'), findsOneWidget);
    });

    testWidgets('no nested shell chrome inside the teacher dashboard',
        (tester) async {
      await pumpRoleHome(tester, teacherContainer());
      // The deleted TeacherHomeScreen was a nested tab shell; the
      // single-shell model renders the dashboard straight into the
      // AppShell body — DashboardScaffold owns no Scaffold/AppBar of its
      // own and there is no tab bar anywhere in the subtree.
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(RoleHomeScreen),
          matching: find.byType(Scaffold),
        ),
        findsNothing,
      );
    });

    testWidgets('teacher quick actions request shell navigation',
        (tester) async {
      final c = teacherContainer();
      await pumpRoleHome(tester, c);

      await tester.ensureVisible(find.text('حاضری لگائیں'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حاضری لگائیں'));
      await tester.pump();
      expect(c.read(shellNavRequestProvider), 'attendance');

      await tester.ensureVisible(find.text('طلبہ دیکھیں'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('طلبہ دیکھیں'));
      await tester.pump();
      expect(c.read(shellNavRequestProvider), 'my-students');

      await tester.ensureVisible(find.text('نمبر درج کریں'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('نمبر درج کریں'));
      await tester.pump();
      expect(c.read(shellNavRequestProvider), 'results');
    });
  });

  group('honest unavailable states via nav builders', () {
    Future<void> pumpDestination(
      WidgetTester tester,
      String id,
      Set<String> permissions,
    ) async {
      final container = ProviderContainer(overrides: [
        currentTenantIdProvider.overrideWithValue('t1'),
        userPermissionsProvider.overrideWithValue(permissions),
      ]);
      addTearDown(container.dispose);
      final destination = findDestination(id)!;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: Builder(builder: destination.builder)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('hostel builder renders the honest unavailable copy',
        (tester) async {
      await pumpDestination(tester, 'hostel', {
        AppPermissions.viewHostel,
        AppPermissions.manageHostel,
      });
      expect(find.text('دارالاقامہ کا ریکارڈ دستیاب نہیں'), findsOneWidget);
      expect(find.textContaining('جلد'), findsNothing);
    });

    testWidgets('transport builder renders the honest unavailable copy',
        (tester) async {
      await pumpDestination(tester, 'transport', {
        AppPermissions.viewTransport,
        AppPermissions.manageTransport,
      });
      expect(find.text('ٹرانسپورٹ کا ریکارڈ دستیاب نہیں'), findsOneWidget);
      expect(find.textContaining('جلد'), findsNothing);
    });

    testWidgets('certificates history renders the honest unavailable copy',
        (tester) async {
      await pumpDestination(tester, 'certificates', {
        AppPermissions.viewCertificates,
        AppPermissions.issueCertificates,
      });
      expect(find.text('سند جاری کریں'), findsOneWidget);
      await tester.tap(find.text('جاری شدہ اسناد'));
      await tester.pumpAndSettle();
      expect(find.text('اجراء کا ریکارڈ دستیاب نہیں'), findsOneWidget);
      expect(find.textContaining('جلد'), findsNothing);
    });
  });

  group('breakpoints — no overflow at phone / tablet / desktop', () {
    const sizes = <String, Size>{
      'phone 360x740': Size(360, 740),
      'tablet 768x1024': Size(768, 1024),
      'desktop 1280x800': Size(1280, 800),
    };

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
          unreadNotificationsCountProvider
              .overrideWith((ref) => Stream.value(0)),
          currentUserProvider.overrideWithValue(fakeTeacherUser()),
          activeRoleKeysProvider.overrideWithValue(const ['teacher']),
          userPermissionsProvider.overrideWithValue({
            AppPermissions.viewFinance,
            AppPermissions.viewFees,
            AppPermissions.collectFees,
            AppPermissions.approveFinance,
            AppPermissions.viewStudents,
          }),
          announcementListProvider.overrideWithValue(const []),
        ];

    List<Student> students() => [
          for (var i = 0; i < 3; i++)
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

    /// Pumps [child] at [size] under forced RTL (like main.dart) and fails
    /// on any thrown exception or reported layout overflow.
    Future<void> pumpResponsive(
      WidgetTester tester, {
      required Size size,
      required List<Override> overrides,
      required Widget child,
      required Type screenType,
    }) async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
        previous?.call(details);
      };
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: overrides,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(body: child),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = previous;
      }
      expect(tester.takeException(), isNull,
          reason: '$screenType threw at ${size.width}x${size.height}');
      final overflows =
          errors.where((e) => e.toString().contains('overflowed')).toList();
      expect(overflows, isEmpty,
          reason: '$screenType overflowed at ${size.width}x${size.height}: '
              '${overflows.map((e) => e.summary).join(' | ')}');
    }

    for (final entry in sizes.entries) {
      testWidgets('FinanceHubScreen dashboard — ${entry.key}', (tester) async {
        await pumpResponsive(
          tester,
          size: entry.value,
          overrides: [
            ...baseOverrides(),
            financeHubOverviewProvider.overrideWith(
              (ref) async => const FinanceHubOverview(
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
          ],
          child: const FinanceHubScreen(section: FinanceSection.dashboard),
          screenType: FinanceHubScreen,
        );
        expect(find.byType(FinanceHubScreen), findsOneWidget);
      });
    }

    for (final entry in sizes.entries) {
      testWidgets('StudentListScreen — ${entry.key}', (tester) async {
        await pumpResponsive(
          tester,
          size: entry.value,
          overrides: [
            ...baseOverrides(),
            allStudentsProvider.overrideWith((ref) async => students()),
            allFeesProvider.overrideWith((ref) async => const <Fee>[]),
          ],
          child: const StudentListScreen(),
          screenType: StudentListScreen,
        );
        expect(find.byType(StudentListScreen), findsOneWidget);
      });
    }
  });

  group('command palette (Ctrl+K)', () {
    List<Override> shellOverrides() => [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          currentTenantIdProvider.overrideWithValue('t1'),
          tenantMembershipsProvider.overrideWith(
            (ref) async => [
              const TenantMembership(
                tenantId: 't1',
                role: 'mohtamim',
                tenantName: 'ٹیسٹ مدرسہ',
              ),
            ],
          ),
          tenantBrandingProvider
              .overrideWith((ref) async => TenantBranding.fallback()),
          unreadNotificationsCountProvider
              .overrideWith((ref) => Stream.value(0)),
          currentUserProvider.overrideWithValue(fakeTeacherUser()),
          // Empty role keys → the light generic dashboard (RoleHomeScreen
          // falls back to GenericDashboardScreen); the palette's entries
          // come from userPermissionsProvider, not from the roles, so the
          // Ctrl+K wiring under test is unchanged.
          activeRoleKeysProvider.overrideWithValue(const <String>[]),
          userPermissionsProvider.overrideWithValue(AppPermissions.allCodes),
          announcementListProvider.overrideWithValue(const []),
        ];

    Future<void> pumpShell(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: shellOverrides(),
          child: const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: AppShell(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Invokes the Ctrl+K [SingleActivator] the shell registered.
    ///
    /// A raw key event needs a focused node inside the Shortcuts scope to
    /// reach the binding; invoking the registered binding exercises the
    /// app's own wiring (binding → _openSearch → CommandPalette.show)
    /// deterministically instead.
    void invokeCtrlK(WidgetTester tester) {
      final hosts =
          tester.widgetList<CallbackShortcuts>(find.byType(CallbackShortcuts));
      final host = hosts.firstWhere(
        (w) => w.bindings.keys.any((a) =>
            a is SingleActivator &&
            a.trigger == LogicalKeyboardKey.keyK &&
            a.control),
        orElse: () => throw StateError('Ctrl+K binding missing on AppShell'),
      );
      final activator = host.bindings.keys.firstWhere((a) =>
          a is SingleActivator &&
          a.trigger == LogicalKeyboardKey.keyK &&
          a.control);
      host.bindings[activator]!();
    }

    Future<void> dismissWithEscape(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+K binding opens the command palette', (tester) async {
      await pumpShell(tester);
      expect(find.byType(CommandPalette), findsNothing);
      invokeCtrlK(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
    });

    testWidgets('Esc closes the palette (real key event)', (tester) async {
      await pumpShell(tester);
      invokeCtrlK(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      await dismissWithEscape(tester);
      expect(find.byType(CommandPalette), findsNothing);
    });

    testWidgets('barrier tap dismisses the palette', (tester) async {
      await pumpShell(tester);
      invokeCtrlK(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      // The palette dialog sits top-centre with an 80px top inset, so
      // (20, 20) lands on the modal barrier behind it.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsNothing);
    });
  });

  group('typed destructive confirmation — barrier guard', () {
    Future<void> pumpOpener(
      WidgetTester tester, {
      required bool requireTyped,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showM360ConfirmDialog(
                ctx,
                title: 'لائسنس منسوخ کریں',
                message: 'یہ عمل ناقابل واپسی ہے۔',
                confirmLabel: 'منسوخ کریں',
                danger: true,
                requireTypedConfirmation: requireTyped,
                expectedText: 'ڈیمو مدرسہ',
                typedHint: 'تصدیق کے لیے مدرسے کا نام لکھیں',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(M360ConfirmDialog), findsOneWidget);
    }

    testWidgets('typed confirmation cannot be dodged via the barrier',
        (tester) async {
      await pumpOpener(tester, requireTyped: true);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      // Still open: with requireTypedConfirmation the dialog is
      // barrier-non-dismissible, so the destructive action can neither be
      // confirmed accidentally nor dismissed by tapping outside.
      expect(find.byType(M360ConfirmDialog), findsOneWidget);
    });

    testWidgets('plain confirmation stays barrier-dismissible', (tester) async {
      await pumpOpener(tester, requireTyped: false);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(M360ConfirmDialog), findsNothing);
    });
  });
}
