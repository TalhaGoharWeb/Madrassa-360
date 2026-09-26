// Phase 7a dashboard framework + router tests.
//
// Widgets under test:
//   lib/presentation/widgets/dashboard/{dashboard_scaffold,stat_card,
//     alert_card,quick_actions,today_tasks,dashboard_section}.dart
//   lib/presentation/screens/dashboards/role_home.dart
//   (RoleHomeScreen routing, GenericDashboardScreen fallback)
//
// The dashboards read live providers; tests override the Supabase-backed
// ones (announcements) so no client is ever constructed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/presentation/screens/dashboards/role_home.dart';
import 'package:madrasa_360/presentation/widgets/dashboard/alert_card.dart';
import 'package:madrasa_360/presentation/widgets/dashboard/dashboard_scaffold.dart';
import 'package:madrasa_360/presentation/widgets/dashboard/dashboard_section.dart';
import 'package:madrasa_360/presentation/widgets/dashboard/quick_actions.dart';
import 'package:madrasa_360/presentation/widgets/dashboard/stat_card.dart';
import 'package:madrasa_360/presentation/widgets/dashboard/today_tasks.dart';
import 'package:madrasa_360/providers/announcement_provider.dart';
import 'package:madrasa_360/providers/auth_provider.dart';

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
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('StatCard', () {
    testWidgets('renders icon, Urdu label and value together', (tester) async {
      await _pump(
        tester,
        _container(),
        const StatCard(icon: Icons.people, label: 'طلبہ', value: '1245'),
      );
      expect(find.text('طلبہ'), findsOneWidget);
      expect(find.text('1245'), findsOneWidget);
      expect(find.byIcon(Icons.people), findsOneWidget);
    });

    testWidgets('tapping with onTap fires the callback', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        _container(),
        StatCard(
          icon: Icons.people,
          label: 'طلبہ',
          value: '1245',
          onTap: () => tapped = true,
        ),
      );
      await tester.tap(find.text('1245'));
      expect(tapped, isTrue);
    });
  });

  group('AlertCard', () {
    testWidgets('message and action button both render', (tester) async {
      var acted = false;
      await _pump(
        tester,
        _container(),
        AlertCard(
          icon: Icons.warning_outlined,
          message: 'فیس باقی ہے',
          actionLabel: 'دیکھیں',
          onAction: () => acted = true,
        ),
      );
      expect(find.text('فیس باقی ہے'), findsOneWidget);
      expect(find.text('دیکھیں'), findsOneWidget);
      await tester.tap(find.text('دیکھیں'));
      expect(acted, isTrue);
    });
  });

  group('QuickActionGrid', () {
    testWidgets('labels render with icons and taps fire', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        _container(),
        QuickActionGrid(items: [
          QuickActionItem(
            icon: Icons.add,
            label: 'طالب علم داخل کریں',
            onTap: () => tapped = true,
          ),
        ]),
      );
      expect(find.text('طالب علم داخل کریں'), findsOneWidget);
      await tester.tap(find.text('طالب علم داخل کریں'));
      expect(tapped, isTrue);
    });
  });

  group('TodayTasks', () {
    testWidgets('checkbox toggle reports back through onToggle',
        (tester) async {
      int? toggledIndex;
      bool? toggledValue;
      await _pump(
        tester,
        _container(),
        TodayTasks(
          tasks: const [TodayTask(label: 'آج کی حاضری مکمل کریں')],
          onToggle: (i, v) {
            toggledIndex = i;
            toggledValue = v;
          },
        ),
      );
      expect(find.text('میرا آج کا کام'), findsOneWidget);
      expect(find.text('آج کی حاضری مکمل کریں'), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      expect(toggledIndex, 0);
      expect(toggledValue, isTrue);
    });
  });

  group('DashboardSection', () {
    testWidgets('renders title and tiles', (tester) async {
      await _pump(
        tester,
        _container(),
        DashboardSection(
          title: 'مالیات',
          tiles: [
            SectionTile(
              icon: Icons.payments_outlined,
              label: 'فیس',
              onTap: () {},
            ),
          ],
        ),
      );
      expect(find.text('مالیات'), findsOneWidget);
      expect(find.text('فیس'), findsOneWidget);
    });
  });

  group('DashboardScaffold', () {
    testWidgets('header shows greeting, name, madrasa and Urdu date',
        (tester) async {
      await _pump(
        tester,
        _container(),
        const DashboardScaffold(
          greeting: 'السلام علیکم ورحمۃ اللہ',
          userName: 'ٹیسٹ صارف',
          madrasaName: 'ٹیسٹ مدرسہ',
          stats: Text('stats'),
        ),
      );
      expect(find.text('السلام علیکم ورحمۃ اللہ'), findsOneWidget);
      expect(find.text('ٹیسٹ صارف'), findsOneWidget);
      expect(find.text('ٹیسٹ مدرسہ'), findsOneWidget);
      // Urdu date line carries a month name like 'ستمبر'.
      expect(find.textContaining('ستمبر'), findsWidgets);
    });
  });

  group('RoleHomeScreen routing', () {
    testWidgets('no role keys → generic dashboard (never blank)',
        (tester) async {
      await _pump(tester, _container(), const RoleHomeScreen());
      expect(find.text('السلام علیکم ورحمۃ اللہ'), findsOneWidget);
      expect(find.text('میری پروفائل'), findsOneWidget);
      expect(find.text('ابھی کوئی اعلان نہیں'), findsOneWidget);
    });

    testWidgets('principal authority → principal dashboard', (tester) async {
      await _pump(
        tester,
        _container(
          permissions: {
            AppPermissions.manageDarjas,
            AppPermissions.publishExams,
            AppPermissions.publishResults,
          },
          roleKeys: const ['mohtamim'],
        ),
        const RoleHomeScreen(),
      );
      expect(find.text('آج مدرسے کا حال'), findsOneWidget);
      expect(find.text('❁ اہم امور'), findsOneWidget);
    });

    testWidgets('teacher role key → teacher home', (tester) async {
      await _pump(
        tester,
        _container(
          permissions: {
            AppPermissions.viewStudents,
            AppPermissions.viewAttendance,
            AppPermissions.markAttendance,
            AppPermissions.viewResults,
            AppPermissions.enterResults,
          },
          roleKeys: const ['teacher'],
        ),
        const RoleHomeScreen(),
      );
      expect(find.text('السلام علیکم استاد محترم'), findsOneWidget);
      expect(find.text('آج کی تدریس'), findsWidgets);
    });

    testWidgets('teacher without finance perms sees no finance UI',
        (tester) async {
      await _pump(
        tester,
        _container(
          permissions: {
            AppPermissions.viewStudents,
            AppPermissions.viewAttendance,
            AppPermissions.markAttendance,
          },
          roleKeys: const ['teacher'],
        ),
        const RoleHomeScreen(),
      );
      expect(find.text('فیس وصول کریں'), findsNothing);
      expect(find.text('مالی حساب'), findsNothing);
      expect(find.text('صارفین'), findsNothing);
    });

    testWidgets('parent role key → generic dashboard', (tester) async {
      await _pump(
        tester,
        _container(roleKeys: const ['parent']),
        const RoleHomeScreen(),
      );
      expect(find.text('السلام علیکم ورحمۃ اللہ'), findsOneWidget);
      expect(find.text('میری پروفائل'), findsOneWidget);
    });
  });
}
