/// اختیار سونپنے کے فراہم کنندگان (Phase 8b)
/// Riverpod wiring for the 8b delegation flows: the delegation list plus a
/// [DelegationController] that runs create/revoke through the real RPC /
/// RLS-guarded delete and maps failures to plain Urdu.
///
/// The repository behind [delegationRepositoryProvider] is overridable, so
/// widget tests never touch Supabase.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/observability/app_logger.dart';
import '../core/services/tenant_context.dart';
import '../data/delegation_policy.dart';
import '../data/delegation_repository.dart';
import 'auth_provider.dart';
import 'role_ux_provider.dart';

// ─────────────────────────────────────────────────────────────
// Repository + read providers
// ─────────────────────────────────────────────────────────────

/// Overridable in tests with a stub — production uses the real Supabase
/// implementation (real RPC/RLS only, no mock data).
final delegationRepositoryProvider = Provider<DelegationRepository>((ref) {
  return SupabaseDelegationRepository();
});

/// Delegations visible in the active tenant. The repository serves the
/// last-known offline cache when the network read fails ([fromCache] is
/// then true and the UI says so honestly).
final delegationsProvider =
    FutureProvider.autoDispose<DelegationListResult>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) {
    return const DelegationListResult(items: [], fromCache: false);
  }
  final userId = ref.watch(currentUserProvider)?.id;
  return ref
      .read(delegationRepositoryProvider)
      .listDelegations(tenantId, userId: userId);
});

/// The signed-in user's own effective permission codes in the active
/// tenant — the ceiling no delegation may exceed. Anything not in this
/// set is never offered in the picker.
final myDelegatableCodesProvider = Provider<Set<String>>((ref) {
  return ref.watch(userPermissionsProvider);
});

/// Invalidate the delegation list (call after any write).
void invalidateDelegationLists(Ref ref) {
  ref.invalidate(delegationsProvider);
}

// ─────────────────────────────────────────────────────────────
// Controller — all writes go through here
// ─────────────────────────────────────────────────────────────

class DelegationController extends StateNotifier<AsyncValue<void>> {
  DelegationController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  DelegationRepository get _repo => _ref.read(delegationRepositoryProvider);
  String? get _tenantId => _ref.read(currentTenantIdProvider);
  String? get _selfId => _ref.read(currentUserProvider)?.id;

  /// Client-side ceiling pre-check, then one `delegate_permission` RPC
  /// per code (the RPC upserts on conflict). Returns null on success,
  /// otherwise a plain-Urdu message. The server re-enforces everything.
  Future<String?> createDelegations({
    required String delegateeId,
    required Set<String> codes,
    required Map<String, DelegationScope> scopesByCode,
    DateTime? expiresAt,
  }) async {
    state = const AsyncValue.loading();
    final tenantId = _tenantId;
    if (tenantId == null) {
      state = const AsyncValue.data(null);
      return 'مدرسہ منتخب نہیں ہے۔';
    }
    final refusal = DelegationPolicy.validateCreate(
      selfId: _selfId,
      delegateeId: delegateeId,
      codes: codes,
      myCodes: _ref.read(myDelegatableCodesProvider),
      expiresAt: expiresAt,
      now: DateTime.now(),
    );
    if (refusal != null) {
      state = const AsyncValue.data(null);
      return refusal;
    }
    try {
      for (final code in codes) {
        await _repo.createDelegation(
          tenantId: tenantId,
          delegateeId: delegateeId,
          code: code,
          scope: scopesByCode[code] ?? const DelegationScope(),
          expiresAt: expiresAt,
        );
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      AppLogger().warning('[Delegations] create failed', error: e);
      return delegationErrorMessage(e);
    }
    invalidateDelegationLists(_ref);
    // A fresh delegation changes the delegatee's effective set, not the
    // delegator's — but invalidating the 8a lists keeps every role screen
    // consistent after delegation changes.
    invalidateRoleUxLists(_ref);
    state = const AsyncValue.data(null);
    return null;
  }

  /// Revokes one delegation (RLS-guarded delete). The row disappears, so
  /// the delegatee's next effective-permission load no longer includes
  /// the code — revocation takes effect immediately.
  Future<String?> revokeDelegation(DelegationInfo delegation) async {
    state = const AsyncValue.loading();
    final tenantId = _tenantId;
    if (tenantId == null) {
      state = const AsyncValue.data(null);
      return 'مدرسہ منتخب نہیں ہے۔';
    }
    if (delegation.tenantId != tenantId) {
      state = const AsyncValue.data(null);
      return 'یہ اختیار کسی اور مدرسے کا ہے۔';
    }
    try {
      await _repo.revokeDelegation(
        tenantId: tenantId,
        delegationId: delegation.id,
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      AppLogger().warning('[Delegations] revoke failed', error: e);
      return delegationErrorMessage(e);
    }
    invalidateDelegationLists(_ref);
    invalidateRoleUxLists(_ref);
    state = const AsyncValue.data(null);
    return null;
  }
}

final delegationControllerProvider =
    StateNotifierProvider<DelegationController, AsyncValue<void>>(
  (ref) => DelegationController(ref),
);
