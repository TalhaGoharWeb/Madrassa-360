/// کردار اور اجازتوں کا ماڈل
/// AppRole & Permission — role-based access control for the system

import 'package:flutter/material.dart' show IconData, Icons;

// ─────────────────────────────────────────────────────────────
// Permissions
// ─────────────────────────────────────────────────────────────

/// Granular permissions that can be toggled per role.
enum Permission {
  viewStudents,
  editStudents,
  viewStaff,
  editStaff,
  viewFees,
  editFees,
  viewAttendance,
  markAttendance,
  viewResults,
  editResults,
  manageUsers,
}

extension PermissionX on Permission {
  String get urduLabel {
    switch (this) {
      case Permission.viewStudents:
        return 'طلباء دیکھنا';
      case Permission.editStudents:
        return 'طلباء ترمیم';
      case Permission.viewStaff:
        return 'عملہ دیکھنا';
      case Permission.editStaff:
        return 'عملہ ترمیم';
      case Permission.viewFees:
        return 'فیس دیکھنا';
      case Permission.editFees:
        return 'فیس ترمیم';
      case Permission.viewAttendance:
        return 'حاضری دیکھنا';
      case Permission.markAttendance:
        return 'حاضری لگانا';
      case Permission.viewResults:
        return 'نتائج دیکھنا';
      case Permission.editResults:
        return 'نتائج ترمیم';
      case Permission.manageUsers:
        return 'صارفین انتظام';
    }
  }

