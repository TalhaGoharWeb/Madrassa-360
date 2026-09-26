// ── Madrasa 360 — AuthorizationService ───────────────────────────────────────
// Single source of truth for "can this user do X in the ACTIVE tenant?".
//
// Holds the effective permission set for the active tenant in memory (loaded
// via [PermissionService.loadEffectivePermissions], i.e. from the
// `get_my_permissions_detailed` RPC — deny > grant > delegation > role is
// resolved server-side). The set is (re)loaded at sign-in and on every
// tenant switch by [AuthNotifier]; [clearCache] drops it.
//
// This service NEVER trusts client-sent roles or tenants: it only caches
// what the server RPC returned for the authenticated user. And it is
// UI-ONLY: Supabase RLS remains the real enforcement — these checks decide
// what the user SEES, never what the user CAN DO.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'permission_service.dart';
import 'scope_service.dart';

class AuthorizationService {
  AuthorizationService(this._ref);

  final Ref _ref;

  String? _tenantId;
  Set<String> _effective = const {};
  Map<String, String> _sources = const {};

  /// The tenant the in-memory set was loaded for (null = nothing loaded).
  String? get loadedTenantId => _tenantId;

  /// Effective codes for the loaded tenant. Empty when nothing is loaded
  /// (fail-closed).
  Set<String> get effectivePermissions => Set.unmodifiable(_effective);

  /// Grant provenance for [permission] (`role` | `override` | `delegation`),
  /// or null when the permission is not held / nothing is loaded.
  String? sourceOf(String permission) => _sources[permission];

  /// Loads the effective set for [tenantId], or returns the in-memory set
  /// when it is already loaded for that tenant.
  ///
  /// [roleKey] is the user's `tenant_memberships.role` key in [tenantId],
  /// used only for the static offline fallback.
  Future<Set<String>> ensureLoaded(String tenantId,
      {required String roleKey}) async {
    if (_tenantId == tenantId) return effectivePermissions;
    final loaded = await PermissionService.loadEffectivePermissions(
      tenantId: tenantId,
      roleKey: roleKey,
    );
    _tenantId = tenantId;
    _effective = loaded.codes;
    _sources = loaded.sources;
    return effectivePermissions;
  }

  /// True when the loaded tenant's set contains [permission].
  /// False when nothing is loaded (fail-closed).
  bool has(String permission) => _effective.contains(permission);

  /// True when the loaded tenant's set contains ALL of [permissions].
  bool hasAll(Iterable<String> permissions) =>
      permissions.every(_effective.contains);

  /// True when the loaded tenant's set contains ANY of [permissions].
  bool hasAny(Iterable<String> permissions) =>
      permissions.any(_effective.contains);

  /// Data-scope row for [permission] in the active tenant (UX-level
  /// filtering; see [ScopeService]).
  Future<PermissionScope?> scopesFor(String permission) =>
      _ref.read(scopeServiceProvider).scopeFor(permission);

  /// Drops the in-memory set and scope rows (call on tenant switch /
  /// sign-out). The persisted offline cache is untouched — call
  /// [PermissionService.clearPersistedCache] on sign-out to remove it.
  void clearCache() {
    _tenantId = null;
    _effective = const {};
    _sources = const {};
    _ref.read(scopeServiceProvider).clearCache();
  }
}

/// The active tenant's authorization facade.
final authorizationServiceProvider = Provider<AuthorizationService>((ref) {
  return AuthorizationService(ref);
});
