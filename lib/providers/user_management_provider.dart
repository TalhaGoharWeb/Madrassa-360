/// صارف انتظام فراہم کنندہ
/// User Management Provider — Riverpod state for roles & user accounts

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
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

  /// Creates a real Supabase Auth user then stores metadata in user_accounts.
  Future<String?> createAccount(UserAccount account) async {
    if (account.password == null || account.password!.length < 6) {
      return 'پاس ورڈ کم از کم 6 حروف کا ہونا چاہیے';
    }

    state = state.copyWith(isLoading: true, clearError: true);

    // ── Step 1: Create user in Supabase Auth via Admin REST API ─────────
    String? authUserId;
    try {
      final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
      final serviceKey  = dotenv.env['SUPABASE_SERVICE_KEY'] ?? '';

      if (serviceKey.isEmpty || serviceKey.startsWith('paste-')) {
        state = state.copyWith(isLoading: false,
            error: 'SUPABASE_SERVICE_KEY .env میں شامل کریں');
        return 'SUPABASE_SERVICE_KEY .env میں شامل کریں';
      }

      final uri = Uri.parse('$supabaseUrl/auth/v1/admin/users');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type':  'application/json',
          'apikey':        serviceKey,
          'Authorization': 'Bearer $serviceKey',
        },
        body: jsonEncode({
          'email':         account.email,
          'password':      account.password,
          'email_confirm': true,          // skip confirmation email
          'user_metadata': {'name': account.name},
          'app_metadata':  {'role': account.roleName},
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final msg  = body['msg'] as String? ??
                     body['message'] as String? ??
                     body['error_description'] as String? ??
                     'Auth خرابی (${response.statusCode})';
        state = state.copyWith(isLoading: false, error: msg);
        return msg;
      }

      final created = jsonDecode(response.body) as Map<String, dynamic>;
      authUserId = created['id'] as String?;
      debugPrint('[UserMgmt] Auth user created: $authUserId');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Auth API خرابی: $e');
      return 'Auth API خرابی: $e';
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

  Future<String?> deleteAccount(String id) async {
    state = state.copyWith(isLoading: true, clearError: true);

    // ── Delete from Supabase Auth first ─────────────────────
    try {
      final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
      final serviceKey  = dotenv.env['SUPABASE_SERVICE_KEY'] ?? '';
      if (serviceKey.isNotEmpty && !serviceKey.startsWith('paste-')) {
        final uri = Uri.parse('$supabaseUrl/auth/v1/admin/users/$id');
        await http.delete(uri, headers: {
          'apikey':        serviceKey,
          'Authorization': 'Bearer $serviceKey',
        });
      }
    } catch (e) {
      debugPrint('[UserMgmt] Auth delete failed: $e');
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
