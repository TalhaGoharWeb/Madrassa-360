/// عملہ کا ماڈل (Supabase)
/// Staff model — maps to the public.staff table

/// Full staff member model backed by Supabase.
///
/// [tenantId] is the multi-tenant owner (public.tenants) — required.
class Staff {
  final String id;
  final String tenantId;
  final String name;
  final String fatherName;
  final String designation;
  final String phone;
  final String? department;
  final String joiningDate; // ISO date string 'YYYY-MM-DD'
  final double? salary;
  final String? cnic;
  final String? userId; // linked auth.users profile (nullable)
  final String? photoUrl;
  final bool isActive;

  const Staff({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.fatherName,
    required this.designation,
    required this.phone,
    required this.joiningDate,
    this.department,
    this.salary,
    this.cnic,
    this.userId,
    this.photoUrl,
    this.isActive = true,
  });

  factory Staff.fromJson(Map<String, dynamic> json) {
    return Staff(
      id: json['id'] as String,
      tenantId: (json['tenant_id'] ?? json['madrasa_id'] ?? '') as String,
      name: json['name'] as String,
      fatherName: json['father_name'] as String,
      designation: json['designation'] as String,
      phone: json['phone'] as String,
      joiningDate: json['joining_date'] as String,
      department: json['department'] as String?,
      salary: (json['salary'] as num?)?.toDouble(),
      cnic: json['cnic'] as String?,
      userId: json['user_id'] as String?,
      photoUrl: json['photo_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'name': name,
        'father_name': fatherName,
        'designation': designation,
        'phone': phone,
        'joining_date': joiningDate,
        'department': department,
        'salary': salary,
        'cnic': cnic,
        'user_id': userId,
        'photo_url': photoUrl,
        'is_active': isActive,
      };

  Staff copyWith({String? photoUrl, bool? isActive}) {
    return Staff(
      id: id,
      tenantId: tenantId,
      name: name,
      fatherName: fatherName,
      designation: designation,
      phone: phone,
      joiningDate: joiningDate,
      department: department,
      salary: salary,
      cnic: cnic,
      userId: userId,
      photoUrl: photoUrl ?? this.photoUrl,
      isActive: isActive ?? this.isActive,
    );
  }

  String get initials {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) return '${words[0][0]}${words[1][0]}';
    return name.isNotEmpty ? name[0] : '?';
  }
}
