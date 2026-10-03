import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../data/repositories/auth_repository.dart';
import '../data/delegation_repository.dart';
import '../core/errors/app_exceptions.dart';
import '../core/errors/error_boundary.dart';
import '../core/security/secure_wipe.dart';
import '../core/services/authorization_service.dart';
import '../core/services/permission_service.dart';
import '../core/services/role_service.dart';
import '../core/services/storage_service.dart';
import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';

// Re-export for convenience so screens don't need a separate import.
// (Directives must precede all declarations in this file.)
export '../data/repositories/auth_repository.dart' show AppUser, UserRole;

// ─────────────────────────────────────────────────────────────
// "Remember me" contract (login screen ⇄ auth gate ⇄ cold start)
//
// The Supabase SDK persists the session on-device by default; the auth
// gate restores it on cold start so the user is not asked for credentials
// every launch. The checkbox on the login screen controls this:
//
//   auth_remember_me = true   (default) → restore the session on next launch
//   auth_remember_me = false            → sign the persisted session out on
//                                          next launch and show the login form
//
// Only the e-mail is ever remembered in prefs — never the password.
// OS-level password autofill is enabled via autofillHints on the fields.
// ─────────────────────────────────────────────────────────────

/// Whether the last login asked to stay signed in across restarts.
const kRememberMeKey = 'auth_remember_me';

/// E-mail to pre-fill on the login form (saved only when remembered).
const kRememberedEmailKey = 'auth_remembered_email';

/// Last signed-in user id — used to detect an account switch without a
/// clean sign-out first (SEC-H12 backstop: wipe before wiring the new user).
const kLastUserIdKey = 'auth_last_user_id';

/// Consecutive failed login attempts (progressive client-side backoff).
const kLoginFailCountKey = 'auth_login_fail_count';
const kLoginFailAtKey = 'auth_login_fail_at_ms';

/// تصدیق کی حالت کا انتظام
/// Authentication State Management (Supabase) — Phase 3
///
/// Post-login routing is decided here, not in screens:
///   - 0 active memberships → [AuthRoute.noAccess]
///       (unless the user is a platform admin → [AuthRoute.home])
///   - exactly 1 membership → [AuthRoute.home] (tenant auto-selected)
///   - >1 memberships → [AuthRoute.tenantPicker]
/// Session expiry surfaces as SIGNED_OUT → route falls back to login.

// ─────────────────────────────────────────────────────────────
// AuthRoute — post-login routing decision
// ─────────────────────────────────────────────────────────────

enum AuthRoute {
  /// Not signed in — show the login screen.
  login,

  /// Signed in but the account has no institution access.
  noAccess,

  /// Signed in with several institutions — let the user pick one.
  tenantPicker,

  /// Signed in with an active tenant (or platform admin) — go to the app.
  home,
}

// ─────────────────────────────────────────────────────────────
// AuthState
// ─────────────────────────────────────────────────────────────

class AuthState {
  final AppUser? user;
  final bool isLoading;
  final String? errorMessage;
  final bool isAuthenticated;

  /// The resolved permission codes for the ACTIVE tenant.
  /// Populated at sign-in and reloaded on every tenant switch by
  /// [AuthorizationService] (via `get_my_permissions_detailed`).
  final Set<String> permissions;

  /// Where the UI should navigate after the auth state settles.
  final AuthRoute route;

