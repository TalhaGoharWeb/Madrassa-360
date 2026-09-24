import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../data/repositories/auth_repository.dart';
import '../core/utils/error_handler.dart';
import '../core/services/permission_service.dart';

/// تصدیق کی حالت کا انتظام
/// Authentication State Management (Supabase)

// Re-export for convenience so screens don't need a separate import
export '../data/repositories/auth_repository.dart' show AppUser, UserRole;

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

  const AuthState({
    this.user,
    this.isLoading = false,
    this.errorMessage,
    this.isAuthenticated = false,
    this.permissions = const {},
  });

  AuthState copyWith({
    AppUser? user,
    bool? isLoading,
    String? errorMessage,
    bool? isAuthenticated,
    Set<String>? permissions,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      permissions: permissions ?? this.permissions,
    );
  }

  factory AuthState.initial() => const AuthState();

  factory AuthState.authenticated(AppUser user, Set<String> perms) =>
      AuthState(user: user, isAuthenticated: true, permissions: perms);

  factory AuthState.unauthenticated() =>
      const AuthState(isAuthenticated: false);

  factory AuthState.loading() => const AuthState(isLoading: true);

  factory AuthState.error(String message) =>
      AuthState(errorMessage: message, isAuthenticated: false);

  /// Convenience: test a permission without a provider.
  bool can(String permission) => permissions.contains(permission);
}

// ─────────────────────────────────────────────────────────────
// AuthNotifier
// ─────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(AuthState.initial()) {
    _init();
  }

  /// Listen to Supabase auth state (handles session restore + token refresh).
  void _init() {
    _repo.authStateChanges.listen((event) async {
      switch (event.event) {
        case sb.AuthChangeEvent.signedIn:
        case sb.AuthChangeEvent.tokenRefreshed:
        case sb.AuthChangeEvent.userUpdated:
          final user = await _repo.getSessionUser();
          if (user != null) {
            final perms = await PermissionService.loadForUser(
              userId: user.id,
              roleName: user.role.name,
              madrasaId: user.madrasaId,
            );
            state = AuthState.authenticated(user.copyWith(permissions: perms), perms);
          }
          break;
        case sb.AuthChangeEvent.signedOut:
          state = AuthState.unauthenticated();
          break;
        default:
          break;
      }
    });
  }

  /// Sign in with [email] + [password].
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      state = AuthState.loading();
      final user = await _repo.signIn(email: email, password: password);
      final perms = await PermissionService.loadForUser(
        userId: user.id,
        roleName: user.role.name,
        madrasaId: user.madrasaId,
      );
      final userWithPerms = user.copyWith(permissions: perms);
      state = AuthState.authenticated(userWithPerms, perms);
      return true;
    } on AuthenticationException catch (e) {
      state = AuthState.error(e.message);
      return false;
    } catch (e) {
      ErrorHandler.logError(e, null);
      state = AuthState.error('لاگ ان میں خرابی: ${e.toString()}');
      return false;
    }
  }

  /// Sign out the current user.
  Future<void> logout() async {
    try {
      await _repo.signOut();
    } catch (e) {
      ErrorHandler.logError(e, null);
    }
    state = AuthState.unauthenticated();
  }

  /// Clear a displayed error message.
  void clearError() => state = state.copyWith(errorMessage: null);
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
  return AuthNotifier(ref.read(authRepositoryProvider));
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
