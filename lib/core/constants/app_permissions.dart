// ── Madrasa 360 — AppPermissions ─────────────────────────────────────────────
// Single source of truth for all permission code strings.
// These map 1-to-1 with the `permissions.code` values in 06_rbac.sql.
//
// Usage:
//   ref.read(hasPermissionProvider(AppPermissions.createStudents))
//
// ─────────────────────────────────────────────────────────────────────────────

abstract class AppPermissions {
  // ── Students ───────────────────────────────────────────────────────────────
  static const String viewStudents   = 'view_students';
  static const String createStudents = 'create_students';
  static const String editStudents   = 'edit_students';
  static const String deleteStudents = 'delete_students';

  // ── Staff ──────────────────────────────────────────────────────────────────
  static const String viewStaff   = 'view_staff';
  static const String createStaff = 'create_staff';
  static const String editStaff   = 'edit_staff';
  static const String deleteStaff = 'delete_staff';

  // ── Attendance ─────────────────────────────────────────────────────────────
  static const String viewAttendance   = 'view_attendance';
  static const String markAttendance   = 'mark_attendance';
  static const String editAttendance   = 'edit_attendance';
  static const String deleteAttendance = 'delete_attendance';

  // ── Fees ───────────────────────────────────────────────────────────────────
  static const String viewFees   = 'view_fees';
  static const String createFees = 'create_fees';
  static const String updateFees = 'update_fees';
  static const String deleteFees = 'delete_fees';

  // ── Results / Exams ────────────────────────────────────────────────────────
  static const String viewResults   = 'view_results';
  static const String enterResults  = 'enter_results';
  static const String editResults   = 'edit_results';
  static const String deleteResults = 'delete_results';
  static const String manageExams   = 'manage_exams';

  // ── Finance ────────────────────────────────────────────────────────────────
  static const String viewFinance    = 'view_finance';
  static const String createFinance  = 'create_finance';
  static const String approveFinance = 'approve_finance';
  static const String deleteFinance  = 'delete_finance';

  // ── Library ────────────────────────────────────────────────────────────────
  static const String viewLibrary   = 'view_library';
  static const String manageLibrary = 'manage_library';

  // ── Hostel ─────────────────────────────────────────────────────────────────
  static const String viewHostel   = 'view_hostel';
  static const String manageHostel = 'manage_hostel';

  // ── Announcements ──────────────────────────────────────────────────────────
  static const String viewAnnouncements   = 'view_announcements';
  static const String createAnnouncements = 'create_announcements';
  static const String editAnnouncements   = 'edit_announcements';
  static const String deleteAnnouncements = 'delete_announcements';

  // ── Admissions ─────────────────────────────────────────────────────────────
  static const String viewAdmissions   = 'view_admissions';
  static const String createAdmissions = 'create_admissions';
  static const String editAdmissions   = 'edit_admissions';
  static const String deleteAdmissions = 'delete_admissions';

  // ── Darjas / Academic structure ────────────────────────────────────────────
  static const String viewDarjas   = 'view_darjas';
  static const String manageDarjas = 'manage_darjas';

  // ── Reports ────────────────────────────────────────────────────────────────
  static const String viewReports   = 'view_reports';
  static const String exportReports = 'export_reports';

  // ── Users ──────────────────────────────────────────────────────────────────
  static const String viewUsers   = 'view_users';
  static const String createUsers = 'create_users';
  static const String editUsers   = 'edit_users';
  static const String deleteUsers = 'delete_users';

  // ── Roles & Permissions ────────────────────────────────────────────────────
  static const String viewRoles         = 'view_roles';
  static const String manageRoles       = 'manage_roles';
  static const String managePermissions = 'manage_permissions';

  // ── Settings ───────────────────────────────────────────────────────────────
  static const String viewSettings   = 'view_settings';
  static const String manageSettings = 'manage_settings';

  // ── Madrasa management ─────────────────────────────────────────────────────
  static const String createMadrasa        = 'create_madrasa';
  static const String updateMadrasa        = 'update_madrasa';
  static const String deleteMadrasa        = 'delete_madrasa';
  static const String assignMadrasaAdmin   = 'assign_madrasa_admin';
  static const String viewAllMadrasas      = 'view_all_madrasas';

  // ── System ─────────────────────────────────────────────────────────────────
  static const String systemFullAccess = 'system_full_access';


