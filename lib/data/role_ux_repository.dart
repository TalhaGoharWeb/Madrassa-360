/// صارف اور ذمہ داریوں کا ڈیٹا رسائی (Phase 8a)
/// Role-UX repository — the single real-data gateway for the 8a user
/// management flows (hub, detail, wizard).
///
/// Write paths (never direct table writes for permission changes):
///   - auth user create / (de)activate / list / safety pre-check
///       -> `manage-users` Edge Function (service key stays server-side)
///   - role assignment            -> `assign_tenant_role` RPC
///   - per-user grant/deny        -> `set_user_permission` RPC
///   - data scopes                -> `permission_scopes` upsert/delete
///       (RLS "role managers write" allows roles.assign holders)
///
/// Reads go through RLS as the authenticated user. Every failure is
/// mapped to plain Urdu by [roleUxErrorMessage] — PostgREST / JWT / RLS
/// text never reaches the UI.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_permissions.dart';
import '../core/observability/app_logger.dart';
import '../core/services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────
// Models (plain data, no mock values anywhere)
// ─────────────────────────────────────────────────────────────

/// One tenant member, resolved for the active tenant.
class TenantUser {
  const TenantUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    required this.roleKey,
    required this.roleUrdu,
    required this.isActive,
    required this.banned,
    this.lastSignInAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String roleKey;
  final String roleUrdu;

  /// Membership is_active && not auth-banned.
  final bool isActive;
  final bool banned;
  final DateTime? lastSignInAt;
  final DateTime? createdAt;

  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String runes(String s) => String.fromCharCodes(s.runes.take(2));
    if (parts.length == 1) {
      return runes(parts.first);
    }
    return String.fromCharCodes(parts.first.runes.take(1)) +
        String.fromCharCodes(parts.last.runes.take(1));
  }
}

/// One tenant role (from `tenant_roles`) with its live permission codes.
class TenantRoleInfo {
  const TenantRoleInfo({
    required this.id,
    required this.key,
    required this.displayUrdu,
    required this.displayName,
    this.description,
    this.isTemplateDefault = false,
    this.permissionCodes = const {},
  });

  final String id;
  final String key;
  final String displayUrdu;
  final String displayName;
  final String? description;
  final bool isTemplateDefault;
  final Set<String> permissionCodes;
}

/// One permission catalog row (from `permissions`, label_urdu seeded by 019).
class PermissionInfo {
  const PermissionInfo({
    required this.id,
    required this.code,
    required this.labelUrdu,
    required this.categoryUrdu,
    required this.sortOrder,
  });

  final String id;
  final String code;
  final String labelUrdu;
  final String categoryUrdu;
  final int sortOrder;
}

class ClassRef {
  const ClassRef({required this.id, required this.name});
  final String id;
  final String name;
}

class StudentRef {
  const StudentRef({required this.id, required this.name});
  final String id;
  final String name;
}

/// Assigned class of a user (from teacher_class_assignments).
class AssignedClassInfo {
  const AssignedClassInfo({required this.id, required this.name});
  final String id;
  final String name;
}

/// Plain-language data scope chosen in the wizard (step 4).
class ScopeSelection {
  const ScopeSelection({
    required this.type,
    this.classIds = const {},
    this.studentIds = const {},
  });

  /// 'all' | 'department' | 'classes' | 'students'
  final String type;
  final Set<String> classIds;
  final Set<String> studentIds;

  /// Codes the server actually enforces scopes for (020 scope_allows).
  static const scopedCodes = <String>{
    'attendance.mark',
    'attendance.edit',
    'attendance.delete',
    'results.enter',
    'results.edit',
  };
}

/// Principal-safety pre-check result (from the `safety_check` edge action).
class SafetyCheck {
  const SafetyCheck({
    required this.ownerCount,
    required this.isLastOwner,
    required this.assignHolderCount,
    required this.isLastAssignHolder,
    this.targetRole,
  });

