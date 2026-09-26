// ── Madrasa 360 — AppPermissions ─────────────────────────────────────────────
// Canonical permission vocabulary: the `permissions.code` values seeded by
// `supabase/migrations/005_rbac.sql` (66 dotted codes) and labelled by
// `supabase/migrations/019_role_ux_schema.sql` (all 122 codes, incl. the 56
// legacy underscore codes still issued by the deprecated `profiles.role`
// branch of `get_my_permissions()`).
//
// The client speaks the server's language directly: there is NO
// dotted↔underscore translation layer. Every code the server can return
// has a constant here, so the validator never drops a known code.
//
// Usage:
//   ref.watch(hasPermissionProvider(AppPermissions.viewStudents))
//
// ─────────────────────────────────────────────────────────────────────────────

abstract class AppPermissions {
  // ── Canonical dotted codes ─────────────────────────────────────────────

  // ── Students ──
  static const String viewStudents = 'students.view';
  static const String createStudents = 'students.create';
  static const String editStudents = 'students.update';
  static const String deleteStudents = 'students.delete';

  // ── Teachers ──
  static const String viewTeachers = 'teachers.view';
  static const String createTeachers = 'teachers.create';
  static const String editTeachers = 'teachers.update';
  static const String deleteTeachers = 'teachers.delete';

  // ── Staff ──
  static const String viewStaff = 'staff.view';
  static const String createStaff = 'staff.create';
  static const String editStaff = 'staff.update';
  static const String deleteStaff = 'staff.delete';

  // ── Attendance ──
  static const String viewAttendance = 'attendance.view';
  static const String markAttendance = 'attendance.mark';
  static const String editAttendance = 'attendance.edit';
  static const String deleteAttendance = 'attendance.delete';

  // ── Academics (darjas / classes) ──
  static const String viewDarjas = 'academics.view';
  static const String manageDarjas = 'academics.manage';

  // ── Exams ──
  static const String viewExams = 'exams.view';
  static const String createExams = 'exams.create';
  static const String editExams = 'exams.update';
  static const String deleteExams = 'exams.delete';
  static const String publishExams = 'exams.publish';

  // ── Results ──
  static const String viewResults = 'results.view';
  static const String enterResults = 'results.enter';
  static const String editResults = 'results.edit';
  static const String publishResults = 'results.publish';

  // ── Fees ──
  static const String viewFees = 'fees.view';
  static const String createFees = 'fees.create';
  static const String collectFees = 'fees.collect';
  static const String refundFees = 'fees.refund';

  // ── Finance ──
  static const String viewFinance = 'finance.view';
  static const String createFinance = 'finance.create';
  static const String updateFinance = 'finance.update';
  static const String deleteFinance = 'finance.delete';
  static const String approveFinance = 'finance.approve';

  // ── Library ──
  static const String viewLibrary = 'library.view';
  static const String manageLibrary = 'library.manage';

  // ── Hostel (dar-ul-iqama) ──
  static const String viewHostel = 'hostel.view';
  static const String manageHostel = 'hostel.manage';

  // ── Transport ──
  static const String viewTransport = 'transport.view';
  static const String manageTransport = 'transport.manage';

  // ── Parents ──
  static const String viewParents = 'parents.view';

  // ── Announcements / notifications ──
  static const String viewAnnouncements = 'notifications.view';
  static const String sendNotifications = 'notifications.send';

  // ── Reports ──
  static const String viewReports = 'reports.view';
  static const String exportReports = 'reports.export';

  // ── Documents ──
  static const String viewDocuments = 'documents.view';
  static const String manageDocuments = 'documents.manage';

  // ── Certificates ──
  static const String viewCertificates = 'certificates.view';
  static const String issueCertificates = 'certificates.issue';

  // ── Users ──
  static const String viewUsers = 'users.view';
  static const String createUsers = 'users.create';
  static const String editUsers = 'users.update';
  static const String deactivateUsers = 'users.deactivate';

  // ── Roles ──
  static const String viewRoles = 'roles.view';
  static const String assignRoles = 'roles.assign';

  // ── Settings ──
  static const String viewSettings = 'settings.view';
  static const String manageSettings = 'settings.update';

  // ── Modules ──
  static const String viewModules = 'modules.view';
  static const String manageModules = 'modules.manage';

