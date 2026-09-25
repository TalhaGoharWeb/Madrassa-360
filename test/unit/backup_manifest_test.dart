// Backup-manifest checksum unit tests.
//
// Implementation file under test:
//   lib/core/backup/backup_service.dart
//
// What is real here:
//   * BackupManifest.fromRows — the exact parser verifyBackup() runs over
//     the _backup_manifest table;
//   * canonicalRowJson — the @visibleForTesting pure helper extracted 1:1
//     from BackupService._dataChecksum (the engine now calls it;
//     encoding unchanged);
//   * requiredManifestKeys / restoreConfirmationPhrase / formatBytes —
//     real constants used by verify/restore/list.
// The golden SHA-256 test assembles bytes EXACTLY the way _dataChecksum
// does ('table:<name>\n' + canonical row JSON + '\n', tables in name
// order, rows in rowid order) using the real canonicalRowJson.
//
// HONESTY NOTE: BackupService.verifyBackup() itself opens a real SQLite
// file through Drift, so it cannot run in a hermetic unit test. The
// tamper group below pins the real manifest-level behaviour (a tampered
// data_sha256 parses to a different digest) plus the documented contract
// (verifyBackup emits 'checksum_mismatch' when the recomputed digest
// differs); end-to-end verify of a tampered file needs an integration
// test with a real .db file.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/backup/backup_service.dart';

Map<String, String> _manifestKv({
  String sha = 'abc123',
  String rowCounts = '{"invoices":2,"payments":5}',
}) =>
    {
      'tenant_id': 'tenant-1',
      'exported_at': '2026-09-25T04:00:00.000Z',
      'app_version': '1.0.0+1',
      'schema_version': '18',
      'row_counts': rowCounts,
      'data_sha256': sha,
    };

void main() {
  group('BackupManifest.fromRows', () {
    test('parses every field', () {
      final m = BackupManifest.fromRows(_manifestKv());
      expect(m.tenantId, 'tenant-1');
      expect(m.exportedAt, DateTime.utc(2026, 9, 25, 4));
      expect(m.appVersion, '1.0.0+1');
      expect(m.schemaVersion, 18);
      expect(m.rowCounts, {'invoices': 2, 'payments': 5});
      expect(m.dataSha256, 'abc123');
      expect(m.totalRows, 7);
    });

    test('missing keys degrade to safe defaults, never crash', () {
      final m = BackupManifest.fromRows({});
      expect(m.tenantId, '');
      expect(m.appVersion, 'unknown');
      expect(m.schemaVersion, -1);
      expect(m.rowCounts, isEmpty);
      expect(m.dataSha256, '');
      expect(m.totalRows, 0);
    });

    test('row counts coerce num -> int', () {
      final m =
          BackupManifest.fromRows(_manifestKv(rowCounts: '{"invoices":2.0}'));
      expect(m.rowCounts['invoices'], 2);
    });

    test('non-map row_counts JSON -> empty counts', () {
      final m = BackupManifest.fromRows(_manifestKv(rowCounts: '[]'));
      expect(m.rowCounts, isEmpty);
    });

    test('unparseable exported_at -> epoch', () {
      final kv = _manifestKv()..['exported_at'] = 'not-a-date';
      final m = BackupManifest.fromRows(kv);
      expect(m.exportedAt.millisecondsSinceEpoch, 0);
    });
  });

  group('canonicalRowJson (checksum canonicalization)', () {
    test('sorts keys so insertion order cannot change the hash', () {
      final a =
          canonicalRowJson({'total': 1500, 'status': 'issued', 'id': 'abc'});
      final b =
          canonicalRowJson({'id': 'abc', 'total': 1500, 'status': 'issued'});
      expect(a, b);
      expect(a, '{"id":"abc","status":"issued","total":1500}');
    });

    test('different values -> different canonical form', () {
      expect(canonicalRowJson({'a': 1}), isNot(canonicalRowJson({'a': 2})));
    });

    test('empty row -> empty object', () {
      expect(canonicalRowJson({}), '{}');
    });

    test('deterministic across repeated calls', () {
      final row = {'z': 'last', 'a': 'first', 'm': 42};
      expect(canonicalRowJson(row), canonicalRowJson(row));
    });
  });

  group('SHA-256 over the documented byte assembly (golden)', () {
    test('single table, single row -> fixed digest', () {
      // Mirrors _dataChecksum exactly: 'table:<name>\n' then one
      // canonical-row-JSON line per row.
      final rowJson =
          canonicalRowJson({'total': 1500, 'status': 'issued', 'id': 'abc'});
      final bytes = utf8.encode('table:invoices\n$rowJson\n');
      expect(sha256.convert(bytes).toString(),
          'd73d50a7973748178703b7e3f4e7c9c3a564367abe8e1bc5b2228976ed3d0d19');
    });

    test('row order changes the digest (rowid order matters)', () {
      final r1 = canonicalRowJson({'id': 'a'});
      final r2 = canonicalRowJson({'id': 'b'});
      final h1 = sha256.convert(utf8.encode('table:t\n$r1\n$r2\n')).toString();
      final h2 = sha256.convert(utf8.encode('table:t\n$r2\n$r1\n')).toString();
      expect(h1, isNot(h2));
    });

    test('any byte flip changes the digest (tamper-evidence)', () {
      final rowJson = canonicalRowJson({'id': 'abc'});
      final good =
          sha256.convert(utf8.encode('table:t\n$rowJson\n')).toString();
      final bad = sha256
          .convert(utf8.encode('table:t\n${canonicalRowJson({'id': 'abd'})}\n'))
          .toString();
      expect(good, isNot(bad));
    });
  });

  group('tampered manifest must fail verification', () {
    test('tampered data_sha256 parses to a different digest', () {
      final original = BackupManifest.fromRows(_manifestKv(sha: 'abc123'));
      final tampered = BackupManifest.fromRows(_manifestKv(
          sha:
              'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'));
      expect(tampered.dataSha256, isNot(original.dataSha256));
      // verifyBackup() recomputes the digest over the file and adds
      // 'checksum_mismatch' when actualSha != manifest.dataSha256 — so a
      // manifest whose sha was altered can never verify as valid.
      expect(tampered.dataSha256, isNotEmpty);
    });

    test('requiredManifestKeys names the six keys verifyBackup enforces', () {
      expect(
          BackupService.requiredManifestKeys,
          containsAll([
            'tenant_id',
            'exported_at',
            'app_version',
            'schema_version',
            'row_counts',
            'data_sha256',
          ]));
    });
  });

  group('restore confirmation + formatting', () {
    test('restore requires the exact typed phrase', () {
      expect(BackupService.restoreConfirmationPhrase, 'RESTORE');
    });

    test('formatBytes boundaries', () {
      expect(BackupService.formatBytes(0), '0 B');
      expect(BackupService.formatBytes(512), '512 B');
      expect(BackupService.formatBytes(1023), '1023 B');
      expect(BackupService.formatBytes(1024), '1.0 KB');
      expect(BackupService.formatBytes(1536), '1.5 KB');
      expect(BackupService.formatBytes(1024 * 1024), '1.0 MB');
    });
  });
}
