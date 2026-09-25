/// بیک اپ سروس — One-file offline tenant backup & restore.
///
/// USER REQUIREMENT (hard): every madrasa must be able to save its COMPLETE
/// data in ONE single file, and it must work OFFLINE (Pakistan has severe
/// internet problems). The local Drift DB is already a single SQLite file
/// per tenant — this service builds on that fact:
///
///   backup  = checkpoint WAL → file copy of `madrassa360.db` →
///             `_backup_manifest` table written INTO the copy →
///             one `.db` file the madrasa can keep on a USB stick.
///
/// The manifest (tenant_id, exported_at, app_version, schema_version,
/// per-table row counts, SHA-256 of the data) travels INSIDE the file, so
/// [verifyBackup] can validate a backup with zero connectivity and
/// [restoreBackup] can refuse a corrupt / foreign / wrong-schema file
/// before touching the live database.
///
/// OFFLINE-FIRST: create / verify / restore / list / delete need no
/// network at all. The optional cloud copy reuses the existing
/// `pending_uploads` machinery (see PendingUploadQueue) and is strictly
/// best-effort — the local file is the source of truth.
///
/// SAFETY RULES (enforced here, not just in the UI):
///   1. `restoreBackup` throws unless `verifyBackup` passes.
///   2. `restoreBackup` throws unless the caller passes the exact typed
///      confirmation phrase ([restoreConfirmationPhrase]).
///   3. `restoreBackup` throws on tenant_id mismatch (no cross-tenant restore).
///   4. The live DB is never overwritten without a timestamped pre-restore
///      copy, and a failed integrity check rolls that copy back.
///   5. `deleteBackup` refuses anything outside the backups directory and
///      refuses the live DB path.
///
/// NOT compiled/analyzed in this environment (no Flutter/Dart toolchain) —
/// run `flutter analyze` + `flutter test` on a dev machine before merging.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_provider.dart';
import '../../data/repositories/storage_repository.dart';
import '../notifications/notification_triggers.dart';

/// Keep in sync with `version:` in pubspec.yaml. There is deliberately no
/// package_info_plus dependency — the manifest just needs a human-readable
/// app version string, and this default avoids another native plugin.
const String kBackupAppVersion = '1.0.0+1';

/// The manifest as read back from a backup file's `_backup_manifest` table.
class BackupManifest {
  BackupManifest({
    required this.tenantId,
    required this.exportedAt,
    required this.appVersion,
    required this.schemaVersion,
    required this.rowCounts,
    required this.dataSha256,
  });

  final String tenantId;
  final DateTime exportedAt;
  final String appVersion;
  final int schemaVersion;
  final Map<String, int> rowCounts;
  final String dataSha256;

  int get totalRows => rowCounts.values.fold(0, (a, b) => a + b);