  /// True when the user has a row in `platform_admins` or `super_admins`.
  /// Platform admins with zero tenant memberships still get [AuthRoute.home]
  /// (master admin area) instead of [AuthRoute.noAccess].
  final bool isPlatformAdmin;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.errorMessage,
    this.isAuthenticated = false,
    this.permissions = const {},
    this.route = AuthRoute.login,
    this.isPlatformAdmin = false,
  });

  AuthState copyWith({
    AppUser? user,
    bool? isLoading,
    String? errorMessage,
    bool? isAuthenticated,
    Set<String>? permissions,
    AuthRoute? route,
    bool? isPlatformAdmin,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      permissions: permissions ?? this.permissions,
      route: route ?? this.route,
      isPlatformAdmin: isPlatformAdmin ?? this.isPlatformAdmin,
    );
  }

  factory AuthState.initial() => const AuthState();

  factory AuthState.authenticated(
    AppUser user,
    Set<String> perms, {
    AuthRoute route = AuthRoute.home,
    bool isPlatformAdmin = false,
  }) =>
      AuthState(
        user: user,
        isAuthenticated: true,
        permissions: perms,
        route: route,
        isPlatformAdmin: isPlatformAdmin,
      );

  factory AuthState.unauthenticated() =>
      const AuthState(isAuthenticated: false, route: AuthRoute.login);

  factory AuthState.loading() =>
      const AuthState(isLoading: true, route: AuthRoute.login);

  factory AuthState.error(String message) => AuthState(
        errorMessage: message,
        isAuthenticated: false,
        route: AuthRoute.login,
      );

  /// Convenience: test a permission without a provider.
  bool can(String permission) => permissions.contains(permission);
}

