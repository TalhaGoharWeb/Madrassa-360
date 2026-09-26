// Phase 7b dashboards + router tests.
//
// Widgets under test:
//   lib/presentation/screens/dashboards/{clerk,accountant,academic_admin,
//     hostel,library,exam}_dashboard.dart
//   lib/presentation/screens/dashboards/exam_wizard_screen.dart
//   lib/presentation/screens/dashboards/role_home.dart (7b routing)
//
// The dashboards read live providers; like the 7a tests, these override
// only the auth/announcement providers. All dashboard data providers bail
// to honest empty values with no tenant, so no Supabase client is ever
// constructed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/presentation/screens/dashboards/accountant_dashboard.dart';
import 'package:madrasa_360/presentation/screens/dashboards/academic_admin_dashboard.dart';
import 'package:madrasa_360/presentation/screens/dashboards/clerk_dashboard.dart';
import 'package:madrasa_360/presentation/screens/dashboards/exam_dashboard.dart';
import 'package:madrasa_360/presentation/screens/dashboards/exam_wizard_screen.dart';
import 'package:madrasa_360/presentation/screens/dashboards/hostel_dashboard.dart';
import 'package:madrasa_360/presentation/screens/dashboards/library_dashboard.dart';
import 'package:madrasa_360/presentation/screens/dashboards/principal_dashboard.dart';
import 'package:madrasa_360/presentation/screens/dashboards/role_home.dart';
import 'package:madrasa_360/providers/announcement_provider.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';