  final int ownerCount;
  final bool isLastOwner;
  final int assignHolderCount;
  final bool isLastAssignHolder;
  final String? targetRole;
}

/// One audit_logs row for the activity view.
class AuditRow {
  const AuditRow({
    required this.action,
    this.entity,
    required this.createdAt,
    this.actorUserId,
  });

  final String action;
  final String? entity;
  final DateTime createdAt;

  /// auth.users id of the actor; null when unknown.
  final String? actorUserId;
}

// ─────────────────────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────────────────────

abstract class RoleUxRepository {
  Future<List<TenantUser>> listUsers(String tenantId, {String? search});
  Future<List<TenantRoleInfo>> listRoles(String tenantId);
  Future<List<PermissionInfo>> permissionCatalog();

  /// Active member count per role key (from tenant_memberships).
  Future<Map<String, int>> roleMemberCounts(String tenantId);

  /// Creates the Supabase Auth user only (no membership). Returns the id.
  Future<String> createAuthUser({
    required String name,
    required String phone,
    required String email,
    required String password,
  });

  Future<void> assignRole({
    required String tenantId,
    required String userId,
    required String roleKey,
  });

  /// effect: 'grant' | 'deny' | null (null clears the override)
  Future<void> setUserPermission({
    required String tenantId,
    required String userId,
    required String code,
    required String? effect,
  });

  /// Reconciles user_permissions with (template ∪ selected): grants for
  /// selected-but-not-template codes, denies for template-but-not-selected
  /// codes, clears stale overrides.
  Future<void> syncUserPermissions({
    required String tenantId,
    required String userId,
    required Set<String> templateCodes,
    required Set<String> selectedCodes,
  });

  Future<void> setActive({required String userId, required bool active});

  /// Best-effort rollback for a half-created user (may 403 for
  /// permission-based callers — the caller reports honestly).
  Future<void> deleteAuthUser(String userId);

  Future<void> writeScopes({
    required String tenantId,
    required String userId,
    required Set<String> codes,
    required ScopeSelection selection,
  });

  Future<Map<String, String>> userOverrides({
    required String tenantId,
    required String userId,
  });

  Future<Map<String, ScopeSelection>> userScopes({
    required String tenantId,
    required String userId,
  });

  Future<List<ClassRef>> listClasses(String tenantId);
  Future<List<StudentRef>> searchStudents(String tenantId, String query);
  Future<List<AssignedClassInfo>> assignedClasses({
    required String tenantId,
    required String userId,
  });
  Future<List<AuditRow>> userActivity({
    required String tenantId,
    required String userId,
  });

  /// Null when the edge function is not (newly) deployed — the UI then
  /// attempts the write and maps the server error honestly.
  Future<SafetyCheck?> safetyCheck({
    required String tenantId,
    required String userId,
  });

  String? get currentUserId;
}

// ─────────────────────────────────────────────────────────────
// Supabase implementation (real data only)
// ─────────────────────────────────────────────────────────────

class SupabaseRoleUxRepository implements RoleUxRepository {
  SupabaseClient get _client => SupabaseService.client;

  @override
  String? get currentUserId => SupabaseService.currentUser?.id;

  Map<String, dynamic> _asMap(Object? v) {
    return v is Map<String, dynamic> ? v : <String, dynamic>{};
  }

