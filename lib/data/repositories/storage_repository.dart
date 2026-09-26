/// اسٹوریج ریپوزیٹری
/// PendingUploadQueue — Phase 5 offline-first storage uploads.
///
/// DESIGN: the app NEVER writes file bytes to Supabase Storage directly
/// from the UI thread. Instead a photo (or any upload) flows through
/// three decoupled steps:
///
///   1. [stageFile] — copy the picked file into app-private storage
///      (`<appSupport>/Madrassa360/uploads/<tenantId>/<fileName>`).
///   2. [enqueueUpload] / [enqueueDelete] — insert a row in the local
///      `pending_uploads` table (`op`: 'upload'/'delete', `status`:
///      'pending'). Returns the upload id.
///   3. The DB row that references the file carries the FUTURE public URL
///      (see [publicUrl]) plus a `_pending_upload_id` hint in its queued
///      payload. The sync engine performs the actual byte upload first and
///      only then pushes any queue row whose payload carries that
///      `_pending_upload_id`.
///
/// ORDERING RULE (why the hold exists): the file bytes stay on local
/// disk, but the DB row references the public URL — which is only valid
/// AFTER the bytes reach the bucket. Pushing the row first would publish
/// a dead URL (or, on the server, violate NOT NULL photo constraints).
/// Holding the row behind the upload guarantees URL validity when the
/// row lands. The `pending_uploads` row is the engine's unit of retry:
/// byte upload → flip to 'done' → release dependent queue rows.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart';
import '../../core/services/supabase_service.dart';

class PendingUploadQueue {
  PendingUploadQueue._();

  /// Copy [photo] into app-private staging:
  /// `<appSupport>/Madrassa360/uploads/<tenantId>/<fileName>`
  /// (directories created as needed). Returns the staged [File].
  static Future<File> stageFile(
      String tenantId, XFile photo, String fileName) async {
    final supportDir = await getApplicationSupportDirectory();
    final dir =
        Directory(p.join(supportDir.path, 'Madrassa360', 'uploads', tenantId));
    await dir.create(recursive: true);
    final staged = File(p.join(dir.path, fileName));
    return File(photo.path).copy(staged.path);
  }

  /// Insert an upload job into `pending_uploads` (status 'pending') and
  /// return the upload id. Callers stamp this id as `_pending_upload_id`
  /// in the queued payload of the DB row that will reference the file's
  /// public URL, so the engine uploads the bytes BEFORE pushing that row.
  static Future<String> enqueueUpload(
    AppDatabase db, {
    required String tenantId,
    required File stagedFile,
    required String bucket,
    required String destPath,
  }) async {
    final id = const Uuid().v4();
    await db.customInsert(
      'INSERT INTO pending_uploads '
      '(id, tenant_id, local_path, bucket, dest_path, op, status, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable.withString(id),
        Variable.withString(tenantId),
        Variable.withString(stagedFile.path),
        Variable.withString(bucket),
        Variable.withString(destPath),
        Variable.withString('upload'),
        Variable.withString('pending'),
        Variable.withInt(DateTime.now().millisecondsSinceEpoch),
      ],
    );
    return id;
  }

  /// Insert a storage-delete job into `pending_uploads` (status 'pending').
  static Future<void> enqueueDelete(
    AppDatabase db, {
    required String tenantId,
    required String bucket,
    required String destPath,
  }) async {
    await db.customInsert(
      'INSERT INTO pending_uploads '
      '(id, tenant_id, local_path, bucket, dest_path, op, status, created_at) '
      'VALUES (?, ?, NULL, ?, ?, ?, ?, ?)',
      variables: [
        Variable.withString(const Uuid().v4()),
        Variable.withString(tenantId),
        Variable.withString(bucket),
        Variable.withString(destPath),
        Variable.withString('delete'),
        Variable.withString('pending'),
        Variable.withInt(DateTime.now().millisecondsSinceEpoch),
      ],
    );
  }

  /// The future public URL of a file at [destPath] in [bucket]. Pure local
  /// computation — no network. Only valid once the upload completes; that
  /// is exactly why DB rows carrying this URL are held behind the upload
  /// (see the ORDERING RULE above).
  static String publicUrl(String bucket, String destPath) =>
      SupabaseService.client.storage.from(bucket).getPublicUrl(destPath);
}
