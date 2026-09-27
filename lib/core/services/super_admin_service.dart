/// سپر ایڈمن کی خدمت
/// Super Admin Service — SaaS control plane (client side)
///
/// Server counterpart: supabase/migrations/023_super_admin.sql
///   * public.super_admins table (SaaS owner registry)
///   * tenants.is_suspended / suspended_at / suspension_reason
///   * tenants.expires_at / admin_message / admin_message_at
///   * is_platform_admin() redefined to include super admins, so every
///     existing RLS policy (`is_platform_admin() OR …`) automatically
///     grants super admins full read/write on ALL tenants — no policy
///     edits were needed.
///   * check_tenant_access(p_tenant_id) RPC — suspension/expiry gate.
///
/// SECURITY MODEL (defense in depth):
///   1. RLS is the real enforcement: only super admins can UPDATE the
///      tenants control columns (members get SELECT on their own tenant).
///   2. Every mutating method below ALSO checks isSuperAdmin() first and
///      throws [SuperAdminDenied] when the caller is not a super admin —
///      fail-closed on the client, never trust the UI.
///   3. Suspension/expiry are enforced app-side: call [checkTenantAccess]
///      on app startup and on tenant switch; block navigation with the
///      returned Urdu [TenantAccessResult.message] when not allowed.
///      RLS is deliberately NOT changed for suspension so a suspended
///      tenant's data stays intact and the super admin can still manage
///      it.
/// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import '../observability/app_logger.dart';
import 'supabase_service.dart';

/// Thrown when a non-super-admin attempts a super-admin mutation.
class SuperAdminDenied implements Exception {
  final String message;
  const SuperAdminDenied(
      [this.message = 'صرف سپر ایڈمن یہ عمل انجام دے سکتا ہے']);
  @override
  String toString() => 'SuperAdminDenied: $message';
}

/// Compact tenant row for the super-admin tenant list.
class TenantSummary {
  final String id;
  final String name;
  final String? nameUrdu;
  final String slug;
  final bool isSuspended;
  final String? suspensionReason;
  final DateTime? expiresAt;
  final String? adminMessage;

  const TenantSummary({
    required this.id,
    required this.name,
    this.nameUrdu,
    required this.slug,
    required this.isSuspended,
    this.suspensionReason,
    this.expiresAt,
    this.adminMessage,
  });

  factory TenantSummary.fromMap(Map<String, dynamic> map) => TenantSummary(
        id: '${map['id']}',
        name: (map['name'] as String?) ?? '',
        nameUrdu: map['name_urdu'] as String?,
        slug: (map['slug'] as String?) ?? '',
        isSuspended: (map['is_suspended'] as bool?) ?? false,
        suspensionReason: map['suspension_reason'] as String?,
        expiresAt: map['expires_at'] == null
            ? null
            : DateTime.tryParse('${map['expires_at']}'),
        adminMessage: map['admin_message'] as String?,
      );

  /// True when the subscription has a past expiry date.
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
}

/// Result of [SuperAdminService.checkTenantAccess].
class TenantAccessResult {
  /// False when the tenant is suspended, expired, or not found.
  final bool allowed;

  /// 'ok' | 'suspended' | 'expired' | 'not_found' | 'error'
  final String reason;

  /// Urdu message suitable for display when [allowed] is false.
  /// Empty when [allowed] is true and no broadcast message exists.
  final String message;

  /// The super admin's broadcast message for this tenant (may be shown
  /// even when access is allowed).
  final String? adminMessage;

  /// The super admin's suspension reason, if any.
  final String? suspensionReason;

  final DateTime? expiresAt;

  const TenantAccessResult({
    required this.allowed,
    required this.reason,
    required this.message,
    this.adminMessage,
    this.suspensionReason,
    this.expiresAt,
  });
}

class SuperAdminService {
  static final _client = SupabaseService.client;
  static AppLogger get _log => AppLogger();

  // ── Queries ──────────────────────────────────────────────────

