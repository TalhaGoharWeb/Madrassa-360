/// Visual-repair regression tests (2026-09-30 full-app pass).
///
/// Locks in the repair the user asked for — "many elements not using
/// Jameel Noori Nastaleeq":
///   1. Theme-level: the M3 NavigationBar, all button themes and the chip
///      theme resolve their Urdu labels to Jameel Noori Nastaleeq.
///   2. Kasheeda confinement: no lib/ source outside the dashboard
///      greeting hero references the Kasheeda family.
///   3. Overflow: auth + no-access screens render clean at 360x740,
///      740x360 (landscape) and 1280x800 at 1.5x text scale under RTL.
///
/// Implementation files under test:
///   lib/core/constants/app_typography.dart
///   lib/core/theme/app_theme.dart
///   lib/presentation/screens/auth/login_screen.dart
///   lib/presentation/screens/auth/no_access_screen.dart
///   lib/providers/auth_provider.dart (authRepositoryProvider override)
///
/// Fakes: [FakeAuthRepository] (test/widget/fake_auth_repository.dart)
/// overrides [authRepositoryProvider]; Supabase is initialized to a dummy
/// URL so `SupabaseService.client` exists, but no network is ever touched.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/theme/app_theme.dart';
import 'package:madrasa_360/presentation/screens/auth/login_screen.dart';
import 'package:madrasa_360/presentation/screens/auth/no_access_screen.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'fake_auth_repository.dart';

const _nastaliq = 'JameelNooriNastaleeq';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'widget-test-anon-key',
    );
  });

  group('button + chip + nav-bar theme labels (Nastaleeq)', () {
    late ThemeData theme;

    setUp(() => theme = AppTheme.lightTheme);

    test('M3 NavigationBar labels use Nastaleeq when selected', () {
      final s = theme.navigationBarTheme.labelTextStyle!
          .resolve({WidgetState.selected});
      expect(s!.fontFamily, _nastaliq);
      expect(s.height, greaterThanOrEqualTo(2.0));
    });

    test('M3 NavigationBar labels use Nastaleeq when unselected', () {
      final s = theme.navigationBarTheme.labelTextStyle!.resolve({});
      expect(s!.fontFamily, _nastaliq);
    });

    test('elevated buttons use the Nastaleeq button style', () {
      final s =
          theme.elevatedButtonTheme.style!.textStyle!.resolve({}) as TextStyle;
      expect(s.fontFamily, _nastaliq);
      expect(s.fontSize, greaterThanOrEqualTo(15));
      expect(s.height, greaterThanOrEqualTo(2.0));
    });

    test('text buttons use Nastaleeq labels', () {
      final s =
          theme.textButtonTheme.style!.textStyle!.resolve({}) as TextStyle;
      expect(s.fontFamily, _nastaliq);
    });

    test('outlined buttons use Nastaleeq labels', () {
      final s =
          theme.outlinedButtonTheme.style!.textStyle!.resolve({}) as TextStyle;
      expect(s.fontFamily, _nastaliq);
    });

    test('chips use Nastaleeq labels', () {
      expect(theme.chipTheme.labelStyle!.fontFamily, _nastaliq);
    });

    test('theme default fontFamily is Nastaleeq (hints, dialogs, tooltips)',
        () {
      // Regression: the ThemeData-level default used to be Noto Naskh,
      // so every unstyled label/hint/dropdown/tooltip rendered in Naskh.
      // ThemeData has no fontFamily getter — it applies the family to the
      // default text theme, observable on slots our textTheme doesn't
      // override (e.g. displayLarge).
      expect(theme.textTheme.displayLarge!.fontFamily, _nastaliq);
    });

    test('textTheme body/label slots all resolve to Nastaleeq', () {
      final styles = [
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.bodySmall,
        theme.textTheme.labelLarge,
        theme.textTheme.labelMedium,
        theme.textTheme.labelSmall,
      ];
      for (final s in styles) {
        expect(s!.fontFamily, _nastaliq);
        expect(s.height, greaterThanOrEqualTo(2.0));
      }
    });
  });

  group('Kasheeda confinement', () {
    test('only the dashboard greeting references the Kasheeda family', () {
      const allowed = {
        'lib/core/constants/app_typography.dart',
        'lib/presentation/widgets/dashboard/dashboard_scaffold.dart',
      };
      final offenders = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (!e.path.endsWith('.dart')) continue;
        final src = File(e.path).readAsStringSync();
        if (src.contains('kasheedaFamily') ||
            src.contains('greetingKasheeda') ||
            src.contains('heroKasheeda')) {
          if (!allowed.contains(e.path)) offenders.add(e.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'Kasheeda used outside the greeting hero: $offenders');
    });
  });

  group('auth screens overflow (360px, landscape, desktop, 1.5x)', () {
    late FakeAuthRepository fakeAuth;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeAuth = FakeAuthRepository();
    });

    tearDown(() => fakeAuth.dispose());

    Future<void> pumpAt(
      WidgetTester tester, {
      required Size size,
      required Widget child,
      List<Override> overrides = const [],
    }) async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(fakeAuth),
              ...overrides,
            ],
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: MaterialApp(
                  theme: AppTheme.lightTheme,
                  home: Scaffold(body: child),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = previous;
      }
      expect(tester.takeException(), isNull,
          reason: 'threw at ${size.width}x${size.height}');
      final overflows =
          errors.where((e) => e.toString().contains('overflowed'));
      expect(overflows, isEmpty,
          reason: 'overflowed at ${size.width}x${size.height}: '
              '${overflows.map((e) => e.summary).join(' | ')}');
    }

    const sizes = {
      'phone 360x740': Size(360, 740),
      'landscape 740x360': Size(740, 360),
      'desktop 1280x800': Size(1280, 800),
    };

    for (final entry in sizes.entries) {
      testWidgets('LoginScreen clean at ${entry.key} + 1.5x text', (t) async {
        await pumpAt(t, size: entry.value, child: const LoginScreen());
        expect(find.byType(LoginScreen), findsOneWidget);
      });

      testWidgets('NoAccessScreen clean at ${entry.key} + 1.5x text',
          (t) async {
        await pumpAt(
          t,
          size: entry.value,
          child: const NoAccessScreen(),
          overrides: [
            authProvider.overrideWith((ref) {
              final n = AuthNotifier(ref);
              n.state = AuthState.authenticated(
                const AppUser(
                  id: 'u1',
                  email: 'mohtamim@madrassa.com',
                  name: 'مہتمم صاحب',
                  role: UserRole.madrasaAdmin,
                ),
                const {},
              );
              return n;
            }),
          ],
        );
        expect(find.text('رسائی دستیاب نہیں'), findsOneWidget);
      });
    }
  });
}