  IconData get icon {
    switch (this) {
      case Permission.viewStudents:
      case Permission.editStudents:
        return Icons.people;
      case Permission.viewStaff:
      case Permission.editStaff:
        return Icons.badge;
      case Permission.viewFees:
      case Permission.editFees:
        return Icons.account_balance_wallet;
      case Permission.viewAttendance:
      case Permission.markAttendance:
        return Icons.fact_check;
      case Permission.viewResults:
      case Permission.editResults:
        return Icons.assessment;
      case Permission.manageUsers:
        return Icons.manage_accounts;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// AppRole
// ─────────────────────────────────────────────────────────────

class AppRole {
  final String? id;
  final String name; // DB/code key e.g. 'teacher'
  final String nameUrdu; // Display label e.g. 'استاد'
  final String? description;
  final Set<Permission> permissions;
  final bool isSystem; // system roles cannot be deleted

  const AppRole({
    this.id,
    required this.name,
    required this.nameUrdu,
    this.description,
    this.permissions = const {},
    this.isSystem = false,
  });

  factory AppRole.fromJson(Map<String, dynamic> json) {
    final permList = (json['permissions'] as List<dynamic>? ?? [])
        .map((p) => Permission.values.firstWhere(
              (pe) => pe.name == p,
              orElse: () => Permission.viewStudents,
            ))
        .toSet();
    return AppRole(
      id: json['id'] as String?,
      name: json['name'] as String,
      nameUrdu: json['name_urdu'] as String? ?? json['name'] as String,
      description: json['description'] as String?,
      permissions: permList,
      isSystem: json['is_system'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'name_urdu': nameUrdu,
        'description': description,
        'permissions': permissions.map((p) => p.name).toList(),
        'is_system': isSystem,
      };

  AppRole copyWith({
    String? nameUrdu,
    String? description,
    Set<Permission>? permissions,
  }) {
    return AppRole(
      id: id,
      name: name,
      nameUrdu: nameUrdu ?? this.nameUrdu,
      description: description ?? this.description,
      permissions: permissions ?? this.permissions,
      isSystem: isSystem,
    );
  }

  // ── Built-in system role defaults ─────────────────────────
  // Keep in sync with 06_rbac.sql Part 7 and UserRole enum.

  // Platform
  static const AppRole superAdmin = AppRole(
    name: 'superAdmin',
    nameUrdu: 'سپر ایڈمن',
    description: 'پلیٹ فارم پر مکمل اختیار',
    permissions: {
      Permission.viewStudents,
      Permission.editStudents,
      Permission.viewStaff,
      Permission.editStaff,
      Permission.viewFees,
      Permission.editFees,
      Permission.viewAttendance,
      Permission.markAttendance,
      Permission.viewResults,
      Permission.editResults,
      Permission.manageUsers,
    },
    isSystem: true,
  );

  static const AppRole franchiseManager = AppRole(
    name: 'franchiseManager',
    nameUrdu: 'فرنچائز مینیجر',
    description: 'تمام مدارس کی نگرانی',
    permissions: {
      Permission.viewStudents,
      Permission.viewStaff,
      Permission.viewFees,
      Permission.viewAttendance,
      Permission.viewResults,
      Permission.manageUsers,
    },
    isSystem: true,
  );

  // Madrasa
  static const AppRole madrasaAdmin = AppRole(
    name: 'madrasaAdmin',
    nameUrdu: 'مدرسہ ایڈمن',
    description: 'مدرسے کا مکمل انتظام (ناظم / مہتمم)',
    permissions: {
      Permission.viewStudents,
      Permission.editStudents,
      Permission.viewStaff,
      Permission.editStaff,
      Permission.viewFees,
      Permission.editFees,
      Permission.viewAttendance,
      Permission.markAttendance,
      Permission.viewResults,
      Permission.editResults,
      Permission.manageUsers,
    },
    isSystem: true,
  );

  static const AppRole admin = AppRole(
    name: 'admin',
    nameUrdu: 'منتظم',
    description: 'مکمل انتظامی اختیارات (پرانا نام)',
    permissions: {
      Permission.viewStudents,
      Permission.editStudents,
      Permission.viewStaff,
      Permission.editStaff,
      Permission.viewFees,
      Permission.editFees,
      Permission.viewAttendance,
      Permission.markAttendance,
      Permission.viewResults,
      Permission.editResults,
      Permission.manageUsers,
    },
    isSystem: true,
  );

  static const AppRole editor = AppRole(
    name: 'editor',
    nameUrdu: 'ایڈیٹر',
    description: 'ڈیٹا درج اور ترمیم، صارف انتظام نہیں',
    permissions: {
      Permission.viewStudents,
      Permission.editStudents,
      Permission.viewStaff,
      Permission.viewAttendance,
      Permission.markAttendance,
      Permission.viewFees,
      Permission.editFees,
      Permission.viewResults,
      Permission.editResults,
    },
    isSystem: true,
  );

  // Academic
  static const AppRole academicManager = AppRole(
    name: 'academicManager',
    nameUrdu: 'تعلیمی مینیجر',
    description: 'تعلیمی ڈھانچہ، امتحانات، نتائج',
    permissions: {
      Permission.viewStudents,
      Permission.editStudents,
      Permission.viewStaff,
      Permission.viewAttendance,
      Permission.markAttendance,
      Permission.viewResults,
      Permission.editResults,
    },
    isSystem: true,
  );

  static const AppRole teacher = AppRole(
    name: 'teacher',
    nameUrdu: 'استاذ',
    description: 'پڑھانا اور حاضری',
    permissions: {
      Permission.viewStudents,
      Permission.viewAttendance,
      Permission.markAttendance,
      Permission.viewResults,
      Permission.editResults,
    },
    isSystem: true,
  );

  static const AppRole attendanceOfficer = AppRole(
    name: 'attendanceOfficer',
    nameUrdu: 'حاضری افسر',
    description: 'تمام جماعتوں کی حاضری',
    permissions: {
      Permission.viewStudents,
      Permission.viewAttendance,
      Permission.markAttendance,
    },
    isSystem: true,
  );

  // Finance
  static const AppRole accountant = AppRole(
    name: 'accountant',
    nameUrdu: 'محاسب',
    description: 'فیس اور روزانہ لین دین',
    permissions: {
      Permission.viewStudents,
      Permission.viewFees,
      Permission.editFees,
    },
    isSystem: true,
  );

  static const AppRole financeManager = AppRole(
    name: 'financeManager',
    nameUrdu: 'مالیاتی مینیجر',
    description: 'مکمل مالیاتی اختیار',
    permissions: {
      Permission.viewStudents,
      Permission.viewFees,
      Permission.editFees,
    },
    isSystem: true,
  );

  // Other departments
  static const AppRole libraryManager = AppRole(
    name: 'libraryManager',
    nameUrdu: 'لائبریری مینیجر',
    description: 'کتب اور اجراء کا انتظام',
    permissions: {Permission.viewStudents},
    isSystem: true,
  );

  static const AppRole hostelManager = AppRole(
    name: 'hostelManager',
    nameUrdu: 'ہاسٹل مینیجر',
    description: 'ہاسٹل ریکارڈ انتظام',
    permissions: {Permission.viewStudents},
    isSystem: true,
  );

  static const AppRole announcementManager = AppRole(
    name: 'announcementManager',
    nameUrdu: 'اعلان مینیجر',
    description: 'اعلانات بنانا اور انتظام',
    permissions: {Permission.viewStudents, Permission.viewStaff},
    isSystem: true,
  );

  static const AppRole admissionOfficer = AppRole(
    name: 'admissionOfficer',
    nameUrdu: 'داخلہ افسر',
    description: 'نئے طلباء کا داخلہ',
    permissions: {
      Permission.viewStudents,
      Permission.editStudents,
      Permission.viewFees,
    },
    isSystem: true,
  );

  static const AppRole itManager = AppRole(
    name: 'itManager',
    nameUrdu: 'آئی ٹی مینیجر',
    description: 'نظام ترتیبات اور صارف انتظام',
    permissions: {Permission.manageUsers},
    isSystem: true,
  );

  // External
  static const AppRole parent = AppRole(
    name: 'parent',
    nameUrdu: 'والدین',
    description: 'بچے کی معلومات دیکھنا',
    permissions: {
      Permission.viewStudents,
      Permission.viewFees,
      Permission.viewAttendance,
      Permission.viewResults,
    },
    isSystem: true,
  );

  static const AppRole student = AppRole(
    name: 'student',
    nameUrdu: 'طالب علم',
    description: 'اپنے تعلیمی ڈیٹا تک رسائی',
    permissions: {
      Permission.viewAttendance,
      Permission.viewResults,
      Permission.viewFees,
    },
    isSystem: true,
  );

  /// All built-in system roles in display order.
  static const List<AppRole> allSystemRoles = [
    superAdmin,
    franchiseManager,
    madrasaAdmin,
    editor,
    academicManager,
    teacher,
    attendanceOfficer,
    accountant,
    financeManager,
    libraryManager,
    hostelManager,
    announcementManager,
    admissionOfficer,
    itManager,
    parent,
    student,
  ];
}