// ─────────────────────────────────────────────────────────────
// AuthNotifier
// ─────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;
  late final AuthRepository _repo;
  StreamSubscription<sb.AuthState>? _authSub;

  AuthNotifier(this._ref) : super(AuthState.initial()) {
    _repo = _ref.read(authRepositoryProvider);
    _init();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Listen to Supabase auth state.
  /// Handles: cold-start session restore (SIGNED_IN fires on restore),
  /// token refresh, and session expiry (failed refresh → SIGNED_OUT).
  ///
  /// The stream can also carry ERRORS: gotrue reports a failed background
  /// token refresh (e.g. no DNS / no internet at launch) via
  /// [Stream.addError] on its broadcast auth-state stream. Without an
  /// [onError] handler such an error becomes an unhandled async error and
  /// crashes the app to the CrashScreen — even though the persisted
  /// session is still perfectly usable offline. The handler below logs
  /// the failure and keeps the existing state; a truly dead session
  /// still arrives as a SIGNED_OUT event.
  void _init() {
    _authSub = _repo.authStateChanges.listen(
      (event) async {
        switch (event.event) {
          case sb.AuthChangeEvent.signedIn:
            // Full post-login wiring (idempotent — safe if login() also ran it).
            await _handleSignedIn();
            break;
          case sb.AuthChangeEvent.passwordRecovery:
            // Recovery link opened: the SDK established a recovery session.
            // Show the set-new-password screen instead of normal post-login
            // routing (SEC-H13).
            _ref.read(passwordRecoveryModeProvider.notifier).state = true;
            break;
          case sb.AuthChangeEvent.tokenRefreshed:
          case sb.AuthChangeEvent.userUpdated:
            // Session still valid — just refresh the user/permissions.
            await _refreshSessionUser();
            break;
          case sb.AuthChangeEvent.signedOut:
            // Includes expired/revoked refresh tokens.
            await _handleSignedOut();
            break;
          default:
            break;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // Transient auth-infrastructure failure (DNS down, captive portal,
        // failed background token refresh). Must not sign the user out and
        // must not crash: the SDK retries the refresh on its next tick.
        ErrorBoundary.handleErrorSimple(
          error,
          stackTrace,
          tag: 'auth/state-stream',
        );
      },
    );
  }

  // ── Cold-start session restore ───────────────────────────────

  /// Restore a persisted Supabase session on app launch (called once by
  /// the auth gate). Honors the "remember me" choice made at login:
  /// when the user unchecked it, the persisted session is signed out
  /// instead of restored, so the next launch shows the login form.
  Future<void> restoreSession() async {
    try {
      final remember =
          StorageService.getBool(kRememberMeKey, defaultValue: true) ?? true;
      if (!remember) {
        await _repo.signOut();
        await _handleSignedOut();
        return;
      }
      if (_repo.isSignedIn) {
        // The SIGNED_IN event may also fire for the restored session;
        // _handleSignedIn is idempotent.
        await _handleSignedIn();
      } else {
        await _handleSignedOut();
      }
    } catch (e, st) {
      ErrorBoundary.handleErrorSimple(e, st, tag: 'auth/restore-session');
      await _handleSignedOut();
    }
  }

  // ── Sign in ──────────────────────────────────────────────────

  /// Sign in with [email] + [password].
  /// On success wires the tenant context and computes [AuthState.route].
  ///
  /// Progressive client-side backoff (SEC-H8): after consecutive failures
  /// the attempt is delayed locally (2s, 4s, 8s … capped at 30s) to slow
  /// credential-stuffing without punishing legitimate typos.
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      state = AuthState.loading();
      final wait = await _loginBackoffDelay();
      if (wait > Duration.zero) {
        state = AuthState.error(
          'بہت زیادہ ناکام کوششیں — براہ کرم ${wait.inSeconds} سیکنڈ بعد دوبارہ کوشش کریں',
        );
        return false;
      }
      await _repo.signIn(email: email, password: password);
      await _recordLoginSuccess();
      // The SIGNED_IN event will also fire; _handleSignedIn is idempotent.
      await _handleSignedIn();
      return state.isAuthenticated;
    } on AppException catch (e, st) {
      // Phase 7: classify (already typed) + log + health counter via the
      // error boundary; the returned message is the same safe Urdu string.
      await _recordLoginFailure();
      final message = ErrorBoundary.handleErrorSimple(e, st, tag: 'auth/login');
      state = AuthState.error(message);
      return false;
    } catch (e, st) {
      await _recordLoginFailure();
      final message = ErrorBoundary.handleErrorSimple(e, st, tag: 'auth/login');
      state = AuthState.error(message);
      return false;
    }
  }

  /// Seconds to wait before the next login attempt given [failures]
  /// consecutive failures. Pure function — unit-tested.
  /// 0-1 failures → no delay; then 2, 4, 8, 16, capped at 30.
  static int backoffSecondsForFailures(int failures) {
    if (failures < 2) return 0;
    // Cap the exponent before shifting: 2^5 = 32 already exceeds the cap,
    // and shifting by >= 64 is undefined/0 on 64-bit ints.
    if (failures > 6) return 30;
    var delay = 1 << (failures - 1); // 2, 4, 8, 16, 32
    if (delay > 30) delay = 30;
    return delay;
  }

  /// Returns the remaining wait before another attempt is allowed, or
  /// [Duration.zero] when the user may try immediately.
  Future<Duration> _loginBackoffDelay() async {
    try {
      final failures = StorageService.getInt(kLoginFailCountKey) ?? 0;
      final delaySecs = backoffSecondsForFailures(failures);
      if (delaySecs <= 0) return Duration.zero;
      final lastAt = StorageService.getInt(kLoginFailAtKey) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastAt;
      final remaining = delaySecs * 1000 - elapsed;
      return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
    } catch (_) {
      return Duration.zero;
    }
  }

  Future<void> _recordLoginFailure() async {
    try {
      final failures = (StorageService.getInt(kLoginFailCountKey) ?? 0) + 1;
      await StorageService.saveInt(kLoginFailCountKey, failures);
      await StorageService.saveInt(
          kLoginFailAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {/* best effort */}
  }

  Future<void> _recordLoginSuccess() async {
    try {
      await StorageService.remove(kLoginFailCountKey);
      await StorageService.remove(kLoginFailAtKey);
    } catch (_) {/* best effort */}
  }

  // ── Sign out ─────────────────────────────────────────────────

  /// Sign out: revoke the Supabase session, clear tenant context
  /// (incl. the persisted active-tenant id), and reset state.
  Future<void> logout() async {
    try {
      await _repo.signOut();
    } catch (e, st) {
      ErrorBoundary.handleErrorSimple(e, st, tag: 'auth/logout');
    } finally {
      // SIGNED_OUT event will also fire; _handleSignedOut is idempotent.
      await _handleSignedOut();
    }
  }

  // ── Password reset / account recovery ────────────────────────

  /// Send a password-reset email. Throws typed [AppException]s —
  /// the caller (forgot-password screen) shows the message.
  Future<void> sendPasswordReset(String email) =>
      _repo.sendPasswordReset(email: email);

  // ── Tenant selection (multi-tenant users) ────────────────────

  /// Switch to [tenantId] and move the route to [AuthRoute.home].
  /// [TenantContext.switchTenant] persists the choice and reloads the
  /// effective permission set for the new tenant (Phase 5).
  Future<void> selectTenant(String tenantId) async {
    await _ref.read(activeTenantIdProvider.notifier).switchTenant(tenantId);
    state = state.copyWith(route: AuthRoute.home);
  }

  /// Re-loads the effective permission set for the current active tenant
  /// into [AuthState.permissions]. Called after tenant switches and on
  /// session refreshes. No-op when signed out or when no tenant is active.
  Future<void> refreshPermissions() async {
    final tenantId = _ref.read(activeTenantIdProvider);
    final user = state.user;
    if (tenantId == null || user == null) return;
    List<TenantMembership> memberships = <TenantMembership>[];
    try {
      memberships = await _ref.read(tenantMembershipsProvider.future);
    } catch (_) {
      // Offline: fall through with no memberships — AuthorizationService
      // falls back to the persisted cache / static role defaults.
    }
    final perms = await _loadPermissionsForActiveTenant(
      tenantId: tenantId,
      memberships: memberships,
      isPlatformAdmin: state.isPlatformAdmin,
    );
    if (!mounted) return;
    state = state.copyWith(
      permissions: perms,
      user: user.copyWith(permissions: perms),
    );
  }

  /// Clear a displayed error message.
  void clearError() => state = state.copyWith(errorMessage: null);

  // ── Internals ────────────────────────────────────────────────

  /// Full post-sign-in wiring: user → tenant context → permissions →
  /// memberships → platform-admin check → routing decision.
  ///
  /// Permissions are loaded AFTER the tenant context is initialized and
  /// are scoped to the active tenant (Phase 5 — audit §C3).
  Future<void> _handleSignedIn() async {
    try {
      final user = await _repo.getSessionUser();
      if (user == null) {
        await _handleSignedOut();
        return;
      }

      // SEC-H12 backstop: if a *different* user signed in without a clean
      // sign-out first (app killed, session expired), wipe the previous
      // tenant's offline data before wiring the new session.
      final lastUserId = StorageService.getString(kLastUserIdKey);
      if (lastUserId != null && lastUserId != user.id) {
        await SecureWipe.wipeOnSignOut(_ref);
      }
      await StorageService.saveString(kLastUserIdKey, user.id);

      // SEC-M26: proactively refuse deactivated accounts on session
      // establish (restore or fresh login). Best-effort: on network/RLS
      // failure we keep the session (offline tolerance) — a server-side
      // ban still kills the session at the next token refresh.
      final active = await _checkAccountActive(user.id);
      if (active == false) {
        // Local-only sign-out: the server session is already dead for
        // banned users (or dies at the next refresh). Going through the
        // SDK's signOut() would emit SIGNED_OUT asynchronously and race
        // the error message below, so the persisted session is removed
        // directly and _handleSignedOut() runs exactly once here.
        await SupabaseService.authStorage?.removePersistedSession();
        await _handleSignedOut();
        state = AuthState.error(
          'آپ کا اکاؤنٹ غیر فعال کر دیا گیا ہے — براہ کرم منتظم سے رابطہ کریں',
        );
        return;
      }

      // Phase 3 wiring: restore/pick the active tenant, then load memberships.
      List<TenantMembership> memberships = <TenantMembership>[];
      bool isPlatformAdmin = false;
      bool tenantLoadOk = true;
      try {
        // Drop any cached membership list (e.g. the empty list cached while
        // signed out) so the reads below use the just-established session.
        // Without this, a stale [] survived into the routing decision and
        // every tenant user landed on NoAccessScreen.
        _ref.invalidate(tenantMembershipsProvider);
        await _ref.read(activeTenantIdProvider.notifier).init();
        memberships = await _ref.read(tenantMembershipsProvider.future);
        isPlatformAdmin = await _checkPlatformAdmin(user.id);
      } catch (e, st) {
        // Tenant wiring must not fail the login itself (e.g. flaky network):
        // fall back to any previously restored active tenant below.
        tenantLoadOk = false;
        ErrorBoundary.handleErrorSimple(e, st, tag: 'auth/tenant-wiring');
      }

      final tenantId = _ref.read(activeTenantIdProvider);
      final perms = await _loadPermissionsForActiveTenant(
        tenantId: tenantId,
        memberships: memberships,
        isPlatformAdmin: isPlatformAdmin,
      );
      final userWithPerms = user.copyWith(permissions: perms);

      final route = _resolveRoute(
        memberships: memberships,
        isPlatformAdmin: isPlatformAdmin,
        tenantLoadOk: tenantLoadOk,
      );

      state = AuthState.authenticated(
        userWithPerms,
        perms,
        route: route,
        isPlatformAdmin: isPlatformAdmin,
      );
    } catch (e, st) {
      final message =
          ErrorBoundary.handleErrorSimple(e, st, tag: 'auth/session-load');
      state = AuthState.error(message);
    }
  }

  /// Loads the effective permission set for [tenantId] via
  /// [AuthorizationService] (server RPC → offline cache → static fallback).
  /// Returns an empty set when no tenant is active.
  Future<Set<String>> _loadPermissionsForActiveTenant({
    required String? tenantId,
    required List<TenantMembership> memberships,
    required bool isPlatformAdmin,
  }) async {
    if (tenantId == null) return <String>{};
    final roleKey = _roleKeyForTenant(
      memberships: memberships,
      tenantId: tenantId,
      isPlatformAdmin: isPlatformAdmin,
    );
    return _ref
        .read(authorizationServiceProvider)
        .ensureLoaded(tenantId, roleKey: roleKey);
  }

  /// The `tenant_memberships.role` key for [tenantId]. Used ONLY to pick the
  /// static offline fallback — it is never sent to the server as authority.
  String _roleKeyForTenant({
    required List<TenantMembership> memberships,
    required String tenantId,
    required bool isPlatformAdmin,
  }) {
    for (final m in memberships) {
      if (m.tenantId == tenantId && m.isActive) return m.role;
    }
    // Platform admins may operate without a membership row.
    if (isPlatformAdmin) return 'platform_owner';
    return '';
  }

  /// Lightweight refresh on TOKEN_REFRESHED / USER_UPDATED:
  /// update user + permissions, keep the current route.
  ///
  /// SEC-L34: platform-admin status is re-verified here (not just at
  /// sign-in) so a revoked admin loses console access at the next refresh.
  /// The check is tri-state: on network/RLS failure the previous value is
  /// kept (offline tolerance) — only a definitive "not admin" demotes.
  Future<void> _refreshSessionUser() async {
    try {
      final user = await _repo.getSessionUser();
      if (user == null) {
        await _handleSignedOut();
        return;
      }
      final adminStatus = await _checkPlatformAdminTriState(user.id);
      // AuthorizationService serves the in-memory set when the tenant has
      // not changed, so this stays cheap on every token refresh.
      await refreshPermissions();
      state = state.copyWith(
        user: user.copyWith(permissions: state.permissions),
        isAuthenticated: true,
        isPlatformAdmin: adminStatus ?? state.isPlatformAdmin,
      );
    } catch (e, st) {
      ErrorBoundary.handleErrorSimple(e, st, tag: 'auth/session-refresh');
      // Keep the existing state — a transient refresh failure must not
      // log the user out; a truly dead session arrives as SIGNED_OUT.
    }
  }

  /// Tear down everything tied to the session.
  Future<void> _handleSignedOut() async {
    final userId = state.user?.id;
    try {
      // Phase 5: drop in-memory authorization state and this user's
      // persisted offline permission cache (keyed per user, so a later
      // device user can never read it).
      _ref.read(authorizationServiceProvider).clearCache();
      _ref.read(roleServiceProvider).clearCache();
      if (userId != null) {
        await PermissionService.clearPersistedCache(userId);
        // Phase 8b: drop this user's cached delegation lists too.
        await DelegationRepository.clearDelegationCache(userId);
      }
      _ref.invalidate(tenantMembershipsProvider);
      await _ref.read(activeTenantIdProvider.notifier).clear();
    } catch (e, st) {
      ErrorBoundary.handleErrorSimple(e, st, tag: 'auth/signout-cleanup');
    }
    // SEC-H12: the offline database holds the tenant's full synced dataset —
    // close it, delete the file (+ WAL/SHM), clear caches and preferences so
    // the next device user inherits nothing. Never blocks the sign-out.
    try {
      await SecureWipe.wipeOnSignOut(_ref);
      await StorageService.remove(kLastUserIdKey);
    } catch (e, st) {
      ErrorBoundary.handleErrorSimple(e, st, tag: 'auth/signout-wipe');
    }
    state = AuthState.unauthenticated();
  }

  /// Routing decision per the multi-tenant spec.
  AuthRoute _resolveRoute({
    required List<TenantMembership> memberships,
    required bool isPlatformAdmin,
    required bool tenantLoadOk,
  }) {
    if (memberships.isEmpty) {
      if (isPlatformAdmin) return AuthRoute.home; // master admin route
      if (!tenantLoadOk) {
        // Tenant list failed to load (e.g. offline): if a tenant was
        // previously restored, let the user in rather than locking them out.
        final restored = _ref.read(activeTenantIdProvider);
        if (restored != null) return AuthRoute.home;
      }
      return AuthRoute.noAccess;
    }
    if (memberships.length == 1) {
      return AuthRoute.home; // auto-selected by init()
    }
    return AuthRoute.tenantPicker;
  }

  /// True when the user has a row in `platform_admins` or `super_admins`.
  /// Any failure (incl. RLS denial) is treated as "not a platform admin".
  Future<bool> _checkPlatformAdmin(String userId) async {
    return (await _checkPlatformAdminTriState(userId)) ?? false;
  }

  /// Tri-state platform-admin check: true/false on a definitive answer,
  /// null when the check itself failed (network/RLS) so callers can keep
  /// the previous value instead of demoting offline users (SEC-L34).
  Future<bool?> _checkPlatformAdminTriState(String userId) async {
    try {
      final adminRow = await SupabaseService.client
          .from('platform_admins')
          .select('role')
          .eq('user_id', userId)
          .maybeSingle();
      if (adminRow != null) return true;
      // Super admins (public.super_admins, migration 023) are platform
      // admins even without a platform_admins row — the old query missed
      // them, so a super admin silently landed on a tenant dashboard.
      final superRow = await SupabaseService.client
          .from('super_admins')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();
      return superRow != null;
    } catch (e, st) {
      ErrorBoundary.handleErrorSimple(e, st, tag: 'auth/platform-admin-check');
      return null;
    }
  }

  /// SEC-M26: is this account still active? Reads `user_accounts.is_active`
  /// (the row the `set_active` Edge Function action maintains). Returns
  /// null when the check cannot be performed (offline/RLS) — callers keep
  /// the session in that case; only a definitive `false` signs out.
  Future<bool?> _checkAccountActive(String userId) async {
    try {
      final row = await SupabaseService.client
          .from('user_accounts')
          .select('is_active')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null; // no row yet — not our call to judge
      return (row['is_active'] as bool?) ?? true;
    } catch (e, st) {
      ErrorBoundary.handleErrorSimple(e, st, tag: 'auth/account-active-check');
      return null;
    }
  }

  /// Leaves password-recovery mode (after the new password is set or the
  /// flow is abandoned) so the auth gate returns to normal routing.
  void completePasswordRecovery() {
    _ref.read(passwordRecoveryModeProvider.notifier).state = false;
  }
}

// ─────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────

/// Repository provider — single instance shared across the app.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// Main auth state provider.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

/// True while the app is in password-recovery mode: the user arrived via a
/// recovery link (PASSWORD_RECOVERY event) and must set a new password
/// before normal routing resumes (SEC-H13).
final passwordRecoveryModeProvider = StateProvider<bool>((ref) => false);

/// The post-login routing decision (login / noAccess / tenantPicker / home).
final authRouteProvider = Provider<AuthRoute>((ref) {
  return ref.watch(authProvider).route;
});

/// true when a valid session exists.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

/// Current [AppUser], or null when signed out.
final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authProvider).user;
});

