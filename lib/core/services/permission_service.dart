// ── Madrasa 360 — PermissionService ──────────────────────────────────────────
// Loads the current user's permission set from Supabase (or falls back to
// the static offline defaults in AppPermissions.roleDefaults).
//
// The SQL function `get_my_permissions()` defined in 06_rbac.sql returns the
// union of:
//   1. role_permissions rows from user_roles table (madrasa-scoped)
//   2. role_permissions rows derived from profiles.role (legacy support)
//
// This service is called once after login and after session restore.
// Results are stored in AuthState.permissions.
// ─────────────────────────────────────────────────────────────────────────────

import '../constants/app_permissions.dart';
import '../observability/app_logger.dart';
import 'supabase_service.dart';

class PermissionService {
  static final _client = SupabaseService.client;

  // ── Load permissions from Supabase ─────────────────────────────────────────

  /// Calls `get_my_permissions()` RPC and returns the permission codes as a Set.
  /// Falls back to role-based offline defaults if anything fails.
  static Future<Set<String>> loadForUser({
    required String userId,
    required String roleName,
    String? madrasaId,
  }) async {
    try {
      // Call the Supabase RPC that unions all role-based permissions for the user
      final response = await _client.rpc(
        'get_my_permissions',
        params: madrasaId != null ? {'p_madrasa_id': madrasaId} : {},
      );

      if (response == null) {
        AppLogger().warning('[Permissions] RPC returned null, using offline fallback');
        return AppPermissions.fallbackFor(roleName);
      }

      // Response is a List<Map<String, dynamic>> where each row has {"code": "..."}
      final List<dynamic> rows = response as List<dynamic>;
      final perms = rows
          .map((row) => (row as Map<String, dynamic>)['code'] as String?)
          .whereType<String>()
          .toSet();

      AppLogger().info('[Permissions] loaded ${perms.length} permissions for $roleName');
      return perms;
    } catch (e) {
      AppLogger().warning('[Permissions] Error loading from DB — using offline fallback', error: e);
      return AppPermissions.fallbackFor(roleName);
    }
  }

  // ── Convenience helpers ────────────────────────────────────────────────────

  /// Returns true if [permissions] contains [permission].
  static bool has(Set<String> permissions, String permission) =>
      permissions.contains(permission);

  /// Returns true if [permissions] contains ALL of [required].
  static bool hasAll(Set<String> permissions, Iterable<String> required) =>
      required.every(permissions.contains);

  /// Returns true if [permissions] contains ANY of [any].
  static bool hasAny(Set<String> permissions, Iterable<String> any) =>
      any.any(permissions.contains);

  // ── Platform role checks ───────────────────────────────────────────────────

  /// Returns true for roles with platform-wide access.
  static bool isPlatformRole(String roleName) =>
      const {'superAdmin', 'franchiseManager'}.contains(roleName);

  /// Returns true for madrasa-level administrative roles.
  static bool isMadrasaAdmin(String roleName) =>
      const {'madrasaAdmin', 'admin', 'editor', 'itManager'}.contains(roleName);

  /// Returns true for staff roles (can log in to madrasa admin panel).
  static bool isStaffRole(String roleName) =>
      const {
        'madrasaAdmin', 'admin', 'editor', 'academicManager',
        'teacher', 'attendanceOfficer', 'accountant', 'financeManager',
        'libraryManager', 'hostelManager', 'announcementManager',
        'admissionOfficer', 'itManager',
      }.contains(roleName);

  /// Returns true for external/guardian roles.
  static bool isExternalRole(String roleName) =>
      const {'parent', 'student'}.contains(roleName);
}
