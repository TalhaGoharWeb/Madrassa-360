/// Riverpod providers for the local Drift database.
///
/// The database file lives in the per-OS application-support directory,
/// inside a `Madrassa360` folder — on Windows this resolves under
/// `%APPDATA%`, never under Program Files. The directory is created on
/// first open.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

AppDatabase? _instance;

/// The database file location, shared by [openDatabase] and any tooling.
Future<File> databaseFile() async {
  final supportDir = await getApplicationSupportDirectory();
  final dir = Directory(p.join(supportDir.path, 'Madrassa360'));
  await dir.create(recursive: true);
  return File(p.join(dir.path, 'madrassa360.db'));
}

/// Opens (and memoizes) the singleton [AppDatabase].
///
/// Call once at startup, then inject the result into the widget tree:
/// ```dart
/// final db = await openDatabase();
/// runApp(ProviderScope(
///   overrides: [appDatabaseProvider.overrideWithValue(db)],
///   child: const MyApp(),
/// ));
/// ```
Future<AppDatabase> openDatabase() async {
  final existing = _instance;
  if (existing != null) return existing;
  final file = await databaseFile();
  final db = AppDatabase(NativeDatabase.createInBackground(file));
  _instance = db;
  return db;
}

/// The app's database. Must be overridden with the result of
/// [openDatabase()] (see above); in tests, override with
/// `AppDatabase(NativeDatabase.memory())`.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw StateError(
    'appDatabaseProvider was read before being overridden. '
    'Call await openDatabase() in main() and pass '
    'appDatabaseProvider.overrideWithValue(db) to ProviderScope.',
  );
});

/// Closes the memoized database and forgets it, so a later [openDatabase]
/// re-opens cleanly. Call on logout and in tests between cases.
///
/// Note: any live `appDatabaseProvider` override must be rebuilt too —
/// call `ref.invalidate(appDatabaseProvider)` or rebuild the ProviderScope.
Future<void> closeDatabase() async {
  final db = _instance;
  _instance = null;
  await db?.close();
}