const _testUser = AppUser(
  id: 'u1',
  email: 'test@example.com',
  name: 'ٹیسٹ صارف',
  role: UserRole.teacher,
);

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer c,
  Widget child,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _container({
  Set<String> permissions = const {},
  List<String> roleKeys = const [],
}) {
  final c = ProviderContainer(overrides: [
    currentUserProvider.overrideWithValue(_testUser),
    userPermissionsProvider.overrideWithValue(permissions),
    activeRoleKeysProvider.overrideWithValue(roleKeys),
    announcementListProvider.overrideWithValue(const []),
    // The dashboards gate module features on tenantModulesProvider; with
    // no tenant the real provider yields an empty set, so enable the
    // modules under test explicitly (same pattern as the reports hub test).
    tenantModulesProvider.overrideWith((ref) async =>
        {'fees', 'academics', 'hostel', 'library', 'exams', 'reports'}),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('Phase 7b router mapping', () {
    testWidgets('daftar_dar routes to the clerk dashboard', (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['daftar_dar'],
          permissions: {
            AppPermissions.viewStudents,
            AppPermissions.createStudents,
            AppPermissions.viewFees,
            AppPermissions.collectFees,
          },
        ),
        const RoleHomeScreen(),
      );
      expect(find.byType(ClerkDashboardScreen), findsOneWidget);
    });

    testWidgets('accountant routes to the finance dashboard', (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['accountant'],
          permissions: {
            AppPermissions.viewFees,
            AppPermissions.collectFees,
            AppPermissions.viewFinance,
            AppPermissions.createFinance,
            AppPermissions.viewReports,
          },
        ),
        const RoleHomeScreen(),
      );
      expect(find.byType(AccountantDashboardScreen), findsOneWidget);
    });

    testWidgets(
        'nazim_taleem routes to the academic dashboard (not '
        'principal, despite satisfying isPrincipal)', (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['nazim_taleem'],
          permissions: {
            AppPermissions.viewDarjas,
            AppPermissions.manageDarjas,
            AppPermissions.viewExams,
            AppPermissions.createExams,
            AppPermissions.publishExams,
            AppPermissions.viewResults,
            AppPermissions.enterResults,
            AppPermissions.publishResults,
            AppPermissions.viewTeachers,
            AppPermissions.viewStudents,
            AppPermissions.viewAttendance,
          },
        ),
        const RoleHomeScreen(),
      );
      expect(find.byType(AcademicAdminDashboardScreen), findsOneWidget);
      expect(find.byType(PrincipalDashboardScreen), findsNothing);
    });

    testWidgets('warden routes to the hostel dashboard', (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['warden'],
          permissions: {
            AppPermissions.viewHostel,
            AppPermissions.viewAttendance,
            AppPermissions.viewStudents,
          },
        ),
        const RoleHomeScreen(),
      );
      expect(find.byType(HostelDashboardScreen), findsOneWidget);
    });

    testWidgets('librarian routes to the library dashboard', (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['librarian'],
          permissions: {
            AppPermissions.viewLibrary,
            AppPermissions.manageLibrary,
          },
        ),
        const RoleHomeScreen(),
      );
      expect(find.byType(LibraryDashboardScreen), findsOneWidget);
    });

    testWidgets('mumtahin routes to the exam dashboard', (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['mumtahin'],
          permissions: {
            AppPermissions.viewExams,
            AppPermissions.createExams,
            AppPermissions.viewResults,
            AppPermissions.enterResults,
            AppPermissions.viewStudents,
          },
        ),
        const RoleHomeScreen(),
      );
      expect(find.byType(ExamDashboardScreen), findsOneWidget);
    });

    testWidgets('mohtamim still routes to the principal dashboard',
        (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['mohtamim'],
          permissions: {
            AppPermissions.manageDarjas,
            AppPermissions.publishExams,
            AppPermissions.publishResults,
            AppPermissions.viewStudents,
          },
        ),
        const RoleHomeScreen(),
      );
      expect(find.byType(PrincipalDashboardScreen), findsOneWidget);
    });
  });

  group('Clerk dashboard', () {
    testWidgets('renders دفتر stats and today-tasks', (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['daftar_dar'],
          permissions: {
            AppPermissions.viewStudents,
            AppPermissions.createStudents,
            AppPermissions.viewFees,
            AppPermissions.collectFees,
            AppPermissions.issueCertificates,
            AppPermissions.viewDocuments,
          },
        ),
        const ClerkDashboardScreen(),
      );
      expect(find.text('دفتر کا جائزہ'), findsOneWidget);
      expect(find.text('نئے داخلے'), findsOneWidget);
      expect(find.text('آج کی فیس'), findsOneWidget);
      expect(find.text('میرا آج کا کام'), findsOneWidget);
      expect(find.text('داخلے مکمل کریں'), findsOneWidget);
      expect(find.text('رسیدیں تیار کریں'), findsOneWidget);
    });
  });

  group('Accountant dashboard', () {
    testWidgets('renders مالی خلاصہ in plain Urdu, no jargon', (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['accountant'],
          permissions: {
            AppPermissions.viewFees,
            AppPermissions.collectFees,
            AppPermissions.viewFinance,
            AppPermissions.createFinance,
            AppPermissions.viewReports,
          },
        ),
        const AccountantDashboardScreen(),
      );
      expect(find.text('آج کا مالی خلاصہ'), findsOneWidget);
      expect(find.text('آج کی وصولی'), findsOneWidget);
      expect(find.text('آج کے اخراجات'), findsOneWidget);
      expect(find.text('بقایا فیس'), findsOneWidget);
      expect(find.text('نقد رقم'), findsOneWidget);
      expect(find.text('تفصیلی حسابات'), findsOneWidget);
      // No accounting jargon anywhere on the dashboard.
      expect(find.textContaining('Ledger'), findsNothing);
      expect(find.textContaining('Debit'), findsNothing);
      expect(find.textContaining('Credit'), findsNothing);
    });
  });

  group('Hostel dashboard', () {
    testWidgets('shows honest empty states, never invented numbers',
        (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['warden'],
          permissions: {
            AppPermissions.viewHostel,
            AppPermissions.viewAttendance,
            AppPermissions.viewStudents,
          },
        ),
        const HostelDashboardScreen(),
      );
      expect(find.text('رہائشی طلبہ'),
          findsOneWidget); // stat only — action omitted (no hostel data source)
      expect(find.text('غیر حاضر'), findsOneWidget);
      // Honest empty states, not zeros presented as data.
      expect(find.text('ابھی دستیاب نہیں'), findsWidgets);
      expect(find.textContaining('جلد مکمل ہوگا'), findsOneWidget);
    });
  });

  group('Library dashboard', () {
    testWidgets('renders library stats and actions', (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['librarian'],
          permissions: {
            AppPermissions.viewLibrary,
            AppPermissions.manageLibrary,
            AppPermissions.viewReports,
          },
        ),
        const LibraryDashboardScreen(),
      );
      expect(find.text('کل کتب'), findsOneWidget);
      expect(find.text('جاری شدہ'), findsOneWidget);
      expect(find.text('واپسی باقی'), findsOneWidget);
      expect(find.text('کتاب جاری کریں'), findsOneWidget);
      expect(find.text('کتاب واپس لیں'), findsOneWidget);
    });
  });

  group('Exam dashboard', () {
    testWidgets('renders exam stats and the wizard entry point',
        (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['mumtahin'],
          permissions: {
            AppPermissions.viewExams,
            AppPermissions.createExams,
            AppPermissions.viewResults,
            AppPermissions.enterResults,
            AppPermissions.viewReports,
          },
        ),
        const ExamDashboardScreen(),
      );
      expect(find.text('جاری امتحانات'), findsOneWidget);
      expect(find.text('نمبر درج ہونا باقی'), findsOneWidget);
      expect(find.text('نتائج تیار'), findsOneWidget);
      expect(find.text('نتائج شائع شدہ'), findsOneWidget);
      expect(find.text('امتحان بنائیں'), findsOneWidget);
    });
  });

  group('Exam wizard', () {
    testWidgets('opens on step 1 with a progress indicator', (tester) async {
      await _pump(
        tester,
        _container(
          roleKeys: const ['mumtahin'],
          permissions: {
            AppPermissions.viewExams,
            AppPermissions.createExams,
            AppPermissions.enterResults,
          },
        ),
        const ExamWizardScreen(),
      );
      expect(find.text('امتحان وزرڈ'), findsOneWidget);
      expect(find.text('مرحلہ 1 از 8'), findsOneWidget);
      expect(find.text('امتحان بنائیں'), findsOneWidget);
      expect(find.text('امتحان کا نام'), findsOneWidget);
      expect(find.text('آگے'), findsOneWidget);
      // The whole workflow is not shown at once.
      expect(find.text('منظوری'), findsNothing);
      expect(find.text('شائع کریں'), findsNothing);
    });
  });
}
