// Offline/online transition tests for the Phase-5 sync engine.
//
// Implementation files under test:
//   lib/core/sync/sync_engine.dart  (decideNormalConflict, isFinancialConflict,
//                                    SyncConflict, SyncQueue, SyncEngine.writeLocalRow,
//                                    SyncEngine.softDeleteLocalRow, financialEntities)
//   lib/data/local/app_database.dart (sync_queue / envelope tables, in-memory)
//
// What is real here:
//   * decideNormalConflict — the EXACT pure function the engine calls inside
//     _handleConflict for normal-entity conflicts (annotated @visibleForTesting
//     for this purpose). Every branch is pinned.
//   * isFinancialConflict — the exact predicate (server `financial` flag
//     authoritative, client financialEntities set as fallback).
//   * SyncConflict.cleanLocalPayload — the exact stripping logic used before
//     any conflict retry payload is built; fromRow/getters as the review UI
//     consumes them.
//   * SyncQueue.enqueue + SyncEngine.writeLocalRow / softDeleteLocalRow —
//     executed against a REAL in-memory Drift database: enqueue atomicity,
//     FIFO ordering contract, tombstone fields, and the sync_queue CHECK
//     constraint on `operation`.
//   * financialEntities — the client fallback set the engine consults when
//     the server omits its `financial` flag.
//
// HONESTY NOTE: the full push/pull cycle (queue drain on reconnect, no
// duplicate push after restart, 401-vs-transport retry accounting, and the
// resolveConflictKeepServer op-scoping from the offline-first audit §13)
// needs a mocked Supabase RPC layer + connectivity harness — SupabaseService
// exposes a static client, so hermetic tests cannot intercept it. Those
// behaviors are recorded as skipped tests below with the exact harness
// gap, so they become runnable the moment the engine accepts an injected
// transport.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/sync/sync_engine.dart';
// Aliased: defines a Drift `Table` named `SyncQueue` which conflicts with the
// engine's `SyncQueue` enqueue helper. The table itself is unused here.
import 'package:madrasa_360/data/local/app_database.dart' as adb;

adb.AppDatabase _openTestDb() {
  final db = adb.AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

Future<Map<String, dynamic>?> _queueRow(
    adb.AppDatabase db, String entityId) async {
  final rows = await db.customSelect(
    'SELECT * FROM sync_queue WHERE entity_id = ? LIMIT 1',
    variables: [Variable.withString(entityId)],
  ).get();
  if (rows.isEmpty) return null;
  return Map<String, dynamic>.from(rows.first.data);
}

Future<List<String>> _queueOrder(adb.AppDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT entity_id FROM sync_queue ORDER BY created_at, operation_id',
      )
      .get();
  return rows.map((r) => '${r.data['entity_id']}').toList();
}

