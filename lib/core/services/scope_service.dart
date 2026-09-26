// ── Madrasa 360 — ScopeService ───────────────────────────────────────────────
// Resolves the signed-in user's DATA SCOPE for a permission in the active
// tenant, from `public.permission_scopes` (019):
//
//   all        → پورا مدرسہ                      (whole madrasa)
//   department → صرف میرے شعبے کے افراد
//   classes    → صرف میری مقرر کردہ جماعتوں کے طلبہ
//   students   → صرف میرے طلبہ
//
// UX-ONLY: these helpers filter lists and hide UI affordances. Supabase RLS
// (`scope_allows()`, 020) remains the real enforcement — a scoped-out write
// is rejected server-side even if the UI showed the row. When the scope rows
// cannot be loaded, the service behaves as "no row" (unrestricted display),
// exactly like `scope_allows()` does.
//
// Null-vs-empty contract for the `*InScope` helpers:
//   null          → unrestricted (no row, or scope `all`): do NOT filter.
//   empty set     → restricted to nothing (fail-closed, e.g. `department`
//                   scope which the data model cannot evaluate).
//   non-empty set → restrict list queries to these ids.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../observability/app_logger.dart';
import 'supabase_service.dart';
import 'tenant_context.dart';

/// One `permission_scopes` row: the data scope for a single permission.
class PermissionScope {
  final String permission;
  final String scopeType; // 'all' | 'department' | 'classes' | 'students'
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

  /// True for `all` (or an unknown type — treated as unrestricted, mirroring
  /// the "no row" default rather than inventing a restriction client-side).
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
      default:
        return 'پورا مدرسہ';
    }
  }

  factory PermissionScope.fromRow({
    required String permission,
    required Map<String, dynamic> row,
  }) {
    final ref = row['scope_ref'];
    final refMap = ref is Map<String, dynamic> ? ref : <String, dynamic>{};
    return PermissionScope(
      permission: permission,
      scopeType: (row['scope_type'] as String?) ?? 'all',
      classIds: _stringSet(refMap['class_ids']),
      studentIds: _stringSet(refMap['student_ids']),
      department: refMap['department'] as String?,
    );
  }

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
  Map<String, PermissionScope> _scopes = const {};

  /// Scope row for [permission] in the active tenant, or null when there is
  /// no row (default per-role behavior — treat as unrestricted in the UI).
  Future<PermissionScope?> scopeFor(String permission) async {
    final scopes = await _ensureLoaded();
    return scopes[permission];
  }

  /// Client mirror of `scope_allows()`: may [classId] be acted on under
  /// [permission]? Fail-closed for narrower scopes with an unverifiable
  /// target. UX hint only — RLS decides.
  Future<bool> scopeAllows(String permission, {String? classId}) async {
    final scope = await scopeFor(permission);
    if (scope == null || scope.isUnrestricted) return true;
    if (classId == null) return false;
    switch (scope.scopeType) {
      case 'classes':
        return scope.classIds.contains(classId);
      case 'students':
        final ids = await studentIdsInScope(permission);
        if (ids == null) return true;
        return await _anyStudentInClass(ids, classId);
      case 'department':
        // No department dimension on classes: fail closed (mirrors 020).
        return false;
      default:
        return false;
    }
  }

  /// Class ids the user may see/act on for [permission].
  /// Null = unrestricted (do not filter); empty = nothing (fail-closed).
  Future<Set<String>?> classIdsInScope(String permission) async {
    final scope = await scopeFor(permission);
    if (scope == null || scope.isUnrestricted) return null;
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
  /// Null = unrestricted (do not filter); empty = nothing (fail-closed).
  Future<Set<String>?> studentIdsInScope(String permission) async {
    final scope = await scopeFor(permission);
    if (scope == null || scope.isUnrestricted) return null;
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
  Future<String> scopeDescriptionUrdu(String permission) async {
    final scope = await scopeFor(permission);
    return scope?.descriptionUrdu ?? 'پورا مدرسہ';
  }

  /// Drops the in-memory scope rows (call on tenant switch / sign-out).
  void clearCache() {
    _tenantId = null;
    _userId = null;
    _scopes = const {};
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<Map<String, PermissionScope>> _ensureLoaded() async {
    final tenantId = _ref.read(activeTenantIdProvider);
    if (tenantId == null) return const {};
    String? userId;
    try {
      userId = SupabaseService.client.auth.currentUser?.id;
    } catch (_) {
      userId = null;
    }
    if (userId == null) return const {};
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
      // Fail open for DISPLAY (mirrors scope_allows' no-row default);
      // writes/reads stay enforced by RLS either way.
      AppLogger()
          .warning('[Scopes] failed to load permission_scopes', error: e);
      return const {};
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
