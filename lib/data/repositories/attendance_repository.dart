/// حاضری ریپوزیٹری
/// Attendance Repository — abstract interface + Mock + Supabase implementations

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attendance_record.dart';
import '../models/attendance_status.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/storage_service.dart';

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

abstract class IAttendanceRepository {
  /// Fetch all attendance records for a class on a given date.
  Future<List<AttendanceRecord>> getClassAttendance({
    required String classId,
    required DateTime date,
  });

  /// Upsert attendance records (insert or update on student_id+date conflict).
  Future<void> saveAttendance(List<AttendanceRecord> records);

  /// Realtime stream of attendance changes for a class+date.
  Stream<List<AttendanceRecord>> subscribeToAttendance({
    required String classId,
    required DateTime date,
  });
}

// ─────────────────────────────────────────────
// Supabase Implementation
// ─────────────────────────────────────────────

class SupabaseAttendanceRepository implements IAttendanceRepository {
  SupabaseClient get _client => SupabaseService.client;

  String get _currentUserId => SupabaseService.currentUser?.id ?? '';
  String _dateStr(DateTime d) => d.toIso8601String().substring(0, 10);

  // ── Cache helpers ───────────────────────────────────────────
  static String _cacheKey(String classId, String dateStr) =>
      'cache_attendance_${classId}_$dateStr';

  static List<AttendanceRecord> _decodeCache(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((e) {
        final m = e as Map<String, dynamic>;
        return AttendanceRecord(
          id:              m['id'] as String?,
          studentId:       m['student_id'] as String,
          studentName:     m['student_name'] as String,
          studentRollNo:   m['student_roll_no'] as String,
          classId:         m['class_id'] as String,
          teacherId:       m['teacher_id'] as String,
          date:            m['date'] as String,
          status:          _parseStatus(m['status'] as String? ?? 'present'),
          note:            m['note'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static AttendanceStatus _parseStatus(String s) {
    switch (s) {
      case 'absent': return AttendanceStatus.absent;
      case 'leave':  return AttendanceStatus.leave;
      default:       return AttendanceStatus.present;
    }
  }

  static Future<void> _writeCache(
      String classId, String dateStr, List<AttendanceRecord> records) async {
    final key = _cacheKey(classId, dateStr);
    final encoded = records.map((r) => {
      'id': r.id,
      'student_id': r.studentId,
      'student_name': r.studentName,
      'student_roll_no': r.studentRollNo,
      'class_id': r.classId,
      'teacher_id': r.teacherId,
      'date': r.date,
      'status': r.status.name,
      'note': r.note,
    }).toList();
    await StorageService.saveString(key, jsonEncode(encoded));
  }

  // ── Queries ─────────────────────────────────────────────────

  @override
  Future<List<AttendanceRecord>> getClassAttendance({
    required String classId,
    required DateTime date,
  }) async {
    final dateStr = _dateStr(date);
    final teacherId = _currentUserId;
    try {
      final response = await _client
          .from('students')
          .select('id, name, roll_no, photo_url, attendance!left(id, status, note)')
          .eq('class_id', classId)
          .eq('is_active', true)
          .eq('attendance.date', dateStr)
          .order('roll_no');
      final records = (response as List).map((row) {
        return AttendanceRecord.fromStudentRow(
          row as Map<String, dynamic>,
          classId,
          teacherId,
          dateStr,
        );
      }).toList();
      await _writeCache(classId, dateStr, records);
      return records;
    } catch (_) {
      final cached = _decodeCache(
          StorageService.getString(_cacheKey(classId, dateStr)));
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  @override
  Future<void> saveAttendance(List<AttendanceRecord> records) async {
    if (records.isEmpty) return;
    final rows = records.map((r) => r.toUpsertJson()).toList();
    await _client.from('attendance').upsert(
          rows,
          onConflict: 'student_id,date',
        );
    // Refresh cache after successful save
    if (records.isNotEmpty) {
      final classId = records.first.classId;
      final dateStr = records.first.date;
      final date = DateTime.tryParse(dateStr);
      if (date != null) await _writeCache(classId, dateStr, records);
    }
  }

  @override
  Stream<List<AttendanceRecord>> subscribeToAttendance({
    required String classId,
    required DateTime date,
  }) {
    final dateStr = _dateStr(date);
    // Stream realtime changes then re-fetch full list on each event
    return _client
        .from('attendance')
        .stream(primaryKey: ['id'])
        .eq('date', dateStr)
        .asyncMap((_) => getClassAttendance(classId: classId, date: date));
  }
}