void main() {
  group('decideNormalConflict — pure conflict rule', () {
    test('server newer -> takeServer', () {
      expect(
        decideNormalConflict(
          serverUpdatedAt: DateTime.utc(2026, 10, 3, 12, 0, 1),
          localUpdatedAt: DateTime.utc(2026, 10, 3, 12, 0, 0),
        ),
        NormalConflictDecision.takeServer,
      );
    });

    test('local newer -> rebaseAndRetry', () {
      expect(
        decideNormalConflict(
          serverUpdatedAt: DateTime.utc(2026, 10, 3, 12, 0, 0),
          localUpdatedAt: DateTime.utc(2026, 10, 3, 12, 0, 1),
        ),
        NormalConflictDecision.rebaseAndRetry,
      );
    });

    test('tied timestamps -> rebaseAndRetry (local wins ties)', () {
      final t = DateTime.utc(2026, 10, 3, 12, 0, 0);
      expect(
        decideNormalConflict(serverUpdatedAt: t, localUpdatedAt: t),
        NormalConflictDecision.rebaseAndRetry,
      );
    });

    test('local time unknown -> takeServer (fail toward server)', () {
      expect(
        decideNormalConflict(
          serverUpdatedAt: DateTime.utc(2026, 10, 3, 12, 0, 0),
          localUpdatedAt: null,
        ),
        NormalConflictDecision.takeServer,
      );
    });

    test('server time unknown -> rebaseAndRetry', () {
      expect(
        decideNormalConflict(
          serverUpdatedAt: null,
          localUpdatedAt: DateTime.utc(2026, 10, 3, 12, 0, 0),
        ),
        NormalConflictDecision.rebaseAndRetry,
      );
    });

    test('both unknown -> takeServer', () {
      expect(
        decideNormalConflict(serverUpdatedAt: null, localUpdatedAt: null),
        NormalConflictDecision.takeServer,
      );
    });
  });

  group('isFinancialConflict — server flag authoritative', () {
    test('server flag true wins even for non-financial entity', () {
      expect(
        isFinancialConflict(serverFinancialFlag: true, entity: 'students'),
        isTrue,
      );
    });

    test('client fallback set catches financial entity without flag', () {
      expect(
        isFinancialConflict(serverFinancialFlag: false, entity: 'payments'),
        isTrue,
      );
      expect(
        isFinancialConflict(serverFinancialFlag: false, entity: 'invoices'),
        isTrue,
      );
    });

    test('normal entity without flag is not financial', () {
      expect(
        isFinancialConflict(serverFinancialFlag: false, entity: 'students'),
        isFalse,
      );
      expect(
        isFinancialConflict(serverFinancialFlag: false, entity: 'attendance'),
        isFalse,
      );
    });

    test('financialEntities covers every money-moving entity', () {
      for (final e in [
        'invoices',
        'payments',
        'transactions',
        'refunds',
        'accounts',
        'income',
        'expenses',
        'discounts',
        'scholarships',
        'invoice_items',
      ]) {
        expect(financialEntities.contains(e), isTrue, reason: e);
      }
    });
  });

  group('SyncConflict model — review metadata handling', () {
    test('cleanLocalPayload strips underscore review keys', () {
      const c = SyncConflict(
        id: 1,
        tenantId: 't1',
        entity: 'payments',
        entityId: 'p1',
        localPayload: {
          'amount': 500,
          '_op': 'update',
          '_reason': 'conflict',
          '_financial': true,
        },
        serverRevision: 7,
        resolved: false,
        createdAtMs: 0,
      );
      expect(c.cleanLocalPayload, {'amount': 500});
      expect(c.isFinancial, isTrue);
      expect(c.operation, 'update');
      expect(c.reason, 'conflict');
      expect(c.status, 'unresolved');
    });

    test('fromRow tolerates missing/invalid JSON', () {
      final c = SyncConflict.fromRow({
        'id': 3,
        'tenant_id': 't1',
        'entity': 'students',
        'entity_id': 's1',
        'local_payload_json': 'not-json{{{',
        'server_payload_json': '',
        'server_revision': null,
        'resolved': 0,
        'created_at': 0,
      });
      expect(c.localPayload, isEmpty);
      expect(c.serverPayload, isNull);
      expect(c.operation, 'update'); // default when _op absent
    });
  });

  group('sync_queue + envelope writes (in-memory Drift)', () {
    test('enqueue inside the write transaction is atomic and pending',
        () async {
      final db = _openTestDb();
      await db.transaction(() async {
        await SyncEngine.writeLocalRow(
          db,
          table: 'students',
          id: 's1',
          tenantId: 't1',
          indexed: {'name': 'Test Student'},
          data: {'name': 'Test Student', 'roll_no': '1'},
        );
        await SyncQueue.enqueue(
          db,
          tenantId: 't1',
          entity: 'students',
          entityId: 's1',
          operation: 'create',
          payload: {'name': 'Test Student'},
          baseRevision: 0,
        );
      });

      final local = await LocalRows.byId(db, 'students', 't1', 's1');
      expect(local, isNotNull);
      expect(local!['revision'], 1);
      expect(local['server_revision'], isNull);

      final q = await _queueRow(db, 's1');
      expect(q, isNotNull);
      expect(q!['sync_status'], 'pending');
      expect(q['retry_count'], 0);
      expect(q['operation'], 'create');
    });

    test('queue CHECK constraint rejects unknown operations', () async {
      final db = _openTestDb();
      expect(
        () => SyncQueue.enqueue(
          db,
          tenantId: 't1',
          entity: 'students',
          entityId: 's9',
          operation: 'bogus',
          payload: const {},
          baseRevision: 0,
        ),
        throwsA(anything),
      );
    });

    test('FIFO order follows created_at', () async {
      final db = _openTestDb();
      for (final id in ['a', 'b', 'c']) {
        await SyncQueue.enqueue(
          db,
          tenantId: 't1',
          entity: 'students',
          entityId: id,
          operation: 'create',
          payload: const {},
          baseRevision: 0,
        );
      }
      // Pin deterministic timestamps so the ordering contract is exact:
      // the engine's claim query is ORDER BY created_at.
      var t = 1000;
      for (final id in ['a', 'b', 'c']) {
        await db.customUpdate(
          'UPDATE sync_queue SET created_at = ? WHERE entity_id = ?',
          variables: [Variable.withInt(t), Variable.withString(id)],
        );
        t += 10;
      }
      expect(await _queueOrder(db), ['a', 'b', 'c']);
    });

    test('softDeleteLocalRow sets tombstone fields and bumps revision',
        () async {
      final db = _openTestDb();
      await SyncEngine.writeLocalRow(
        db,
        table: 'students',
        id: 's2',
        tenantId: 't1',
        indexed: const {'name': 'Gone Student'},
        data: const {'name': 'Gone Student'},
      );
      await SyncEngine.softDeleteLocalRow(
        db,
        table: 'students',
        id: 's2',
        tenantId: 't1',
      );
      final local = await LocalRows.byId(db, 'students', 't1', 's2');
      // byId filters deleted_at IS NULL -> tombstoned row is invisible.
      expect(local, isNull);
      final raw = await db.customSelect(
        'SELECT deleted_at, revision FROM students WHERE id = ?',
        variables: [Variable.withString('s2')],
      ).get();
      expect(raw, isNotEmpty);
      expect((raw.first.data['deleted_at'] as num?)?.toInt(), greaterThan(0));
      expect((raw.first.data['revision'] as num).toInt(), 2);
    });
  });

  group('offline transitions needing a transport harness', () {
    test(
      'queue drains on reconnect after offline writes',
      () {},
      skip: 'needs mocked sync_apply RPC + connectivity harness; '
          'SupabaseService.client is static and cannot be intercepted '
          'hermetically.',
    );

    test(
      'no duplicate push of the same operation_id after restart',
      () {},
      skip: 'needs RPC mock to observe call counts across engine '
          'start() reclaim cycles.',
    );

    test(
      '401 does not burn transport retries; prompts re-login instead',
      () {},
      skip: 'needs auth mock returning 401 then a refreshed session; '
          'offline-first audit §10.',
    );

    test(
      'resolveConflictKeepServer completes only the conflicted operation_id',
      () {},
      skip: 'regression test for offline-first audit §13 (currently marks '
          'ALL non-done queue rows for the entity done). Needs RPC mock for '
          'the server-row fetch inside resolveConflictKeepServer.',
    );

    test(
      'tombstone pulled from server deletes local row exactly once',
      () {},
      skip: 'needs mocked pull pages (PostgREST) with server_version '
          'watermarks.',
    );
  });
}