// ─────────────────────────────────────────────────────────────
// Display name contract (profile screen ⇄ shell chips ⇄ dashboards)
//
// The profile screen persists the user's chosen name locally
// (SharedPreferences key [kLocalProfileNameKey]) — it is the name the
// user typed themselves, so it wins over everything else.
// [AppUser.name] falls back to the login email when the Supabase
// `profiles` row has no name; an email address must never be shown
// as a person's name, so email-like values are treated as "no name".
// ─────────────────────────────────────────────────────────────

/// SharedPreferences key for the locally-edited profile display name.
const kLocalProfileNameKey = 'profile_name';

/// The local profile display name, seeded from SharedPreferences at
/// startup (see main.dart's ProviderScope override) and updated by the
/// profile screen on save so every chip/greeting refreshes immediately.
final localProfileNameProvider = StateProvider<String>((ref) => '');

/// Resolved display name for UI: local profile edit first, then the
/// Supabase profile name (never an email address), then [fallback]
/// (e.g. 'مہمان') when nothing real is known.
final displayNameProvider = Provider.family<String, String>((ref, fallback) {
  final local = ref.watch(localProfileNameProvider).trim();
  if (local.isNotEmpty) return local;
  final authName = (ref.watch(currentUserProvider)?.name ?? '').trim();
  if (authName.isNotEmpty && !authName.contains('@')) return authName;
  return fallback;
});