  // ── Offline fallback: role → default permissions ──────────────────────────
  // Used when the Supabase RBAC tables are unavailable (offline mode).
  // Must be kept in sync with 06_rbac.sql Part 8.
  static const Map<String, Set<String>> roleDefaults = {
    'superAdmin': {
      viewStudents, createStudents, editStudents, deleteStudents,
      viewStaff, createStaff, editStaff, deleteStaff,
      viewAttendance, markAttendance, editAttendance, deleteAttendance,
      viewFees, createFees, updateFees, deleteFees,
      viewResults, enterResults, editResults, deleteResults, manageExams,
      viewFinance, createFinance, approveFinance, deleteFinance,
      viewLibrary, manageLibrary,
      viewHostel, manageHostel,
      viewAnnouncements, createAnnouncements, editAnnouncements, deleteAnnouncements,
      viewAdmissions, createAdmissions, editAdmissions, deleteAdmissions,
      viewDarjas, manageDarjas,
      viewReports, exportReports,
      viewUsers, createUsers, editUsers, deleteUsers,
      viewRoles, manageRoles, managePermissions,
      viewSettings, manageSettings,
      createMadrasa, updateMadrasa, deleteMadrasa, assignMadrasaAdmin, viewAllMadrasas,
      systemFullAccess,
    },
    'franchiseManager': {
      viewStudents, viewStaff, viewAttendance, viewFees, viewResults, viewFinance,
      viewLibrary, viewHostel,
      viewAnnouncements, createAnnouncements, editAnnouncements,
      viewAdmissions, viewDarjas, viewReports, exportReports,
      viewUsers, createUsers, editUsers,
      viewRoles, viewSettings, updateMadrasa, assignMadrasaAdmin, viewAllMadrasas,
    },
    'madrasaAdmin': {
      viewStudents, createStudents, editStudents, deleteStudents,
      viewStaff, createStaff, editStaff, deleteStaff,
      viewAttendance, markAttendance, editAttendance, deleteAttendance,
      viewFees, createFees, updateFees, deleteFees,
      viewResults, enterResults, editResults, deleteResults, manageExams,
      viewFinance, createFinance, approveFinance, deleteFinance,
      viewLibrary, manageLibrary, viewHostel, manageHostel,
      viewAnnouncements, createAnnouncements, editAnnouncements, deleteAnnouncements,
      viewAdmissions, createAdmissions, editAdmissions, deleteAdmissions,
      viewDarjas, manageDarjas, viewReports, exportReports,
      viewUsers, createUsers, editUsers,
      viewRoles, manageRoles, viewSettings, manageSettings, updateMadrasa,
    },
    'admin': { // legacy alias
      viewStudents, createStudents, editStudents, deleteStudents,
      viewStaff, createStaff, editStaff, deleteStaff,
      viewAttendance, markAttendance, editAttendance, deleteAttendance,
      viewFees, createFees, updateFees, deleteFees,
      viewResults, enterResults, editResults, deleteResults, manageExams,
      viewFinance, createFinance, approveFinance, deleteFinance,
      viewLibrary, manageLibrary, viewHostel, manageHostel,
      viewAnnouncements, createAnnouncements, editAnnouncements, deleteAnnouncements,
      viewAdmissions, createAdmissions, editAdmissions, deleteAdmissions,
      viewDarjas, manageDarjas, viewReports, exportReports,
      viewUsers, createUsers, editUsers,
      viewRoles, manageRoles, viewSettings, manageSettings, updateMadrasa,
    },
    'editor': {
      viewStudents, createStudents, editStudents,
      viewStaff, viewAttendance, markAttendance, editAttendance,
      viewFees, createFees, updateFees,
      viewResults, enterResults, editResults,
      viewFinance, createFinance, viewLibrary,
      viewAnnouncements, createAnnouncements,
      viewAdmissions, createAdmissions, editAdmissions,
      viewDarjas, viewReports,
    },
    'academicManager': {
      viewStudents, editStudents, viewStaff,
      viewAttendance, markAttendance, editAttendance,
      viewResults, enterResults, editResults, deleteResults, manageExams,
      viewDarjas, manageDarjas,
      viewAnnouncements, createAnnouncements,
      viewReports, exportReports,
    },
    'teacher': {
      viewStudents, viewAttendance, markAttendance,
      viewResults, enterResults,
      viewDarjas, viewAnnouncements, viewFees,
    },
    'attendanceOfficer': {
      viewStudents, viewAttendance, markAttendance, editAttendance,
      viewDarjas, viewAnnouncements, viewReports,
    },
    'accountant': {
      viewStudents, viewFees, createFees, updateFees,
      viewFinance, createFinance, viewReports, exportReports,
      viewAnnouncements,
    },
    'financeManager': {
      viewStudents, viewFees, createFees, updateFees, deleteFees,
      viewFinance, createFinance, approveFinance, deleteFinance,
      viewReports, exportReports, viewAnnouncements,
    },
    'libraryManager': {
      viewStudents, viewLibrary, manageLibrary,
      viewAnnouncements, viewReports,
    },
    'hostelManager': {
      viewStudents, viewHostel, manageHostel,
      viewAnnouncements, viewReports,
    },
    'announcementManager': {
      viewStudents, viewStaff,
      viewAnnouncements, createAnnouncements, editAnnouncements, deleteAnnouncements,
    },
    'admissionOfficer': {
      viewStudents, createStudents, editStudents,
      viewAdmissions, createAdmissions, editAdmissions, deleteAdmissions,
      viewFees, createFees, viewAnnouncements, viewReports,
    },
    'itManager': {
      viewUsers, createUsers, editUsers, deleteUsers,
      viewRoles, manageRoles, viewSettings, manageSettings,
      viewAnnouncements, viewReports,
    },
    'parent': {
      viewStudents, viewAttendance, viewFees, viewResults, viewAnnouncements,
    },
    'student': {
      viewAttendance, viewResults, viewFees, viewAnnouncements, viewLibrary,
    },
  };

  /// Returns offline fallback permissions for a given role name.
  /// Falls back to empty set if role is unknown.
  static Set<String> fallbackFor(String roleName) =>
      roleDefaults[roleName] ?? const {};
}