  static BackupManifest fromRows(Map<String, String> kv) {
    final rowCounts = <String, int>{};
    final decoded = jsonDecode(kv['row_counts'] ?? '{}');
    if (decoded is Map) {
      decoded.forEach((k, v) {
        rowCounts['$k'] = (v as num).toInt();
      });
    }
    return BackupManifest(
      tenantId: kv['tenant_id'] ?? '',
      exportedAt:
          DateTime.tryParse(kv['exported_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      appVersion: kv['app_version'] ?? 'unknown',
      schemaVersion: int.tryParse(kv['schema_version'] ?? '') ?? -1,
      rowCounts: rowCounts,
      dataSha256: kv['data_sha256'] ?? '',
    );
  }
}

/// Structured outcome of [BackupService.verifyBackup].
class BackupVerification {
  BackupVerification({
    required this.path,
    required this.valid,
    required this.reasons,
    this.manifest,
  });

  final String path;
  final bool valid;
  final List<String> reasons;
  final BackupManifest? manifest;
}

/// What [BackupService.createBackup] produced.
class BackupResult {
  BackupResult({
    required this.file,
    required this.manifest,
    required this.sizeBytes,
    this.cloudUploadId,
  });

  final File file;
  final BackupManifest manifest;
  final int sizeBytes;
  final String? cloudUploadId;
}

/// One row of [BackupService.listBackups].
class BackupMetadata {
  BackupMetadata({
    required this.file,
    required this.sizeBytes,
    required this.modifiedAt,
    this.manifest,
    this.cloudStatus,
    this.note,
  });

  final File file;
  final int sizeBytes;
  final DateTime modifiedAt;
  final BackupManifest? manifest; // null => not a Madrassa-360 backup
  final String? cloudStatus; // pending_uploads.status or null
  final String? note;
}

/// What [BackupService.restoreBackup] did (for the UI/audit log).
class RestoreReport {
  RestoreReport({
    required this.restoredFrom,
    required this.preRestoreCopy,
    required this.manifest,
  });

  final String restoredFrom;
  final String preRestoreCopy;
  final BackupManifest manifest;
}

class BackupService {
  BackupService({
    required AppDatabase db,
    required String tenantId,
    this.appVersion = kBackupAppVersion,
  })  : _db = db,
        _tenantId = tenantId;

  final AppDatabase _db;
  final String _tenantId;
  final String appVersion;

  // ── constants ──────────────────────────────────────────────────

  /// Name of the manifest table written into every backup copy.
  static const manifestTable = '_backup_manifest';

  /// The user must TYPE this exact phrase to authorize a restore.
  /// The UI collects it; this service enforces it. Case-sensitive.
  static const restoreConfirmationPhrase = 'RESTORE';

  static const backupFilePrefix = 'madrassa360-backup';
  static const preRestorePrefix = 'madrassa360-pre-restore';

  /// Supabase Storage bucket for best-effort cloud copies. The bucket must
  /// exist (created by platform ops); objects land at
  /// `{tenant_id}/backups/<fileName>`. See docs/BACKUP_RESTORE.md.
  static const cloudBucket = 'tenant-backups';

  /// Keys that MUST be present in every manifest.
  static const requiredManifestKeys = <String>{
    'tenant_id',
    'exported_at',
    'app_version',
    'schema_version',
    'row_counts',
    'data_sha256',
  };

  // ── locations ──────────────────────────────────────────────────

  /// `<appSupport>/Madrassa360/backups` — created on demand. On Windows
  /// this is under %APPDATA%, never Program Files.
  Future<Directory> defaultBackupDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'Madrassa360', 'backups'));
    await dir.create(recursive: true);
    return dir;
  }

  String _timestamp() {
    final t = DateTime.now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  // ── create ─────────────────────────────────────────────────────

  /// Create a one-file backup of the live database.
  ///
  /// Steps: WAL checkpoint (TRUNCATE) → copy `madrassa360.db` →
  /// compute per-table row counts + SHA-256 over the data →
  /// write `_backup_manifest` INTO the copy → optional cloud-copy enqueue.
  ///
  /// Works fully offline. When [enqueueCloudCopy] is true (default) the
  /// file is registered in `pending_uploads` via [PendingUploadQueue] and
  /// the sync engine uploads it on the next online window (best-effort;
  /// the local file is the source of truth).
  Future<BackupResult> createBackup({
    String? destinationDir,
    bool enqueueCloudCopy = true,
  }) async {
    // 1. Flush the WAL into the main DB file so the copy is complete and
    //    self-contained. Without this, recent writes could live only in
    //    the -wal sidecar and the copy would silently miss them.
    await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');

    final live = await databaseFile();
    if (!await live.exists()) {
      throw StateError('Live database file not found at ${live.path}.');
    }

    final dir = destinationDir == null
        ? await defaultBackupDir()
        : await Directory(destinationDir).create(recursive: true);
    final fileName =
        '${BackupService.backupFilePrefix}-$_tenantId-${_timestamp()}.db';
    final copy = await live.copy(p.join(dir.path, fileName));

    BackupManifest manifest;
    AppDatabase? copyDb;
    try {
      copyDb = AppDatabase(NativeDatabase(File(copy.path)));
      final rowCounts = await _tableRowCounts(copyDb);
      final sha = await _dataChecksum(copyDb);
      await _writeManifest(copyDb, rowCounts, sha);
      manifest = BackupManifest(
        tenantId: _tenantId,
        exportedAt: DateTime.now().toUtc(),
        appVersion: appVersion,
        schemaVersion: _db.schemaVersion,
        rowCounts: rowCounts,
        dataSha256: sha,
      );
    } finally {
      await copyDb?.close();
    }

    String? uploadId;
    if (enqueueCloudCopy) {
      // Reuses the Phase-5 pending_uploads machinery — no new queue, no
      // new retry logic. The sync engine's _ensureUploadDone performs the
      // byte upload with upsert on its next online pass.
      uploadId = await PendingUploadQueue.enqueueUpload(
        _db,
        tenantId: _tenantId,
        stagedFile: copy,
        bucket: cloudBucket,
        destPath: '$_tenantId/backups/$fileName',
      );
    }

    final sizeBytes = await copy.length();

    // Local-first notification — best-effort: a notification failure must
    // never fail the backup.
    try {
      await NotificationTriggers.onBackupCompleted(
        _db,
        tenantId: _tenantId,
        filePath: copy.path,
        sizeBytes: sizeBytes,
        cloudUploadId: uploadId,
      );
    } catch (_) {}

    return BackupResult(
      file: copy,
      manifest: manifest,
      sizeBytes: sizeBytes,
      cloudUploadId: uploadId,
    );
  }

  /// User tables in the database, discovered dynamically so the manifest
  /// survives future schema migrations. Excludes SQLite internals and the
  /// manifest table itself (written after the checksum is computed).
  Future<List<String>> _userTables(AppDatabase db) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' AND name != '$manifestTable' "
          'ORDER BY name',
        )
        .get();
    return rows.map((r) => '${r.data['name']}').toList();
  }

  Future<Map<String, int>> _tableRowCounts(AppDatabase db) async {
    final counts = <String, int>{};
    for (final table in await _userTables(db)) {
      final rows = await db
          .customSelect('SELECT COUNT(*) AS c FROM "$table"')
          .get();
      counts[table] = ((rows.first.data['c'] as num?)?.toInt() ?? 0);
    }
    return counts;
  }

  /// Deterministic SHA-256 over the data: for every user table (name
  /// order), every row in rowid order, every column JSON-encoded with
  /// sorted keys. The manifest table itself is excluded — the checksum
  /// covers exactly what existed BEFORE the manifest was written, which
  /// is what [verifyBackup] recomputes.
  Future<String> _dataChecksum(AppDatabase db) async {
    final bytes = BytesBuilder(copy: false);
    for (final table in await _userTables(db)) {
      bytes.add(utf8.encode('table:$table\n'));
      final rows =
          await db.customSelect('SELECT * FROM "$table" ORDER BY rowid').get();
      for (final row in rows) {
        final sorted = Map.fromEntries(
          row.data.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)),
        );
        bytes.add(utf8.encode('${jsonEncode(sorted)}\n'));
      }
    }
    return sha256.convert(bytes.toBytes()).toString();
  }

  Future<void> _writeManifest(
    AppDatabase db,
    Map<String, int> rowCounts,
    String sha,
  ) async {
    await db.customStatement(
      'CREATE TABLE $manifestTable (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    final kv = <String, String>{
      'tenant_id': _tenantId,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'app_version': appVersion,
      'schema_version': _db.schemaVersion.toString(),
      'row_counts': jsonEncode(rowCounts),
      'data_sha256': sha,
    };
    for (final entry in kv.entries) {
      await db.customInsert(
        'INSERT INTO $manifestTable (key, value) VALUES (?, ?)',
        variables: [
          Variable.withString(entry.key),
          Variable.withString(entry.value),
        ],
      );
    }
  }

  // ── verify ─────────────────────────────────────────────────────

  /// Verify a backup file WITHOUT trusting it. Opens the file with
  /// `PRAGMA query_only = ON` (no write is possible), then checks:
  /// SQLite magic header → manifest present & complete → schema_version
  /// compatibility → per-table row counts → data SHA-256.
  ///
  /// Returns a structured result; never throws for a bad file (only for
  /// programmer errors). Fully offline.
  Future<BackupVerification> verifyBackup(String path) async {
    final reasons = <String>[];
    final file = File(path);
    if (!await file.exists()) {
      return BackupVerification(
          path: path, valid: false, reasons: ['file_not_found']);
    }
    final size = await file.length();
    if (size < 100) {
      return BackupVerification(
          path: path, valid: false, reasons: ['file_too_small:$size']);
    }
    // Cheap pre-check: SQLite files start with a fixed 16-byte magic.
    final header = await file.openRead(0, 16).first;
    if (utf8.decode(header, allowMalformed: true) !=
        'SQLite format 3\u0000') {
      return BackupVerification(
          path: path, valid: false, reasons: ['not_a_sqlite_file']);
    }

    AppDatabase? db;
    try {
      db = AppDatabase(NativeDatabase(File(path)));
      // Belt and braces: even if our own code had a write bug, SQLite
      // itself will refuse writes on this connection.
      await db.customStatement('PRAGMA query_only = ON;');

      final tables = await _userTables(db);
      if (!tables.contains(manifestTable)) {
        return BackupVerification(
          path: path,
          valid: false,
          reasons: ['manifest_missing'],
        );
      }

      final kv = <String, String>{};
      final mrows = await db
          .customSelect('SELECT key, value FROM $manifestTable')
          .get();
      for (final r in mrows) {
        kv['${r.data['key']}'] = '${r.data['value']}';
      }
      final missing = requiredManifestKeys.difference(kv.keys.toSet());
      if (missing.isNotEmpty) {
        reasons.add('manifest_incomplete:${missing.join(',')}');
      }
      final manifest = BackupManifest.fromRows(kv);

      if (manifest.tenantId.isEmpty) {
        reasons.add('manifest_tenant_missing');
      }
      if (manifest.dataSha256.isEmpty) {
        reasons.add('manifest_checksum_missing');
      }
      // Schema policy: restore only into the SAME schema version. Older or
      // newer backups are reported, never silently restored — a migration
      // path must be explicit (see docs/BACKUP_RESTORE.md).
      if (manifest.schemaVersion != _db.schemaVersion) {
        reasons.add(
          'schema_mismatch:backup=${manifest.schemaVersion},app=${_db.schemaVersion}',
        );
      }

      // Row counts — recompute only for tables the manifest knows about,
      // so a backup from a newer schema (extra tables) fails on the
      // schema check above, not here.
      if (reasons.isEmpty || !reasons.any((r) => r.startsWith('schema_mismatch'))) {
        for (final entry in manifest.rowCounts.entries) {
          if (!tables.contains(entry.key)) {
            reasons.add('table_missing_in_file:${entry.key}');
            continue;
          }
          final crows = await db
              .customSelect('SELECT COUNT(*) AS c FROM "${entry.key}"')
              .get();
          final actual = ((crows.first.data['c'] as num?)?.toInt() ?? -1);
          if (actual != entry.value) {
            reasons.add(
                'row_count_mismatch:${entry.key}:manifest=${entry.value},actual=$actual');
          }
        }
        final actualSha = await _dataChecksum(db);
        if (actualSha != manifest.dataSha256) {
          reasons.add('checksum_mismatch');
        }
      }

      return BackupVerification(
        path: path,
        valid: reasons.isEmpty,
        reasons: reasons,
        manifest: manifest,
      );
    } catch (e) {
      return BackupVerification(
        path: path,
        valid: false,
        reasons: ['open_failed:${e.toString().split('\n').first}'],
      );
    } finally {
      await db?.close();
    }
  }

  // ── restore ────────────────────────────────────────────────────

  /// Restore the live database from a backup file.
  ///
  /// Exact steps:
  ///   1. [confirmationToken] must equal [restoreConfirmationPhrase]
  ///      (the UI makes the user TYPE it — enforced here).
  ///   2. [verifyBackup] must pass; tenant_id must equal this service's.
  ///   3. WAL-checkpoint the live DB, then copy it to a timestamped
  ///      pre-restore file in the backups dir (never overwritten).
  ///   4. Close the live connection, remove stale -wal/-shm sidecars,
  ///      copy the backup over the live DB path.
  ///   5. Re-open via [openDatabase] and run `PRAGMA integrity_check`.
  ///   6. On ANY failure after step 3, roll back from the pre-restore
  ///      copy and rethrow.
  ///
  /// Returns the freshly opened database AND a [RestoreReport]. The caller
  /// MUST rebuild the `appDatabaseProvider` override with the returned
  /// instance (or restart the app) — the old override still points at the
  /// closed connection. See docs/BACKUP_RESTORE.md.
  Future<({AppDatabase db, RestoreReport report})> restoreBackup(
    String path, {
    required String confirmationToken,
  }) async {
    if (confirmationToken != restoreConfirmationPhrase) {
      throw StateError(
        'Restore requires the typed confirmation phrase. '
        'Pass confirmationToken: BackupService.restoreConfirmationPhrase.',
      );
    }

    final verification = await verifyBackup(path);
    if (!verification.valid) {
      throw StateError(
        'Backup did not verify: ${verification.reasons.join('; ')}',
      );
    }
    final manifest = verification.manifest!;
    if (manifest.tenantId != _tenantId) {
      throw StateError(
        'Cross-tenant restore blocked: backup belongs to tenant '
        '${manifest.tenantId}, this session is $_tenantId.',
      );
    }

    // Checkpoint so the pre-restore copy is complete, then snapshot it.
    await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');
    final live = await databaseFile();
    final backupsDir = await defaultBackupDir();
    final preRestore = File(p.join(
      backupsDir.path,
      '${BackupService.preRestorePrefix}-$_tenantId-${_timestamp()}.db',
    ));
    await live.copy(preRestore.path);
    if (await preRestore.length() != await live.length()) {
      throw StateError('Pre-restore copy size mismatch — aborting restore.');
    }

    try {
      // Close the live connection BEFORE touching its file. (WAL mode:
      // the checkpointer runs inside close.)
      await closeDatabase();

      // Stale sidecars must not survive: the restored file was
      // checkpointed at backup time and is self-contained.
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final sidecar = File('${live.path}$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }

      await File(path).copy(live.path);

      // Re-open through the provider machinery so _instance is memoized
      // again for the rest of the app.
      final fresh = await openDatabase();
      final check = await fresh
          .customSelect('PRAGMA integrity_check')
          .get();
      final ok = check.isNotEmpty &&
          '${check.first.data.values.first}'.toLowerCase() == 'ok';
      if (!ok) {
        throw StateError(
          'integrity_check failed on the restored database.',
        );
      }

      return (
        db: fresh,
        report: RestoreReport(
          restoredFrom: path,
          preRestoreCopy: preRestore.path,
          manifest: manifest,
        ),
      );
    } catch (e) {
      // Roll back: put the pre-restore copy back and reopen, so the app
      // is never left with a half-restored database.
      try {
        await closeDatabase();
        for (final suffix in ['-wal', '-shm', '-journal']) {
          final sidecar = File('${live.path}$suffix');
          if (await sidecar.exists()) await sidecar.delete();
        }
        await preRestore.copy(live.path);
        await openDatabase();
      } catch (rollbackErr) {
        throw StateError(
          'Restore failed ($e) AND rollback failed ($rollbackErr). '
          'A known-good copy exists at ${preRestore.path} — restore it manually.',
        );
      }
      rethrow;
    }
  }

  // ── list / delete ──────────────────────────────────────────────

  /// List backup files in the backups directory (default) with manifest
  /// metadata and cloud-copy status. Fully offline; the cloud status is
  /// read from the local `pending_uploads` table.
  Future<List<BackupMetadata>> listBackups({String? directory}) async {
    final dir = directory == null
        ? await defaultBackupDir()
        : Directory(directory);
    if (!await dir.exists()) return [];

    final out = <BackupMetadata>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith(backupFilePrefix) || !name.endsWith('.db')) {
        continue;
      }
      final stat = await entity.stat();
      BackupManifest? manifest;
      String? note;
      try {
        final v = await verifyBackup(entity.path);
        manifest = v.manifest;
        if (!v.valid) {
          note = 'unverified: ${v.reasons.join('; ')}';
        }
      } catch (_) {
        note = 'unreadable';
      }
      out.add(BackupMetadata(
        file: entity,
        sizeBytes: stat.size,
        modifiedAt: stat.modified,
        manifest: manifest,
        cloudStatus: await _cloudStatusFor(name),
        note: note,
      ));
    }
    out.sort((a, b) {
      final ad = a.manifest?.exportedAt;
      final bd = b.manifest?.exportedAt;
      if (ad != null && bd != null) return bd.compareTo(ad);
      return b.modifiedAt.compareTo(a.modifiedAt);
    });
    return out;
  }

  /// Latest `pending_uploads` status for this tenant's cloud copy of
  /// [fileName], or null when no cloud copy was ever enqueued.
  Future<String?> _cloudStatusFor(String fileName) async {
    final destPath = '$_tenantId/backups/$fileName';
    final rows = await _db
        .customSelect(
          'SELECT status FROM pending_uploads WHERE tenant_id = ? '
          'AND dest_path = ? ORDER BY created_at DESC LIMIT 1',
          variables: [
            Variable.withString(_tenantId),
            Variable.withString(destPath),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    return '${rows.first.data['status']}';
  }

  /// Delete a backup file. Safety: the path must resolve INSIDE the
  /// backups directory, and it must never be the live database file.
  /// Throws [StateError] on any violation.
  Future<void> deleteBackup(String path) async {
    final backupsDir = await defaultBackupDir();
    final canonical = p.canonicalize(path);
    final dirCanonical = p.canonicalize(backupsDir.path);
    if (!p.isWithin(dirCanonical, canonical)) {
      throw StateError(
          'Refusing to delete outside the backups directory: $path');
    }
    final live = await databaseFile();
    if (p.canonicalize(live.path) == canonical) {
      throw StateError('Refusing to delete the live database file.');
    }
    final file = File(canonical);
    if (!await file.exists()) {
      throw StateError('Backup file not found: $path');
    }
    await file.delete();
  }

  // ── cloud-copy helpers ─────────────────────────────────────────

  /// Best-effort cloud copy of an EXISTING backup file, independent of
  /// [createBackup]'s enqueue flag. Reuses [PendingUploadQueue]; the sync
  /// engine uploads on the next online window.
  Future<String> enqueueCloudCopy(File backupFile) async {
    final fileName = p.basename(backupFile.path);
    if (!await backupFile.exists()) {
      throw StateError('Backup file not found: ${backupFile.path}');
    }
    return PendingUploadQueue.enqueueUpload(
      _db,
      tenantId: _tenantId,
      stagedFile: backupFile,
      bucket: cloudBucket,
      destPath: '$_tenantId/backups/$fileName',
    );
  }

  /// Human-readable one-liner for UI display.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
