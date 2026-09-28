/// ڈیٹا حدود — ڈائریکٹری ریپازٹری (Phase 9)
///
/// Tenant-wide read model over `public.permission_scopes` (019): one
/// [ScopeAssignment] per (user × permission) row, with display names
/// resolved client-side from member-readable tables (`profiles`,
/// `tenant_memberships`, `classes`, `students`) — never the
/// `manage-users` edge function, so a `roles.assign` holder without
/// `users.view` can still open the screen.
///
/// Writes reuse [RoleUxRepository.writeScopes]: 020 RLS (`roles.assign`
/// or owner/admin) is the server-side enforcement, and the 019
/// auto-audit trigger writes `permission_scopes.created|updated|deleted`
/// rows (rendered human-readable by `audit_urdu.dart`).
///
/// Offline: the last-known-good list is cached per (user, tenant) in
/// SharedPreferences with a fetched-at timestamp. On a network failure
/// the cache is served with [ScopeAssignmentListResult.fromCache] true
/// and the UI shows an honest stale banner. Tenant isolation is
/// defense-in-depth: every query carries `.eq('tenant_id', …)` and rows
/// for any other tenant are dropped before caching.

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/observability/app_logger.dart';
import '../core/services/storage_service.dart';
import '../core/services/supabase_service.dart';
import '../core/utils/audit_urdu.dart';
import 'role_ux_repository.dart';

// ─────────────────────────────────────────────────────────────
// Models (plain data — no mock values anywhere)
// ─────────────────────────────────────────────────────────────

/// One `permission_scopes` row with resolved display names.
class ScopeAssignment {
  const ScopeAssignment({
    required this.id,
    required this.tenantId,
    required this.userId,
    required this.userName,
    required this.userRoleUrdu,
    required this.permissionCode,
    required this.permissionLabelUrdu,
    required this.scopeType,
    this.classIds = const {},
    this.studentIds = const {},
    this.classNames = const {},
    this.studentNames = const {},
    required this.createdAt,
  });

  final String id;
  final String tenantId;
  final String userId;

  /// Display name from `profiles` (Urdu-first); falls back to a
  /// shortened id — never blank, never a raw auth id in the UI.
  final String userName;

  /// Plain-Urdu role label (via [roleKeyUrdu]).
  final String userRoleUrdu;
  final String permissionCode;
  final String permissionLabelUrdu;

  /// 'all' | 'department' | 'classes' | 'students'
  final String scopeType;
  final Set<String> classIds;
  final Set<String> studentIds;
  final Map<String, String> classNames;
  final Map<String, String> studentNames;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'user_id': userId,
        'user_name': userName,
        'user_role_urdu': userRoleUrdu,
        'permission_code': permissionCode,
        'permission_label_urdu': permissionLabelUrdu,
        'scope_type': scopeType,
        'class_ids': classIds.toList(),
        'student_ids': studentIds.toList(),
        'class_names': classNames,
        'student_names': studentNames,
        'created_at': createdAt.toIso8601String(),
      };

  factory ScopeAssignment.fromJson(Map<String, dynamic> j) {
    String s(Object? v) => v is String ? v : '';
    Set<String> set(Object? v) => v is List
        ? {
            for (final e in v)
              if ('$e'.isNotEmpty) '$e'
          }
        : <String>{};
    Map<String, String> strMap(Object? v) => v is Map
        ? {
            for (final e in v.entries)
              if ('${e.key}'.isNotEmpty) '${e.key}': '${e.value}',
          }
        : <String, String>{};
    return ScopeAssignment(
      id: s(j['id']),
      tenantId: s(j['tenant_id']),
      userId: s(j['user_id']),
      userName: s(j['user_name']),
      userRoleUrdu: s(j['user_role_urdu']),
      permissionCode: s(j['permission_code']),
      permissionLabelUrdu: s(j['permission_label_urdu']),
      scopeType: s(j['scope_type']).isEmpty ? 'all' : s(j['scope_type']),
      classIds: set(j['class_ids']),
      studentIds: set(j['student_ids']),
      classNames: strMap(j['class_names']),
      studentNames: strMap(j['student_names']),
      createdAt: DateTime.tryParse(s(j['created_at'])) ?? DateTime.now(),
    );
  }
}

/// Scope list result: the rows, whether they came from the offline cache,
/// and when they were last fetched from the network (null for a pure
/// cache hit whose timestamp was lost — the UI then says "unknown").
class ScopeAssignmentListResult {
  const ScopeAssignmentListResult({
    required this.items,
    required this.fromCache,
    this.fetchedAt,
  });

  final List<ScopeAssignment> items;

  /// True when the rows came from the last-known offline cache because
  /// the network read failed.
  final bool fromCache;
  final DateTime? fetchedAt;
}

// ─────────────────────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────────────────────

