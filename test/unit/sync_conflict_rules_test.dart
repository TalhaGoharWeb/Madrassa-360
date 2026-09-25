// Sync-conflict rule unit tests.
//
// Implementation file under test:
//   lib/core/sync/sync_engine.dart
//
// What is real here:
//   * financialEntities — the exact client-side fallback set used by
//     SyncEngine._handleConflict to classify financial vs normal entities;
//   * isFinancialConflict / decideNormalConflict — @visibleForTesting pure
//     helpers extracted 1:1 from the branch logic of _handleConflict
//     (the engine now calls them; behaviour unchanged);
//   * SyncConflict — the parsed sync_conflicts row (reason/operation/
//     isFinancial/cleanLocalPayload).
//
// BEHAVIOUR NOTE: the task brief described "higher revision wins; equal
// revision -> updated_at tiebreak". The REAL implemented rule (see the doc
// comment on _handleConflict and the header of sync_engine.dart) is
// updated_at-based: server newer -> take the server row; local newer, tied,
// or server time unknown -> rebase the local op onto the fresh
// base_revision (= server_revision) and retry the RPC exactly once; if the
// retry still conflicts -> park in sync_conflicts. Revision decides the
// rebase base, not the winner.
//
// HONESTY NOTE: _handleConflict itself needs a live Drift database plus
// the Supabase RPC, so it is NOT driven here. The end-to-end paths
// (park on financial conflict, take-server write, rebase retry, drop on
// server-deleted) must be covered by integration tests with a fake RPC.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/sync/sync_engine.dart';

void main() {
  group('financialEntities classification set', () {
    test('covers every finance table', () {
      expect(
          financialEntities,
          containsAll([
            'invoices',
            'invoice_items',
            'payments',
            'transactions',
            'refunds',
            'accounts',
            'income',
            'expenses',
            'discounts',
            'scholarships',
          ]));
    });

    test('does not swallow normal entities', () {
      for (final e in [
        'students',
        'attendance',
        'results',
        'exams',
        'classes',
        'announcements',
      ]) {
        expect(financialEntities.contains(e), isFalse, reason: e);
      }
    });
  });

  group('isFinancialConflict (financial -> ALWAYS park, never overwrite)',
      () {
    test('server financial flag is authoritative even for normal entities',
        () {
      expect(
          isFinancialConflict(
              serverFinancialFlag: true, entity: 'students'),
          isTrue);
    });

    test('client fallback catches finance tables when the flag is absent',
        () {
      expect(
          isFinancialConflict(
              serverFinancialFlag: false, entity: 'invoices'),
          isTrue);
      expect(
          isFinancialConflict(
              serverFinancialFlag: false, entity: 'payments'),
          isTrue);
    });

    test('normal entity without the flag is not financial', () {
      expect(
          isFinancialConflict(
              serverFinancialFlag: false, entity: 'attendance'),
          isFalse);
    });
  });

  group('decideNormalConflict (latest valid timestamp wins)', () {
    final t1 = DateTime.utc(2026, 9, 1, 10);
    final t2 = DateTime.utc(2026, 9, 1, 12);

    test('server newer -> take the server row', () {
      expect(
          decideNormalConflict(serverUpdatedAt: t2, localUpdatedAt: t1),
          NormalConflictDecision.takeServer);
    });

    test('local newer -> rebase onto fresh base_revision and retry once',
        () {
      expect(
          decideNormalConflict(serverUpdatedAt: t1, localUpdatedAt: t2),
          NormalConflictDecision.rebaseAndRetry);
    });

    test('timestamps tied -> rebase and retry (local wins ties)', () {
      expect(
          decideNormalConflict(serverUpdatedAt: t1, localUpdatedAt: t1),
          NormalConflictDecision.rebaseAndRetry);
    });

    test('server time unknown -> rebase and retry', () {
      expect(
          decideNormalConflict(serverUpdatedAt: null, localUpdatedAt: t1),
          NormalConflictDecision.rebaseAndRetry);
    });

    test('local time unknown -> take the server row (safe default)', () {
      expect(
          decideNormalConflict(serverUpdatedAt: t2, localUpdatedAt: null),
          NormalConflictDecision.takeServer);
    });
  });

  group('SyncConflict row model', () {
    Map<String, dynamic> row({
      String localPayload = '{"_op":"update","_reason":"conflict",'
          '"_financial":true,"student_id":"s1"}',
      String? serverPayload,
      int resolved = 0,
    }) =>
        {
          'id': 7,
          'tenant_id': 't1',
          'entity': 'invoices',
          'entity_id': 'inv-1',
          'local_payload_json': localPayload,
          'server_payload_json': serverPayload,
          'server_revision': 42,
          'resolved': resolved,
          'created_at': 1758772800000,
        };

    test('parses reason/operation/isFinancial from the payload envelope',
        () {
      final c = SyncConflict.fromRow(row());
      expect(c.conflictId, '7');
      expect(c.entity, 'invoices');
      expect(c.reason, 'conflict');
      expect(c.operation, 'update');
      expect(c.isFinancial, isTrue);
      expect(c.serverRevision, 42);
      expect(c.status, 'unresolved');
    });

    test('missing review keys fall back to safe defaults', () {
      final c = SyncConflict.fromRow(row(localPayload: '{"a":1}'));
      expect(c.reason, 'conflict');
      expect(c.operation, 'update');
      expect(c.isFinancial, isFalse);
    });

    test('cleanLocalPayload strips review metadata before any retry', () {
      final c = SyncConflict.fromRow(row());
      expect(c.cleanLocalPayload, {'student_id': 's1'});
      expect(
          c.cleanLocalPayload.keys.any((k) => k.startsWith('_')), isFalse);
    });

    test('resolved flag maps to status', () {
      expect(SyncConflict.fromRow(row(resolved: 1)).status, 'resolved');
      expect(
          SyncConflict.fromRow(row(resolved: 0)).status, 'unresolved');
    });

    test('malformed payload JSON -> empty maps, never a crash', () {
      final c = SyncConflict.fromRow(
          row(localPayload: 'not-json', serverPayload: 'also-not-json'));
      expect(c.localPayload, isEmpty);
      expect(c.serverPayload, isNull);
      expect(c.reason, 'conflict');
    });

    test('createdAt preserves the stored epoch millis', () {
      final c = SyncConflict.fromRow(row());
      expect(c.createdAt.millisecondsSinceEpoch, 1758772800000);
    });
  });
}