  // ── Activity log ──
  static const String viewAudit = 'audit.view';

  // ── Tenants (platform) ──
  static const String viewAllMadrasas = 'tenants.view';
  static const String createMadrasa = 'tenants.create';
  static const String updateMadrasa = 'tenants.update';
  static const String suspendTenant = 'tenants.suspend';

  // ── Legacy catalog codes ───────────────────────────────────────────────
  // Still live in `permissions` (019 labels them) and still issuable via
  // the deprecated `profiles.role` branch. Kept so nothing the server
  // returns is unrepresentable client-side.
  /// No dotted twin: exam management in this app's UI (create/update/delete/publish).
  static const String manageExams = 'manage_exams';

  /// No fees.update in the catalog: 007 RLS gates every fee mutation on fees.collect.
  static const String updateFees = 'fees.collect';

  /// No fees.delete in the catalog: 007 RLS lets fees.collect double as update+delete.
  static const String deleteFees = 'fees.collect';

  /// No results.delete in the catalog: 007 RLS lets results.edit double as delete.
  static const String deleteResults = 'results.edit';

  /// The server's user-removal code is users.deactivate (see 007 profiles policies).
  static const String deleteUsers = 'users.deactivate';

  /// Legacy catalog code; the closest dotted codes are roles.view / roles.assign.
  static const String manageRoles = 'manage_roles';

  /// Legacy catalog code with no dotted twin.
  static const String managePermissions = 'manage_permissions';

  /// Admissions has no dotted codes in the catalog.
  static const String viewAdmissions = 'view_admissions';

  /// Admissions has no dotted codes in the catalog.
  static const String createAdmissions = 'create_admissions';

  /// Admissions has no dotted codes in the catalog.
  static const String editAdmissions = 'edit_admissions';

  /// Admissions has no dotted codes in the catalog.
  static const String deleteAdmissions = 'delete_admissions';

  /// Legacy twin of notifications.send.
  static const String createAnnouncements = 'create_announcements';

  /// Legacy catalog code with no dotted twin.
  static const String editAnnouncements = 'edit_announcements';

  /// Legacy catalog code with no dotted twin.
  static const String deleteAnnouncements = 'delete_announcements';

  /// Legacy catalog code with no dotted twin.
  static const String assignMadrasaAdmin = 'assign_madrasa_admin';

  /// Legacy platform-level code.
  static const String systemFullAccess = 'system_full_access';

  // One constant per remaining legacy underscore code (name = legacy +
  // CamelCase of the code).
  static const String legacyApproveFinance = 'approve_finance';
  static const String legacyCreateFees = 'create_fees';
  static const String legacyCreateFinance = 'create_finance';
  static const String legacyCreateMadrasa = 'create_madrasa';
  static const String legacyCreateStaff = 'create_staff';
  static const String legacyCreateStudents = 'create_students';
  static const String legacyCreateUsers = 'create_users';
  static const String legacyDeleteAttendance = 'delete_attendance';
  static const String legacyDeleteFees = 'delete_fees';
  static const String legacyDeleteFinance = 'delete_finance';
  static const String legacyDeleteMadrasa = 'delete_madrasa';
  static const String legacyDeleteResults = 'delete_results';
  static const String legacyDeleteStaff = 'delete_staff';
  static const String legacyDeleteStudents = 'delete_students';
  static const String legacyDeleteUsers = 'delete_users';
  static const String legacyEditAttendance = 'edit_attendance';
  static const String legacyEditResults = 'edit_results';
  static const String legacyEditStaff = 'edit_staff';
  static const String legacyEditStudents = 'edit_students';
  static const String legacyEditUsers = 'edit_users';
  static const String legacyEnterResults = 'enter_results';
  static const String legacyExportReports = 'export_reports';
  static const String legacyManageDarjas = 'manage_darjas';
  static const String legacyManageHostel = 'manage_hostel';
  static const String legacyManageLibrary = 'manage_library';
  static const String legacyManageSettings = 'manage_settings';
  static const String legacyMarkAttendance = 'mark_attendance';
  static const String legacyUpdateFees = 'update_fees';
  static const String legacyUpdateMadrasa = 'update_madrasa';
  static const String legacyViewAllMadrasas = 'view_all_madrasas';
  static const String legacyViewAnnouncements = 'view_announcements';
  static const String legacyViewAttendance = 'view_attendance';
  static const String legacyViewDarjas = 'view_darjas';
  static const String legacyViewFees = 'view_fees';
  static const String legacyViewFinance = 'view_finance';
  static const String legacyViewHostel = 'view_hostel';
  static const String legacyViewLibrary = 'view_library';
  static const String legacyViewReports = 'view_reports';
  static const String legacyViewResults = 'view_results';
  static const String legacyViewRoles = 'view_roles';
  static const String legacyViewSettings = 'view_settings';
  static const String legacyViewStaff = 'view_staff';
  static const String legacyViewStudents = 'view_students';
  static const String legacyViewUsers = 'view_users';

