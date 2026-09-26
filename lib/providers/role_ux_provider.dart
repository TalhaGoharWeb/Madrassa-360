/// صارف انتظام فراہم کنندگان (Phase 8a)
/// Riverpod wiring for the 8a user-management flows: list providers plus a
/// [RoleUxController] that runs every write through the real RPCs / Edge
/// Function and maps failures to plain Urdu.
///
/// The repository behind [roleUxRepositoryProvider] is overridable, so
/// widget tests never touch Supabase.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/observability/app_logger.dart';
import '../core/services/tenant_context.dart';
import '../data/role_ux_repository.dart';
import 'auth_provider.dart';

// ─────────────────────────────────────────────────────────────
// Repository + read providers
// ─────────────────────────────────────────────────────────────

/// Overridable in tests with a stub — production uses the real Supabase
/// implementation (real RPCs only, no mock data).
final roleUxRepositoryProvider = Provider<RoleUxRepository>((ref) {
  return SupabaseRoleUxRepository();
});

/// Users of the active tenant, filtered by [search] (name / role).
final tenantUsersProvider =
    FutureProvider.autoDispose.family<List<TenantUser>, String>(
        (ref, search) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  return ref
      .read(roleUxRepositoryProvider)
      .listUsers(tenantId, search: search.isEmpty ? null : search);
});

/// Tenant roles with their live permission codes.
final tenantRolesUxProvider =
    FutureProvider.autoDispose<List<TenantRoleInfo>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return const [];
  return ref.read(roleUxRepositoryProvider).listRoles(tenantId);
});

/// Full permission catalog (Urdu labels from the DB, 019-seeded).
final permissionCatalogProvider =
    FutureProvider.autoDispose<List<PermissionInfo>>((ref) async {
  return ref.read(roleUxRepositoryProvider).permissionCatalog();
});

/// Invalidate every 8a list (call after any write).
void invalidateRoleUxLists(Ref ref) {
  ref.invalidate(tenantUsersProvider);
  ref.invalidate(tenantRolesUxProvider);
}

// ─────────────────────────────────────────────────────────────
// Controller — all writes go through here
// ─────────────────────────────────────────────────────────────

class RoleUxController extends StateNotifier<AsyncValue<void>> {
  RoleUxController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  RoleUxRepository get _repo => _ref.read(roleUxRepositoryProvider);
  String? get _tenantId => _ref.read(currentTenantIdProvider);
  String? get _selfId => _ref.read(currentUserProvider)?.id;

  /// Runs [op], mapping any failure to plain Urdu. Returns null on
  /// success, otherwise the Urdu message. Refreshes the lists on success.
  Future<String?> _run(Future<void> Function() op) async {
    state = const AsyncValue.loading();
    try {
      await op();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      AppLogger().warning('[RoleUx] write failed', error: e);
      if (e is _UrduRefusal) return e.message;
      return roleUxErrorMessage(e);
    }
    invalidateRoleUxLists(_ref);
    state = const AsyncValue.data(null);
    return null;
  }

