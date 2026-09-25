/// Shared test fixture: a controllable [AuthRepository] fake for widget tests.
///
/// Implementation files under test that consume it:
///   lib/presentation/screens/auth/login_screen.dart
///   lib/presentation/screens/auth/tenant_picker_screen.dart
///   lib/providers/auth_provider.dart (authRepositoryProvider override)
///
/// `AuthRepository`'s field initializer reads `SupabaseService.client`, so
/// every test file that builds this fake must first call
/// `Supabase.initialize(url: ..., anonKey: ...)` (no network is touched —
/// the URL is never requested because all sign-in paths go through the
/// overridden methods below).

import 'dart:async';

import 'package:madrasa_360/core/errors/app_exceptions.dart';
import 'package:madrasa_360/data/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository();

  final _events = StreamController<sb.AuthState>.broadcast();

  /// When set, [signIn] delegates to this handler. Otherwise it throws.
  Future<AppUser> Function(String email, String password)? signInHandler;

  AppUser? sessionUser;

  @override
  Stream<sb.AuthState> get authStateChanges => _events.stream;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    if (signInHandler != null) return signInHandler!(email, password);
    throw const AuthenticationException(userMessageUr: 'لاگ ان میں خرابی');
  }

  @override
  Future<AppUser?> getSessionUser() async => sessionUser;

  @override
  Future<void> signOut() async {
    sessionUser = null;
    _events.add(sb.AuthState(sb.AuthChangeEvent.signedOut, null));
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  void dispose() => _events.close();
}

/// A signed-in teacher user for tests that need [currentUserProvider].
AppUser fakeTeacherUser() => const AppUser(
      id: 'user-teacher-1',
      email: 'teacher@test.local',
      name: 'Test Teacher',
      role: UserRole.teacher,
    );