  @override
  Future<List<TenantUser>> listUsers(String tenantId, {String? search}) async {
    final res = await _client.functions.invoke(
      'manage-users',
      body: {
        'action': 'list_users',
        'tenant_id': tenantId,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'limit': 200,
      },
    );
    final data = _asMap(res.data);
    final items = (data['users'] as List?) ?? const [];
    final users = <TenantUser>[];
    for (final item in items) {
      final u = _asMap(item);
      final tenants = (u['tenants'] as List?) ?? const [];
      Map<String, dynamic>? mine;
      for (final t in tenants) {
        final m = _asMap(t);
        if ((m['tenant_id'] as String?) == tenantId) {
          mine = m;
          break;
        }
      }
      if (mine == null) continue;
      final roleKey = (mine['role'] as String?) ?? '';
      final banned = (u['banned'] as bool?) ?? false;
      final memberActive = (mine['is_active'] as bool?) ?? true;
      final name = ((u['name'] as String?) ?? '').trim();
      users.add(TenantUser(
        id: (u['id'] as String?) ?? '',
        name: name.isEmpty ? ((u['email'] as String?) ?? '') : name,
        email: (u['email'] as String?) ?? '',
        roleKey: roleKey,
        roleUrdu: roleKey, // resolved to Urdu by the UI layer (RoleService)
        isActive: memberActive && !banned,
        banned: banned,
        lastSignInAt: _parseTime(u['last_sign_in_at']),
        createdAt: _parseTime(u['created_at']),
      ));
    }
    users.sort((a, b) => a.name.compareTo(b.name));
    return users;
  }

  DateTime? _parseTime(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  @override
  Future<List<TenantRoleInfo>> listRoles(String tenantId) async {
    final rows = await _client
        .from('tenant_roles')
        .select('id, key, display_name, display_urdu, description, '
            'is_template_default')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('display_urdu');
    final roles = (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return TenantRoleInfo(
        id: (m['id'] as String?) ?? '',
        key: (m['key'] as String?) ?? '',
        displayUrdu: ((m['display_urdu'] as String?) ?? '').trim(),
        displayName: ((m['display_name'] as String?) ?? '').trim(),
        description: (m['description'] as String?)?.trim(),
        isTemplateDefault: (m['is_template_default'] as bool?) ?? false,
      );
    }).toList();

    // Live permission codes per role.
    final ids = roles.map((r) => r.id).where((id) => id.isNotEmpty).toList();
    final Map<String, Set<String>> codesByRole = {};
    if (ids.isNotEmpty) {
      final catalog = await permissionCatalog();
      final codeById = {for (final p in catalog) p.id: p.code};
      final trp = await _client
          .from('tenant_role_permissions')
          .select('tenant_role_id, permission_id')
          .inFilter('tenant_role_id', ids);
      for (final row in (trp as List)) {
        final m = row as Map<String, dynamic>;
        final rid = m['tenant_role_id'];
        final code = _codeFor(codeById, m['permission_id']);
        if (rid is String && code != null) {
          codesByRole.putIfAbsent(rid, () => <String>{}).add(code);
        }
      }
    }
    return [
      for (final r in roles)
        TenantRoleInfo(
          id: r.id,
          key: r.key,
          displayUrdu:
              r.displayUrdu.isEmpty ? _fallbackRoleUrdu(r.key) : r.displayUrdu,
          displayName: r.displayName,
          description: r.description,
          isTemplateDefault: r.isTemplateDefault,
          permissionCodes: codesByRole[r.id] ?? const {},
        ),
    ];
  }

  /// Minimal static Urdu fallback (the tenant's own display_urdu wins).
  static String _fallbackRoleUrdu(String key) {
    const map = <String, String>{
      'tenant_owner': 'مالک',
      'tenant_admin': 'ناظم اعلیٰ',
      'mohtamim': 'مہتمم',
      'naib_mohtamim': 'نائب مہتمم',
      'nazim_aala': 'ناظم اعلیٰ',
      'nazim_taleem': 'ناظم تعلیم',
      'nazim_intizamia': 'ناظم انتظامیہ',
      'nazim_maliyat': 'ناظم مالیات',
      'daftar_dar': 'دفتر دار',
      'ustad': 'استاد',
      'ustad_hifz': 'مدرس حفظ',
      'nazim_hifz': 'ناظم حفظ',
      'nazim_darul_iqama': 'ناظم دارالاقامہ',
      'warden': 'وارڈن',
      'mumtahin': 'ممتحن',
      'store_incharge': 'اسٹور انچارج',
      'hr_incharge': 'عملہ انچارج',
      'principal': 'پرنسپل',
      'accountant': 'محاسب',
      'teacher': 'استاد',
      'librarian': 'لائبریرین',
      'hostel_manager': 'ہاسٹل مینیجر',
      'staff': 'عملہ',
      'parent': 'والدین',
      'student': 'طالب علم',
    };
    return map[key] ?? key;
  }

