// ── Madrasa 360 — RoleService ────────────────────────────────────────────────
// Active-tenant role resolution + permission-derived capability helpers.
//
// - WHICH role(s) the user holds in the active tenant comes from
//   `tenant_memberships` (via [tenantMembershipsProvider]) — never from
//   `auth.users.app_metadata` / `profiles.role` (deprecated single-role
//   columns the audit found the old code reading).
// - Urdu role labels come from the tenant's own `tenant_roles.display_urdu`
//   (cached per tenant), with static template fallbacks below.
// - Capability helpers (`canManageRoles`, `isPrincipal`, …) are derived from
//   the EFFECTIVE PERMISSION SET, never from role-name string comparisons.
//   UI logic must not hard-code role names; the two role-key helpers at the
//   bottom exist only for tenant-administration flows where the server
//   itself is role-based (`protect_last_owner()`), never for feature gating.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../constants/app_permissions.dart';
import '../observability/app_logger.dart';
import 'supabase_service.dart';
import 'tenant_context.dart';

class RoleService {
  RoleService(this._ref);

  final Ref _ref;

  /// Role keys the user holds in the active tenant. `tenant_memberships`
  /// enforces one row per user+tenant, so this is normally a single key.
  List<String> activeRoleKeys() {
    final tenantId = _ref.read(activeTenantIdProvider);
    if (tenantId == null) return const [];
    final memberships = _ref.read(tenantMembershipsProvider).valueOrNull;
    if (memberships == null) return const [];
    return [
      for (final m in memberships)
        if (m.tenantId == tenantId && m.isActive) m.role,
    ];
  }

  bool _has(String permission) =>
      _ref.read(userPermissionsProvider).contains(permission);

  // ── Permission-derived capabilities (use these for feature gating) ─────────

  /// Can manage tenant roles and grants (`roles.assign` holders).
  bool canManageRoles() => _has(AppPermissions.assignRoles);

  /// Can manage user accounts.
  bool canManageUsers() => _has(AppPermissions.viewUsers);

  /// Can collect fees at the front desk.
  bool canCollectFees() => _has(AppPermissions.collectFees);

  /// Can approve financial transactions.
  bool canApproveFinance() => _has(AppPermissions.approveFinance);

  /// Can publish exam results.
  bool canPublishResults() => _has(AppPermissions.publishResults);

  /// Can broadcast announcements.
  bool canSendAnnouncements() => _has(AppPermissions.sendNotifications);

  /// Can configure the academic structure (darjas / classes / sections).
  bool managesAcademics() => _has(AppPermissions.manageDarjas);

  /// Principal-level academic authority (مہتمم-style oversight): full
  /// academic configuration plus exam/result publishing. Derived from
  /// permissions — NOT from the role name being 'principal'.
  bool isPrincipal() =>
      _has(AppPermissions.manageDarjas) &&
      _has(AppPermissions.publishExams) &&
      _has(AppPermissions.publishResults);

  // ── Role-key helpers (tenant administration only) ──────────────────────────

  /// True when the active membership role is `tenant_owner`.
  /// Role-key based (not permission-derived): for tenant-administration
  /// flows where the server itself is role-based, never for feature gating.
  bool isTenantOwner() => activeRoleKeys().contains('tenant_owner');

  /// True for `tenant_owner` / `tenant_admin` in the active tenant.
  /// Same caveat as [isTenantOwner].
  bool isTenantAdmin() =>
      activeRoleKeys().any((k) => k == 'tenant_owner' || k == 'tenant_admin');

  // ── Urdu role labels ───────────────────────────────────────────────────────

  /// Static Urdu labels for the template role keys (019). The tenant's own
  /// `tenant_roles.display_urdu` wins when it can be loaded (custom roles).
  static const Map<String, String> _fallbackRoleUrdu = {
    'tenant_owner': 'مالک',
    'tenant_admin': 'ناظم اعلیٰ',
    'mohtamim': 'مہتمم',
    'naib_mohtamim': 'نائب مہتمم',
    'nazim_aala': 'ناظم اعلیٰ',
    'nazim_taleem': 'ناظم تعلیم',
    'nazim_intizamia': 'ناظم انتظامیہ',
    'nazim_maliyat': 'ناظم مالیات',
    'daftar_dar': 'دفتر دار',
    'principal': 'پرنسپل',
    'accountant': 'محاسب',
    'teacher': 'استاد',
    'ustad': 'استاد',
    'ustad_hifz': 'مدرس حفظ',
    'nazim_hifz': 'ناظم حفظ',
    'nazim_darul_iqama': 'ناظم دارالاقامہ',
    'warden': 'وارڈن',
    'mumtahin': 'ممتحن',
    'librarian': 'لائبریرین',
    'hostel_manager': 'ہاسٹل مینیجر',
    'store_incharge': 'اسٹور انچارج',
    'hr_incharge': 'عملہ انچارج',
    'staff': 'عملہ',
    'parent': 'والدین',
    'student': 'طالب علم',
    'platform_owner': 'پلیٹ فارم مالک',
    'platform_support': 'پلیٹ فارم سپورٹ',
  };

  final Map<String, Map<String, String>> _urduCache = {};

  /// Urdu display label for a tenant role key. Prefers the tenant's own
  /// `tenant_roles.display_urdu` (so custom roles show their own name),
  /// falls back to the template labels above, then to the raw key.
  Future<String> roleUrduLabel(String roleKey) async {
    final tenantId = _ref.read(activeTenantIdProvider);
    if (tenantId != null) {
      final cached = _urduCache[tenantId];
      if (cached != null && cached.containsKey(roleKey)) {
        return cached[roleKey]!;
      }
      try {
        final rows = await SupabaseService.client
            .from('tenant_roles')
            .select('key, display_urdu')
            .eq('tenant_id', tenantId)
            .eq('is_active', true);
        final map = <String, String>{};
        for (final row in (rows as List)) {
          final r = row as Map<String, dynamic>;
          final key = (r['key'] as String?) ?? '';
          final urdu = (r['display_urdu'] as String?) ?? '';
          if (key.isNotEmpty) map[key] = urdu;
        }
        _urduCache[tenantId] = map;
        final hit = map[roleKey];
        if (hit != null && hit.isNotEmpty) return hit;
      } catch (e) {
        AppLogger()
            .warning('[Roles] failed to load tenant role labels', error: e);
      }
    }
    return _fallbackRoleUrdu[roleKey] ?? roleKey;
  }

  /// Drops the cached Urdu labels (call on tenant switch / sign-out).
  void clearCache() => _urduCache.clear();
}

final roleServiceProvider = Provider<RoleService>((ref) {
  return RoleService(ref);
});

/// Role keys held in the active tenant. Re-resolves on tenant switch and on
/// membership reloads.
final activeRoleKeysProvider = Provider<List<String>>((ref) {
  ref.watch(activeTenantIdProvider);
  ref.watch(tenantMembershipsProvider);
  return ref.read(roleServiceProvider).activeRoleKeys();
});