  /// True when [userId] (default: current user) is a SaaS super admin.
  /// Reads public.super_admins — its RLS allows platform/super admins;
  /// a non-admin gets zero rows (not an error), hence the row check.
  static Future<bool> isSuperAdmin([String? userId]) async {
    try {
      final uid = userId ?? _client.auth.currentUser?.id;
      if (uid == null) return false;
      final rows = await _client
          .from('super_admins')
          .select('user_id')
          .eq('user_id', uid)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (e) {
      _log.warning('[SuperAdmin] isSuperAdmin check failed', error: e);
      return false; // fail-closed
    }
  }

  /// All tenants with their SaaS control state, newest first.
  /// RLS: super admins bypass tenant RLS via is_platform_admin().
  static Future<List<TenantSummary>> getAllTenants() async {
    await _requireSuperAdmin();
    final rows = await _client.from('tenants').select(
        'id, name, name_urdu, slug, is_suspended, suspension_reason, '
        'expires_at, admin_message').order('created_at', ascending: false);
    return (rows as List)
        .map((r) => TenantSummary.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Suspension/expiry gate for [tenantId].
  ///
  /// Calls the `check_tenant_access` RPC (SECURITY DEFINER, callable by
  /// any authenticated user) and composes the Urdu [TenantAccessResult.message].
  /// Call on app startup and on tenant switch; block navigation when
  /// [TenantAccessResult.allowed] is false.
  static Future<TenantAccessResult> checkTenantAccess(String tenantId) async {
    try {
      final raw = await _client.rpc(
        'check_tenant_access',
        params: {'p_tenant_id': tenantId},
      );
      final map = Map<String, dynamic>.from(raw as Map);
      final allowed = (map['allowed'] as bool?) ?? false;
      final reason = (map['reason'] as String?) ?? 'error';
      final suspensionReason = map['suspension_reason'] as String?;
      final adminMessage = map['admin_message'] as String?;
      final expiresAt = map['expires_at'] == null
          ? null
          : DateTime.tryParse('${map['expires_at']}');
      return TenantAccessResult(
        allowed: allowed,
        reason: reason,
        message: _urduMessageFor(
          reason: reason,
          suspensionReason: suspensionReason,
          adminMessage: adminMessage,
        ),
        adminMessage: adminMessage,
        suspensionReason: suspensionReason,
        expiresAt: expiresAt,
      );
    } catch (e) {
      _log.warning('[SuperAdmin] checkTenantAccess RPC failed', error: e);
      // Fail-closed on transport errors, but surface it distinctly so
      // the UI can offer a retry instead of a suspension message.
      return const TenantAccessResult(
        allowed: false,
        reason: 'error',
        message: 'رسائی کی جانچ نہیں ہو سکی۔ براہ کرم دوبارہ کوشش کریں۔',
      );
    }
  }

  // ── Mutations (super admin only) ─────────────────────────────

  /// Suspend [tenantId] immediately with an optional [reason].
  static Future<void> suspendTenant(String tenantId, [String? reason]) async {
    await _requireSuperAdmin();
    await _client.from('tenants').update({
      'is_suspended': true,
      'suspended_at': DateTime.now().toIso8601String(),
      'suspension_reason': reason,
    }).eq('id', tenantId);
    _log.info('[SuperAdmin] suspended tenant $tenantId'
        '${reason == null ? '' : ' — $reason'}');
  }

  /// Lift a suspension on [tenantId].
  static Future<void> unsuspendTenant(String tenantId) async {
    await _requireSuperAdmin();
    await _client.from('tenants').update({
      'is_suspended': false,
      'suspended_at': null,
      'suspension_reason': null,
    }).eq('id', tenantId);
    _log.info('[SuperAdmin] unsuspended tenant $tenantId');
  }

  /// Restrict usage after [expiresAt] (any future date — days, months
  /// or years out). NULL expiry is not allowed here; use
  /// [clearTenantExpiry] to remove it.
  static Future<void> setTenantExpiry(
      String tenantId, DateTime expiresAt) async {
    await _requireSuperAdmin();
    await _client.from('tenants').update({
      'expires_at': expiresAt.toIso8601String(),
    }).eq('id', tenantId);
    _log.info('[SuperAdmin] set expiry for tenant $tenantId → $expiresAt');
  }

  /// Remove the expiry on [tenantId] (unlimited usage).
  static Future<void> clearTenantExpiry(String tenantId) async {
    await _requireSuperAdmin();
    await _client
        .from('tenants')
        .update({'expires_at': null}).eq('id', tenantId);
    _log.info('[SuperAdmin] cleared expiry for tenant $tenantId');
  }

  /// Show [message] (e.g. a payment reminder) on the tenant's screens.
  static Future<void> setTenantMessage(
      String tenantId, String message) async {
    await _requireSuperAdmin();
    await _client.from('tenants').update({
      'admin_message': message,
      'admin_message_at': DateTime.now().toIso8601String(),
    }).eq('id', tenantId);
    _log.info('[SuperAdmin] set admin message for tenant $tenantId');
  }

  /// Remove the broadcast message from [tenantId].
  static Future<void> clearTenantMessage(String tenantId) async {
    await _requireSuperAdmin();
    await _client.from('tenants').update({
      'admin_message': null,
      'admin_message_at': null,
    }).eq('id', tenantId);
    _log.info('[SuperAdmin] cleared admin message for tenant $tenantId');
  }

  // ── Internals ────────────────────────────────────────────────

  /// Client-side fail-closed guard. RLS remains the real enforcement;
  /// this stops a mis-wired UI from even attempting the mutation.
  static Future<void> _requireSuperAdmin() async {
    if (!await isSuperAdmin()) {
      _log.warning('[SuperAdmin] denied: caller is not a super admin');
      throw const SuperAdminDenied();
    }
  }

  /// Urdu UI message for a [checkTenantAccess] reason. The super admin's
  /// own broadcast/suspension text is appended when present.
  static String _urduMessageFor({
    required String reason,
    String? suspensionReason,
    String? adminMessage,
  }) {
    final extra = [
      if (suspensionReason != null && suspensionReason.trim().isNotEmpty)
        suspensionReason.trim(),
      if (adminMessage != null && adminMessage.trim().isNotEmpty)
        adminMessage.trim(),
    ].join('\n');
    final suffix = extra.isEmpty ? '' : '\n$extra';
    switch (reason) {
      case 'ok':
        return '';
      case 'suspended':
        return 'اس مدرسے کی رسائی عارضی طور پر معطل کر دی گئی ہے۔'
            ' براہ کرم انتظامیہ سے رابطہ کریں۔$suffix';
      case 'expired':
        return 'اس مدرسے کی رکنیت کی میعاد ختم ہو چکی ہے۔'
            ' جاری رکھنے کے لیے براہ کرم ادائیگی کریں۔$suffix';
      case 'not_found':
        return 'مدرسہ نہیں ملا۔ براہ کرم دوبارہ لاگ اِن کریں۔';
      default:
        return 'رسائی کی جانچ نہیں ہو سکی۔ براہ کرم دوبارہ کوشش کریں۔';
    }
  }

  @visibleForTesting
  static String urduMessageForTesting({
    required String reason,
    String? suspensionReason,
    String? adminMessage,
  }) =>
      _urduMessageFor(
        reason: reason,
        suspensionReason: suspensionReason,
        adminMessage: adminMessage,
      );
}