  @override
  Future<Map<String, int>> roleMemberCounts(String tenantId) async {
    try {
      final rows = await _client
          .from('tenant_memberships')
          .select('role')
          .eq('tenant_id', tenantId)
          .eq('is_active', true);
      final counts = <String, int>{};
      for (final row in (rows as List)) {
        final role = (row as Map<String, dynamic>)['role'] as String?;
        if (role != null && role.isNotEmpty) {
          counts[role] = (counts[role] ?? 0) + 1;
        }
      }
      return counts;
    } catch (_) {
      // RLS may hide memberships from non-admin callers — the UI then
      // shows counts only where readable (honest, never fabricated).
      return const {};
    }
  }

  @override
  Future<List<PermissionInfo>> permissionCatalog() async {
    final rows = await _client
        .from('permissions')
        .select('id, code, label_urdu, category_urdu, sort_order')
        .order('sort_order')
        .order('code');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final code = (m['code'] as String?) ?? '';
      final label = ((m['label_urdu'] as String?) ?? '').trim();
      return PermissionInfo(
        id: (m['id'] as String?) ?? '',
        code: code,
        labelUrdu: label.isEmpty ? AppPermissions.urduLabelFor(code) : label,
        categoryUrdu: ((m['category_urdu'] as String?) ?? '').trim().isEmpty
            ? 'دیگر'
            : (m['category_urdu'] as String).trim(),
        sortOrder: (m['sort_order'] as int?) ?? 999,
      );
    }).toList();
  }

  @override
  Future<String> createAuthUser({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    final res = await _client.functions.invoke(
      'manage-users',
      body: {
        'action': 'create_user',
        'email': email.trim(),
        'password': password,
        'user_metadata': {
          'name': name.trim(),
          if (phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      },
    );
    final data = _asMap(res.data);
    final id = (data['id'] ?? data['user_id'])?.toString() ?? '';
    if (id.isEmpty) {
      throw StateError('create_user: server did not return a user id');
    }
    AppLogger().info('[RoleUx] auth user created', context: {'user_id': id});
    return id;
  }

  @override
  Future<void> assignRole({
    required String tenantId,
    required String userId,
    required String roleKey,
  }) async {
    await _client.rpc('assign_tenant_role', params: {
      'p_tenant_id': tenantId,
      'p_user_id': userId,
      'p_role_key': roleKey,
    });
  }

  @override
  Future<void> setUserPermission({
    required String tenantId,
    required String userId,
    required String code,
    required String? effect,
  }) async {
    await _client.rpc('set_user_permission', params: {
      'p_tenant_id': tenantId,
      'p_user_id': userId,
      'p_code': code,
      'p_effect': effect,
    });
  }

  @override
  Future<void> syncUserPermissions({
    required String tenantId,
    required String userId,
    required Set<String> templateCodes,
    required Set<String> selectedCodes,
  }) async {
    final existing = await userOverrides(tenantId: tenantId, userId: userId);
    final codes = <String>{
      ...templateCodes,
      ...selectedCodes,
      ...existing.keys
    };
    for (final code in codes) {
      final inTemplate = templateCodes.contains(code);
      final selected = selectedCodes.contains(code);
      final String? desired = (selected && !inTemplate)
          ? 'grant'
          : ((!selected && inTemplate) ? 'deny' : null);
      if (existing[code] != desired) {
        await setUserPermission(
          tenantId: tenantId,
          userId: userId,
          code: code,
          effect: desired,
        );
      }
    }
  }

  @override
  Future<void> setActive({required String userId, required bool active}) async {
    await _client.functions.invoke(
      'manage-users',
      body: {'action': 'set_active', 'user_id': userId, 'active': active},
    );
  }

  @override
  Future<void> deleteAuthUser(String userId) async {
    await _client.functions.invoke(
      'manage-users',
      body: {'action': 'delete_user', 'user_id': userId},
    );
  }

  @override
  Future<void> writeScopes({
    required String tenantId,
    required String userId,
    required Set<String> codes,
    required ScopeSelection selection,
  }) async {
    final catalog = await permissionCatalog();
    final idsByCode = {for (final p in catalog) p.code: p.id};
    final ids = [
      for (final c in codes)
        if (idsByCode[c] != null) idsByCode[c]!,
    ];
    if (ids.isEmpty) return;

    if (selection.type == 'all' || selection.type == 'department') {
      // 'all' is the default (no row). 'department' is NOT server-enforced
      // (020 scope_allows is fail-closed for it), so writing a row would
      // lock the user out — the UI says this honestly and writes nothing.
      await _client
          .from('permission_scopes')
          .delete()
          .eq('tenant_id', tenantId)
          .eq('user_id', userId)
          .inFilter('permission_id', ids);
      return;
    }
    final ref = selection.type == 'classes'
        ? {
            'class_ids': selection.classIds.toList(),
          }
        : {
            'student_ids': selection.studentIds.toList(),
          };
    for (final pid in ids) {
      await _client.from('permission_scopes').upsert(
        {
          'tenant_id': tenantId,
          'user_id': userId,
          'permission_id': pid,
          'scope_type': selection.type,
          'scope_ref': ref,
        },
        onConflict: 'tenant_id,user_id,permission_id',
      );
    }
  }

  @override
  Future<Map<String, String>> userOverrides({
    required String tenantId,
    required String userId,
  }) async {
    final catalog = await permissionCatalog();
    final codeById = {for (final p in catalog) p.id: p.code};
    final rows = await _client
        .from('user_permissions')
        .select('permission_id, effect')
        .eq('tenant_id', tenantId)
        .eq('user_id', userId);
    final out = <String, String>{};
    for (final row in (rows as List)) {
      final m = row as Map<String, dynamic>;
      final code = _codeFor(codeById, m['permission_id']);
      final effect = m['effect'];
      if (code != null && effect is String) out[code] = effect;
    }
    return out;
  }

  @override
  Future<Map<String, ScopeSelection>> userScopes({
    required String tenantId,
    required String userId,
  }) async {
    final catalog = await permissionCatalog();
    final codeById = {for (final p in catalog) p.id: p.code};
    final rows = await _client
        .from('permission_scopes')
        .select('permission_id, scope_type, scope_ref')
        .eq('tenant_id', tenantId)
        .eq('user_id', userId);
    final out = <String, ScopeSelection>{};
    for (final row in (rows as List)) {
      final m = row as Map<String, dynamic>;
      final code = _codeFor(codeById, m['permission_id']);
      if (code == null) continue;
      final ref = _asMap(m['scope_ref']);
      out[code] = ScopeSelection(
        type: (m['scope_type'] as String?) ?? 'all',
        classIds: _stringSet(ref['class_ids']),
        studentIds: _stringSet(ref['student_ids']),
      );
    }
    return out;
  }

  Set<String> _stringSet(Object? v) {
    if (v is! List) return const {};
    return {for (final e in v) e.toString()};
  }

  /// Permission id -> code without any casts (dynamic JSON values).
  String? _codeFor(Map<String, String> codeById, Object? permissionId) =>
      permissionId is String ? codeById[permissionId] : null;

  @override
  Future<List<ClassRef>> listClasses(String tenantId) async {
    final rows = await _client
        .from('classes')
        .select('id, name')
        .eq('tenant_id', tenantId)
        .order('name');
    return (rows as List)
        .map((r) {
          final m = r as Map<String, dynamic>;
          final id = m['id'];
          final name = m['name'];
          return ClassRef(
            id: id is String ? id : '',
            name: name is String ? name : '',
          );
        })
        .where((c) => c.id.isNotEmpty)
        .toList();
  }

  @override
  Future<List<StudentRef>> searchStudents(String tenantId, String query) async {
    final q = query.trim().replaceAll('%', '');
    if (q.isEmpty) return const [];
    final rows = await _client
        .from('students')
        .select('id, name')
        .eq('tenant_id', tenantId)
        .ilike('name', '%$q%')
        .order('name')
        .limit(25);
    return (rows as List)
        .map((r) {
          final m = r as Map<String, dynamic>;
          final id = m['id'];
          final name = m['name'];
          return StudentRef(
            id: id is String ? id : '',
            name: name is String ? name : '',
          );
        })
        .where((s) => s.id.isNotEmpty)
        .toList();
  }

  @override
  Future<List<AssignedClassInfo>> assignedClasses({
    required String tenantId,
    required String userId,
  }) async {
    try {
      final rows = await _client
          .from('teacher_class_assignments')
          .select('class_id, classes(name)')
          .eq('tenant_id', tenantId)
          .eq('teacher_user_id', userId)
          .eq('is_active', true);
      return (rows as List)
          .map((r) {
            final m = r as Map<String, dynamic>;
            final cls = _asMap(m['classes']);
            return AssignedClassInfo(
              id: (m['class_id'] as String?) ?? '',
              name: (cls['name'] as String?) ?? '',
            );
          })
          .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
          .toList();
    } catch (_) {
      // RLS may hide other users' assignments from non-admin callers.
      return const [];
    }
  }

  @override
  Future<List<AuditRow>> userActivity({
    required String tenantId,
    required String userId,
  }) async {
    try {
      // Both directions: actions the user performed (actor) and actions
      // performed on the user (target) — e.g. account created, role
      // changed, deactivated.
      final results = await Future.wait([
        _client
            .from('audit_logs')
            .select('action, entity, created_at, user_id')
            .eq('tenant_id', tenantId)
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(20),
        _client
            .from('audit_logs')
            .select('action, entity, created_at, user_id')
            .eq('tenant_id', tenantId)
            .eq('entity_id', userId)
            .inFilter(
                'entity', const ['auth_user', 'tenant_membership', 'user'])
            .order('created_at', ascending: false)
            .limit(20),
      ]);
      final seen = <String>{};
      final rows = <AuditRow>[];
      for (final result in results) {
        for (final r in (result as List)) {
          final m = r as Map<String, dynamic>;
          final key =
              '${m['action']}|${m['entity']}|${m['created_at']}|${m['user_id']}';
          if (!seen.add(key)) continue;
          rows.add(AuditRow(
            action: (m['action'] as String?) ?? '',
            entity: m['entity'] as String?,
            createdAt: _parseTime(m['created_at']) ?? DateTime.now(),
            actorUserId: m['user_id'] as String?,
          ));
        }
      }
      rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rows.take(20).toList();
    } catch (_) {
      // audit_logs RLS may hide rows from this caller — honest empty state.
      return const [];
    }
  }

  @override
  Future<SafetyCheck?> safetyCheck({
    required String tenantId,
    required String userId,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'manage-users',
        body: {
          'action': 'safety_check',
          'tenant_id': tenantId,
          'user_id': userId,
        },
      );
      final d = _asMap(res.data);
      return SafetyCheck(
        ownerCount: (d['owner_count'] as int?) ?? 0,
        isLastOwner: (d['is_last_owner'] as bool?) ?? false,
        assignHolderCount: (d['assign_holder_count'] as int?) ?? 0,
        isLastAssignHolder: (d['is_last_assign_holder'] as bool?) ?? false,
        targetRole: d['target_role'] as String?,
      );
    } catch (_) {
      // Edge function not (re)deployed yet — caller falls back to
      // attempting the write and mapping the server error honestly.
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Plain-Urdu error mapping (never leaks PostgREST/JWT/RLS text)
// ─────────────────────────────────────────────────────────────

/// Extracts the edge-function `{error: code}` when the server rejected the
/// call (defensive: FunctionException.details shape varies by version).
String? edgeErrorCode(Object e) {
  if (e is! FunctionException) return null;
  try {
    final details = (e as dynamic).details;
    if (details is Map) {
      final code = details['error'];
      if (code is String && code.isNotEmpty) return code;
      // Some versions nest under 'data'.
      final nested = details['data'];
      if (nested is Map && nested['error'] is String) {
        return nested['error'] as String;
      }
    }
    if (details is String) {
      final m = RegExp(r'"error"\s*:\s*"([a-z_]+)"').firstMatch(details);
      if (m != null) return m.group(1);
    }
  } catch (_) {
    // ignore — fall through to text matching
  }
  return null;
}

/// Maps any repository failure to a human, plain-Urdu message.
/// The raw error is logged (see callers) but never shown.
String roleUxErrorMessage(Object e) {
  final code = edgeErrorCode(e);
  final hay = '${code ?? ''} ${e.toString()}'.toLowerCase();

  if (code == 'last_owner' ||
      hay.contains('last_owner') ||
      hay.contains('protect_last_owner') ||
      hay.contains('last active tenant_owner')) {
    return 'یہ مدرسے کا واحد مالک ہے — پہلے کسی اور کو مالک بنائیں، پھر یہ عمل کریں۔';
  }
  if (code == 'last_platform_owner' || code == 'last_platform_admin') {
    return 'یہ پلیٹ فارم کا واحد منتظم ہے — اسے ہٹایا نہیں جا سکتا۔';
  }
  if (hay.contains('already registered') ||
      hay.contains('already exists') ||
      hay.contains('duplicate') && hay.contains('email')) {
    return 'یہ ای میل پہلے سے درج ہے — کوئی دوسرا ای میل استعمال کریں۔';
  }
  if (code == 'weak_password' || hay.contains('at least 6 characters')) {
    return 'پاس ورڈ کم از کم 6 حروف کا ہونا چاہیے۔';
  }
  if (code == 'invalid_email') {
    return 'درست ای میل درج کریں۔';
  }
  if (hay.contains('not an active role') || code == 'invalid_role') {
    return 'یہ ذمہ داری اس مدرسے میں فعال نہیں ہے۔';
  }
  if (hay.contains('requires roles.assign')) {
    return 'آپ کے پاس ذمہ داریاں سونپنے کی اجازت نہیں ہے۔';
  }
  if (code == 'forbidden' ||
      hay.contains('42501') ||
      hay.contains('permission denied')) {
    return 'آپ کے پاس اس عمل کی اجازت نہیں ہے۔';
  }
  if (code == 'unauthorized' ||
      hay.contains('invalid or expired token') ||
      hay.contains('jwt expired')) {
    return 'آپ کی لاگ اِن میعاد ختم ہو گئی ہے — دوبارہ لاگ اِن کریں۔';
  }
  if (hay.contains('404') ||
      hay.contains('not found') && hay.contains('function')) {
    return 'سرور فنکشن دستیاب نہیں ہے — manage-users Edge Function deploy کرنا ہوگا۔';
  }
  if (hay.contains('failed host lookup') ||
      hay.contains('socketexception') ||
      hay.contains('network is unreachable') ||
      hay.contains('connection refused') ||
      hay.contains('connection timed out')) {
    return 'انٹرنیٹ سے رابطہ نہیں ہو سکا — کنکشن چیک کر کے دوبارہ کوشش کریں۔';
  }
  if (hay.contains('server did not return a user id')) {
    return 'صارف بنانے میں مسئلہ ہوا — دوبارہ کوشش کریں۔';
  }
  AppLogger()
      .warning('[RoleUx] unmapped error, generic message shown', error: e);
  return 'عمل مکمل نہیں ہو سکا — دوبارہ کوشش کریں۔';
}
