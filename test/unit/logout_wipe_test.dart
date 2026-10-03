// SEC-H12 regression tests — sign-out must not leave the tenant's offline
// database on disk for the next device user.
//
// What is real here:
//   * wipeAndReopenDatabase — the exact function SecureWipe calls: closes
//     the Drift database, deletes madrassa360.db (+ WAL/SHM/journal) and
//     re-creates a fresh empty database.
//   * A real file-backed Drift database in a temp dir (via
//     testSupportDirOverride, so no platform channels are needed).
// The test fails if any row survives the wipe.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/data/local/database_provider.dart';

Future<int> _rowCount(dynamic db) async {
  final rows =
      await db.customSelect('SELECT COUNT(*) AS n FROM sync_queue').get();
  return (rows.first.data['n'] as num).toInt();
}

void main() {
  test('wipeAndReopenDatabase deletes every row and re-creates the file',
      () async {
    final tmp = await Directory.systemTemp.createTemp('wipe_test');
    testSupportDirOverride = tmp;
    try {
      final db = await openDatabase();
      await db.customInsert(
        'INSERT INTO sync_queue (operation_id, tenant_id, entity, entity_id,'
        ' operation, payload_json, created_at)'
        ' VALUES (\'op1\',\'t1\',\'students\',\'s1\',\'create\',\'{}\', 0)',
      );
      expect(await _rowCount(db), 1);

      final file = await databaseFile();
      expect(await file.exists(), isTrue);

      final fresh = await wipeAndReopenDatabase();

      // Fresh database: schema exists, zero rows.
      expect(await _rowCount(fresh), 0);
      expect(await file.exists(), isTrue);
      // The old instance is closed; the new one is memoized.
      final again = await openDatabase();
      expect(identical(again, fresh), isTrue);
      await closeDatabase();
    } finally {
      testSupportDirOverride = null;
      await closeDatabase();
      await tmp.delete(recursive: true);
    }
  });

  test('database companions are removed by the wipe', () async {
    final tmp = await Directory.systemTemp.createTemp('wipe_test2');
    testSupportDirOverride = tmp;
    try {
      await openDatabase();
      final file = await databaseFile();
      // Simulate WAL/SHM companions left by SQLite.
      await File('${file.path}-wal').writeAsString('x');
      await File('${file.path}-shm').writeAsString('x');

      await wipeAndReopenDatabase();

      expect(await File('${file.path}-wal').exists(), isFalse);
      expect(await File('${file.path}-shm').exists(), isFalse);
      await closeDatabase();
    } finally {
      testSupportDirOverride = null;
      await closeDatabase();
      await tmp.delete(recursive: true);
    }
  });
}
