/// طلباء پروائیڈر
/// Student Provider — repository-backed state management

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../data/models/student.dart';
import '../data/repositories/student_repository.dart';
import '../data/repositories/storage_repository.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/sync_providers.dart';
import '../core/services/tenant_context.dart';

// ─────────────────────────────────────────────
// Repository Provider
// ─────────────────────────────────────────────

final studentRepositoryProvider = Provider<IStudentRepository>((ref) {
  return LocalStudentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncEngineProvider),
  );
});

// ─────────────────────────────────────────────
// All Students
// ─────────────────────────────────────────────

final allStudentsProvider = FutureProvider<List<Student>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Student>[];
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getAllStudents(tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Students by Class (family provider keyed by classId)
// ─────────────────────────────────────────────

final studentsByClassProvider =
    FutureProvider.family<List<Student>, String>((ref, classId) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Student>[];
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getStudentsByClass(classId, tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Students by Darja (family provider keyed by darjaId)
// ─────────────────────────────────────────────

final studentsByDarjaProvider =
    FutureProvider.family<List<Student>, String>((ref, darjaId) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Student>[];
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getStudentsByDarja(darjaId, tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Single Student (family provider keyed by studentId)
// ─────────────────────────────────────────────

final studentByIdProvider =
    FutureProvider.family<Student?, String>((ref, studentId) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return null;
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getStudentById(studentId, tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Student Mutations Notifier
// ─────────────────────────────────────────────

class StudentNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<Student> save(Student student) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) throw StateError('No active tenant');
    final repo = ref.read(studentRepositoryProvider);
    final saved = await repo.upsertStudent(student, tenantId: tenantId);
    // Invalidate relevant caches
    ref.invalidate(allStudentsProvider);
    ref.invalidate(studentsByClassProvider(student.classId));
    ref.invalidate(studentsByDarjaProvider(student.darjaId));
    return saved;
  }

  Future<void> delete(String studentId) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) throw StateError('No active tenant');
    final repo = ref.read(studentRepositoryProvider);
    final student = await repo.getStudentById(studentId, tenantId: tenantId);
    await repo.deleteStudent(studentId, tenantId: tenantId);
    ref.invalidate(allStudentsProvider);
    if (student != null) {
      ref.invalidate(studentsByClassProvider(student.classId));
      ref.invalidate(studentsByDarjaProvider(student.darjaId));
    }
  }

  /// Stage a profile photo for upload and point the student record at its
  /// future public URL (offline-first): the bytes are staged locally and
  /// queued in `pending_uploads`; the local 'students' row is updated via
  /// writeLocalRow + a queued 'update' whose payload carries
  /// '_pending_upload_id', so the engine uploads the bytes BEFORE pushing
  /// the row. Returns the (future) public URL.
  Future<String?> uploadPhoto(String studentId, XFile photo) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) return null;
    try {
      final ext = photo.name.split('.').last.toLowerCase();
      const bucket = 'student-photos';
      // Tenant-prefixed destination aligns with the {tenant_id}/ storage
      // policy (the old path lacked the tenant prefix).
      final destPath = '$tenantId/students/$studentId.$ext';
      final File staged = await PendingUploadQueue.stageFile(
          tenantId, photo, '$studentId.$ext');
      final db = ref.read(appDatabaseProvider);
      final uploadId = await PendingUploadQueue.enqueueUpload(
        db,
        tenantId: tenantId,
        stagedFile: staged,
        bucket: bucket,
        destPath: destPath,
      );
      final url = PendingUploadQueue.publicUrl(bucket, destPath);
      final engine = ref.read(syncEngineProvider);
      final row = await LocalRows.byId(db, 'students', tenantId, studentId);
      if (row == null) return null;
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final data = <String, dynamic>{
        ...(row['_data'] as Map<String, dynamic>),
        'photo_url': url,
      };
      final baseRev =
          await SyncQueue.currentRevision(db, 'students', tenantId, studentId);
      await db.transaction(() async {
        await SyncEngine.writeLocalRow(
          db,
          table: 'students',
          id: studentId,
          tenantId: tenantId,
          indexed: {
            'name': row['name'],
            'roll_no': row['roll_no'],
            'class_id': row['class_id'],
          },
          data: data,
        );
        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'students',
          entityId: studentId,
          operation: 'update',
          payload: {
            ...data,
            'id': studentId,
            'tenant_id': tenantId,
            'updated_at': nowIso,
            '_pending_upload_id': uploadId,
          },
          baseRevision: baseRev,
        );
      });
      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());
      ref.invalidate(allStudentsProvider);
      return url;
    } catch (_) {
      return null;
    }
  }
}

final studentNotifierProvider =
    AsyncNotifierProvider<StudentNotifier, void>(StudentNotifier.new);
