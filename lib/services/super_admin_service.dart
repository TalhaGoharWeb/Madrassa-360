/// سپر ایڈمن سروس
/// Super Admin service — platform-operator tenant controls (SaaS).
///
/// Coordinated contract (backend migration):
///   - `super_admins(user_id)` identifies the super admin. Falls back to
///     `platform_admins` rows with role = 'platform_owner', then to the
///     bootstrap owner email below.
///   - `tenants` carries the SaaS control columns: `status`
///     ('trial'|'active'|'suspended'|'expired'|'cancelled'|'archived') plus
///     the migration-added `suspension_reason`, `expires_at`, `admin_message`.
///
/// Reads are defensive: missing/new columns degrade to defaults so the UI
/// keeps working before the migration lands. Writes go through the `status`
/// column (present since 001) and best-effort new columns.
///
/// SECURITY: this service is a UX/convenience layer. Real enforcement is
/// server-side (RLS + the manage-tenant Edge Function). [isSuperAdmin]
/// fails CLOSED; [getTenantAccess] fails OPEN (a network error must never
/// false-lock a paying tenant out — RLS remains the enforcement).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bootstrap super-admin email (user request). Used only when neither the
/// `super_admins` nor the `platform_admins` table yields a row — the
/// migration is expected to register this user in `super_admins`.
const String kSuperAdminBootstrapEmail = 'muhaqqiqcreates@gmail.com';

/// One tenant/madrasa as seen by the Super Admin console.
class Tenant {
  final String id;
  final String name;
  final String urduName;
  final String status;
  final bool isSuspended;
  final String? suspensionReason;
  final DateTime? expiresAt;
  final String? adminMessage;
  final int memberCount;
  final DateTime? createdAt;

  const Tenant({
    required this.id,
    required this.name,
    required this.urduName,
    required this.status,
    required this.isSuspended,
    this.suspensionReason,
    this.expiresAt,
    this.adminMessage,
    this.memberCount = 0,
    this.createdAt,
  });

  /// Display name prefers Urdu, falls back to the Latin name.
  String get displayName => urduName.isNotEmpty ? urduName : name;

  /// True when the expiry date has passed.
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  /// Whole days left until expiry, null when no expiry is set.
  int? get daysRemaining {
    final e = expiresAt;
    if (e == null) return null;
    return e.difference(DateTime.now()).inDays;
  }

  /// True when the tenant can currently use the app.
  bool get isUsable => !isSuspended && !isExpired;

  factory Tenant.fromJson(Map<String, dynamic> j, {int memberCount = 0}) {
    final status = (j['status'] as String?) ?? 'active';
    // Newer migrations may carry an explicit boolean; otherwise derive
    // from the lifecycle status column (present since 001).
    final suspendedFlag = j['is_suspended'] as bool?;
    final isSuspended = suspendedFlag ?? status == 'suspended';
    return Tenant(
      id: (j['id'] as String?) ?? '',
      name: (j['name'] as String?) ?? '',
      urduName: (j['name_urdu'] as String?) ?? '',
      status: status,
      isSuspended: isSuspended,
      suspensionReason: j['suspension_reason'] as String?,
      expiresAt: _parseDate(j['expires_at']),
      adminMessage: j['admin_message'] as String?,
      memberCount: memberCount,
      createdAt: _parseDate(j['created_at']),
    );
  }

  static DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}

/// Tenant-side access snapshot used by the access guard.
class TenantAccessStatus {
  final bool suspended;
  final String? suspensionReason;
  final bool expired;
  final DateTime? expiresAt;
  final String? adminMessage;

  const TenantAccessStatus({
    this.suspended = false,
    this.suspensionReason,
    this.expired = false,
    this.expiresAt,
    this.adminMessage,
  });

  /// Fail-open snapshot used when the check itself errors (network/RLS).
  /// A check failure must never false-lock a tenant out of the app.
  static const TenantAccessStatus allowed = TenantAccessStatus();

  bool get blocked => suspended || expired;
  bool get hasMessage =>
      adminMessage != null && adminMessage!.trim().isNotEmpty;
}

class SuperAdminService {
  final SupabaseClient _client;

  SuperAdminService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  // ── Super-admin identity ──────────────────────────────────────────

  /// True when [userId] is a super admin. Fails CLOSED on any error.
  Future<bool> isSuperAdmin(String userId) async {
    if (userId.isEmpty) return false;
    // 1) Dedicated super_admins table (backend migration).
    try {
      final row = await _client
          .from('super_admins')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();
      if (row != null) return true;
    } catch (_) {
      // Table may not exist yet — fall through to the next source.
    }
    // 2) Platform owners are super admins too.
    try {
      final row = await _client
          .from('platform_admins')
          .select('role')
          .eq('user_id', userId)
          .eq('role', 'platform_owner')
          .maybeSingle();
      if (row != null) return true;
    } catch (_) {
      // fall through
    }
    // 3) Bootstrap owner (user request) — lets the very first super admin
    //    in before any table row exists.
    try {
      final email = _client.auth.currentUser?.email?.trim().toLowerCase();
      if (email == kSuperAdminBootstrapEmail) return true;
    } catch (_) {
      // fall through
    }
    return false;
  }

