/// طالب علم کا ماڈل (Supabase)
/// Student model — maps to the public.students table

import 'attendance_status.dart';

/// Full student model backed by Supabase.
/// Used by [StudentRepository] and all real providers.
///
/// [tenantId] is the multi-tenant owner (public.tenants). It is required:
/// every query and insert must be scoped to it (Phase 2 SaaS).
/// `fromJson` also accepts the legacy `madrasa_id` key so old
/// SharedPreferences caches keep decoding during the migration.
class Student {
  final String id;
  final String tenantId;
  final String rollNo;
  final String name;
  final String fatherName;
  final String darjaId;
  final String darjaName; // joined from public.darjas
  final String classId;
  final String className; // joined from public.classes
  final String? parentUserId;
  final String? dateOfBirth;
  final String? dateOfAdmit;
  final String? phone;
  final String? address;
  final String? photoUrl;
  final bool isActive;

  // Transient — populated by AttendanceRepository when loading class list
  final AttendanceStatus attendanceStatus;

  const Student({
    required this.id,
    required this.tenantId,
    required this.rollNo,
    required this.name,
    required this.fatherName,
    required this.darjaId,
    required this.darjaName,
    required this.classId,
    required this.className,
    this.parentUserId,
    this.dateOfBirth,
    this.dateOfAdmit,
    this.phone,
    this.address,
    this.photoUrl,
    this.isActive = true,
    this.attendanceStatus = AttendanceStatus.present,
  });

  /// Build from a Supabase row.
  /// Pass [selectWithJoin: true] when the query includes
  /// `.select('*, darjas(name), classes(name)')`.
  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'] as String,
      tenantId: (json['tenant_id'] ?? json['madrasa_id'] ?? '') as String,
      rollNo: json['roll_no'] as String,
      name: json['name'] as String,
      fatherName: json['father_name'] as String,
      darjaId: json['darja_id'] as String? ?? '',
      darjaName: (json['darjas'] as Map?)?['name'] as String? ?? '',
      classId: json['class_id'] as String? ?? '',
      className: (json['classes'] as Map?)?['name'] as String? ?? '',
      parentUserId: json['parent_user_id'] as String?,
      dateOfBirth: json['date_of_birth'] as String?,
      dateOfAdmit: json['date_of_admit'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      photoUrl: json['photo_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  /// Serialise for INSERT / UPDATE (excludes generated/read-only cols).
  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'roll_no': rollNo,
        'name': name,
        'father_name': fatherName,
        'darja_id': darjaId,
        'class_id': classId,
        'parent_user_id': parentUserId,
        'date_of_birth': dateOfBirth,
        'date_of_admit': dateOfAdmit,
        'phone': phone,
        'address': address,
        'photo_url': photoUrl,
        'is_active': isActive,
      };

  Student copyWith({
    AttendanceStatus? attendanceStatus,
    String? photoUrl,
    bool? isActive,
  }) {
    return Student(
      id: id,
      tenantId: tenantId,
      rollNo: rollNo,
      name: name,
      fatherName: fatherName,
      darjaId: darjaId,
      darjaName: darjaName,
      classId: classId,
      className: className,
      parentUserId: parentUserId,
      dateOfBirth: dateOfBirth,
      dateOfAdmit: dateOfAdmit,
      phone: phone,
      address: address,
      photoUrl: photoUrl ?? this.photoUrl,
      isActive: isActive ?? this.isActive,
      attendanceStatus: attendanceStatus ?? this.attendanceStatus,
    );
  }

  /// Initials for avatar placeholder (works with Urdu names).
  String get initials {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) return '${words[0][0]}${words[1][0]}';
    return name.isNotEmpty ? name[0] : '?';
  }

  @override
  String toString() =>
      'Student(id: $id, name: $name, roll: $rollNo, class: $className)';
}
