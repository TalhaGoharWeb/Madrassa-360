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

  /// Which of [classIds] have at least one (non-deleted) attendance record
  /// for [date] — single query. Powers the teacher's "attendance done"
  /// dashboard card without one full fetch per class.
  Future<Set<String>> getMarkedClassIds({
    required List<String> classIds,
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
  Future<Set<String>> getMarkedClassIds({
    required List<String> classIds,
    required DateTime date,
    required String tenantId,
  }) async {
    if (classIds.isEmpty) return const {};
    final dateStr = _dateStr(date);
    // One query for all classes: distinct class_ids with any record that
    // day. Placeholders are bound positionally — never interpolated.
    final placeholders = List.filled(classIds.length, '?').join(', ');
    final rows = await LocalRows.query(
      _db,
      'SELECT DISTINCT class_id AS class_id FROM attendance_records '
      'WHERE tenant_id = ? AND date = ? AND deleted_at IS NULL '
      'AND class_id IN ($placeholders)',
      [
        Variable.withString(tenantId),
        Variable.withString(dateStr),
        for (final id in classIds) Variable.withString(id),
      ],
    );
    return {
      for (final r in rows)
        if (r['class_id'] is String) r['class_id'] as String,
    };
  }

  @override
  Future<void> saveAttendance(List<AttendanceRecord> records) async {
    if (records.isEmpty) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // Stable ids first — same rule as before (reuse or generate).
    final ids = <String>[for (final r in records) r.id ?? _uuid.v4()];

    // ONE pre-fetch for the whole batch: existence + local/server revisions.
    // Replaces per-row rowExists + currentRevision + _localRevisionOf
    // (~3 selects per student → 1 total).
    final prev = await _existingRevisions(ids);

    await _db.transaction(() async {
      final envelopes = <EnvelopeWrite>[];
      final queueRows = <QueueWrite>[];
      for (var i = 0; i < records.length; i++) {
        final r = records[i];
        final id = ids[i];
        final p = prev[id];
        // Tenant-scoped existence, mirroring SyncQueue.rowExists.
        final exists = p != null && p.tenantId == r.tenantId;
        final baseRev = exists ? p.serverRevision : 0;

        // Server-shaped payload: id + the model's upsert fields. Kept in
        // the envelope's data JSON AND queued for the RPC.
        final data = {
          ...r.toUpsertJson(),
          'id': id,
        };

        // Local write spec (indexed hints + data JSON; preserves
        // server_revision, refreshes updated_at as epoch millis).
        // localRevision mirrors _localRevisionOf: (revision ?? 0) + 1.
        envelopes.add(EnvelopeWrite(
          id: id,
          tenantId: r.tenantId,
          indexed: {
            'student_id': r.studentId,
            'class_id': r.classId,
            'date': r.date,
            'status': r.status.name,
          },
          data: data,
          localRevision: (exists ? p.revision : 0) + 1,
        ));

        // Enqueue in the SAME transaction (crash safety).
        queueRows.add(QueueWrite(
          tenantId: r.tenantId,
          entity: 'attendance',
          entityId: id,
          operation: exists ? 'update' : 'create',
          payload: {...data, 'updated_at': nowIso},
          baseRevision: baseRev,
        ));
      }
      // Two batched statements for the whole class (was ~2 per student).
      await SyncEngine.writeLocalRows(
        _db,
        table: 'attendance_records',
        rows: envelopes,
      );
      await SyncQueue.enqueueAll(_db, queueRows);
    });

    // Opportunistic sync (no-op when offline or engine unavailable).
    _engine?.notifyLocalChange();
    unawaited(_engine?.syncNow() ?? Future.value());
  }

  /// Batch pre-fetch of local envelope state for [ids]: id → tenant,
  /// local revision, and last-known server revision. One query total.
  Future<Map<String, ({String tenantId, int revision, int serverRevision})>>
      _existingRevisions(List<String> ids) async {
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await LocalRows.query(
      _db,
      'SELECT id, tenant_id, revision, server_revision FROM attendance_records '
      'WHERE id IN ($placeholders)',
      [for (final id in ids) Variable.withString(id)],
    );
    return {
      for (final r in rows)
        (r['id'] as String): (
          tenantId: (r['tenant_id'] as String?) ?? '',
          revision: (r['revision'] as num?)?.toInt() ?? 0,
          serverRevision: (r['server_revision'] as num?)?.toInt() ?? 0,
        ),
    };
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
