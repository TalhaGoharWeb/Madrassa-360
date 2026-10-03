/// Local-database tenant-isolation integration tests.
///
/// Implementation files under test:
///   lib/data/local/app_database.dart (AppDatabase, StudentsDao)
///
/// What is real here: a REAL in-memory Drift database (no mocks). Every
/// query runs the actual SQL the app executes on-device. These tests pin
/// the local tenant-isolation boundary: on shared school devices the
/// offline database holds multiple tenants' rows only transiently, and
/// every DAO read MUST scope by tenant_id — an unscoped read would leak
/// Tenant B's students to Tenant A's session.
///
/// This complements the server-side cross-tenant suite (test/db/
/// 04_cross_tenant_isolation.sql): that one asserts RLS; this one asserts
/// the on-device cache.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/data/local/app_database.dart';

AppDatabase _openTestDb() {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

StudentsCompanion _student({
  required String id,
  required String tenantId,
  required String name,
  int updatedAt = 1000,
  int? deletedAt,
}) =>
    StudentsCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      name: Value(name),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
    );

Future<void> _seedTwoTenants(AppDatabase db) async {
  final dao = db.studentsDao;
  await dao.upsert(_student(id: 's-a1', tenantId: 'tenant-a', name: 'احمد'));
  await dao.upsert(_student(id: 's-a2', tenantId: 'tenant-a', name: 'بلال'));
  await dao.upsert(_student(id: 's-b1', tenantId: 'tenant-b', name: 'چاند'));
}

void main() {
  group('StudentsDao tenant isolation (in-memory Drift)', () {
    test('listByTenant returns only the requested tenant rows', () async {
      final db = _openTestDb();
      await _seedTwoTenants(db);

      final aRows = await db.studentsDao.listByTenant('tenant-a');
      final bRows = await db.studentsDao.listByTenant('tenant-b');

      expect(aRows.map((r) => r.id).toSet(), {'s-a1', 's-a2'});
      expect(bRows.map((r) => r.id).toSet(), {'s-b1'});
    });

    test('getById with the wrong tenant returns null (local IDOR guard)',
        () async {
      final db = _openTestDb();
      await _seedTwoTenants(db);

      // s-a1 exists, but not in tenant-b: must not resolve.
      expect(await db.studentsDao.getById('s-a1', 'tenant-b'), isNull);
      // Sanity: it resolves under its own tenant.
      expect(await db.studentsDao.getById('s-a1', 'tenant-a'), isNotNull);
    });

    test('soft-deleted rows are invisible to tenant reads', () async {
      final db = _openTestDb();
      await _seedTwoTenants(db);
      await db.studentsDao.upsert(
        _student(
            id: 's-a1', tenantId: 'tenant-a', name: 'احمد', deletedAt: 2000),
      );

      expect(
        (await db.studentsDao.listByTenant('tenant-a')).map((r) => r.id),
        ['s-a2'],
      );
      expect(await db.studentsDao.getById('s-a1', 'tenant-a'), isNull);
    });

    test('markClean with the wrong tenant does not touch the row', () async {
      final db = _openTestDb();
      await _seedTwoTenants(db);

      await db.studentsDao.markClean('s-a1', 'tenant-b');
      final row = await db.studentsDao.getById('s-a1', 'tenant-a');
      expect(row, isNotNull);
      expect(row!.serverRevision, isNull);
    });

    test('markClean under the right tenant stamps serverRevision', () async {
      final db = _openTestDb();
      await _seedTwoTenants(db);

      await db.studentsDao.markClean('s-a1', 'tenant-a');
      final row = await db.studentsDao.getById('s-a1', 'tenant-a');
      expect(row!.serverRevision, row.revision);
    });

    test('upsert is idempotent on primary key (no duplicates)', () async {
      final db = _openTestDb();
      await _seedTwoTenants(db);
      await db.studentsDao.upsert(
        _student(id: 's-a1', tenantId: 'tenant-a', name: 'احمد نیا'),
      );

      final rows = await db.studentsDao.listByTenant('tenant-a');
      expect(rows.where((r) => r.id == 's-a1'), hasLength(1));
      expect(rows.firstWhere((r) => r.id == 's-a1').name, 'احمد نیا');
    });
  });
}
