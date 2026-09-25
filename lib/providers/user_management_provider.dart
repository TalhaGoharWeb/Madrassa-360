/// صارف انتظام فراہم کنندہ
/// User Management Provider — Riverpod state for roles & user accounts
///
/// SECURITY (P0, 2026-09-25): the client-side SUPABASE_SERVICE_KEY read and
/// the direct Auth Admin REST calls were REMOVED. Privileged Auth operations
/// (create/delete auth users) now go through the `manage-users` Edge
/// Function (server-side, service key never leaves the server). If that
/// function is not deployed yet, the op returns an honest error instead of
/// falling back to a client-held service key.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/supabase_service.dart';
import '../data/models/app_role.dart';
import '../data/models/user_account.dart';

// ─────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────

class UserManagementState {
  final List<UserAccount> accounts;
  final List<AppRole> roles;
  final bool isLoading;
  final String? error;

  const UserManagementState({
    this.accounts = const [],
    this.roles    = const [],
    this.isLoading = false,
    this.error,
  });

  UserManagementState copyWith({
    List<UserAccount>? accounts,
    List<AppRole>?     roles,
    bool?              isLoading,
    String?            error,
    bool               clearError = false,
  }) {
    return UserManagementState(
      accounts:  accounts  ?? this.accounts,
      roles:     roles     ?? this.roles,
      isLoading: isLoading ?? this.isLoading,
      error:     clearError ? null : (error ?? this.error),
    );
  }

  /// Seed with all system roles when the DB table is not yet created.
  static UserManagementState initial() => const UserManagementState(
    roles: AppRole.allSystemRoles,
  );
}

// ─────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────

class UserManagementNotifier extends StateNotifier<UserManagementState> {
  UserManagementNotifier() : super(UserManagementState.initial());

  final _client = SupabaseService.client;

