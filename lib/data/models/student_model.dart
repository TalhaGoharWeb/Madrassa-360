import 'attendance_status.dart';

/// طالب علم کا ماڈل
/// Mock Student Model for Phase 1 (No Firebase)
class MockStudent {
  final String id;
  final String name;           // طالب علم کا نام (Urdu)
  final String fatherName;     // والد کا نام (Urdu)
  final String rollNo;         // رول نمبر
  final String darjaName;      // درجہ کا نام (Level)
  final String className;      // جماعت (Class section)
  final String? photoUrl;      // تصویر (Optional)
  AttendanceStatus status;     // حاضری کی حالت (Default: Present)

  MockStudent({
    required this.id,
    required this.name,
    required this.fatherName,
    required this.rollNo,
    required this.darjaName,
    required this.className,
    this.photoUrl,
    this.status = AttendanceStatus.present, // ⭐ Default is PRESENT
  });

  /// Get initials from Urdu name (first letter of first two words)
  String get initials {
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}';
    }
    return name.isNotEmpty ? name[0] : '?';
  }

  /// Copy with method for immutability
  MockStudent copyWith({
    String? id,
    String? name,
    String? fatherName,
    String? rollNo,
    String? darjaName,
    String? className,
    String? photoUrl,
    AttendanceStatus? status,
  }) {
    return MockStudent(
      id: id ?? this.id,
      name: name ?? this.name,
      fatherName: fatherName ?? this.fatherName,
      rollNo: rollNo ?? this.rollNo,
      darjaName: darjaName ?? this.darjaName,
      className: className ?? this.className,
      photoUrl: photoUrl ?? this.photoUrl,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    return 'MockStudent(id: $id, name: $name, rollNo: $rollNo, status: $status)';
  }
}
