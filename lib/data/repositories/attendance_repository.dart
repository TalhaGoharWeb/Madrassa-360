/// حاضری ریپوزیٹری
/// Attendance Repository — LOCAL-FIRST (Phase 5 offline-first sync).
///
/// Reads come from the local Drift envelope tables (`students` ⨝
/// `attendance_records`); writes go to Drift + a `sync_queue` row in the
/// SAME transaction, then opportunistically trigger [SyncEngine.syncNow].
/// Direct Supabase writes are FORBIDDEN in this repository — the sync engine
/// is the only writer to the server (via the `sync_apply` RPC).
///
/// Local schema (sibling contract, `016_create_core_schema.sql`):
/// envelope columns `id, tenant_id, student_id, class_id, date, status,
/// revision, server_revision, updated_at, deleted_at, data` — the `data`
/// JSON is authoritative; indexed columns are query hints. `teacher_id`
/// and `note` live ONLY in `data`/payloads (and on the server).
///
/// Remote reads kept: NONE. The realtime stream is now event-driven:
/// an initial local read, then a re-read after every engine event
/// (local write, push/pull completion). No Supabase realtime dependency.
///
/// Status round-trip: `status.name` (present/absent/leave/late) is stored
/// verbatim in Drift and in the `sync_queue`/`sync_apply` payloads, and
/// parsed back by [_parseStatus] — including `'late'` (Phase 5), which the
/// legacy parsers used to collapse to `present`.
///
/// Public method signatures are IDENTICAL to the previous Supabase
/// implementation (a sibling worker's attendance screen codes against them).

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart' hide SyncQueue;
import '../../core/sync/sync_engine.dart';
import '../../core/services/supabase_service.dart';
import '../models/attendance_record.dart';
import '../models/attendance_status.dart';

// ─────────────────────────────────────────────
// Interface (unchanged)
// ─────────────────────────────────────────────

abstract class IAttendanceRepository {
  /// Fetch all attendance records for a class on a given date.
  Future<List<AttendanceRecord>> getClassAttendance({
    required String classId,
    required DateTime date,
    required String tenantId,
  });

  /// Upsert attendance records (insert or update on student_id+date conflict).
  /// Records carry their own tenant_id (see [AttendanceRecord.toUpsertJson]).
  Future<void> saveAttendance(List<AttendanceRecord> records);

  /// Stream of attendance changes for a class+date (local-first: re-reads
  /// the local DB after every sync-engine event).
  Stream<List<AttendanceRecord>> subscribeToAttendance({
    required String classId,
    required DateTime date,
    required String tenantId,
  });
}

// ─────────────────────────────────────────────
// Local-first implementation
// ─────────────────────────────────────────────

class LocalAttendanceRepository implements IAttendanceRepository {
  LocalAttendanceRepository(this._db, this._engine);

  final AppDatabase _db;

  /// Null when logged out / no active tenant — writes still enqueue
  /// locally and sync later; the opportunistic trigger is skipped.
  final SyncEngine? _engine;

  static const _uuid = Uuid();

  String get _currentUserId => SupabaseService.currentUser?.id ?? '';
  String _dateStr(DateTime d) => d.toIso8601String().substring(0, 10);

  static AttendanceStatus _parseStatus(String s) {
    switch (s) {
      case 'absent':
        return AttendanceStatus.absent;
      case 'leave':
        return AttendanceStatus.leave;
      case 'late':
        return AttendanceStatus.late;
      default:
        return AttendanceStatus.present;
    }
  }