abstract class ScopeManagerRepository {
  /// Every `permission_scopes` row in [tenantId] with display names.
  /// Falls back to the last-known offline cache when the network fails.
  Future<ScopeAssignmentListResult> listAssignments(
    String tenantId, {
    String? userId,
  });

  /// Display names for student ids (member-readable `students` table).
  Future<Map<String, String>> studentNames(String tenantId, Set<String> ids);

  /// class_id per student id — used by [ScopePolicy] to check that a
  /// requested student set sits inside the granter's class set.
  Future<Map<String, String>> classIdOfStudents(
      String tenantId, Set<String> studentIds);

  String? get currentUserId;
}

// ─────────────────────────────────────────────────────────────
// Supabase implementation
// ─────────────────────────────────────────────────────────────

class SupabaseScopeManagerRepository implements ScopeManagerRepository {
  SupabaseScopeManagerRepository({required RoleUxRepository roleUx})
      : _roleUx = roleUx;

  final RoleUxRepository _roleUx;

  SupabaseClient get _client => SupabaseService.client;
  AppLogger get _log => AppLogger();

  @override
  String? get currentUserId => _roleUx.currentUserId;

  static String _cacheKey(String tenantId, String userId) =>
      'scope_assignments.v1.$userId.$tenantId';

  static String _cacheTimeKey(String tenantId, String userId) =>
      'scope_assignments.v1.$userId.$tenantId.fetched_at';

  Map<String, dynamic> _asMap(Object? v) =>
      v is Map<String, dynamic> ? v : <String, dynamic>{};

  Set<String> _stringSet(Object? v) {
    if (v is! List) return <String>{};
    return {
      for (final e in v)
        if ('$e'.isNotEmpty) '$e'
    };
  }

