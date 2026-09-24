/// آف لائن سنک سروس
/// Offline Sync Service — queues attendance saves locally when offline
/// and replays them when connectivity is restored.
///
/// Usage:
///   await OfflineSyncService.init();
///   await OfflineSyncService.queueAttendance(records);
///   // Replays automatically on connectivity change; or manually:
///   await OfflineSyncService.flushAttendance(repository);

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/models/attendance_status.dart';
import '../../../data/repositories/attendance_repository.dart';
import 'storage_service.dart';

class OfflineSyncService {
  static const String _pendingAttendanceKey = 'pending_attendance_queue';

  static StreamSubscription<ConnectivityResult>? _sub;
  static IAttendanceRepository? _attendanceRepo;

  /// Call once from main.dart after SupabaseService.init().
  static void init({IAttendanceRepository? attendanceRepository}) {
    _attendanceRepo = attendanceRepository;
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen(
      (result) async {
        final online = result != ConnectivityResult.none;
        if (online && _attendanceRepo != null) {
          await flushAttendance(_attendanceRepo!);
        }
      },
    );
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  // ─────────────────────────────────────────────
  // Attendance queue
  // ─────────────────────────────────────────────

  /// Append a batch of records to the local pending queue.
  static Future<void> queueAttendance(List<AttendanceRecord> records) async {
    final existing = await _loadQueue();
    existing.addAll(records.map(_recordToMap));
    await _saveQueue(existing);
  }

  /// Attempt to push all queued records to Supabase.
  /// On success the queue is cleared; on failure it's left intact.
  static Future<void> flushAttendance(IAttendanceRepository repo) async {
    final queue = await _loadQueue();
    if (queue.isEmpty) return;

    try {
      final records = queue
          .map(_mapToRecord)
          .whereType<AttendanceRecord>()
          .toList();
      await repo.saveAttendance(records);
      await _clearQueue(); // Only clear on success
    } catch (_) {
      // Remain queued; will retry on next connectivity event
    }
  }

  /// Number of records waiting to be synced.
  static Future<int> pendingCount() async {
    final q = await _loadQueue();
    return q.length;
  }

  // ─────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────

  static Map<String, dynamic> _recordToMap(AttendanceRecord r) => {
    'id':              r.id,
    'student_id':      r.studentId,
    'student_name':    r.studentName,
    'student_roll_no': r.studentRollNo,
    'class_id':        r.classId,
    'teacher_id':      r.teacherId,
    'date':            r.date,
    'status':          r.status.name,
    'note':            r.note,
  };

  static AttendanceRecord? _mapToRecord(Map<String, dynamic> m) {
    try {
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
    } catch (_) {
      return null;
    }
  }

  static AttendanceStatus _parseStatus(String s) {
    switch (s) {
      case 'absent': return AttendanceStatus.absent;
      case 'leave':  return AttendanceStatus.leave;
      default:       return AttendanceStatus.present;
    }
  }

  static Future<List<Map<String, dynamic>>> _loadQueue() async {
    final raw = StorageService.getString(_pendingAttendanceKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => e as Map<String, dynamic>),
      );
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveQueue(List<Map<String, dynamic>> queue) async {
    await StorageService.saveString(_pendingAttendanceKey, jsonEncode(queue));
  }

  static Future<void> _clearQueue() async {
    await StorageService.saveString(_pendingAttendanceKey, '[]');
  }
}