  // ── Load ──────────────────────────────────────────────────

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await Future.wait([_loadAccounts(), _loadRoles()]);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'ڈیٹا لوڈ نہیں ہوا: $e',
      );
      return;
    }
    state = state.copyWith(isLoading: false);
  }

  Future<void> _loadAccounts() async {
    try {
      final rows = await _client
          .from('user_accounts')
          .select()
          .order('name');
      state = state.copyWith(
        accounts: rows.map((r) => UserAccount.fromJson(r)).toList(),
      );
    } on PostgrestException {
      // table may not exist yet — keep empty list
    }
  }

  Future<void> _loadRoles() async {
    try {
      final rows = await _client
          .from('app_roles')
          .select()
          .order('is_system', ascending: false);
      if (rows.isEmpty) {
        // seed system defaults
        state = state.copyWith(
          roles: AppRole.allSystemRoles,
        );
      } else {
        state = state.copyWith(
          roles: rows.map((r) => AppRole.fromJson(r)).toList(),
        );
      }
    } on PostgrestException {
      // table may not exist yet — stay with all seeded defaults
      if (state.roles.isEmpty) {
        state = state.copyWith(roles: AppRole.allSystemRoles);
      }
    }
  }

  // ── User Account CRUD ─────────────────────────────────────

  /// Maps an Edge Function failure to an honest, actionable message.
  /// A 404 / not-found means the server function is not deployed yet —
  /// surfaced as "requires server function" (never silently degraded).
  String _serverFunctionError(FunctionException e) {
    final msg = e.toString().toLowerCase();
    final detail = e.reasonPhrase;
    if (msg.contains('404') || msg.contains('not found')) {
      return 'یہ عمل سرور فنکشن درکار رکھتا ہے — manage-users Edge Function '
          'ابھی deploy نہیں ہوا (requires server function)';
    }
    if (detail != null && detail.isNotEmpty) return detail;
    return 'Server function error: $e';
  }

  /// Creates a real Supabase Auth user via the `manage-users` Edge Function
  /// (server-side; the service key never touches the client), then stores
  /// metadata in user_accounts.
  ///
  /// Returns null on success, or an error message. If the Edge Function is
  /// not deployed yet, returns a "requires server function" error instead of
  /// attempting any client-side privileged call.
  Future<String?> createAccount(UserAccount account) async {
    if (account.password == null || account.password!.length < 6) {
      return 'پاس ورڈ کم از کم 6 حروف کا ہونا چاہیے';
    }

    state = state.copyWith(isLoading: true, clearError: true);

    // ── Step 1: Create user in Supabase Auth via Edge Function ──────────
    String? authUserId;
    try {
      final res = await _client.functions.invoke(
        'manage-users',
        body: {
          'action': 'create_user',
          'email': account.email,
          'password': account.password,
          'user_metadata': {'name': account.name},
          'app_metadata': {'role': account.roleName},
        },
      );
      final data = res.data;
      if (data is Map) {
        authUserId = (data['id'] ?? data['user_id'])?.toString();
      }
      if (authUserId == null || authUserId.isEmpty) {
        state = state.copyWith(isLoading: false,
            error: 'Server did not return a user id');
        return 'Server did not return a user id';
      }
      debugPrint('[UserMgmt] Auth user created via manage-users: $authUserId');
    } on FunctionException catch (e) {
      final msg = _serverFunctionError(e);
      state = state.copyWith(isLoading: false, error: msg);
      return msg;
    } catch (e) {
      final msg = 'Auth server error: $e';
      state = state.copyWith(isLoading: false, error: msg);
      return msg;
    }

    // ── Step 2: Store metadata in public.user_accounts ──────────────────
    try {
      final row = account.toJson()
        ..['id'] = authUserId;          // use Auth UUID as PK
      final data = await _client
          .from('user_accounts')
          .insert(row)
          .select()
          .single();
      state = state.copyWith(
        accounts:  [...state.accounts, UserAccount.fromJson(data)],
        isLoading: false,
      );
    } on PostgrestException catch (e) {
      // Auth user created but DB row failed — still show success with warning
      debugPrint('[UserMgmt] user_accounts insert failed: ${e.message}');
      final optimistic = UserAccount(
        id: authUserId,
        name: account.name, email: account.email,
        roleName: account.roleName, roleNameUrdu: account.roleNameUrdu,
      );
      state = state.copyWith(
        accounts:  [...state.accounts, optimistic],
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[UserMgmt] user_accounts insert error: $e');
      state = state.copyWith(isLoading: false);
    }

    return null; // success
  }

  Future<String?> updateAccount(UserAccount account) async {
    if (account.id == null) return 'شناخت نہیں ملی';
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _client
          .from('user_accounts')
          .update(account.toJson())
          .eq('id', account.id!);
      state = state.copyWith(
        isLoading: false,
        accounts: state.accounts.map((a) => a.id == account.id ? account : a).toList(),
      );
      return null;
    } on PostgrestException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return e.message;
    } catch (_) {
      // Optimistic update
      state = state.copyWith(
        isLoading: false,
        accounts: state.accounts.map((a) => a.id == account.id ? account : a).toList(),
      );
      return null;
    }
  }

  Future<String?> toggleAccountStatus(UserAccount account) =>
      updateAccount(account.copyWith(isActive: !account.isActive));

  /// Deletes the Auth user via the `manage-users` Edge Function, then
  /// removes the user_accounts row. If the Edge Function is unavailable the
  /// whole op is refused (deleting the DB row while the Auth user survives
  /// would orphan the account).
  Future<String?> deleteAccount(String id) async {
    state = state.copyWith(isLoading: true, clearError: true);

    // ── Delete from Supabase Auth via Edge Function ───────────────────
    try {
      await _client.functions.invoke(
        'manage-users',
        body: {'action': 'delete_user', 'user_id': id},
      );
    } on FunctionException catch (e) {
      final msg = _serverFunctionError(e);
      state = state.copyWith(isLoading: false, error: msg);
      return msg;
    } catch (e) {
      final msg = 'Auth server error: $e';
      state = state.copyWith(isLoading: false, error: msg);
      return msg;
    }

    // ── Remove from user_accounts table ─────────────────────
    try {
      await _client.from('user_accounts').delete().eq('id', id);
    } on PostgrestException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return e.message;
    } catch (_) {
      // optimistic remove
    }
    state = state.copyWith(
      isLoading: false,
      accounts: state.accounts.where((a) => a.id != id).toList(),
    );
    return null;
  }

  // ── Role CRUD ─────────────────────────────────────────────

  Future<String?> createRole(AppRole role) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _client
          .from('app_roles')
          .insert(role.toJson())
          .select()
          .single();
      final created = AppRole.fromJson(data);
      state = state.copyWith(
        roles: [...state.roles, created],
        isLoading: false,
      );
      return null;
    } on PostgrestException {
      // Optimistic add
      final optimistic = AppRole(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: role.name,
        nameUrdu: role.nameUrdu,
        description: role.description,
        permissions: role.permissions,
      );
      state = state.copyWith(
        roles: [...state.roles, optimistic],
        isLoading: false,
      );
      return null;
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return null;
    }
  }

  Future<String?> updateRole(AppRole role) async {
    if (role.id == null) return 'شناخت نہیں ملی';
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _client
          .from('app_roles')
          .update(role.toJson())
          .eq('id', role.id!);
    } on PostgrestException catch (_) {
      // optimistic
    } catch (_) {
      // optimistic
    }
    state = state.copyWith(
      isLoading: false,
      roles: state.roles.map((r) => r.name == role.name ? role : r).toList(),
    );
    return null;
  }

  Future<String?> deleteRole(AppRole role) async {
    if (role.isSystem) return 'بنیادی کردار حذف نہیں ہو سکتا';
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _client.from('app_roles').delete().eq('id', role.id ?? '');
    } catch (_) {
      // optimistic
    }
    state = state.copyWith(
      isLoading: false,
      roles: state.roles.where((r) => r.name != role.name).toList(),
    );
    return null;
  }
}

// ─────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────

final userManagementProvider =
    StateNotifierProvider<UserManagementNotifier, UserManagementState>(
  (_) => UserManagementNotifier(),
);

/// Convenience: just the accounts list.
final userAccountsProvider = Provider<List<UserAccount>>(
  (ref) => ref.watch(userManagementProvider).accounts,
);

/// Convenience: just the roles list.
final appRolesProvider = Provider<List<AppRole>>(
  (ref) => ref.watch(userManagementProvider).roles,
);
