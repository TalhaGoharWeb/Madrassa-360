// Phase 8 module widget tests.
//
// Widgets under test:
//   lib/presentation/screens/hostel/hostel_screen.dart
//   lib/presentation/screens/transport/transport_screen.dart
//   lib/presentation/screens/certificates/certificates_screen.dart
//   lib/presentation/shell/nav_destinations.dart (IA wiring)
//   lib/presentation/screens/hostel/hostel_forms.dart (delete confirmation)
//   lib/presentation/screens/transport/transport_forms.dart (delete confirmation)
//   lib/providers/hostel_provider.dart (honest unavailable state)
//
// The providers read the isolated repository interfaces whose current
// implementations throw [BackendUnavailableException]; the tests assert
// the UI renders the honest backend-unavailable copy — never a
// "coming soon" placeholder, never invented rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/data/repositories/hostel_repository.dart';
import 'package:madrasa_360/presentation/screens/certificates/certificates_screen.dart';
import 'package:madrasa_360/presentation/screens/hostel/hostel_forms.dart';
import 'package:madrasa_360/presentation/screens/hostel/hostel_screen.dart';
import 'package:madrasa_360/presentation/screens/transport/transport_forms.dart';
import 'package:madrasa_360/presentation/screens/transport/transport_screen.dart';
import 'package:madrasa_360/presentation/shell/nav_destinations.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/hostel_provider.dart';

ProviderContainer _container({Set<String> permissions = const {}}) {
  final c = ProviderContainer(overrides: [
    currentTenantIdProvider.overrideWithValue('t1'),
    userPermissionsProvider.overrideWithValue(permissions),
  ]);
  addTearDown(c.dispose);
  return c;
}

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

void main() {
  group('Phase 8 provider honesty', () {
    test('hostel load() lands in backendUnavailable with no backend', () async {
      final c = _container();
      await c.read(hostelProvider.notifier).load();
      final s = c.read(hostelProvider);
      expect(s.backendUnavailable, isTrue);
      expect(s.error, isNotNull);
    });

    test('hostel writes fail honestly — never fake success', () async {
      final c = _container();
      final ok = await c.read(hostelProvider.notifier).saveBuilding(
            const HostelBuilding(id: 'b1', tenantId: 't1', name: 'بلاک اے'),
          );
      expect(ok, isFalse);
      expect(c.read(hostelProvider).error, isNotNull);
      expect(c.read(hostelProvider).error, isNot(contains('جلد')));
    });
  });

  group('Phase 8 honest unavailable states', () {
    testWidgets('hostel hub renders the honest unavailable state',
        (tester) async {
      await _pump(
        tester,
        _container(permissions: {
          AppPermissions.viewHostel,
          AppPermissions.manageHostel,
        }),
        const HostelScreen(),
      );
      expect(find.text('دارالاقامہ کا ریکارڈ دستیاب نہیں'), findsOneWidget);
      expect(find.textContaining('جلد'), findsNothing);
      // All four tabs exist.
      expect(find.text('عمارتیں'), findsOneWidget);
      expect(find.text('کمرے'), findsOneWidget);
      expect(find.text('بستر'), findsOneWidget);
      expect(find.text('رہائشی'), findsOneWidget);
    });

    testWidgets('transport hub renders the honest unavailable state',
        (tester) async {
      await _pump(
        tester,
        _container(permissions: {
          AppPermissions.viewTransport,
          AppPermissions.manageTransport,
        }),
        const TransportScreen(),
      );
      expect(find.text('ٹرانسپورٹ کا ریکارڈ دستیاب نہیں'), findsOneWidget);
      expect(find.textContaining('جلد'), findsNothing);
      expect(find.text('گاڑیاں'), findsOneWidget);
      expect(find.text('ڈرائیور'), findsOneWidget);
      expect(find.text('راستے'), findsOneWidget);
      expect(find.text('اسائنمنٹس'), findsOneWidget);
    });

    testWidgets('certificates history tab renders the honest unavailable state',
        (tester) async {
      await _pump(
        tester,
        _container(permissions: {
          AppPermissions.viewCertificates,
          AppPermissions.issueCertificates,
        }),
        const CertificatesScreen(),
      );
      // Issue tab renders first: type picker + student search.
      expect(find.text('سند جاری کریں'), findsOneWidget);
      expect(find.text('کردار سرٹیفکیٹ'), findsOneWidget);
      expect(find.text('منتقلی سرٹیفکیٹ'), findsOneWidget);
      // Switch to the history tab.
      await tester.tap(find.text('جاری شدہ اسناد'));
      await tester.pumpAndSettle();
      expect(find.text('اجراء کا ریکارڈ دستیاب نہیں'), findsOneWidget);
      expect(find.textContaining('جلد'), findsNothing);
    });
  });

  group('Phase 8 destructive confirmations', () {
    testWidgets('hostel delete asks for destructive confirmation',
        (tester) async {
      bool? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                confirmed = await confirmHostelDelete(
                  ctx,
                  itemLabel: 'بلاک اے',
                );
              },
              child: const Text('del'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('del'));
      await tester.pumpAndSettle();
      expect(find.text('حذف کرنے کی تصدیق'), findsOneWidget);
      expect(find.textContaining('بلاک اے'), findsOneWidget);
      // Danger confirm label present.
      expect(find.text('حذف کریں'), findsOneWidget);
      await tester.tap(find.text('حذف کریں'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });

    testWidgets('transport delete asks for destructive confirmation',
        (tester) async {
      bool? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                confirmed = await confirmTransportDelete(
                  ctx,
                  itemLabel: 'LHR-1234',
                );
              },
              child: const Text('del'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('del'));
      await tester.pumpAndSettle();
      expect(find.text('حذف کرنے کی تصدیق'), findsOneWidget);
      expect(find.textContaining('LHR-1234'), findsOneWidget);
      expect(find.text('حذف کریں'), findsOneWidget);
      // Cancel path leaves confirmed == false.
      await tester.tap(find.text('منسوخ کریں'));
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);
    });
  });

  group('Phase 8 navigation wiring', () {
    test('hostel destination builds the real hub', () {
      final d = findDestination('hostel')!;
      expect(
        d.requiredPermissions,
        contains(AppPermissions.viewHostel),
      );
    });

    test('transport destination builds the real hub', () {
      final d = findDestination('transport')!;
      expect(
        d.requiredPermissions,
        contains(AppPermissions.viewTransport),
      );
    });

    test('certificates destination builds the real screen', () {
      final d = findDestination('certificates')!;
      expect(
        d.requiredPermissions,
        contains(AppPermissions.issueCertificates),
      );
    });

    testWidgets('hostel builder renders HostelScreen', (tester) async {
      final d = findDestination('hostel')!;
      await _pump(
        tester,
        _container(permissions: {AppPermissions.viewHostel}),
        Builder(builder: d.builder),
      );
      expect(find.byType(HostelScreen), findsOneWidget);
    });

    testWidgets('transport builder renders TransportScreen', (tester) async {
      final d = findDestination('transport')!;
      await _pump(
        tester,
        _container(permissions: {AppPermissions.viewTransport}),
        Builder(builder: d.builder),
      );
      expect(find.byType(TransportScreen), findsOneWidget);
    });

    testWidgets('certificates builder renders CertificatesScreen',
        (tester) async {
      final d = findDestination('certificates')!;
      await _pump(
        tester,
        _container(permissions: {AppPermissions.viewCertificates}),
        Builder(builder: d.builder),
      );
      expect(find.byType(CertificatesScreen), findsOneWidget);
    });
  });
}
