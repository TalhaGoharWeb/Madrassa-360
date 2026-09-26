/// ڈیٹا حدود کے فراہم کنندگان (Phase 9)
/// Riverpod wiring for the Data Scopes manager: the tenant-wide scope
/// directory plus a [ScopeManagerController] that runs create/update/
/// delete through [RoleUxRepository.writeScopes] (RLS-enforced) after
/// the client-side narrow-only [ScopePolicy] check.
///
/// The repository behind [scopeManagerRepositoryProvider] is overridable,
/// so widget tests never touch Supabase.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/observability/app_logger.dart';
import '../core/services/scope_policy.dart';
import '../core/services/tenant_context.dart';
import '../data/role_ux_repository.dart';
import '../data/scope_manager_repository.dart';
import 'auth_provider.dart';
import 'role_ux_provider.dart';

// ─────────────────────────────────────────────────────────────
// Repository + read providers
// ─────────────────────────────────────────────────────────────

/// Overridable in tests with a stub — production uses the real Supabase
/// implementation (real RLS reads + offline cache, no mock data).
final scopeManagerRepositoryProvider = Provider<ScopeManagerRepository>((ref) {
  return SupabaseScopeManagerRepository(
    roleUx: ref.read(roleUxRepositoryProvider),
  );
});

/// Every data-scope assignment in the active tenant. The repository
/// serves the last-known offline cache when the network read fails
/// ([ScopeAssignmentListResult.fromCache] is then true and the UI shows
/// an honest stale banner with the last fetch time).
final scopeAssignmentsProvider =
    FutureProvider.autoDispose<ScopeAssignmentListResult>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) {
    return const ScopeAssignmentListResult(items: [], fromCache: false);
  }
  final userId = ref.watch(currentUserProvider)?.id;
  return ref
      .read(scopeManagerRepositoryProvider)
      .listAssignments(tenantId, userId: userId);
});

/// Invalidate the scope directory (call after any write).
void invalidateScopeAssignments(Ref ref) {
  ref.invalidate(scopeAssignmentsProvider);
}

// ─────────────────────────────────────────────────────────────
// Controller — all writes go through here
// ─────────────────────────────────────────────────────────────

class ScopeManagerController extends StateNotifier<AsyncValue<void>> {
  ScopeManagerController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  RoleUxRepository get _roleUx => _ref.read(roleUxRepositoryProvider);
  ScopeManagerRepository get _scopes =>
      _ref.read(scopeManagerRepositoryProvider);
  String? get _tenantId => _ref.read(currentTenantIdProvider);
  String? get _selfId => _ref.read(currentUserProvider)?.id;

  /// Saves one scope selection for [targetUserId] across [codes].
  ///
  /// Fail-closed: the granter's own scopes are loaded first; when they
  /// cannot be loaded the write is refused before anything is sent.
  /// [ScopePolicy] then refuses any grant wider than the granter's own
  /// scope for each code. Returns null on success, otherwise a
  /// plain-Urdu message (server text never leaks).
  Future<String?> saveScope({
    required String targetUserId,
    required Set<String> codes,
    required ScopeSelection selection,
  }) async {
    state = const AsyncValue.loading();
    final tenantId = _tenantId;
    if (tenantId == null) {
      state = const AsyncValue.data(null);
      return 'مدرسہ منتخب نہیں ہے۔';
    }
    final selfId = _selfId;
    if (selfId == null) {
      state = const AsyncValue.data(null);
      return 'آپ لاگ اِن نہیں ہیں — دوبارہ لاگ اِن کریں۔';
    }
    if (codes.isEmpty) {
      state = const AsyncValue.data(null);
      return 'کم از کم ایک اختیار منتخب کریں۔';
    }

    // 1. Granter's own scopes (fail closed on load failure).
    Map<String, ScopeSelection> granter = const {};
    var granterKnown = false;
    try {
      granter = await _roleUx.userScopes(tenantId: tenantId, userId: selfId);
      granterKnown = true;
    } catch (e) {
      AppLogger().warning('[Scopes] failed to load granter scopes', error: e);
    }

    // 2. Resolve the classes of requested students once (needed for the
    //    narrow-only check when the granter is class-scoped).
    Set<String> requestedStudentClassIds = const {};
    if (selection.type == 'students' && selection.studentIds.isNotEmpty) {
      try {
        final byStudent =
            await _scopes.classIdOfStudents(tenantId, selection.studentIds);
        requestedStudentClassIds = {
          for (final id in selection.studentIds)
            if (byStudent[id] != null) byStudent[id]!,
        };
      } catch (e) {
        AppLogger()
            .warning('[Scopes] failed to resolve student classes', error: e);
        state = const AsyncValue.data(null);
        return 'طلبہ کی جماعتوں کی تصدیق نہیں ہو سکی — '
            'حفاظتی طور پر تبدیلی محفوظ نہیں کی گئی۔';
      }
    }

    // 3. Narrow-only check per permission area.
    for (final code in codes) {
      final g = granter[code];
      final refusal = ScopePolicy.validateGrant(
        granterKnown: granterKnown,
        granterType: g?.type ?? 'all',
        granterClassIds: g?.classIds ?? const {},
        granterStudentIds: g?.studentIds ?? const {},
        requestedType: selection.type,
        requestedClassIds: selection.classIds,
        requestedStudentIds: selection.studentIds,
        requestedStudentClassIds: requestedStudentClassIds,
      );
      if (refusal != null) {
        state = const AsyncValue.data(null);
        return refusal;
      }
    }

    // 4. Write (RLS `roles.assign` enforced server-side; the 019 trigger
    //    writes the human-readable audit rows).
    try {
      await _roleUx.writeScopes(
        tenantId: tenantId,
        userId: targetUserId,
        codes: codes,
        selection: selection,
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      AppLogger().warning('[Scopes] write failed', error: e);
      return roleUxErrorMessage(e);
    }

    invalidateScopeAssignments(_ref);
    invalidateRoleUxLists(_ref);
    state = const AsyncValue.data(null);
    return null;
  }

  /// Removes the narrowed scope rows for [codes] (back to the default
  /// "پورا مدرسہ"). The 019 trigger writes `permission_scopes.deleted`
  /// audit rows.
  Future<String?> removeScopes({
    required String targetUserId,
    required Set<String> codes,
  }) {
    return saveScope(
      targetUserId: targetUserId,
      codes: codes,
      selection: const ScopeSelection(type: 'all'),
    );
  }
}

final scopeManagerControllerProvider =
    StateNotifierProvider<ScopeManagerController, AsyncValue<void>>((ref) {
  return ScopeManagerController(ref);
});
