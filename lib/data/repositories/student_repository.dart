/// طلباء ریپوزیٹری
/// Student Repository — LOCAL-FIRST (Phase 5 offline-first sync).
///
/// Reads come from the local Drift envelope tables (`students` with
/// `classes`/`darjas` name joins); writes go to Drift + a `sync_queue` row
/// in the SAME transaction, then opportunistically trigger
/// [SyncEngine.syncNow]. Direct Supabase writes are FORBIDDEN in this
/// repository — the sync engine is the only writer to the server (via the
/// `sync_apply` RPC).
///
/// Local schema (sibling contract, `016_create_core_schema.sql`):
/// `students(id, tenant_id, name, roll_no, class_id, revision,
/// server_revision, updated_at, deleted_at, data)` — the `data` JSON is
/// authoritative; `darja_id`, `father_name`, `is_active`, `photo_url`, etc.
/// live ONLY in `data`/payloads (and on the server). Darja is reached via
/// the class (`classes.darja_id`) — the normalized model the envelope
/// schema implies.
///
/// Remote reads kept: NONE. (The old SharedPreferences JSON cache is gone —
/// Drift is the cache now.)
///
/// Public method signatures are IDENTICAL to the previous Supabase
/// implementation.

import 'dart:async';

import 'package:drift/drift.dart';

import '../../data/local/app_database.dart';
import '../../core/sync/sync_engine.dart';
import '../models/student.dart';

// ─────────────────────────────────────────────
// Interface (unchanged)
// ─────────────────────────────────────────────

abstract class IStudentRepository {
  Future<List<Student>> getAllStudents({required String tenantId});
  Future<List<Student>> getStudentsByClass(String classId,
      {required String tenantId});
  Future<List<Student>> getStudentsByDarja(String darjaId,
      {required String tenantId});
  Future<Student?> getStudentById(String id, {required String tenantId});
  Future<Student> upsertStudent(Student student, {required String tenantId});
  Future<void> deleteStudent(String id, {required String tenantId});
}

// ─────────────────────────────────────────────
// Local-first implementation
// ─────────────────────────────────────────────

class LocalStudentRepository implements IStudentRepository {
  LocalStudentRepository(this._db, this._engine);

  final AppDatabase _db;

  /// Null when logged out / no active tenant — writes still enqueue
  /// locally and sync later; the opportunistic trigger is skipped.
  final SyncEngine? _engine;

  /// Shape an envelope row into what [Student.fromJson] expects:
  /// the decoded `data` JSON (flat, server-shaped) plus nested
  /// `darjas`/`classes` join maps for the names.
  Student _fromRow(Map<String, dynamic> r) {
    final data =
        (r['_data'] as Map<String, dynamic>?) ?? const {};
    return Student.fromJson({
      ...data,
      'darjas': {'name': r['darja_name']},
      'classes': {'name': r['class_name']},
    });
  }

  // Darja is reached through the class (normalized): s → c → d.
  static const _select = 's.data AS data, d.name AS darja_name, '
      'c.name AS class_name '
      'FROM students s '
      'LEFT JOIN classes c ON c.id = s.class_id '
      'AND c.tenant_id = s.tenant_id AND c.deleted_at IS NULL '
      'LEFT JOIN darjas d ON d.id = c.darja_id '
      'AND d.tenant_id = c.tenant_id AND d.deleted_at IS NULL ';

  // `is_active` lives in the data JSON (SQLite json_extract maps JSON
  // true → 1, covering both bool and int encodings).
  static const _liveFilter = "s.deleted_at IS NULL "
      "AND (json_extract(s.data, '\$.is_active') IS NULL "
      "OR json_extract(s.data, '\$.is_active') = 1) ";

  Future<List<Student>> _queryList(String where, List<Variable> vars) async {
    final rows = await LocalRows.query(
      _db,
      'SELECT $_select WHERE $where ORDER BY s.roll_no',
      vars,
    );
    return rows.map(_fromRow).toList();
  }

  // ── Queries (local) ─────────────────────────────────────────

  @override
  Future<List<Student>> getAllStudents({required String tenantId}) =>
      _queryList(
        's.tenant_id = ? AND $_liveFilter',
        [Variable.withString(tenantId)],
      );

  @override
  Future<List<Student>> getStudentsByClass(String classId,
          {required String tenantId}) =>
      _queryList(
        's.tenant_id = ? AND s.class_id = ? AND $_liveFilter',
        [Variable.withString(tenantId), Variable.withString(classId)],
      );

  @override
  Future<List<Student>> getStudentsByDarja(String darjaId,
          {required String tenantId}) =>
      _queryList(
        's.tenant_id = ? AND s.class_id IN ('
        'SELECT id FROM classes WHERE tenant_id = ? AND darja_id = ? '
        'AND deleted_at IS NULL) AND $_liveFilter',
        [
          Variable.withString(tenantId),
          Variable.withString(tenantId),
          Variable.withString(darjaId),
        ],
      );

  @override
  Future<Student?> getStudentById(String id,
      {required String tenantId}) async {
    final rows = await LocalRows.query(
      _db,
      'SELECT $_select WHERE s.tenant_id = ? AND s.id = ? '
      'AND s.deleted_at IS NULL LIMIT 1',
      [Variable.withString(tenantId), Variable.withString(id)],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  // ── Writes (local + queue, same transaction) ─────────────────

  @override
  Future<Student> upsertStudent(Student student,
      {required String tenantId}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final exists = await SyncQueue.rowExists(
        _db, 'students', tenantId, student.id);
    final baseRev = exists
        ? await SyncQueue.currentRevision(
            _db, 'students', tenantId, student.id)
        : 0;

    // Server-shaped payload kept in the envelope's data JSON and queued.
    final data = {
      ...student.toJson(),
      'id': student.id,
      'tenant_id': tenantId,
    };

    await _db.transaction(() async {
      await SyncEngine.writeLocalRow(
        _db,
        table: 'students',
        id: student.id,
        tenantId: tenantId,
        indexed: {
          'name': student.name,
          'roll_no': student.rollNo,
          'class_id': student.classId,
        },
        data: data,
      );

      await SyncQueue.enqueue(
        _db,
        tenantId: tenantId,
        entity: 'students',
        entityId: student.id,
        operation: exists ? 'update' : 'create',
        payload: {...data, 'updated_at': nowIso},
        baseRevision: baseRev,
      );
    });

    _engine?.notifyLocalChange();
    unawaited(_engine?.syncNow() ?? Future.value());
    return student;
  }

  @override
  Future<void> deleteStudent(String id, {required String tenantId}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final baseRev =
        await SyncQueue.currentRevision(_db, 'students', tenantId, id);

    await _db.transaction(() async {
      // Soft delete locally: sets deleted_at (epoch millis), refreshes
      // updated_at, bumps revision, and patches the data JSON so the row
      // still reads as inactive until the push completes.
      await SyncEngine.softDeleteLocalRow(
        _db,
        table: 'students',
        id: id,
        tenantId: tenantId,
        dataPatch: {'is_active': false},
      );

      await SyncQueue.enqueue(
        _db,
        tenantId: tenantId,
        entity: 'students',
        entityId: id,
        operation: 'delete',
        payload: {'id': id, 'tenant_id': tenantId, 'updated_at': nowIso},
        baseRevision: baseRev,
      );
    });

    _engine?.notifyLocalChange();
    unawaited(_engine?.syncNow() ?? Future.value());
  }
}
