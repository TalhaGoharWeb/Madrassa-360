/// اختیار سونپنے کا ڈیٹا رسائی (Phase 8b)
/// Delegation repository — the single real-data gateway for the 8b
/// delegation management flows (list, create, revoke).
///
/// Write paths (never direct unchecked writes):
///   - create -> `delegate_permission` RPC (SECURITY DEFINER, 019 ceiling
///     trigger re-enforces: caller must hold `roles.assign` AND effectively
///     hold the delegated code themselves; delegations never chain)
///   - revoke -> RLS-guarded DELETE on `permission_delegations`
///     ("role managers write" policy: tenant admin or `roles.assign`)
///
/// Reads go through RLS as the authenticated user ("tenant members read").
/// The list is offline-cached per (user, tenant) like [PermissionService]:
/// network -> last-known cache -> honest error. Failures are mapped to
/// plain Urdu by [delegationErrorMessage] — PostgREST / RLS text never
/// reaches the UI.

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/observability/app_logger.dart';
import '../core/services/storage_service.dart';
import '../core/services/supabase_service.dart';
import 'role_ux_repository.dart';

// ─────────────────────────────────────────────────────────────
// Models (plain data, no mock values anywhere)
// ─────────────────────────────────────────────────────────────

/// One row of `permission_delegations` (019), with the permission code
/// resolved from the embedded `permissions` relation.
class DelegationInfo {
  const DelegationInfo({
    required this.id,
    required this.tenantId,
    required this.delegatorId,
    required this.delegateeId,
    required this.permissionId,
    required this.permissionCode,
    required this.scopeType,
    this.scopeRef = const {},
    required this.startsAt,
    this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String tenantId;
  final String delegatorId;
  final String delegateeId;
  final String permissionId;
  final String permissionCode;

  /// 'all' | 'department' | 'classes' | 'students'
  final String scopeType;
  final Map<String, dynamic> scopeRef;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final DateTime createdAt;

  /// True when the delegation still grants at [now]: no expiry set, or
  /// the expiry is in the future. The server honors the same rule —
  /// `get_my_permissions_detailed` (020) excludes expired rows, so an
  /// expired delegation stops granting immediately.
  bool isActiveAt(DateTime now) => expiresAt == null || expiresAt!.isAfter(now);

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'delegator_id': delegatorId,
        'delegatee_id': delegateeId,
        'permission_id': permissionId,
        'permission_code': permissionCode,
        'scope_type': scopeType,
        'scope_ref': scopeRef,
        'starts_at': startsAt.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  factory DelegationInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    final ref = json['scope_ref'];
    return DelegationInfo(
      id: '${json['id'] ?? ''}',
      tenantId: '${json['tenant_id'] ?? ''}',
      delegatorId: '${json['delegator_id'] ?? ''}',
      delegateeId: '${json['delegatee_id'] ?? ''}',
      permissionId: '${json['permission_id'] ?? ''}',
      permissionCode: '${json['permission_code'] ?? ''}',
      scopeType: '${json['scope_type'] ?? 'all'}',
      scopeRef: ref is Map<String, dynamic> ? ref : const {},
      startsAt: parse(json['starts_at']) ?? DateTime.now(),
      expiresAt: parse(json['expires_at']),
      createdAt: parse(json['created_at']) ?? DateTime.now(),
    );
  }
}

/// Delegation list result: the rows plus whether they came from the
/// offline cache (the UI shows an honest "offline" banner then).
class DelegationListResult {
  const DelegationListResult({
    required this.items,
    required this.fromCache,
  });

  final List<DelegationInfo> items;

  /// True when the rows came from the last-known offline cache because
  /// the network read failed.
  final bool fromCache;
}

/// Scope written on a delegation row. Never wider than the delegator's
/// own scope for that permission (the create screen resolves this via
/// [ScopeService]).
class DelegationScope {
  const DelegationScope({this.type = 'all', this.ref = const {}});

