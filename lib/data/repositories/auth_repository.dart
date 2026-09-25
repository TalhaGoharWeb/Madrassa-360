/// تصدیق کا ذخیرہ
/// Authentication Repository — wraps Supabase Auth (Phase 3: production-grade)
///
/// Covers Mission §19: email/password sign-in, password reset / account
/// recovery, session persistence & expiry, sign-out, and auth state events.
/// All failures surface as typed [AppException]s — never raw SDK errors.

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../core/services/supabase_service.dart';
import '../../core/observability/app_logger.dart';
import '../../core/utils/error_handler.dart';

// ─────────────────────────────────────────────────────────────
// User Role
// ─────────────────────────────────────────────────────────────

enum UserRole {
  // Platform
  superAdmin,
  franchiseManager,
  // Madrasa
  madrasaAdmin,
  admin, // legacy alias for madrasaAdmin
  editor,
  // Academic
  academicManager,
  teacher,
  attendanceOfficer,
  // Finance
  accountant,
  financeManager,
  // Other departments
  libraryManager,
  hostelManager,
  announcementManager,
  admissionOfficer,
  itManager,
  // External
  parent,
  student,
}

// ─────────────────────────────────────────────────────────────
// AppUser — the app's own user model (wraps Supabase user)
// ─────────────────────────────────────────────────────────────