  // ── Tenant listing ────────────────────────────────────────────────

  /// All tenants, newest last. Best-effort member counts.
  Future<List<Tenant>> getAllTenants() async {
    final rows = await _client.from('tenants').select().order('created_at');
    final list = <Tenant>[];
    for (final r in (rows as List)) {
      final map = Map<String, dynamic>.from(r as Map);
      final count = await _memberCount(map['id'] as String? ?? '');
      list.add(Tenant.fromJson(map, memberCount: count));
    }
    return list;
  }

  /// Member count for one tenant. Best effort — 0 on any error.
  Future<int> getTenantMemberCount(String tenantId) =>
      _memberCount(tenantId);

  Future<int> _memberCount(String tenantId) async {
    if (tenantId.isEmpty) return 0;
    try {
      final rows = await _client
          .from('tenant_memberships')
          .select('id')
          .eq('tenant_id', tenantId)
          .eq('is_active', true);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Single tenant row (or null). Used by the detail screen refresh.
  Future<Tenant?> getTenant(String tenantId) async {
    try {
      final row = await _client
          .from('tenants')
          .select()
          .eq('id', tenantId)
          .maybeSingle();
      if (row == null) return null;
      final count = await _memberCount(tenantId);
      return Tenant.fromJson(Map<String, dynamic>.from(row),
          memberCount: count);
    } catch (_) {
      return null;
    }
  }

  // ── Tenant-side access check ──────────────────────────────────────

  /// Suspension/expiry/message snapshot for the tenant-side guard.
  /// FAILS OPEN: any error returns [TenantAccessStatus.allowed].
  Future<TenantAccessStatus> getTenantAccess(String tenantId) async {
    if (tenantId.isEmpty) return TenantAccessStatus.allowed;
    try {
      final row = await _client
          .from('tenants')
          .select('status, suspension_reason, expires_at, admin_message')
          .eq('id', tenantId)
          .maybeSingle();
      if (row == null) return TenantAccessStatus.allowed;
      final map = Map<String, dynamic>.from(row);
      final status = (map['status'] as String?) ?? 'active';
      final expiresAt = Tenant._parseDate(map['expires_at']);
      final expired =
          expiresAt != null && expiresAt.isBefore(DateTime.now());
      return TenantAccessStatus(
        suspended: status == 'suspended',
        suspensionReason: map['suspension_reason'] as String?,
        expired: expired || status == 'expired',
        expiresAt: expiresAt,
        adminMessage: map['admin_message'] as String?,
      );
    } catch (_) {
      return TenantAccessStatus.allowed;
    }
  }

  // ── Mutations ─────────────────────────────────────────────────────

  /// Suspend a tenant with a reason. Updates the lifecycle `status`
  /// (present since 001) and best-effort `suspension_reason`.
  Future<void> suspendTenant(String tenantId, String reason) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Suspension reason is required');
    }
    await _client
        .from('tenants')
        .update({'status': 'suspended'}).eq('id', tenantId);
    // Best effort — column lands with the backend migration.
    try {
      await _client.from('tenants').update(
          {'suspension_reason': trimmed}).eq('id', tenantId);
    } catch (_) {
      // ignore: reason is still conveyed via status; migration backfills.
    }
  }

  /// Lift a suspension (back to active).
  Future<void> unsuspendTenant(String tenantId) async {
    await _client.from('tenants').update({'status': 'active'}).eq(
        'id', tenantId);
    try {
      await _client.from('tenants').update(
          {'suspension_reason': null}).eq('id', tenantId);
    } catch (_) {
      // ignore — column may not exist yet.
    }
  }

  /// Set the SaaS expiry date. Best effort until the migration lands.
  Future<void> setTenantExpiry(String tenantId, DateTime expiresAt) async {
    await _client.from('tenants').update(
        {'expires_at': expiresAt.toIso8601String()}).eq('id', tenantId);
  }

  /// Remove the expiry (lifetime access).
  Future<void> clearTenantExpiry(String tenantId) async {
    await _client
        .from('tenants')
        .update({'expires_at': null}).eq('id', tenantId);
  }

  /// Broadcast message shown on the tenant's dashboards.
  Future<void> setTenantMessage(String tenantId, String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Message is required');
    }
    await _client.from('tenants').update(
        {'admin_message': trimmed}).eq('id', tenantId);
  }

  /// Remove the broadcast message.
  Future<void> clearTenantMessage(String tenantId) async {
    await _client
        .from('tenants')
        .update({'admin_message': null}).eq('id', tenantId);
  }
}

/// Riverpod access to the service.
final superAdminServiceProvider = Provider<SuperAdminService>((ref) {
  return SuperAdminService();
});

/// Async super-admin check for a user id (fails closed → false).
final isSuperAdminProvider =
    FutureProvider.family<bool, String>((ref, userId) async {
  return ref.watch(superAdminServiceProvider).isSuperAdmin(userId);
});

/// Tenant access snapshot for the tenant-side guard (fails open).
final tenantAccessProvider =
    FutureProvider.family<TenantAccessStatus, String>((ref, tenantId) async {
  return ref.watch(superAdminServiceProvider).getTenantAccess(tenantId);
});
