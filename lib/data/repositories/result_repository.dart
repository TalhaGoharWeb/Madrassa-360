/// نتائج ریپوزیٹری
/// Result Repository — LOCAL-FIRST (Phase 5 offline-first sync).
///
/// Reads come from the local Drift envelope tables (`exams`, `results` ⨝
/// `students`); writes go to Drift + a `sync_queue` row in the SAME
/// transaction, then opportunistically trigger [SyncEngine.syncNow].
/// Direct Supabase writes are FORBIDDEN in this repository — the sync engine
/// is the only writer to the server (via the `sync_apply` RPC).
///
/// Local schema (sibling contract, `016_create_core_schema.sql`):
/// `exams(id, tenant_id, name, class_id, revision, server_revision,
/// updated_at, deleted_at, data)` and `results(id, tenant_id, exam_id,
/// student_id, marks, revision, server_revision, updated_at, deleted_at,
/// data)`. `exam_date`/`total_marks`/`subject` live ONLY in `data`/payloads
/// (and on the server) — the `data` JSON is authoritative.
///
/// Remote reads kept: NONE.
///
/// Public method signatures are IDENTICAL to the previous Supabase
/// implementation.

import 'dart:async';

import 'package:drift/drift.dart';

import '../../data/local/app_database.dart' hide SyncQueue;
import '../../core/sync/sync_engine.dart';
import '../models/result.dart';

// ─────────────────────────────────────────────
// Interface (unchanged)
// ─────────────────────────────────────────────

abstract class IResultRepository {
  Future<List<Exam>> getExams({required String tenantId});
  Future<Exam?> getExamById(String id, {required String tenantId});
  Future<List<StudentResult>> getExamResults(String examId,
      {required String tenantId});
  Future<List<SubjectResult>> getStudentSubjectResults({
    required String studentId,
    required String examId,
    required String tenantId,
  });
  Future<SubjectResult> upsertResult(SubjectResult result,
      {required String tenantId});

  /// Creates a new exam header row (used by the step-by-step exam wizard).
  /// Local-first: writes the envelope + sync_queue row in one transaction.
  Future<Exam> createExam(Exam exam, {required String tenantId});
}

// ─────────────────────────────────────────────
// Local-first implementation
// ─────────────────────────────────────────────

class LocalResultRepository implements IResultRepository {
  LocalResultRepository(this._db, this._engine);

  final AppDatabase _db;

  /// Null when logged out / no active tenant — writes still enqueue
  /// locally and sync later; the opportunistic trigger is skipped.
  final SyncEngine? _engine;

  // ── Queries (local) ─────────────────────────────────────────

  @override
  Future<List<Exam>> getExams({required String tenantId}) async {
    // `exam_date` is not an indexed column — sort inside the data JSON.
    final rows = await LocalRows.query(
      _db,
      'SELECT data FROM exams WHERE tenant_id = ? AND deleted_at IS NULL '
      "ORDER BY json_extract(data, '\$.exam_date') DESC",
      [Variable.withString(tenantId)],
    );
    return rows
        .map((r) =>
            Exam.fromJson((r['_data'] as Map<String, dynamic>?) ?? const {}))
        .toList();
  }

  @override
  Future<Exam?> getExamById(String id, {required String tenantId}) async {
    final row = await LocalRows.byId(_db, 'exams', tenantId, id);
    if (row == null) return null;
    return Exam.fromJson((row['_data'] as Map<String, dynamic>?) ?? const {});
  }

  @override
  Future<List<StudentResult>> getExamResults(String examId,
      {required String tenantId}) async {
    final exam = await getExamById(examId, tenantId: tenantId);
    // Names come from the indexed envelope columns (fast); the marks
    // themselves from each result's data JSON.
    final rows = await LocalRows.query(
      _db,
      'SELECT r.data AS data, s.name AS student_name, c.name AS class_name '
      'FROM results r '
      'LEFT JOIN students s ON s.id = r.student_id '
      'AND s.tenant_id = r.tenant_id AND s.deleted_at IS NULL '
      'LEFT JOIN classes c ON c.id = s.class_id '
      'AND c.tenant_id = s.tenant_id AND c.deleted_at IS NULL '
      'WHERE r.tenant_id = ? AND r.exam_id = ? '
      'AND r.deleted_at IS NULL '
      'ORDER BY r.student_id',
      [Variable.withString(tenantId), Variable.withString(examId)],
    );

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final row in rows) {
      final payload = (row['_data'] as Map<String, dynamic>?) ?? const {};
      final sid = (payload['student_id'] ?? '') as String;
      grouped.putIfAbsent(sid, () => []).add({
        ...payload,
        'student_name': row['student_name'],
        'class_name': row['class_name'],
      });
    }

