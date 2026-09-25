/// تصدیق کی خدمت
/// Authentication Service — RETIRED.
///
/// The Phase-1 local mock implementation (with hard-coded demo credentials)
/// was removed in Phase 3. All authentication now goes through Supabase Auth
/// via [AuthRepository] (`lib/data/repositories/auth_repository.dart`) and
/// the Riverpod auth providers (`lib/providers/auth_provider.dart`).
///
/// This file is kept as a stub so the retirement is explicit; nothing in
/// the app imports it. It will be deleted once the migration is fully done.

/// @deprecated Use AuthRepository (Supabase Auth) instead.
@Deprecated('Phase-1 mock auth retired in Phase 3 — use AuthRepository')
class AuthService {
  AuthService._(); // static-only, never instantiated

  /// @deprecated Always throws — mock auth no longer exists.
  @Deprecated('Use AuthRepository.signIn via authProvider')
  static Future<Never> login({
    required String username,
    required String password,
    required Object role,
  }) =>
      throw UnsupportedError(
        'Phase-1 mock auth was retired in Phase 3. '
        'Use AuthRepository (Supabase Auth) instead.',
      );

  /// @deprecated Always throws — mock auth no longer exists.
  @Deprecated('Use authProvider.notifier.logout()')
  static Future<Never> logout() => throw UnsupportedError(
        'Phase-1 mock auth was retired in Phase 3. '
        'Use AuthRepository (Supabase Auth) instead.',
      );
}