/// Current [UserRole], or null when signed out.
final currentUserRoleProvider = Provider<UserRole?>((ref) {
  return ref.watch(authProvider).user?.role;
});

/// The current user's effective permission set for the ACTIVE tenant.
/// Watches [authProvider]; reloaded by [AuthorizationService] at sign-in,
/// on tenant switches, and on session refreshes (Phase 5).
final userPermissionsProvider = Provider<Set<String>>((ref) {
  return ref.watch(authProvider).permissions;
});

/// True when the signed-in user is a platform admin (`platform_admins`).
final isPlatformAdminProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isPlatformAdmin;
});

/// Returns true when the current user holds [permission] in the ACTIVE tenant.
/// Usage: `ref.watch(hasPermissionProvider('students.view'))`
final hasPermissionProvider = Provider.family<bool, String>((ref, permission) {
  return ref.watch(userPermissionsProvider).contains(permission);
});

/// Returns true when the current user holds ALL of the supplied permissions
/// in the ACTIVE tenant.
/// Usage: `ref.watch(hasAllPermissionsProvider({'students.create', 'students.edit'}))`
final hasAllPermissionsProvider =
    Provider.family<bool, Set<String>>((ref, required) {
  final perms = ref.watch(userPermissionsProvider);
  return required.every(perms.contains);
});