  // ── Catalog sets ───────────────────────────────────────────────────────
  /// All 66 canonical dotted codes.
  static const List<String> allDottedCodes = [
    'students.view',
    'students.create',
    'students.update',
    'students.delete',
    'teachers.view',
    'teachers.create',
    'teachers.update',
    'teachers.delete',
    'staff.view',
    'staff.create',
    'staff.update',
    'staff.delete',
    'attendance.view',
    'attendance.mark',
    'attendance.edit',
    'attendance.delete',
    'academics.view',
    'academics.manage',
    'exams.view',
    'exams.create',
    'exams.update',
    'exams.delete',
    'exams.publish',
    'results.view',
    'results.enter',
    'results.edit',
    'results.publish',
    'fees.view',
    'fees.create',
    'fees.collect',
    'fees.refund',
    'finance.view',
    'finance.create',
    'finance.update',
    'finance.delete',
    'finance.approve',
    'library.view',
    'library.manage',
    'hostel.view',
    'hostel.manage',
    'transport.view',
    'transport.manage',
    'parents.view',
    'notifications.view',
    'notifications.send',
    'reports.view',
    'reports.export',
    'documents.view',
    'documents.manage',
    'certificates.view',
    'certificates.issue',
    'users.view',
    'users.create',
    'users.update',
    'users.deactivate',
    'roles.view',
    'roles.assign',
    'settings.view',
    'settings.update',
    'modules.view',
    'modules.manage',
    'audit.view',
    'tenants.view',
    'tenants.create',
    'tenants.update',
    'tenants.suspend',
  ];

  /// Every code the server can issue (dotted + legacy). The permission
  /// validator accepts exactly this set.
  static final Set<String> allCodes = {
    ...allDottedCodes,
    'manage_exams',
    'fees.collect',
    'results.edit',
    'users.deactivate',
    'manage_roles',
    'manage_permissions',
    'view_admissions',
    'create_admissions',
    'edit_admissions',
    'delete_admissions',
    'create_announcements',
    'edit_announcements',
    'delete_announcements',
    'assign_madrasa_admin',
    'system_full_access',
    'approve_finance',
    'create_fees',
    'create_finance',
    'create_madrasa',
    'create_staff',
    'create_students',
    'create_users',
    'delete_attendance',
    'delete_fees',
    'delete_finance',
    'delete_madrasa',
    'delete_results',
    'delete_staff',
    'delete_students',
    'delete_users',
    'edit_attendance',
    'edit_results',
    'edit_staff',
    'edit_students',
    'edit_users',
    'enter_results',
    'export_reports',
    'manage_darjas',
    'manage_hostel',
    'manage_library',
    'manage_settings',
    'mark_attendance',
    'update_fees',
    'update_madrasa',
    'view_all_madrasas',
    'view_announcements',
    'view_attendance',
    'view_darjas',
    'view_fees',
    'view_finance',
    'view_hostel',
    'view_library',
    'view_reports',
    'view_results',
    'view_roles',
    'view_settings',
    'view_staff',
    'view_students',
    'view_users',
  };

