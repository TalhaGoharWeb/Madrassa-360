// ── Madrasa 360 — ScopeService ───────────────────────────────────────────────
// Resolves the signed-in user's DATA SCOPE for a permission in the active
// tenant, from `public.permission_scopes` (019):
//
//   all        → پورا مدرسہ                      (whole madrasa)
//   department → صرف میرے شعبے کے افراد
//   classes    → صرف میری مقرر کردہ جماعتوں کے طلبہ
//   students   → صرف میرے طلبہ
//
// FAIL-CLOSED (migration 022): `scope_allows()` denies when NO
// `permission_scopes` row exists for an effective grant, and the 022
// provisioning triggers keep a row present for every grant (backfilled for
// existing grants; insert-only triggers for membership / role-grant /
// explicit-grant / delegation changes). This service mirrors that contract
// for the UI:
//
//   * no row for a permission      → treat as DENIED (hide / filter out)
//   * scope rows fail to load       → treat as DENIED (hide / filter out)
//   * unknown scope_type            → treat as DENIED (never as `all`)
//
// UX-ONLY: these helpers filter lists and hide UI affordances. Supabase RLS
// (`scope_allows()`, 020/022) remains the real enforcement — a scoped-out
// write is rejected server-side even if the UI showed the row.
//
// Null-vs-empty contract for the `*InScope` helpers:
//   null          → the row is `all`: do NOT filter.
//   empty set     → restricted to nothing (fail-closed: no row, load error,
//                   or an unevaluatable scope such as `department`).
//   non-empty set → restrict list queries to these ids.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../observability/app_logger.dart';
import 'supabase_service.dart';
import 'tenant_context.dart';

/// One `permission_scopes` row: the data scope for a single permission.
class PermissionScope {
  final String permission;
  final String
      scopeType; // 'all' | 'department' | 'classes' | 'students' | 'unknown'
  final Set<String> classIds; // scope_ref.class_ids
  final Set<String> studentIds; // scope_ref.student_ids
  final String? department; // scope_ref.department

  const PermissionScope({
    required this.permission,
    required this.scopeType,
    this.classIds = const {},
    this.studentIds = const {},
    this.department,
  });

  /// True only for an explicit `all` row. Anything else — narrower scopes
  /// AND the defensive `unknown` type — is a restriction.
  bool get isUnrestricted => scopeType == 'all';

  /// Plain-language Urdu description for UI (never a raw code or jargon).
  String get descriptionUrdu {
    switch (scopeType) {
      case 'department':
        return 'صرف میرے شعبے کے افراد';
      case 'classes':
        return 'صرف میری مقرر کردہ جماعتوں کے طلبہ';
      case 'students':
        return 'صرف میرے طلبہ';
      case 'all':
        return 'پورا مدرسہ';
      default:
        return 'نامعلوم دائرہ';
    }
  }

  factory PermissionScope.fromRow({
    required String permission,
    required Map<String, dynamic> row,
  }) {
    final ref = row['scope_ref'];
    final refMap = ref is Map<String, dynamic> ? ref : <String, dynamic>{};
    final rawType = row['scope_type'] as String?;
    return PermissionScope(
      permission: permission,
      // Fail closed: a missing or unrecognized type is `unknown`
      // (restricted), never `all`.
      scopeType: _knownScopeType(rawType) ? rawType! : 'unknown',
      classIds: _stringSet(refMap['class_ids']),
      studentIds: _stringSet(refMap['student_ids']),
      department: refMap['department'] as String?,
    );
  }

  static bool _knownScopeType(String? t) =>
      t == 'all' || t == 'department' || t == 'classes' || t == 'students';

  static Set<String> _stringSet(dynamic value) {
    if (value is List) return {for (final e in value) '$e'};
    return const {};
  }
}

class ScopeService {
  ScopeService(this._ref);

  final Ref _ref;

  String? _tenantId;
  String? _userId;

  /// Loaded scope rows, or null when unknown: not yet loaded, the load
  /// failed, or no tenant/user is active. Null is FAIL-CLOSED — every
  /// helper below treats it as "deny / show nothing".
  Map<String, PermissionScope>? _scopes;

  /// Scope row for [permission] in the active tenant, or null when there is
  /// no row, the rows failed to load, or no tenant/user is active.
  ///
  /// Null is FAIL-CLOSED (deny): under migration 022 `scope_allows()`
  /// denies when no row exists, so a missing row must never be read as
  /// "unrestricted" in the UI.
  Future<PermissionScope?> scopeFor(String permission) async {
    final scopes = await _ensureLoaded();
    return scopes?[permission];
  }

  /// Client mirror of `scope_allows()`: may [classId] be acted on under
  /// [permission]? Fail-closed: no row, load error, narrower scopes with an
  /// unverifiable target, and unknown scope types all deny.
  /// UX hint only — RLS decides.
  Future<bool> scopeAllows(String permission, {String? classId}) async {
    final scope = await scopeFor(permission);
    if (scope == null) return false;
    if (scope.isUnrestricted) return true;
    if (classId == null) return false;
    switch (scope.scopeType) {
      case 'classes':
        return scope.classIds.contains(classId);
      case 'students':
        final ids = await studentIdsInScope(permission);
        if (ids == null || ids.isEmpty) return false;
        return await _anyStudentInClass(ids, classId);
      case 'department':
        // No department dimension on classes: fail closed (mirrors 020).
        return false;
      default:
        return false;
    }
  }

