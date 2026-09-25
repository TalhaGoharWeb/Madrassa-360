/// Tenant context — multi-tenant session state (Phase 2 SaaS transformation).
///
/// Holds the *active* tenant for the signed-in user and exposes
/// [currentTenantIdProvider], which every data provider must use to scope
/// its Supabase queries. RLS enforces isolation server-side; this is the
/// client-side companion that always sends the active `tenant_id`.
///
/// Wiring (Phase 3 — done in AuthNotifier):
///   await ref.read(activeTenantIdProvider.notifier).init();  // after sign-in
///   await ref.read(activeTenantIdProvider.notifier).clear(); // after sign-out

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/auth_provider.dart';
import 'supabase_service.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────

/// One row of `tenant_memberships` joined with its `tenants` row.
class TenantMembership {
  final String tenantId;
  final String role;
  final String tenantName;
  final String? tenantNameUrdu;
  final String? logoUrl;
  final bool isActive;

  const TenantMembership({
    required this.tenantId,
    required this.role,
    required this.tenantName,
    this.tenantNameUrdu,
    this.logoUrl,
    this.isActive = true,
  });

  factory TenantMembership.fromJson(Map<String, dynamic> json) {
    final tenant = json['tenants'] as Map<String, dynamic>? ?? {};
    return TenantMembership(
      tenantId:      (json['tenant_id'] ?? '') as String,
      role:          (json['role'] ?? '') as String,
      tenantName:    (tenant['name'] ?? '') as String,
      tenantNameUrdu: tenant['name_urdu'] as String?,
      logoUrl:        tenant['logo_url'] as String?,
      isActive:       json['is_active'] as bool? ?? true,
    );
  }
}

// ─────────────────────────────────────────────
// Memberships of the signed-in user
// ─────────────────────────────────────────────

/// All active tenant memberships for the current user.
/// Returns [] (not an error) when logged out, so watchers never crash.
final tenantMembershipsProvider =
    FutureProvider<List<TenantMembership>>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return <TenantMembership>[];
  final rows = await SupabaseService.client
      .from('tenant_memberships')
      .select('tenant_id, role, is_active, tenants!inner(name, name_urdu, logo_url)')
      .eq('user_id', userId)
      .eq('is_active', true);
  return (rows as List)
      .map((r) => TenantMembership.fromJson(r as Map<String, dynamic>))
      .toList();
});

// ─────────────────────────────────────────────
// Active tenant (persisted)
// ─────────────────────────────────────────────

/// Holds the active tenant id, persisted in SharedPreferences under
/// `active_tenant_id`. Falls back to the first membership once loaded.
class TenantContext extends StateNotifier<String?> {
  TenantContext(this._ref) : super(null);

  final Ref _ref;
  static const prefsKey = 'active_tenant_id';

  /// Restore the saved tenant, or fall back to the first membership.
  /// Call once after login / at app bootstrap.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(prefsKey);
    final memberships = await _ref.read(tenantMembershipsProvider.future);
    if (memberships.isEmpty) {
      state = null;
      return;
    }
    final valid =
        saved != null && memberships.any((m) => m.tenantId == saved);
    final id = valid ? saved! : memberships.first.tenantId;
    state = id;
    await prefs.setString(prefsKey, id);
  }

  /// Switch the active tenant and persist the choice.
  Future<void> switchTenant(String id) async {
    state = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, id);
  }

  /// Re-fetch memberships and re-resolve the active tenant
  /// (e.g. after login, logout, or role change).
  Future<void> refresh() async {
    _ref.invalidate(tenantMembershipsProvider);
    await init();
  }

  /// Clear the active tenant and drop the persisted choice (on logout).
  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }
}

/// The active tenant id (null until [TenantContext.init] runs, or logged out).
final activeTenantIdProvider =
    StateNotifierProvider<TenantContext, String?>(
        (ref) => TenantContext(ref));

// ─────────────────────────────────────────────
// Effective tenant for queries
// ─────────────────────────────────────────────

/// The tenant id every data provider must scope its queries with.
/// Null when logged out or while memberships are still loading —
/// callers must bail out (return []) instead of querying unscoped.
final currentTenantIdProvider = Provider<String?>((ref) {
  final activeId = ref.watch(activeTenantIdProvider);
  final memberships = ref.watch(tenantMembershipsProvider).valueOrNull;
  if (memberships == null || memberships.isEmpty) return null;
  if (activeId != null && memberships.any((m) => m.tenantId == activeId)) {
    return activeId;
  }
  // init() hasn't run yet (or the saved tenant was revoked): first membership.
  return memberships.first.tenantId;
});