  /// Principal-safety pre-check before disabling / demoting [user].
  /// Returns a plain-Urdu refusal, or null when the action may proceed.
  /// A null [SafetyCheck] (edge function not redeployed) means "proceed —
  /// the server backstops will refuse with an honest mapped error".
  Future<String?> _safetyRefusal(
    TenantUser user, {
    required bool disabling,
    required String newRoleKey,
    required Set<String> assignHolderKeys,
  }) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'مدرسہ منتخب نہیں ہے۔';
    if (user.id == _selfId && disabling) {
      return 'آپ اپنا اکاؤنٹ خود غیر فعال نہیں کر سکتے۔';
    }
    final check = await _repo.safetyCheck(tenantId: tenantId, userId: user.id);
    if (check == null) return null;
    if (disabling && check.isLastOwner) {
      return 'یہ مدرسے کا واحد مالک ہے — پہلے کسی اور کو مالک بنائیں، پھر غیر فعال کریں۔';
    }
    final demotingOwner =
        !disabling && user.roleKey == 'tenant_owner' && newRoleKey != 'tenant_owner';
    if (demotingOwner && check.isLastOwner) {
      return 'یہ مدرسے کا واحد مالک ہے — پہلے کسی اور کو مالک بنائیں، پھر ذمہ داری تبدیل کریں۔';
    }
    // Demoting the last roles.assign holder would lock role management.
    final losingAssign = !disabling &&
        check.isLastAssignHolder &&
        !assignHolderKeys.contains(newRoleKey);
    if (losingAssign) {
      return 'یہ واحد صارف ہے جو ذمہ داریاں سونپ سکتا ہے — پہلے کسی اور کو یہ اختیار دیں، پھر ذمہ داری تبدیل کریں۔';
    }
    return null;
  }

  /// (De)activates one user (edge `set_active`), with principal safety.
  Future<String?> setUserActive(TenantUser user, bool active) {
    return _run(() async {
      final refusal = await _safetyRefusal(
        user,
        disabling: !active,
        newRoleKey: user.roleKey,
        assignHolderKeys: const {},
      );
      if (refusal != null) throw _UrduRefusal(refusal);
      await _repo.setActive(userId: user.id, active: active);
    });
  }

  /// Changes one user's role (RPC `assign_tenant_role`), with principal safety.
  Future<String?> assignUserRole(
    TenantUser user,
    String roleKey,
    Set<String> assignHolderKeys,
  ) {
    return _run(() async {
      if (roleKey == user.roleKey) return;
      final refusal = await _safetyRefusal(
        user,
        disabling: false,
        newRoleKey: roleKey,
        assignHolderKeys: assignHolderKeys,
      );
      if (refusal != null) throw _UrduRefusal(refusal);
      final tenantId = _tenantId!;
      await _repo.assignRole(
          tenantId: tenantId, userId: user.id, roleKey: roleKey);
    });
  }

  /// Full create flow for the wizard:
  /// edge `create_user` -> RPC `assign_tenant_role` -> user permission
  /// overrides -> permission_scopes. Best-effort rollback of the auth user
  /// when the role assignment fails.
  /// Returns (userId, null) on success or (null, urduError).
  Future<({String? userId, String? error})> createUserFull({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String roleKey,
    required Set<String> templateCodes,
    required Set<String> selectedCodes,
    required Set<String> scopeCodes,
    required ScopeSelection scope,
  }) async {
    state = const AsyncValue.loading();
    final tenantId = _tenantId;
    if (tenantId == null) {
      state = const AsyncValue.data(null);
      return (userId: null, error: 'مدرسہ منتخب نہیں ہے۔');
    }
    String userId;
    try {
      userId = await _repo.createAuthUser(
        name: name,
        phone: phone,
        email: email,
        password: password,
      );
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      AppLogger().warning('[RoleUx] createAuthUser failed', error: e);
      return (userId: null, error: roleUxErrorMessage(e));
    }
    try {
      await _repo.assignRole(
          tenantId: tenantId, userId: userId, roleKey: roleKey);
      await _repo.syncUserPermissions(
        tenantId: tenantId,
        userId: userId,
        templateCodes: templateCodes,
        selectedCodes: selectedCodes,
      );
      await _repo.writeScopes(
        tenantId: tenantId,
        userId: userId,
        codes: scopeCodes,
        selection: scope,
      );
    } catch (e) {
      AppLogger().warning('[RoleUx] post-create setup failed, rolling back',
          error: e);
      try {
        await _repo.deleteAuthUser(userId);
      } catch (rb) {
        AppLogger().warning('[RoleUx] rollback delete failed', error: rb);
        state = AsyncValue.error(e, StackTrace.current);
        return (
          userId: null,
          error: 'صارف تو بن گیا مگر ذمہ داری نہ سونپی جا سکی — '
              '${roleUxErrorMessage(e)}'
        );
      }
      state = AsyncValue.error(e, StackTrace.current);
      return (userId: null, error: roleUxErrorMessage(e));
    }
    invalidateRoleUxLists(_ref);
    state = const AsyncValue.data(null);
    return (userId: userId, error: null);
  }

  /// Edit flow from the user detail screen: role + overrides + scopes.
  Future<String?> updateUserSetup({
    required TenantUser user,
    required String roleKey,
    required Set<String> templateCodes,
    required Set<String> selectedCodes,
    required Set<String> scopeCodes,
    required ScopeSelection scope,
    required Set<String> assignHolderKeys,
  }) {
    return _run(() async {
      final tenantId = _tenantId!;
      if (roleKey != user.roleKey) {
        final refusal = await _safetyRefusal(
          user,
          disabling: false,
          newRoleKey: roleKey,
          assignHolderKeys: assignHolderKeys,
        );
        if (refusal != null) throw _UrduRefusal(refusal);
        await _repo.assignRole(
            tenantId: tenantId, userId: user.id, roleKey: roleKey);
      }
      await _repo.syncUserPermissions(
        tenantId: tenantId,
        userId: user.id,
        templateCodes: templateCodes,
        selectedCodes: selectedCodes,
      );
      await _repo.writeScopes(
        tenantId: tenantId,
        userId: user.id,
        codes: scopeCodes,
        selection: scope,
      );
    });
  }

  /// Bulk (de)activation with per-user principal safety. Returns null when
  /// every user was processed, otherwise a summary of what was refused.
  Future<String?> bulkSetActive(List<TenantUser> users, bool active) {
    return _run(() async {
      final refused = <String>[];
      for (final u in users) {
        final refusal = await _safetyRefusal(
          u,
          disabling: !active,
          newRoleKey: u.roleKey,
          assignHolderKeys: const {},
        );
        if (refusal != null) {
          refused.add('${u.name}: $refusal');
          continue;
        }
        await _repo.setActive(userId: u.id, active: active);
      }
      if (refused.isNotEmpty) {
        throw _UrduRefusal(refused.join('\n'));
      }
    });
  }

  /// Bulk role change (role only — individual overrides stay untouched).
  Future<String?> bulkAssignRole(
    List<TenantUser> users,
    String roleKey,
    Set<String> assignHolderKeys,
  ) {
    return _run(() async {
      final refused = <String>[];
      for (final u in users) {
        if (u.roleKey == roleKey) continue;
        final refusal = await _safetyRefusal(
          u,
          disabling: false,
          newRoleKey: roleKey,
          assignHolderKeys: assignHolderKeys,
        );
        if (refusal != null) {
          refused.add('${u.name}: $refusal');
          continue;
        }
        await _repo.assignRole(
            tenantId: _tenantId!, userId: u.id, roleKey: roleKey);
      }
      if (refused.isNotEmpty) {
        throw _UrduRefusal(refused.join('\n'));
      }
    });
  }
}

/// A pre-check refusal already phrased in plain Urdu — passes through
/// [roleUxErrorMessage] untouched.
class _UrduRefusal implements Exception {
  _UrduRefusal(this.message);
  final String message;
  @override
  String toString() => message;
}

final roleUxControllerProvider =
    StateNotifierProvider<RoleUxController, AsyncValue<void>>(
  (ref) => RoleUxController(ref),
);