  // ── Urdu labels (from 019_role_ux_schema.sql) ────────────────────────────
  /// Human-readable Urdu label per code, for permission-management UI.
  /// Normal screens never show raw codes.
  static const Map<String, String> urduLabels = {
    'students.view': 'طلبہ دیکھنا',
    'students.create': 'نئے طلبہ شامل کرنا',
    'students.update': 'طلبہ کی معلومات درست کرنا',
    'students.delete': 'طلبہ کا ریکارڈ ختم کرنا',
    'teachers.view': 'اساتذہ کو دیکھنا',
    'teachers.create': 'نئے اساتذہ شامل کرنا',
    'teachers.update': 'اساتذہ کی معلومات درست کرنا',
    'teachers.delete': 'اساتذہ کا ریکارڈ ختم کرنا',
    'staff.view': 'عملے کو دیکھنا',
    'staff.create': 'نیا عملہ شامل کرنا',
    'staff.update': 'عملے کی معلومات درست کرنا',
    'staff.delete': 'عملے کا ریکارڈ ختم کرنا',
    'attendance.view': 'حاضری دیکھنا',
    'attendance.mark': 'حاضری لگانا',
    'attendance.edit': 'حاضری درست کرنا',
    'attendance.delete': 'حاضری کا ریکارڈ ختم کرنا',
    'academics.view': 'تعلیمی نظام دیکھنا',
    'academics.manage': 'تعلیمی نظام ترتیب دینا',
    'exams.view': 'امتحانات دیکھنا',
    'exams.create': 'امتحان بنانا',
    'exams.update': 'امتحان میں تبدیلی کرنا',
    'exams.delete': 'امتحان ختم کرنا',
    'exams.publish': 'امتحان کا اعلان کرنا',
    'results.view': 'نتائج دیکھنا',
    'results.enter': 'نمبر درج کرنا',
    'results.edit': 'نمبر درست کرنا',
    'results.publish': 'نتائج شائع کرنا',
    'fees.view': 'فیس کا حساب دیکھنا',
    'fees.create': 'فیس مقرر کرنا',
    'fees.collect': 'فیس وصول کرنا',
    'fees.refund': 'فیس واپس کرنا',
    'finance.view': 'مالی حساب دیکھنا',
    'finance.create': 'مالی لین دین درج کرنا',
    'finance.update': 'مالی ریکارڈ درست کرنا',
    'finance.delete': 'مالی ریکارڈ ختم کرنا',
    'finance.approve': 'مالی لین دین کی منظوری دینا',
    'library.view': 'کتب خانہ دیکھنا',
    'library.manage': 'کتب خانے کا انتظام کرنا',
    'hostel.view': 'دارالاقامہ دیکھنا',
    'hostel.manage': 'دارالاقامہ کا انتظام کرنا',
    'transport.view': 'ٹرانسپورٹ دیکھنا',
    'transport.manage': 'ٹرانسپورٹ کا انتظام کرنا',
    'parents.view': 'والدین کی معلومات دیکھنا',
    'notifications.view': 'اعلانات دیکھنا',
    'notifications.send': 'اعلان بھیجنا',
    'reports.view': 'رپورٹس دیکھنا',
    'reports.export': 'رپورٹس محفوظ کرنا',
    'documents.view': 'دستاویزات دیکھنا',
    'documents.manage': 'دستاویزات کا انتظام کرنا',
    'certificates.view': 'اسناد دیکھنا',
    'certificates.issue': 'سند جاری کرنا',
    'users.view': 'صارفین دیکھنا',
    'users.create': 'نیا صارف بنانا',
    'users.update': 'صارف کی معلومات درست کرنا',
    'users.deactivate': 'صارف غیر فعال کرنا',
    'roles.view': 'ذمہ داریاں دیکھنا',
    'roles.assign': 'ذمہ داریاں سونپنا',
    'settings.view': 'ترتیبات دیکھنا',
    'settings.update': 'ترتیبات تبدیل کرنا',
    'modules.view': 'شعبے دیکھنا',
    'modules.manage': 'شعبے فعال یا غیر فعال کرنا',
    'audit.view': 'سرگرمی کا ریکارڈ دیکھنا',
    'tenants.view': 'مدارس دیکھنا',
    'tenants.create': 'نیا مدرسہ بنانا',
    'tenants.update': 'مدرسے کی معلومات درست کرنا',
    'tenants.suspend': 'مدرسہ معطل یا بحال کرنا',
    'approve_finance': 'مالی لین دین کی منظوری دینا',
    'assign_madrasa_admin': 'مدرسے کا منتظم مقرر کرنا',
    'create_admissions': 'نیا داخلہ کرنا',
    'create_announcements': 'اعلان بنانا',
    'create_fees': 'فیس مقرر کرنا',
    'create_finance': 'مالی لین دین درج کرنا',
    'create_madrasa': 'نیا مدرسہ بنانا',
    'create_staff': 'نیا عملہ شامل کرنا',
    'create_students': 'نئے طلبہ شامل کرنا',
    'create_users': 'نیا صارف بنانا',
    'delete_admissions': 'داخلہ ختم کرنا',
    'delete_announcements': 'اعلان ختم کرنا',
    'delete_attendance': 'حاضری کا ریکارڈ ختم کرنا',
    'delete_fees': 'فیس کا ریکارڈ ختم کرنا',
    'delete_finance': 'مالی ریکارڈ ختم کرنا',
    'delete_madrasa': 'مدرسہ ختم کرنا',
    'delete_results': 'نتائج ختم کرنا',
    'delete_staff': 'عملے کا ریکارڈ ختم کرنا',
    'delete_students': 'طلبہ کا ریکارڈ ختم کرنا',
    'delete_users': 'صارف ختم کرنا',
    'edit_admissions': 'داخلے میں تبدیلی کرنا',
    'edit_announcements': 'اعلان میں تبدیلی کرنا',
    'edit_attendance': 'حاضری درست کرنا',
    'edit_results': 'نمبر درست کرنا',
    'edit_staff': 'عملے کی معلومات درست کرنا',
    'edit_students': 'طلبہ کی معلومات درست کرنا',
    'edit_users': 'صارف کی معلومات درست کرنا',
    'enter_results': 'نمبر درج کرنا',
    'export_reports': 'رپورٹس محفوظ کرنا',
    'manage_darjas': 'درجات کا انتظام کرنا',
    'manage_exams': 'امتحانات کا انتظام کرنا',
    'manage_hostel': 'دارالاقامہ کا انتظام کرنا',
    'manage_library': 'کتب خانے کا انتظام کرنا',
    'manage_permissions': 'اختیارات کا انتظام کرنا',
    'manage_roles': 'ذمہ داریوں کا انتظام کرنا',
    'manage_settings': 'ترتیبات کا انتظام کرنا',
    'mark_attendance': 'حاضری لگانا',
    'system_full_access': 'مکمل رسائی',
    'update_fees': 'فیس میں تبدیلی کرنا',
    'update_madrasa': 'مدرسے کی معلومات درست کرنا',
    'view_admissions': 'داخلے دیکھنا',
    'view_all_madrasas': 'تمام مدارس دیکھنا',
    'view_announcements': 'اعلانات دیکھنا',
    'view_attendance': 'حاضری دیکھنا',
    'view_darjas': 'درجات دیکھنا',
    'view_fees': 'فیس کا حساب دیکھنا',
    'view_finance': 'مالی حساب دیکھنا',
    'view_hostel': 'دارالاقامہ دیکھنا',
    'view_library': 'کتب خانہ دیکھنا',
    'view_reports': 'رپورٹس دیکھنا',
    'view_results': 'نتائج دیکھنا',
    'view_roles': 'ذمہ داریاں دیکھنا',
    'view_settings': 'ترتیبات دیکھنا',
    'view_staff': 'عملے کو دیکھنا',
    'view_students': 'طلبہ دیکھنا',
    'view_users': 'صارفین دیکھنا',
  };

