/// Widget tests for the login screen.
///
/// Implementation files under test:
///   lib/presentation/screens/auth/login_screen.dart
///   lib/providers/auth_provider.dart          (login flow, error state)
///   lib/core/utils/validators.dart            (email / required messages)
///   lib/core/utils/error_handler.dart         (error SnackBar)
///   lib/core/widgets/loading_widget.dart      (LoadingOverlay)
///
/// Fakes: [FakeAuthRepository] (test/widget/fake_auth_repository.dart)
/// overrides [authRepositoryProvider]; Supabase is initialized to a dummy
/// URL so `SupabaseService.client` exists, but no network is ever touched.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_strings.dart';
import 'package:madrasa_360/core/errors/app_exceptions.dart';
import 'package:madrasa_360/presentation/screens/auth/login_screen.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth_repository.dart';

/// Asset bundle for widget tests: the login screen shows the real app logo
/// via Image.asset, which the flutter_test asset bundle cannot resolve.
/// Serve a 1x1 transparent PNG for any image request instead of failing the
/// test (an Image errorBuilder alone is not enough — the image-service error
/// is still reported to the test zone and fails the test).
class _TestAssetBundle extends CachingAssetBundle {
  /// A 1x1 transparent PNG, served for any image asset request.
  static final ByteData _pixels = ByteData.view(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  ).buffer);

  @override
  Future<ByteData> load(String key) async => _pixels;

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      Future.value('');
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Dummy init: only needed so SupabaseService.client exists.
    // No HTTP request is ever issued.
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'widget-test-anon-key',
    );
  });

  late FakeAuthRepository fakeAuth;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeAuth = FakeAuthRepository();
  });

  tearDown(() => fakeAuth.dispose());

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
        ],
        child: DefaultAssetBundle(
          bundle: _TestAssetBundle(),
          child: const MaterialApp(home: LoginScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder emailField() =>
      find.widgetWithText(TextFormField, 'اپنا ای میل درج کریں');
  Finder passwordField() =>
      find.widgetWithText(TextFormField, 'اپنا پاس ورڈ درج کریں');
  Finder loginButton() =>
      find.widgetWithText(ElevatedButton, AppStrings.loginButton);

  group('LoginScreen validation', () {
    testWidgets('empty fields show required-field errors', (tester) async {
      await pumpLogin(tester);

      await tester.ensureVisible(loginButton());
      await tester.pumpAndSettle();
      await tester.tap(loginButton());
      await tester.pump(); // validators run, no sign-in attempted

      // Validators.email('') → 'ای میل ضروری ہے'
      expect(find.text('ای میل ضروری ہے'), findsOneWidget);
      // Validators.required('', fieldName: 'پاس ورڈ') → 'پاس ورڈ ضروری ہے'
      expect(find.text('پاس ورڈ ضروری ہے'), findsOneWidget);
    });

    testWidgets('invalid email format shows the format error', (tester) async {
      await pumpLogin(tester);

      await tester.enterText(emailField(), 'not-an-email');
      await tester.enterText(passwordField(), 'secret123');
      await tester.ensureVisible(loginButton());
      await tester.pumpAndSettle();
      await tester.tap(loginButton());
      await tester.pump();

      expect(find.text('غلط ای میل فارمیٹ'), findsOneWidget);
      // No error on the (valid) password field.
      expect(find.text('پاس ورڈ ضروری ہے'), findsNothing);
    });
  });

  group('LoginScreen sign-in states', () {
    testWidgets('shows the loading overlay while sign-in is in flight',
        (tester) async {
      final gate = Completer<AppUser>();
      fakeAuth.signInHandler = (_, __) => gate.future;

      await pumpLogin(tester);

      await tester.enterText(emailField(), 'teacher@test.local');
      await tester.enterText(passwordField(), 'secret123');
      await tester.ensureVisible(loginButton());
      await tester.pumpAndSettle();
      await tester.tap(loginButton());
      await tester.pump(); // _handleLogin: validate ok → _isLoading = true

      // LoadingOverlay message from LoginScreen._handleLogin.
      expect(find.text('لاگ ان ہو رہا ہے...'), findsOneWidget);
      // The button swaps its label for a spinner and is disabled.
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );

      // Release the gate with a failure so the widget can settle.
      gate.completeError(const AuthenticationException(
          userMessageUr: 'غلط ای میل یا پاس ورڈ'));
      await tester.pumpAndSettle();
      expect(find.text('لاگ ان ہو رہا ہے...'), findsNothing);
    });

    testWidgets('auth failure shows the provider error in a SnackBar',
        (tester) async {
      fakeAuth.signInHandler = (_, __) => throw const AuthenticationException(
            userMessageUr: 'غلط ای میل یا پاس ورڈ',
          );

      await pumpLogin(tester);

      await tester.enterText(emailField(), 'teacher@test.local');
      await tester.enterText(passwordField(), 'wrong-password');
      await tester.ensureVisible(loginButton());
      await tester.pumpAndSettle();
      await tester.tap(loginButton());
      await tester.pumpAndSettle();

      // authProvider.state.errorMessage surfaced via ErrorHandler SnackBar.
      expect(find.text('غلط ای میل یا پاس ورڈ'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      // Still on the login screen (no navigation on failure).
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
