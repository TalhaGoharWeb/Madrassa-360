/// Riverpod providers for the local Drift database.
///
/// The database file lives in the per-OS application-support directory,
/// inside a `Madrassa360` folder — on Windows this resolves under
/// `%APPDATA%`, never under Program Files. The directory is created on
/// first open.
///
/// SEC-H12: the file holds the tenant's full synced dataset, so sign-out
/// (and account switch) must not merely close it — [wipeAndReopenDatabase]
/// deletes the file and re-creates a fresh empty database. The provider
/// below reads the module singleton (not a startup override) so the fresh
/// instance is picked up after `ref.invalidate(appDatabaseProvider)`.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

AppDatabase? _instance;

/// Test override for the support directory, so unit tests can use a temp
/// dir instead of the real application-support directory (which needs
/// platform channels). Also read by [SecureWipe] so the wipe targets the
/// same directory the database was opened from in tests.
Directory? testSupportDirOverride;

/// The database file location, shared by [openDatabase] and any tooling.
Future<File> databaseFile() async {
  final supportDir =
      testSupportDirOverride ?? await getApplicationSupportDirectory();
  final dir = Directory(p.join(supportDir.path, 'Madrassa360'));
  await dir.create(recursive: true);
  return File(p.join(dir.path, 'madrassa360.db'));
}

/// Opens (and memoizes) the singleton [AppDatabase].
///
/// Call once at startup; [appDatabaseProvider] serves the memoized instance.
Future<AppDatabase> openDatabase() async {
  final existing = _instance;
  if (existing != null) return existing;
  final file = await databaseFile();
  final db = AppDatabase(NativeDatabase.createInBackground(file));
  _instance = db;
  return db;
}

/// The app's database. Reads the module singleton created by
/// [openDatabase]; in tests, override with
/// `AppDatabase(NativeDatabase.memory())`.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = _instance;
  if (db == null) {
    throw StateError(
      'appDatabaseProvider was read before the database was opened. '
      'Call await openDatabase() in main() before runApp.',
    );
  }
  return db;
});

/// Closes the memoized database and forgets it, so a later [openDatabase]
/// re-opens cleanly. Call on soft restart and in tests between cases.
///
/// Note: anything watching [appDatabaseProvider] should be invalidated too —
/// call `ref.invalidate(appDatabaseProvider)` after this.
Future<void> closeDatabase() async {
  final db = _instance;
  _instance = null;
  await db?.close();
}

/// SEC-H12 — Secure tenant-data wipe for sign-out / account switch.
///
/// Closes the database, deletes the SQLite file **and** its WAL/SHM/journal
/// companions (which can hold un-checkpointed rows), then re-creates a fresh
/// empty database and memoizes it. Callers must `ref.invalidate(
/// appDatabaseProvider)` (and anything watching it, e.g. the sync engine)
/// so the fresh instance is used afterwards.
///
/// Never throws — a failed wipe is logged by the caller; the sign-out
/// itself must not be blocked by it.
Future<AppDatabase> wipeAndReopenDatabase() async {
  await closeDatabase();
  final file = await databaseFile();
  for (final suffix in <String>['', '-wal', '-shm', '-journal']) {
    try {
      final f = suffix.isEmpty ? file : File('${file.path}$suffix');
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best effort per companion file — keep trying the rest.
    }
  }
  final db = AppDatabase(NativeDatabase.createInBackground(file));
  _instance = db;
  return db;
}