  /// Urdu label for [code], or the code itself when unknown.
  static String urduLabelFor(String code) => urduLabels[code] ?? code;

  // ── Offline fallback: role key → default permissions ───────────────────
  // Used when the server cannot be reached (offline mode). The sets mirror
  // the template permission sets seeded by 005_rbac.sql / 019_role_ux_schema.sql
  // for the tenant role keys. Keyed by the `tenant_memberships.role` keys —
  // NOT the legacy Dart `UserRole` names.
  //
  // "All tenant codes" (019 §b) = every dotted code except the platform-level
  // `tenants.*` codes and `audit.view` — the same definition the migrations
  // use for tenant_owner / tenant_admin / mohtamim / naib_mohtamim.

  /// Every dotted tenant code (excludes `tenants.*` and `audit.view`).
  static final Set<String> allTenantCodes = allDottedCodes
      .where((c) => !c.startsWith('tenants.') && c != viewAudit)
      .toSet();

  /// Offline teacher-family base set (005/019 `teacher` template).
  static const Set<String> _teacherBase = {
    viewStudents,
    viewAttendance,
    markAttendance,
    editAttendance,
    viewExams,
    viewResults,
    enterResults,
    editResults,
    viewAnnouncements,
  };

  static final Map<String, Set<String>> roleDefaults = {
    'tenant_owner': allTenantCodes,
    'tenant_admin': allTenantCodes,
    'mohtamim': allTenantCodes,
    'naib_mohtamim': allTenantCodes,
    'principal': {
      viewDarjas,
      manageDarjas,
      viewExams,
      createExams,
      editExams,
      deleteExams,
      publishExams,
      viewResults,
      enterResults,
      editResults,
      publishResults,
      viewReports,
      exportReports,
      viewAttendance,
      viewStaff,
      viewFees,
    },
    'accountant': {
      viewFees,
      createFees,
      collectFees,
      refundFees,
      viewFinance,
      createFinance,
      updateFinance,
      deleteFinance,
      approveFinance,
      viewReports,
      exportReports,
    },
    'teacher': _teacherBase,
    'ustad': _teacherBase,
    'ustad_hifz': {
      ..._teacherBase,
      viewHostel,
    },
    'librarian': {
      viewLibrary,
      manageLibrary,
    },
    'hostel_manager': {
      viewHostel,
      manageHostel,
    },
    'staff': {
      viewAttendance,
      markAttendance,
    },
    'parent': {
      viewAnnouncements,
    },
    'student': {
      viewAnnouncements,
    },
    'nazim_aala': {
      viewStudents,
      createStudents,
      editStudents,
      deleteStudents,
      viewTeachers,
      createTeachers,
      editTeachers,
      deleteTeachers,
      viewStaff,
      createStaff,
      editStaff,
      deleteStaff,
      viewAttendance,
      markAttendance,
      editAttendance,
      deleteAttendance,
      viewDarjas,
      manageDarjas,
      viewReports,
      exportReports,
      viewUsers,
      viewAnnouncements,
      sendNotifications,
    },
    'nazim_taleem': {
      viewDarjas,
      manageDarjas,
      viewExams,
      createExams,
      editExams,
      deleteExams,
      publishExams,
      viewResults,
      enterResults,
      editResults,
      publishResults,
      viewAttendance,
      viewTeachers,
      viewReports,
      exportReports,
    },
    'nazim_intizamia': {
      viewStaff,
      createStaff,
      editStaff,
      deleteStaff,
      viewDocuments,
      manageDocuments,
      sendNotifications,
      viewUsers,
    },
    'nazim_maliyat': {
      viewFees,
      createFees,
      collectFees,
      refundFees,
      viewFinance,
      createFinance,
      updateFinance,
      deleteFinance,
      approveFinance,
    },
    'daftar_dar': {
      viewStudents,
      createStudents,
      editStudents,
      viewFees,
      collectFees,
      issueCertificates,
      viewAnnouncements,
      viewDocuments,
      manageDocuments,
    },
    'nazim_hifz': {
      viewDarjas,
      viewExams,
      createExams,
      viewResults,
      enterResults,
      editResults,
      viewAttendance,
    },
    'nazim_darul_iqama': {
      viewHostel,
      manageHostel,
      viewStudents,
      viewAttendance,
    },
    'warden': {
      viewHostel,
      viewAttendance,
      markAttendance,
      viewStudents,
    },
    'mumtahin': {
      viewExams,
      createExams,
      editExams,
      viewResults,
      enterResults,
      editResults,
      viewStudents,
    },
    'store_incharge': {
      viewDocuments,
      manageDocuments,
      viewReports,
    },
    'hr_incharge': {
      viewStaff,
      createStaff,
      editStaff,
      deleteStaff,
      viewUsers,
      viewAttendance,
      viewReports,
    },
    'platform_owner': allCodes,
    'platform_support': {
      viewAllMadrasas,
      viewUsers,
      viewAudit,
      viewReports,
    },
  };

  /// Offline fallback permissions for a tenant role [roleKey].
  /// Unknown keys yield an empty set (fail-closed).
  static Set<String> fallbackFor(String roleKey) =>
      roleDefaults[roleKey] ?? const {};
}
