// ── Madrasa 360 — PermissionService ──────────────────────────────────────────
// Loads the current user's permission set from Supabase (or falls back to
// the static offline defaults in AppPermissions.roleDefaults).
//
// The SQL function `get_my_permissions()` defined in
// `supabase/migrations/005_rbac.sql` returns the union of permission codes
// across all of the caller's ACTIVE tenant memberships (tenant-aware RBAC).
// NOTE: the server returns canonical dotted codes (`students.view`); they
// are translated to the legacy underscore vocabulary via
// [PermissionService.normalizeServerCodes] before use.
//
// This service is called once after login and after session restore.
// Results are stored in AuthState.permissions.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import '../constants/app_permissions.dart';
import '../observability/app_logger.dart';
import 'supabase_service.dart';

class PermissionService {
  static final _client = SupabaseService.client;

  /// Canonical translation of server (dotted, `module.action`) permission
  /// codes — see `supabase/migrations/005_rbac.sql` — into the legacy
  /// underscore vocabulary the Dart UI checks (`AppPermissions.*`).
  ///
  /// Phase-8 fix: `get_my_permissions()` returns dotted codes but every
  /// `PermissionService.has()` call site passes underscore constants, so
  /// without this translation every online permission check evaluated to
  /// false (fail-closed, but the app denied everything online). Codes with
  /// no clean Dart equivalent are DROPPED with a warning (fail-closed);
  /// the server-side RLS remains the real enforcement point.
  static const Map<String, String> _dottedToLegacy = {
    // students
    'students.view': AppPermissions.viewStudents,
    'students.create': AppPermissions.createStudents,
    'students.update': AppPermissions.editStudents,
    'students.delete': AppPermissions.deleteStudents,
    // teachers → staff capability family (this app's UI manages teachers
    // under the staff module; no separate teacher.* Dart codes exist)
    'teachers.view': AppPermissions.viewStaff,
    'teachers.create': AppPermissions.createStaff,
    'teachers.update': AppPermissions.editStaff,
    'teachers.delete': AppPermissions.deleteStaff,
    // staff
    'staff.view': AppPermissions.viewStaff,
    'staff.create': AppPermissions.createStaff,
    'staff.update': AppPermissions.editStaff,
    'staff.delete': AppPermissions.deleteStaff,
    // attendance
    'attendance.view': AppPermissions.viewAttendance,
    'attendance.mark': AppPermissions.markAttendance,
    'attendance.edit': AppPermissions.editAttendance,
    'attendance.delete': AppPermissions.deleteAttendance,
    // fees & finance
    // NOTE: 'fees.collect' / 'fees.refund' have no Dart counterpart;
    // fee-collection UI is gated on view_fees and the server enforces
    // fees.collect via RLS on the finance tables.
    'fees.view': AppPermissions.viewFees,
    'fees.create': AppPermissions.createFees,
    'finance.view': AppPermissions.viewFinance,
    'finance.create': AppPermissions.createFinance,
    'finance.delete': AppPermissions.deleteFinance,
    'finance.approve': AppPermissions.approveFinance,
    // results & exams
    // NOTE: 'results.publish' / 'exams.publish' have no Dart counterpart;
    // publish flows are server-gated.
    'results.view': AppPermissions.viewResults,
    'results.enter': AppPermissions.enterResults,
    'results.edit': AppPermissions.editResults,
    'exams.view': AppPermissions.manageExams,
    'exams.create': AppPermissions.manageExams,
    'exams.update': AppPermissions.manageExams,
    'exams.delete': AppPermissions.manageExams,
    // reports / library / hostel
    'reports.view': AppPermissions.viewReports,
    'reports.export': AppPermissions.exportReports,
    'library.view': AppPermissions.viewLibrary,
    'library.manage': AppPermissions.manageLibrary,
    'hostel.view': AppPermissions.viewHostel,
    'hostel.manage': AppPermissions.manageHostel,
    // settings / users / tenants
    'settings.view': AppPermissions.viewSettings,
    'settings.update': AppPermissions.manageSettings,
    'users.view': AppPermissions.viewUsers,
    'users.create': AppPermissions.createUsers,
    'users.update': AppPermissions.editUsers,
    // NOTE: 'users.deactivate' has no Dart counterpart (deactivation UI
    // is platform-admin only, server-gated).
    'roles.view': AppPermissions.viewRoles,
    // NOTE: 'roles.assign' intentionally unmapped — translating it to
    // manage_roles would over-grant in the client.
    'academics.view': AppPermissions.viewDarjas,
    'tenants.view': AppPermissions.viewAllMadrasas,
    'tenants.create': AppPermissions.createMadrasa,
    'tenants.update': AppPermissions.updateMadrasa,
    'tenants.suspend': AppPermissions.updateMadrasa, // lifecycle management
    // Deliberately unmapped (fail-closed, server-enforced): audit.view,
    // certificates.view/issue, documents.view/manage, modules.view/manage,
    // notifications.view/send, parents.view, transport.view/manage,
    // fees.collect, fees.refund, results.publish, users.deactivate,
    // roles.assign.
  };

  /// Translates a raw server permission-code set into the Dart vocabulary.
  /// Pure and unit-tested.
  @visibleForTesting
  static Set<String> normalizeServerCodes(Set<String> codes,
      {String? roleName}) {
    final out = <String>{};
    for (final code in codes) {
      final mapped = _dottedToLegacy[code];
      if (mapped != null) {
        out.add(mapped);
      } else if (!code.contains('.')) {
        out.add(code); // already Dart vocabulary (e.g. legacy rows)
      } else {
        AppLogger().warning('[Permissions] dropping unmapped server code: $code'
            '${roleName == null ? '' : ' (role $roleName)'}');
      }
    }
    return out;
  }

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
        AppLogger()
            .warning('[Permissions] RPC returned null, using offline fallback');
        return AppPermissions.fallbackFor(roleName);
      }

      // Response is a List<Map<String, dynamic>> where each row has {"code": "..."}
      final List<dynamic> rows = response as List<dynamic>;
      final perms = rows
          .map((row) => (row as Map<String, dynamic>)['code'] as String?)
          .whereType<String>()
          .toSet();

      AppLogger()
          .info('[Permissions] loaded ${perms.length} raw codes for $roleName');
      final normalized = normalizeServerCodes(perms, roleName: roleName);
      AppLogger().info(
          '[Permissions] normalized to ${normalized.length} Dart permissions for $roleName');
      return normalized;
    } catch (e) {
      AppLogger().warning(
          '[Permissions] Error loading from DB — using offline fallback',
          error: e);
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
  static bool isStaffRole(String roleName) => const {
        'madrasaAdmin',
        'admin',
        'editor',
        'academicManager',
        'teacher',
        'attendanceOfficer',
        'accountant',
        'financeManager',
        'libraryManager',
        'hostelManager',
        'announcementManager',
        'admissionOfficer',
        'itManager',
      }.contains(roleName);

  /// Returns true for external/guardian roles.
  static bool isExternalRole(String roleName) =>
      const {'parent', 'student'}.contains(roleName);
}