  AttendanceRecord _fromRow(Map<String, dynamic> r, String classId,
      String teacherId, String dateStr) {
    // `_data` is the decoded attendance_records.data JSON (server-shaped
    // for pulled rows, model-shaped for locally written rows).
    final d = (r['_data'] as Map<String, dynamic>?) ?? const {};
    return AttendanceRecord(
      id: r['aid'] as String?,
      tenantId: (d['tenant_id'] ?? r['tenant_id'] ?? '') as String,
      studentId: (r['sid'] ?? '') as String,
      studentName: (r['name'] ?? '') as String,
      studentRollNo: (r['roll_no'] ?? '') as String,
      studentPhotoUrl: r['photo_url'] as String?,
      classId: classId,
      teacherId: (d['teacher_id'] as String?) ?? teacherId,
      date: dateStr,
      status: _parseStatus((d['status'] ?? 'present') as String),
      note: d['note'] as String?,
    );
  }

  // ── Queries (local) ─────────────────────────────────────────

  @override
  Future<List<AttendanceRecord>> getClassAttendance({
    required String classId,
    required DateTime date,
    required String tenantId,
  }) async {
    final dateStr = _dateStr(date);
    final teacherId = _currentUserId;
    // `photo_url` is not an indexed column — read it from the student
    // envelope's data JSON. `is_active` likewise lives in data (SQLite's
    // json_extract maps JSON true → 1).
    final rows = await LocalRows.query(
      _db,
      'SELECT a.id AS aid, a.data AS data, '
      's.id AS sid, s.tenant_id, s.name, s.roll_no, '
      "json_extract(s.data, '\$.photo_url') AS photo_url "
      'FROM students s LEFT JOIN attendance_records a '
      'ON a.student_id = s.id AND a.date = ? AND a.tenant_id = s.tenant_id '
      'AND a.deleted_at IS NULL '
      'WHERE s.tenant_id = ? AND s.class_id = ? '
      'AND s.deleted_at IS NULL '
      "AND (json_extract(s.data, '\$.is_active') IS NULL "
      "OR json_extract(s.data, '\$.is_active') = 1) "
      'ORDER BY s.roll_no',
      [
        Variable.withString(dateStr),
        Variable.withString(tenantId),
        Variable.withString(classId),
      ],
    );
    return rows.map((r) => _fromRow(r, classId, teacherId, dateStr)).toList();
  }

  @override
  Future<void> saveAttendance(List<AttendanceRecord> records) async {
    if (records.isEmpty) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await _db.transaction(() async {
      for (final r in records) {
        final id = r.id ?? _uuid.v4();
        final exists = await SyncQueue.rowExists(
            _db, 'attendance_records', r.tenantId, id);
        final baseRev = exists
            ? await SyncQueue.currentRevision(
                _db, 'attendance_records', r.tenantId, id)
            : 0;

        // Server-shaped payload: id + the model's upsert fields. Kept in
        // the envelope's data JSON AND queued for the RPC.
        final data = {
          ...r.toUpsertJson(),
          'id': id,
        };

        // Local write (indexed hints + data JSON; preserves
        // server_revision, refreshes updated_at as epoch millis).
        await SyncEngine.writeLocalRow(
          _db,
          table: 'attendance_records',
          id: id,
          tenantId: r.tenantId,
          indexed: {
            'student_id': r.studentId,
            'class_id': r.classId,
            'date': r.date,
            'status': r.status.name,
          },
          data: data,
        );

        // Enqueue in the SAME transaction (crash safety).
        await SyncQueue.enqueue(
          _db,
          tenantId: r.tenantId,
          entity: 'attendance',
          entityId: id,
          operation: exists ? 'update' : 'create',
          payload: {...data, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      }
    });

    // Opportunistic sync (no-op when offline or engine unavailable).
    _engine?.notifyLocalChange();
    unawaited(_engine?.syncNow() ?? Future.value());
  }

  @override
  Stream<List<AttendanceRecord>> subscribeToAttendance({
    required String classId,
    required DateTime date,
    required String tenantId,
  }) async* {
    yield await getClassAttendance(
        classId: classId, date: date, tenantId: tenantId);
    final engine = _engine;
    if (engine == null) return;
    await for (final _ in engine.events) {
      yield await getClassAttendance(
          classId: classId, date: date, tenantId: tenantId);
    }
  }
}