class AppUser {
  final String id;
  final String email;
  final String name;
  final UserRole role;
  final String? phone;
  final String? photoUrl;
  /// Permission codes loaded from Supabase RBAC tables (or offline fallback).
  final Set<String> permissions;
  /// The madrasa this user is primarily associated with (null for platform roles).
  final String? madrasaId;

  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.phone,
    this.photoUrl,
    this.permissions = const {},
    this.madrasaId,
  });

  /// Build from a Supabase [user] + the matching row from public.profiles.
  factory AppUser.fromSupabase(
    sb.User user,
    Map<String, dynamic> profile,
  ) {
    // Prefer app_metadata (set by admin/service key), fall back to profiles table.
    // Case-insensitive match so 'superAdmin', 'superadmin', 'SUPERADMIN' all work.
    final rawRole = (user.appMetadata['role'] as String?)?.trim() ??
        (profile['role'] as String?)?.trim() ??
        'teacher';

    final role = UserRole.values.firstWhere(
      (r) => r.name.toLowerCase() == rawRole.toLowerCase(),
      orElse: () => UserRole.teacher,
    );

    AppLogger().debug('[Auth] resolved role: "$rawRole" → ${role.name}');

    return AppUser(
      id: user.id,
      email: user.email ?? '',
      name: profile['name'] as String? ?? user.email ?? '',
      role: role,
      phone: profile['phone'] as String?,
      photoUrl: profile['photo_url'] as String?,
      // madrasaId is loaded here but permissions are loaded separately
      // via PermissionService after login (see AuthNotifier).
      madrasaId: profile['madrasa_id'] as String?,
    );
  }

  /// Convenience: check a single permission without a provider.
  bool can(String permission) => permissions.contains(permission);

  /// True for platform-wide roles (superAdmin, franchiseManager).
  bool get isPlatformRole =>
      role == UserRole.superAdmin || role == UserRole.franchiseManager;

  /// True for madrasa staff (can access admin panel).
  bool get isStaff =>
      role != UserRole.parent && role != UserRole.student;

  AppUser copyWith({
    String? name,
    String? phone,
    String? photoUrl,
    Set<String>? permissions,
    String? madrasaId,
  }) {
    return AppUser(
      id: id,
      email: email,
      name: name ?? this.name,
      role: role,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      permissions: permissions ?? this.permissions,
      madrasaId: madrasaId ?? this.madrasaId,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AuthRepository
// ─────────────────────────────────────────────────────────────

class AuthRepository {
  final _client = SupabaseService.client;

  // ── Sign In ──────────────────────────────────────────────────

  /// Sign in with [email] + [password]. Returns [AppUser] on success.
  /// Throws [AuthenticationException] / [NetworkException] on failure.
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || password.isEmpty) {
      throw ValidationException('ای میل اور پاس ورڈ ضروری ہیں');
    }
    try {
      final response = await _client.auth.signInWithPassword(
        email: cleanEmail,
        password: password,
      );

      final user = response.user;
      if (user == null) throw AuthenticationException('لاگ ان ناکام');

      final profile = await _fetchProfile(user.id);
      return AppUser.fromSupabase(user, profile);
    } on sb.AuthException catch (e) {
      throw AuthenticationException(_mapAuthError(e.message));
    } on AuthenticationException {
      rethrow;
    } on HandshakeException {
      throw NetworkException('نیٹ ورک ہینڈشیک ناکام — برا کرم دوبارہ کوشش کریں');
    } on TlsException {
      throw NetworkException('SSL/TLS خرابی — سیکیورٹی کنکشن ناکام');
    } on SocketException {
      throw NetworkException('انٹرنیٹ کنکشن نہیں — برا کرم نیٹ ورک چیک کریں');
    } catch (e) {
      // Phase 7: ErrorHandler.logError now routes to AppLogger (file log +
      // redaction); the duplicate debugPrint is removed to avoid double logging.
      ErrorHandler.logError(e, null);
      throw AuthenticationException('لاگ ان میں خرابی');
    }
  }

  // ── Sign Out ─────────────────────────────────────────────────

  /// Sign out locally and revoke the server session.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on sb.AuthException catch (e) {
      throw AuthenticationException(_mapAuthError(e.message));
    } catch (e) {
      ErrorHandler.logError(e, null);
      // Local session is cleared by the SDK even when the server call fails;
      // don't block logout on a network error.
      AppLogger().warning('[Auth] signOut error (non-fatal)', error: e);
    }
  }

  // ── Password Reset / Account Recovery ────────────────────────

  /// Send a password-reset email via Supabase Auth.
  /// The link in the email lets the user set a new password (account recovery).
  /// Throws [ValidationException] for a blank email, [AuthenticationException]
  /// for rate-limits / unknown accounts, [NetworkException] when offline.
  Future<void> sendPasswordReset({required String email}) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw ValidationException('ای میل ضروری ہے');
    }
    try {
      await _client.auth.resetPasswordForEmail(cleanEmail);
    } on sb.AuthException catch (e) {
      throw AuthenticationException(_mapAuthError(e.message));
    } on SocketException {
      throw NetworkException('انٹرنیٹ کنکشن نہیں — برا کرم نیٹ ورک چیک کریں');
    } catch (e) {
      // Phase 7: ErrorHandler.logError now routes to AppLogger (file log +
      // redaction); the duplicate debugPrint is removed to avoid double logging.
      ErrorHandler.logError(e, null);
      throw AuthenticationException('پاس ورڈ ری سیٹ لنک بھیجنے میں خرابی');
    }
  }

  // ── Session ──────────────────────────────────────────────────

  /// The persisted Supabase session (restored automatically at app start),
  /// or null when signed out / expired.
  sb.Session? get currentSession => _client.auth.currentSession;

  /// The currently signed-in Supabase user, or null.
  sb.User? get currentUser => _client.auth.currentUser;

  /// True when a session exists (SDK auto-refreshes tokens in the background).
  bool get isSignedIn => _client.auth.currentSession != null;

  /// Force a token refresh. Throws [AuthenticationException] when the
  /// refresh token is expired/revoked — callers should then sign out.
  Future<void> refreshSession() async {
    try {
      await _client.auth.refreshSession();
    } on sb.AuthException catch (e) {
      throw AuthenticationException(_mapAuthError(e.message));
    } catch (e) {
      ErrorHandler.logError(e, null);
      throw AuthenticationException('سیشن ریفریش ناکام — دوبارہ لاگ ان کریں');
    }
  }

  /// Returns the current [AppUser] from an existing session, or null.
  Future<AppUser?> getSessionUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final profile = await _fetchProfile(user.id);
      return AppUser.fromSupabase(user, profile);
    } catch (_) {
      return null;
    }
  }

  // ── Auth State Stream ────────────────────────────────────────

  /// Emits Supabase [AuthState] events.
  /// Relevant events: SIGNED_IN, SIGNED_OUT, TOKEN_REFRESHED, USER_UPDATED.
  /// A failed background refresh surfaces as SIGNED_OUT (session expired).
  Stream<sb.AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

  // ── Helpers ──────────────────────────────────────────────────

  /// Fetch a single row from public.profiles by [userId].
  Future<Map<String, dynamic>> _fetchProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    // Profile may not exist yet (e.g. trigger hasn't run) — return empty map
    return row ?? {};
  }

  /// Convert Supabase error messages to Urdu.
  String _mapAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid email or password')) {
      return 'غلط ای میل یا پاس ورڈ';
    }
    if (lower.contains('email not confirmed')) {
      return 'ای میل کی تصدیق نہیں ہوئی';
    }
    if (lower.contains('too many requests') ||
        lower.contains('rate limit')) {
      return 'بہت زیادہ کوششیں — کچھ دیر بعد دوبارہ کوشش کریں';
    }
    if (lower.contains('user not found') ||
        lower.contains('no user found')) {
      return 'یہ اکاؤنٹ موجود نہیں';
    }
    if (lower.contains('expired') || lower.contains('invalid refresh')) {
      return 'سیشن ختم ہو گیا — دوبارہ لاگ ان کریں';
    }
    return 'لاگ ان میں خرابی';
  }
}