  /// Class ids the user may see/act on for [permission].
  /// Null = the row is `all` (do not filter); empty = show nothing
  /// (fail-closed: no row, load error, or unevaluatable scope).
  Future<Set<String>?> classIdsInScope(String permission) async {
    final scope = await scopeFor(permission);
    if (scope == null) return <String>{};
    if (scope.isUnrestricted) return null;
    switch (scope.scopeType) {
      case 'classes':
        return scope.classIds;
      case 'students':
        return _classIdsOfStudents(scope.studentIds);
      case 'department':
      default:
        return <String>{};
    }
  }

  /// Student ids the user may see/act on for [permission].
  /// Null = the row is `all` (do not filter); empty = show nothing
  /// (fail-closed: no row, load error, or unevaluatable scope).
  Future<Set<String>?> studentIdsInScope(String permission) async {
    final scope = await scopeFor(permission);
    if (scope == null) return <String>{};
    if (scope.isUnrestricted) return null;
    switch (scope.scopeType) {
      case 'students':
        return scope.studentIds;
      case 'classes':
        return _studentIdsInClasses(scope.classIds);
      case 'department':
      default:
        return <String>{};
    }
  }

  /// Plain-language Urdu scope description for UI badges/hints.
  /// Unknown / missing scope is reported as such — never as "whole madrasa".
  Future<String> scopeDescriptionUrdu(String permission) async {
    final scope = await scopeFor(permission);
    return scope?.descriptionUrdu ?? 'نامعلوم دائرہ';
  }

  /// Drops the in-memory scope rows (call on tenant switch / sign-out).
  void clearCache() {
    _tenantId = null;
    _userId = null;
    _scopes = null;
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<Map<String, PermissionScope>?> _ensureLoaded() async {
    final tenantId = _ref.read(activeTenantIdProvider);
    if (tenantId == null) return null;
    String? userId;
    try {
      userId = SupabaseService.client.auth.currentUser?.id;
    } catch (_) {
      userId = null;
    }
    if (userId == null) return null;
    if (_tenantId == tenantId && _userId == userId) return _scopes;

    final out = <String, PermissionScope>{};
    try {
      final rows = await SupabaseService.client
          .from('permission_scopes')
          .select('scope_type, scope_ref, permissions!inner(code)')
          .eq('tenant_id', tenantId)
          .eq('user_id', userId);
      for (final row in (rows as List)) {
        final map = row as Map<String, dynamic>;
        final perm =
            (map['permissions'] as Map<String, dynamic>?)?['code'] as String?;
        if (perm == null) continue;
        out[perm] = PermissionScope.fromRow(permission: perm, row: map);
      }
    } catch (e) {
      // Fail closed: a load error must not read as "unrestricted".
      // The failure is NOT cached, so the next call retries.
      AppLogger()
          .warning('[Scopes] failed to load permission_scopes', error: e);
      return null;
    }
    _tenantId = tenantId;
    _userId = userId;
    _scopes = out;
    return out;
  }

  Future<Set<String>> _classIdsOfStudents(Set<String> studentIds) async {
    if (studentIds.isEmpty || _tenantId == null) return <String>{};
    try {
      final rows = await SupabaseService.client
          .from('students')
          .select('class_id')
          .eq('tenant_id', _tenantId!)
          .inFilter('id', studentIds.toList());
      return {
        for (final r in (rows as List))
          if ((r as Map<String, dynamic>)['class_id'] != null)
            '${r['class_id']}',
      };
    } catch (e) {
      AppLogger()
          .warning('[Scopes] failed to resolve student classes', error: e);
      return <String>{};
    }
  }

  Future<Set<String>> _studentIdsInClasses(Set<String> classIds) async {
    if (classIds.isEmpty || _tenantId == null) return <String>{};
    try {
      final rows = await SupabaseService.client
          .from('students')
          .select('id')
          .eq('tenant_id', _tenantId!)
          .inFilter('class_id', classIds.toList());
      return {
        for (final r in (rows as List)) '${(r as Map<String, dynamic>)['id']}',
      };
    } catch (e) {
      AppLogger()
          .warning('[Scopes] failed to resolve class students', error: e);
      return <String>{};
    }
  }

  Future<bool> _anyStudentInClass(
      Set<String> studentIds, String classId) async {
    if (studentIds.isEmpty || _tenantId == null) return false;
    try {
      final rows = await SupabaseService.client
          .from('students')
          .select('id')
          .eq('tenant_id', _tenantId!)
          .eq('class_id', classId)
          .inFilter('id', studentIds.toList())
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (e) {
      AppLogger().warning('[Scopes] failed scope class check', error: e);
      return false;
    }
  }
}

/// Per-tenant scope rows for the signed-in user.
final scopeServiceProvider = Provider<ScopeService>((ref) {
  return ScopeService(ref);
});