  final String type;
  final Map<String, dynamic> ref;
}

// ─────────────────────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────────────────────

abstract class DelegationRepository {
  /// Delegations visible in [tenantId] (RLS: tenant members read).
  /// Falls back to the last-known offline cache when the network fails.
  Future<DelegationListResult> listDelegations(
    String tenantId, {
    String? userId,
  });

  /// Delegates [code] to [delegateeId] in [tenantId] via the
  /// `delegate_permission` RPC. The server enforces the ceiling; the
  /// failure is mapped to plain Urdu by the caller.
  Future<void> createDelegation({
    required String tenantId,
    required String delegateeId,
    required String code,
    DelegationScope scope = const DelegationScope(),
    DateTime? expiresAt,
  });

  /// Revokes one delegation: RLS-guarded delete (role managers only).
  /// [tenantId] is always sent — defense in depth on top of RLS.
  Future<void> revokeDelegation({
    required String tenantId,
    required String delegationId,
  });

  String? get currentUserId;

  /// Drops every cached delegation list for [userId] (call on sign-out).
  static Future<void> clearDelegationCache(String userId) async {
    try {
      final prefix = 'delegations.v1.$userId.';
      final keys = StorageService.getAllKeys()
          .where((k) => k.startsWith(prefix))
          .toList();
      for (final k in keys) {
        await StorageService.remove(k);
      }
    } catch (e) {
      AppLogger()
          .warning('[Delegations] failed to clear persisted cache', error: e);
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Supabase implementation (real data only)
// ─────────────────────────────────────────────────────────────

class SupabaseDelegationRepository implements DelegationRepository {
  SupabaseClient get _client => SupabaseService.client;
  AppLogger get _log => AppLogger();

  @override
  String? get currentUserId => SupabaseService.currentUser?.id;

  static String _cacheKey(String tenantId, String userId) =>
      'delegations.v1.$userId.$tenantId';

  Map<String, dynamic> _asMap(Object? v) =>
      v is Map<String, dynamic> ? v : <String, dynamic>{};

  DateTime? _parseTime(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  DelegationInfo _fromRow(Map<String, dynamic> m) {
    final perm = _asMap(m['permissions']);
    return DelegationInfo(
      id: '${m['id'] ?? ''}',
      tenantId: '${m['tenant_id'] ?? ''}',
      delegatorId: '${m['delegator_id'] ?? ''}',
      delegateeId: '${m['delegatee_id'] ?? ''}',
      permissionId: '${m['permission_id'] ?? ''}',
      permissionCode: '${perm['code'] ?? ''}',
      scopeType: '${m['scope_type'] ?? 'all'}',
      scopeRef: _asMap(m['scope_ref']),
      startsAt: _parseTime(m['starts_at']) ?? DateTime.now(),
      expiresAt: _parseTime(m['expires_at']),
      createdAt: _parseTime(m['created_at']) ?? DateTime.now(),
    );
  }

  @override
  Future<DelegationListResult> listDelegations(
    String tenantId, {
    String? userId,
  }) async {
    final uid = userId ?? currentUserId;
    try {
      final rows = await _client
          .from('permission_delegations')
          .select('id, tenant_id, delegator_id, delegatee_id, permission_id, '
              'scope_type, scope_ref, starts_at, expires_at, created_at, '
              'permissions(code)')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false);
      final items = (rows as List)
          .map((r) => _fromRow(r as Map<String, dynamic>))
          // Defensive: the query is already tenant-filtered; never accept
          // a row for another tenant into this tenant's list.
          .where((d) => d.tenantId == tenantId && d.id.isNotEmpty)
          .toList();
      await _persistList(tenantId, uid, items);
      return DelegationListResult(items: items, fromCache: false);
    } catch (e) {
      _log.warning(
          '[Delegations] list failed for tenant $tenantId — '
          'trying offline cache',
          error: e);
      final cached = await _readCachedList(tenantId, uid);
      if (cached != null) {
        _log.info(
            '[Delegations] using last-known cached list (${cached.length} rows)');
        return DelegationListResult(items: cached, fromCache: true);
      }
      rethrow;
    }
  }

  /// Persists the last-known-good list. Never persists without a user id —
  /// the cache is keyed per user so one device user cannot read another's.
  Future<void> _persistList(
      String tenantId, String? userId, List<DelegationInfo> items) async {
    if (userId == null) return;
    try {
      await StorageService.saveStringList(
        _cacheKey(tenantId, userId),
        [for (final d in items) jsonEncode(d.toJson())],
      );
    } catch (e) {
      _log.warning('[Delegations] failed to persist list cache', error: e);
    }
  }

  Future<List<DelegationInfo>?> _readCachedList(
      String tenantId, String? userId) async {
    if (userId == null) return null;
    try {
      final raw = StorageService.getStringList(_cacheKey(tenantId, userId));
      if (raw == null) return null;
      final items = <DelegationInfo>[];
      for (final s in raw) {
        try {
          final d =
              DelegationInfo.fromJson(jsonDecode(s) as Map<String, dynamic>);
          if (d.tenantId == tenantId && d.id.isNotEmpty) items.add(d);
        } catch (_) {
          // Skip a single corrupt row rather than dropping the cache.
        }
      }
      return items;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createDelegation({
    required String tenantId,
    required String delegateeId,
    required String code,
    DelegationScope scope = const DelegationScope(),
    DateTime? expiresAt,
  }) async {
    await _client.rpc('delegate_permission', params: {
      'p_tenant_id': tenantId,
      'p_delegatee': delegateeId,
      'p_code': code,
      'p_scope_type': scope.type,
      'p_scope_ref': scope.ref,
      'p_expires_at': expiresAt?.toUtc().toIso8601String(),
    });
    _log.info('[Delegations] delegated $code', context: {
      'tenant_id': tenantId,
      'delegatee': delegateeId,
    });
  }

  @override
  Future<void> revokeDelegation({
    required String tenantId,
    required String delegationId,
  }) async {
    await _client
        .from('permission_delegations')
        .delete()
        .eq('id', delegationId)
        .eq('tenant_id', tenantId);
    _log.info('[Delegations] revoked delegation',
        context: {'tenant_id': tenantId, 'delegation_id': delegationId});
  }
}

// ─────────────────────────────────────────────────────────────
// Plain-Urdu error mapping (never leaks PostgREST / RLS text)
// ─────────────────────────────────────────────────────────────

/// Maps delegation failures to human, plain-Urdu messages. Delegation-
/// specific cases first, then the shared [roleUxErrorMessage] mapping.
/// The raw error is logged by callers but never shown.
String delegationErrorMessage(Object e) {
  final hay = e.toString().toLowerCase();

  if (hay.contains('cannot delegate to yourself') ||
      hay.contains('delegator and delegatee must differ')) {
    return 'آپ خود کو اختیار نہیں سونپ سکتے۔';
  }
  if (hay.contains('does not effectively hold permission')) {
    return 'یہ اختیار آپ کے پاس خود موجود نہیں — آپ صرف وہی اختیار سونپ '
        'سکتے ہیں جو آپ کو حاصل ہو۔';
  }
  if (hay.contains('lacks roles.assign')) {
    return 'آپ کے پاس اختیار سونپنے کی اجازت نہیں ہے۔';
  }
  if (hay.contains('p_expires_at must be in the future') ||
      hay.contains('expires_at must be after starts_at')) {
    return 'میعاد کی تاریخ آج سے آگے کی ہونی چاہیے۔';
  }
  if (hay.contains('is not a member of tenant')) {
    return 'منتخب صارف اس مدرسے کا رکن نہیں ہے۔';
  }
  return roleUxErrorMessage(e);
}