  @override
  Future<ScopeAssignmentListResult> listAssignments(
    String tenantId, {
    String? userId,
  }) async {
    final uid = userId ?? currentUserId;
    try {
      final rows = await _client
          .from('permission_scopes')
          .select('id, tenant_id, user_id, permission_id, scope_type, '
              'scope_ref, created_at, permissions!inner(code)')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false);

      final raw = [
        for (final r in (rows as List)) _asMap(r),
      ]
          // Defensive: the query is already tenant-filtered; never accept
          // a row for another tenant into this tenant's list.
          .where((m) => '${m['tenant_id']}' == tenantId)
          .toList();

      final items = await _resolve(raw, tenantId);
      final fetchedAt = DateTime.now();
      await _persistList(tenantId, uid, items, fetchedAt);
      return ScopeAssignmentListResult(
          items: items, fromCache: false, fetchedAt: fetchedAt);
    } catch (e) {
      _log.warning(
          '[Scopes] list failed for tenant $tenantId — trying offline cache',
          error: e);
      final cached = await _readCachedList(tenantId, uid);
      if (cached != null) {
        _log.info(
            '[Scopes] using last-known cached list (${cached.items.length} rows)');
        return cached;
      }
      rethrow;
    }
  }

  /// Resolves display names for raw scope rows (all member-readable).
  Future<List<ScopeAssignment>> _resolve(
      List<Map<String, dynamic>> raw, String tenantId) async {
    if (raw.isEmpty) return const [];

    final userIds = {for (final m in raw) '${m['user_id']}'}..remove('');
    final studentIds = <String>{
      for (final m in raw) ..._stringSet(_asMap(m['scope_ref'])['student_ids']),
    };
    final classIds = <String>{
      for (final m in raw) ..._stringSet(_asMap(m['scope_ref'])['class_ids']),
    };

    final names = await _profileNames(userIds);
    final roleKeys = await _membershipRoles(tenantId, userIds);
    final catalog = await _roleUx.permissionCatalog();
    final labelByCode = {for (final p in catalog) p.code: p.labelUrdu};
    final classes = await _roleUx.listClasses(tenantId);
    final classNameById = {for (final c in classes) c.id: c.name};
    final studentNameById = await studentNames(tenantId, studentIds);

    return [
      for (final m in raw)
        _toAssignment(
          m,
          tenantId: tenantId,
          names: names,
          roleKeys: roleKeys,
          labelByCode: labelByCode,
          classNameById: classNameById,
          studentNameById: studentNameById,
          knownClassIds: classIds,
        ),
    ];
  }

  ScopeAssignment _toAssignment(
    Map<String, dynamic> m, {
    required String tenantId,
    required Map<String, String> names,
    required Map<String, String> roleKeys,
    required Map<String, String> labelByCode,
    required Map<String, String> classNameById,
    required Map<String, String> studentNameById,
    required Set<String> knownClassIds,
  }) {
    final ref = _asMap(m['scope_ref']);
    final code = '${_asMap(m['permissions'])['code']}';
    final userId = '${m['user_id']}';
    final classIds = _stringSet(ref['class_ids']);
    final studentIds = _stringSet(ref['student_ids']);
    return ScopeAssignment(
      id: '${m['id']}',
      tenantId: tenantId,
      userId: userId,
      userName: names[userId] ??
          (userId.length > 8 ? 'صارف ${userId.substring(0, 8)}…' : 'صارف'),
      userRoleUrdu: roleKeyUrdu(roleKeys[userId]),
      permissionCode: code,
      permissionLabelUrdu: labelByCode[code] ?? (code.isEmpty ? 'اجازت' : code),
      scopeType: '${m['scope_type']}'.isEmpty ? 'all' : '${m['scope_type']}',
      classIds: classIds,
      studentIds: studentIds,
      classNames: {
        for (final id in classIds)
          if (classNameById[id] != null) id: classNameById[id]!,
      },
      studentNames: {
        for (final id in studentIds)
          if (studentNameById[id] != null) id: studentNameById[id]!,
      },
      createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
    );
  }

  /// Display names from `profiles` (tenant members may read).
  Future<Map<String, String>> _profileNames(Set<String> userIds) async {
    if (userIds.isEmpty) return const {};
    try {
      final rows = await _client
          .from('profiles')
          .select('id, name')
          .inFilter('id', userIds.toList());
      return {
        for (final r in (rows as List))
          if ('${(r as Map)['id']}'.isNotEmpty)
            '${r['id']}': '${r['name']}'.isNotEmpty ? '${r['name']}' : 'صارف',
      };
    } catch (e) {
      _log.warning('[Scopes] failed to resolve profile names', error: e);
      return const {};
    }
  }

  /// Role key per user from `tenant_memberships` (member-readable).
  Future<Map<String, String>> _membershipRoles(
      String tenantId, Set<String> userIds) async {
    if (userIds.isEmpty) return const {};
    try {
      final rows = await _client
          .from('tenant_memberships')
          .select('user_id, role')
          .eq('tenant_id', tenantId)
          .inFilter('user_id', userIds.toList());
      return {
        for (final r in (rows as List))
          if ('${(r as Map)['user_id']}'.isNotEmpty)
            '${r['user_id']}': '${r['role']}',
      };
    } catch (e) {
      _log.warning('[Scopes] failed to resolve membership roles', error: e);
      return const {};
    }
  }

  @override
  Future<Map<String, String>> studentNames(
      String tenantId, Set<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final rows = await _client
          .from('students')
          .select('id, name')
          .eq('tenant_id', tenantId)
          .inFilter('id', ids.toList());
      return {
        for (final r in (rows as List))
          if ('${(r as Map)['id']}'.isNotEmpty && '${r['name']}'.isNotEmpty)
            '${r['id']}': '${r['name']}',
      };
    } catch (e) {
      _log.warning('[Scopes] failed to resolve student names', error: e);
      return const {};
    }
  }

  @override
  Future<Map<String, String>> classIdOfStudents(
      String tenantId, Set<String> studentIds) async {
    if (studentIds.isEmpty) return const {};
    try {
      final rows = await _client
          .from('students')
          .select('id, class_id')
          .eq('tenant_id', tenantId)
          .inFilter('id', studentIds.toList());
      return {
        for (final r in (rows as List))
          if ('${(r as Map)['id']}'.isNotEmpty && '${r['class_id']}'.isNotEmpty)
            '${r['id']}': '${r['class_id']}',
      };
    } catch (e) {
      _log.warning('[Scopes] failed to resolve student classes', error: e);
      return const {};
    }
  }

  /// Persists the last-known-good list with its fetch time. Never
  /// persists without a user id — the cache is keyed per user so one
  /// device user cannot read another's.
  Future<void> _persistList(String tenantId, String? userId,
      List<ScopeAssignment> items, DateTime fetchedAt) async {
    if (userId == null) return;
    try {
      await StorageService.saveStringList(
        _cacheKey(tenantId, userId),
        [for (final a in items) jsonEncode(a.toJson())],
      );
      await StorageService.saveString(
        _cacheTimeKey(tenantId, userId),
        fetchedAt.toIso8601String(),
      );
    } catch (e) {
      _log.warning('[Scopes] failed to persist list cache', error: e);
    }
  }

  Future<ScopeAssignmentListResult?> _readCachedList(
      String tenantId, String? userId) async {
    if (userId == null) return null;
    try {
      final raw = StorageService.getStringList(_cacheKey(tenantId, userId));
      if (raw == null) return null;
      final items = <ScopeAssignment>[];
      for (final s in raw) {
        try {
          final a =
              ScopeAssignment.fromJson(jsonDecode(s) as Map<String, dynamic>);
          // Defensive: never serve another tenant's rows from this cache.
          if (a.tenantId == tenantId && a.id.isNotEmpty) items.add(a);
        } catch (_) {
          // Skip a single corrupt row rather than dropping the cache.
        }
      }
      final atRaw = StorageService.getString(_cacheTimeKey(tenantId, userId));
      return ScopeAssignmentListResult(
        items: items,
        fromCache: true,
        fetchedAt: DateTime.tryParse(atRaw ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}
