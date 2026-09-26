// ── Madrasa 360 — PermissionService ──────────────────────────────────────────
// Low-level permission loading + pure set-evaluation helpers.
//
// The server (`get_my_permissions_detailed`, supabase/migrations/020) returns
// canonical codes; this service validates them against
// [AppPermissions.allCodes] (unknown codes are dropped with a warning —
// fail-closed) and persists the last-known-good set per (user, tenant) in
// [StorageService] for offline use.
//
// The in-memory per-tenant cache and the "active tenant" facade live in
// [AuthorizationService]; UI code should use the guards / Riverpod providers,
// not this class directly.
//
// Offline chain in [loadEffectivePermissions]:
//   RPC → last-known persisted set → static [AppPermissions.fallbackFor]
//   defaults for the tenant role key (fail-closed for unknown keys).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import '../constants/app_permissions.dart';
import '../observability/app_logger.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

/// Effective permission set for one tenant, with grant provenance
/// (`source` ∈ `role` | `override` | `delegation`, from
/// `get_my_permissions_detailed`).
class EffectivePermissions {
  final Set<String> codes;

  /// Grant provenance per code; empty when the set came from cache/fallback.
  final Map<String, String> sources;

  const EffectivePermissions({
    required this.codes,
    this.sources = const {},
  });
}

class PermissionService {
  static final _client = SupabaseService.client;
  static AppLogger get _log => AppLogger();

  // ── Pure set-evaluation helpers (unit-tested) ──────────────────────────────

  /// Returns true if [permissions] contains [permission].
  static bool has(Set<String> permissions, String permission) =>
      permissions.contains(permission);

  /// Returns true if [permissions] contains ALL of [required].
  static bool hasAll(Set<String> permissions, Iterable<String> required) =>
      required.every(permissions.contains);

  /// Returns true if [permissions] contains ANY of [any].
  static bool hasAny(Set<String> permissions, Iterable<String> any) =>
      any.any(permissions.contains);

  /// Pass-through validator: keeps exactly the codes the server is allowed
  /// to issue ([AppPermissions.allCodes]). Unknown codes are dropped with a
  /// warning (fail-closed). Pure and unit-tested.
  ///
  /// There is deliberately NO dotted↔underscore translation here: the client
  /// speaks the server's canonical vocabulary directly (Phase 5).
  @visibleForTesting
  static Set<String> validateServerCodes(Set<String> codes) {
    final out = <String>{};
    for (final code in codes) {
      if (AppPermissions.allCodes.contains(code)) {
        out.add(code);
      } else {
        _log.warning('[Permissions] dropping unknown server code: $code');
      }
    }
    return out;
  }

  // ── Load effective permissions for one tenant ──────────────────────────────

  /// Calls `get_my_permissions_detailed(p_tenant_id)` and returns the
  /// effective codes for the signed-in user in [tenantId] (020 resolves
  /// deny > grant > delegation > role server-side).
  ///
  /// [roleKey] is the user's `tenant_memberships.role` key in [tenantId],
  /// used only for the static offline fallback.
  static Future<EffectivePermissions> loadEffectivePermissions({
    required String tenantId,
    required String roleKey,
  }) async {
    String? userId;
    try {
      // Inside try: in unit tests (or before Supabase init) merely touching
      // the client throws — that must land in the offline fallback below,
      // not escape as an unhandled error.
      userId = _client.auth.currentUser?.id;
      final response = await _client.rpc(
        'get_my_permissions_detailed',
        params: {'p_tenant_id': tenantId},
      );
      final rows = (response as List?) ?? <dynamic>[];
      final codes = <String>{};
      final sources = <String, String>{};
      for (final row in rows) {
        final map = row as Map<String, dynamic>;
        final code = map['code'] as String?;
        // Defensive: the RPC is already tenant-filtered; never accept a
        // row for another tenant into this tenant's set.
        if (code == null || '${map['tenant_id']}' != tenantId) continue;
        codes.add(code);
        sources[code] = (map['source'] as String?) ?? 'role';
      }
      final valid = validateServerCodes(codes);
      await _persist(tenantId, userId, valid);
      _log.info(
          '[Permissions] loaded ${valid.length} codes for tenant $tenantId');
      return EffectivePermissions(
        codes: valid,
        sources: {for (final c in valid) c: sources[c] ?? 'role'},
      );
    } catch (e) {
      _log.warning(
        '[Permissions] RPC failed for tenant $tenantId — trying offline cache',
        error: e,
      );
      final cached = await _readPersisted(tenantId, userId);
      if (cached != null) {
        _log.info(
            '[Permissions] using last-known cached set (${cached.length} codes)');
        return EffectivePermissions(codes: cached);
      }
      final fallback = AppPermissions.fallbackFor(roleKey);
      _log.warning(
          '[Permissions] no cache; static fallback for role "$roleKey" '
          '(${fallback.length} codes)');
      return EffectivePermissions(
        codes: fallback,
        sources: {for (final c in fallback) c: 'role'},
      );
    }
  }

  // ── Offline persistence (per user + tenant) ────────────────────────────────

  static String _cacheKey(String tenantId, String userId) =>
      'authz.perms.v1.$userId.$tenantId';

  /// Persists the last-known-good set. Never persists without a user id —
  /// the cache is keyed per user so one device user cannot read another's.
  static Future<void> _persist(
      String tenantId, String? userId, Set<String> codes) async {
    if (userId == null) return;
    try {
      final list = codes.toList()..sort();
      await StorageService.saveStringList(_cacheKey(tenantId, userId), list);
    } catch (e) {
      _log.warning('[Permissions] failed to persist permission cache',
          error: e);
    }
  }

  static Future<Set<String>?> _readPersisted(
      String tenantId, String? userId) async {
    if (userId == null) return null;
    try {
      final list = StorageService.getStringList(_cacheKey(tenantId, userId));
      if (list == null) return null;
      return validateServerCodes(list.toSet());
    } catch (_) {
      return null;
    }
  }

  /// Removes every persisted permission set for [userId].
  /// Call on sign-out so a later device user cannot read them.
  static Future<void> clearPersistedCache(String userId) async {
    try {
      final prefix = 'authz.perms.v1.$userId.';
      final keys = StorageService.getAllKeys()
          .where((k) => k.startsWith(prefix))
          .toList();
      for (final k in keys) {
        await StorageService.remove(k);
      }
    } catch (e) {
      _log.warning('[Permissions] failed to clear persisted cache', error: e);
    }
  }
}