    return grouped.entries.map((entry) {
      final rows = entry.value;
      final first = rows.first;
      return StudentResult(
        examId: examId,
        examName: exam?.name ?? '',
        examDate: exam?.examDate ?? '',
        studentId: entry.key,
        studentName: (first['student_name'] ?? '') as String,
        className: (first['class_name'] ?? '') as String,
        subjects: rows.map((r) => SubjectResult.fromJson(r)).toList(),
      );
    }).toList();
  }

  @override
  Future<List<SubjectResult>> getStudentSubjectResults({
    required String studentId,
    required String examId,
    required String tenantId,
  }) async {
    final rows = await LocalRows.query(
      _db,
      'SELECT data FROM results WHERE tenant_id = ? AND student_id = ? '
      'AND exam_id = ? AND deleted_at IS NULL',
      [
        Variable.withString(tenantId),
        Variable.withString(studentId),
        Variable.withString(examId),
      ],
    );
    return rows
        .map((r) => SubjectResult.fromJson(
            (r['_data'] as Map<String, dynamic>?) ?? const {}))
        .toList();
  }

  // ── Writes (local + queue, same transaction) ─────────────────

  @override
  Future<SubjectResult> upsertResult(SubjectResult result,
      {required String tenantId}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final exists =
        await SyncQueue.rowExists(_db, 'results', tenantId, result.id);
    final baseRev = exists
        ? await SyncQueue.currentRevision(_db, 'results', tenantId, result.id)
        : 0;

    // Server-shaped payload kept in the envelope's data JSON and queued.
    final data = {
      ...result.toJson(),
      'id': result.id,
      'tenant_id': tenantId,
    };

    await _db.transaction(() async {
      await SyncEngine.writeLocalRow(
        _db,
        table: 'results',
        id: result.id,
        tenantId: tenantId,
        indexed: {
          'exam_id': result.examId,
          'student_id': result.studentId,
          'marks': result.marksObtained,
        },
        data: data,
      );

      await SyncQueue.enqueue(
        _db,
        tenantId: tenantId,
        entity: 'results',
        entityId: result.id,
        operation: exists ? 'update' : 'create',
        payload: {...data, 'updated_at': nowIso},
        baseRevision: baseRev,
      );
    });

    _engine?.notifyLocalChange();
    unawaited(_engine?.syncNow() ?? Future.value());
    return result;
  }

  // ── Exam creation (exam wizard, Phase 7b) ──────────────────────────

  @override
  Future<Exam> createExam(Exam exam, {required String tenantId}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // Server-shaped payload kept in the envelope's data JSON and queued.
    // exam_date / total_marks live in data (and on the server); the
    // envelope's indexed columns are name + class_id (see file header).
    final data = {
      ...exam.toJson(),
      'id': exam.id,
      'tenant_id': tenantId,
    };

    await _db.transaction(() async {
      await SyncEngine.writeLocalRow(
        _db,
        table: 'exams',
        id: exam.id,
        tenantId: tenantId,
        indexed: {
          'name': exam.name,
          'class_id': exam.classId,
        },
        data: data,
      );

      await SyncQueue.enqueue(
        _db,
        tenantId: tenantId,
        entity: 'exams',
        entityId: exam.id,
        operation: 'create',
        payload: {...data, 'updated_at': nowIso},
        baseRevision: 0,
      );
    });

    _engine?.notifyLocalChange();
    unawaited(_engine?.syncNow() ?? Future.value());
    return exam;
  }
}
