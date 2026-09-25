/// حاضری ریکارڈ ماڈل (Supabase)
/// Attendance record — one row per student per day in public.attendance

import 'attendance_status.dart';

/// A single student's attendance record for one date.
/// Used by [AttendanceRepository] and the updated attendance screen.
class AttendanceRecord {
  final String? id;           // null for unsaved (optimistic) records
  final String tenantId;      // multi-tenant owner (public.tenants) — required
  final String studentId;
  final String studentName;
  final String studentRollNo;
  final String? studentPhotoUrl;
  final String classId;
  final String teacherId;
  final String date;          // ISO 'YYYY-MM-DD'
  final AttendanceStatus status;
  final String? note;

  const AttendanceRecord({
    this.id,
    required this.tenantId,
    required this.studentId,
    required this.studentName,
    required this.studentRollNo,
    this.studentPhotoUrl,
    required this.classId,
    required this.teacherId,
    required this.date,
    this.status = AttendanceStatus.present,
    this.note,
  });

  factory AttendanceRecord.fromStudentRow(Map<String, dynamic> json, String classId, String teacherId, String date) {
    // Response shape when fetching students + embedded attendance:
    // { id, name, roll_no, photo_url, attendance: [ { status, note } ] }
    final List<dynamic> att = json['attendance'] as List<dynamic>? ?? [];
    final Map<String, dynamic>? todayAtt =
        att.isNotEmpty ? att.first as Map<String, dynamic> : null;

    final statusStr = todayAtt?['status'] as String? ?? 'present';
    return AttendanceRecord(
      id:               todayAtt?['id'] as String?,
      tenantId:         (json['tenant_id'] ?? json['madrasa_id'] ?? '') as String,
      studentId:        json['id'] as String,
      studentName:      json['name'] as String,
      studentRollNo:    json['roll_no'] as String,
      studentPhotoUrl:  json['photo_url'] as String?,
      classId:          classId,
      teacherId:        teacherId,
      date:             date,
      status:           _parseStatus(statusStr),
      note:             todayAtt?['note'] as String?,
    );
  }

  /// Parse DB string to enum.
  static AttendanceStatus _parseStatus(String s) {
    switch (s) {
      case 'absent': return AttendanceStatus.absent;
      case 'leave':  return AttendanceStatus.leave;
      default:       return AttendanceStatus.present;
    }
  }

  /// Serialise for upsert into public.attendance.
  Map<String, dynamic> toUpsertJson() => {
    'tenant_id':  tenantId,
    'student_id': studentId,
    'class_id':   classId,
    'teacher_id': teacherId,
    'date':       date,
    'status':     status.name, // 'present' | 'absent' | 'leave'
    'note':       note,
  };

  AttendanceRecord copyWith({AttendanceStatus? status, String? note}) {
    return AttendanceRecord(
      id:              id,
      tenantId:        tenantId,
      studentId:       studentId,
      studentName:     studentName,
      studentRollNo:   studentRollNo,
      studentPhotoUrl: studentPhotoUrl,
      classId:         classId,
      teacherId:       teacherId,
      date:            date,
      status:          status ?? this.status,
      note:            note ?? this.note,
    );
  }

  /// Initials for avatar fallback.
  String get initials {
    final words = studentName.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) return '${words[0][0]}${words[1][0]}';
    return studentName.isNotEmpty ? studentName[0] : '?';
  }
}
