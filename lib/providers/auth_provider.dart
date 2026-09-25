import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../data/repositories/auth_repository.dart';
import '../core/utils/error_handler.dart';
import '../core/services/permission_service.dart';
import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';

/// تصدیق کی حالت کا انتظام
/// Authentication State Management (Supabase) — Phase 3
///
/// Post-login routing is decided here, not in screens:
///   - 0 active memberships → [AuthRoute.noAccess]
///       (unless the user is a platform admin → [AuthRoute.home])
///   - exactly 1 membership → [AuthRoute.home] (tenant auto-selected)
///   - >1 memberships → [AuthRoute.tenantPicker]
/// Session expiry surfaces as SIGNED_OUT → route falls back to login.

// Re-export for convenience so screens don't need a separate import
export '../data/repositories/auth_repository.dart' show AppUser, UserRole;

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

  /// The resolved permission codes for the current user.
  /// Populated after login by [PermissionService.loadForUser].
  final Set<String> permissions;

  /// Where the UI should navigate after the auth state settles.
  final AuthRoute route;

  /// True when the user has a row in `platform_admins`.
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
  void _init() {
    _authSub = _repo.authStateChanges.listen((event) async {
      switch (event.event) {
        case sb.AuthChangeEvent.signedIn:
          // Full post-login wiring (idempotent — safe if login() also ran it).
          await _handleSignedIn();
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
    });
  }

  // ── Sign in ──────────────────────────────────────────────────

  /// Sign in with [email] + [password].
  /// On success wires the tenant context and computes [AuthState.route].
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      state = AuthState.loading();
      await _repo.signIn(email: email, password: password);
      // The SIGNED_IN event will also fire; _handleSignedIn is idempotent.
      await _handleSignedIn();
      return state.isAuthenticated;
    } on AppException catch (e) {
      state = AuthState.error(e.message);
      return false;
    } catch (e) {
      ErrorHandler.logError(e, null);
      state = AuthState.error('لاگ ان میں خرابی');
      return false;
    }
  }

  // ── Sign out ─────────────────────────────────────────────────

  /// Sign out: revoke the Supabase session, clear tenant context
  /// (incl. the persisted active-tenant id), and reset state.
  Future<void> logout() async {
    try {
      await _repo.signOut();
    } catch (e) {
      ErrorHandler.logError(e, null);
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
  Future<void> selectTenant(String tenantId) async {
    await _ref.read(activeTenantIdProvider.notifier).switchTenant(tenantId);
    state = state.copyWith(route: AuthRoute.home);
  }

  /// Clear a displayed error message.
  void clearError() => state = state.copyWith(errorMessage: null);

  // ── Internals ────────────────────────────────────────────────

  /// Full post-sign-in wiring: user → permissions → tenant context →
  /// memberships → platform-admin check → routing decision.
  Future<void> _handleSignedIn() async {
    try {
      final user = await _repo.getSessionUser();
      if (user == null) {
        await _handleSignedOut();
        return;
      }
      final perms = await PermissionService.loadForUser(
        userId: user.id,
        roleName: user.role.name,
        madrasaId: user.madrasaId,
      );
      final userWithPerms = user.copyWith(permissions: perms);

      // Phase 3 wiring: restore/pick the active tenant, then load memberships.
      List<TenantMembership> memberships = <TenantMembership>[];
      bool isPlatformAdmin = false;
      bool tenantLoadOk = true;
      try {
        await _ref.read(activeTenantIdProvider.notifier).init();
        memberships = await _ref.read(tenantMembershipsProvider.future);
        isPlatformAdmin = await _checkPlatformAdmin(user.id);
      } catch (e) {
        // Tenant wiring must not fail the login itself (e.g. flaky network):
        // fall back to any previously restored active tenant below.
        tenantLoadOk = false;
        ErrorHandler.logError(e, null);
      }

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
    } catch (e) {
      ErrorHandler.logError(e, null);
      state = AuthState.error('سیشن لوڈ کرنے میں خرابی');
    }
  }

  /// Lightweight refresh on TOKEN_REFRESHED / USER_UPDATED:
  /// update user + permissions, keep the current route.
  Future<void> _refreshSessionUser() async {
    try {
      final user = await _repo.getSessionUser();
      if (user == null) {
        await _handleSignedOut();
        return;
      }
      final perms = await PermissionService.loadForUser(
        userId: user.id,
        roleName: user.role.name,
        madrasaId: user.madrasaId,
      );
      state = state.copyWith(
        user: user.copyWith(permissions: perms),
        isAuthenticated: true,
        permissions: perms,
      );
    } catch (e) {
      ErrorHandler.logError(e, null);
      // Keep the existing state — a transient refresh failure must not
      // log the user out; a truly dead session arrives as SIGNED_OUT.
    }
  }

  /// Tear down everything tied to the session.
  Future<void> _handleSignedOut() async {
    try {
      _ref.invalidate(tenantMembershipsProvider);
      await _ref.read(activeTenantIdProvider.notifier).clear();
    } catch (e) {
      ErrorHandler.logError(e, null);
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
    if (memberships.length == 1) return AuthRoute.home; // auto-selected by init()
    return AuthRoute.tenantPicker;
  }

  /// True when the user has a row in `platform_admins`.
  /// Any failure (incl. RLS denial) is treated as "not a platform admin".
  Future<bool> _checkPlatformAdmin(String userId) async {
    try {
      final row = await SupabaseService.client
          .from('platform_admins')
          .select('role')
          .eq('user_id', userId)
          .maybeSingle();
      return row != null;
    } catch (e) {
      ErrorHandler.logError(e, null);
      return false;
    }
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

/// Current [UserRole], or null when signed out.
final currentUserRoleProvider = Provider<UserRole?>((ref) {
  return ref.watch(authProvider).user?.role;
});

/// The current user's set of permission codes.
final userPermissionsProvider = Provider<Set<String>>((ref) {
  return ref.watch(authProvider).permissions;
});

/// True when the signed-in user is a platform admin (`platform_admins`).
final isPlatformAdminProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isPlatformAdmin;
});

/// Returns true when the current user holds [permission].
/// Usage: `ref.watch(hasPermissionProvider('view_students'))`
final hasPermissionProvider = Provider.family<bool, String>((ref, permission) {
  return ref.watch(userPermissionsProvider).contains(permission);
});

/// Returns true when the current user holds ALL of the supplied permissions.
/// Usage: `ref.watch(hasAllPermissionsProvider({'create_students', 'edit_students'}))`
final hasAllPermissionsProvider =
    Provider.family<bool, Set<String>>((ref, required) {
  final perms = ref.watch(userPermissionsProvider);
  return required.every(perms.contains);
});
