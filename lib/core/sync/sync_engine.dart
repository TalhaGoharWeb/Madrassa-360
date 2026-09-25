/// ─────────────────────────────────────────────────────────────
/// Sync Engine — offline-first push/pull with optimistic concurrency
/// (Phase 5 of the Madrassa-360 multi-tenant SaaS transformation).
///
/// Responsibilities:
///   * PUSH: claim this tenant's [sync_queue] rows (FIFO per entity),
///     apply each through the server `sync_apply` RPC, mark done/failed
///     transactionally, exponential backoff (5s ×2, 5 retries → dead_letter).
///   * PULL: per entity, read the watermark from [sync_state], fetch
///     `server_version > watermark` pages (+ a tombstone pass for
///     `deleted_at`), upsert locally, advance the watermark.
///   * CONFLICTS (mission §23 + 016_sync.sql):
///       - the RPC returns `{ok:false, reason, server_revision, server_row,
///         financial}`; the server's `financial` flag is authoritative.
///       - normal entities: "latest valid revision wins" — if the server row
///         is newer (`updated_at`), take the server row; otherwise rebase
///         the local op onto the fresh `base_revision` and retry ONCE.
///         If the retry still conflicts, park it in [sync_conflicts].
///       - FINANCIAL entities: on ANY conflict, write a [sync_conflicts]
///         row and NEVER overwrite server data. The local row is left
///         untouched (dirty-flagged for review via the conflict record);
///         the queue row is parked as `dead_letter` so push never retries
///         it automatically.
///
/// Multi-tenancy: one engine instance per ACTIVE tenant. The engine is
/// created by [syncEngineProvider], which watches `currentTenantIdProvider`
/// and therefore recreates (disposing the old engine) on tenant switch.
/// Every queue row, local row and conflict row carries `tenant_id`, and
/// the engine only ever touches rows for its own [tenantId].
///
/// Crash safety:
///   * A queue row is marked `done` only inside the SAME Drift transaction
///     as the local `server_revision` bookkeeping update.
///   * Claiming sets `sync_status='in_progress'` with a 10-minute lease in
///     `next_retry_at`; on [start], stale `in_progress` rows whose lease
///     expired are reclaimed to `pending` (survives process death mid-push).
///   * Pull never clobbers unpushed local work: rows with a non-`done`
///     queue entry or an unresolved conflict are skipped on pull (they
///     converge via push / review).
///
/// REAL CONTRACTS (verified against the siblings' landed files — the task
/// brief's preliminary description differed, this is authoritative):
///   * `lib/data/local/app_database.dart` — Drift `AppDatabase`. Entity
///     tables are ENVELOPES: `id, tenant_id, <indexed cols>, revision,
///     server_revision, updated_at, deleted_at, data` where `data` is the
///     full row as JSON and all timestamps are INTEGER epoch millis.
///     `revision` = local mutation counter; `server_revision` = last known
///     server `revision` (the optimistic-concurrency base).
///   * `sync_queue`: operation_id PK, tenant_id, entity, entity_id,
///     operation CHECK IN ('create','update','delete'), payload_json,
///     base_revision, created_at INT ms, sync_status, retry_count,
///     last_error NULLABLE, next_retry_at INT ms NULLABLE.
///   * `sync_conflicts`: id INTEGER PK autoincrement, tenant_id, entity,
///     entity_id, local_payload_json, server_payload_json,
///     server_revision, created_at INT ms, resolved INT 0/1. There are NO
///     operation/reason/resolution columns — those are encoded as `_op`,
///     `_reason`, `_financial`, `_resolution`, `_resolved_at` keys inside
///     `local_payload_json` (stripped before any retry payload).
///   * `sync_state` (table `sync_state`): PK(entity, tenant_id),
///     last_server_version, last_pull_at.
///   * `supabase/migrations/016_sync.sql` — `sync_apply(p_entity,
///     p_entity_id, p_base_revision, p_payload, p_op)` with
///     p_op IN ('insert','update','delete'). NOTE the queue stores
///     'create' but the RPC wants 'insert' — the engine maps it at call
///     time. `p_base_revision` is compared against the server row's
///     `revision`; success returns `{ok:true, new_revision}`; conflicts
///     return `{ok:false, reason, server_revision, server_row, financial}`
///     with reason IN ('conflict','already_exists','deleted','not_found').
///   * Pull watermark = server `server_version` (BIGINT sequence); base
///     revision = server `revision` (INT optimistic counter). They are
///     different columns — do not mix them.
///
/// App-resume hook: [notifyAppResumed] is the hook point — wire it to a
/// `WidgetsBindingObserver.didChangeAppLifecycleState(resumed)` in the
/// coordinator's bootstrap (see sync_providers.dart).
///
/// NOTE: no Flutter toolchain is available in this environment, so this
/// file is written carefully but UNCOMPILED. Delimiter balance was
/// checked by script; treat as needing `flutter analyze` before merge.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart';
import '../errors/error_boundary.dart';
import '../observability/app_logger.dart';
import '../services/supabase_service.dart';

// ─────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────

/// Client-side fallback financial set (mission §23). The server's
/// `financial` flag in the RPC response is authoritative; this covers the
/// case where the flag is absent.
const Set<String> financialEntities = {
  'invoices',
  'payments',
  'transactions',
  'refunds',
  // Mirrors the server's v_financial list in 016_sync.sql (the server's
  // `financial` flag stays authoritative; this covers a missing flag).
  'accounts',
  'income',
  'expenses',
  'discounts',
  'scholarships',
  'invoice_items',
};

/// Local Drift table per queue entity name.
const Map<String, String> _localTables = {
  'students': 'students',
  'classes': 'classes',
  'darjas': 'darjas',
  'attendance': 'attendance_records',
  'exams': 'exams',
  'results': 'results',
  'announcements': 'announcements',
  'invoices': 'invoices',
  'payments': 'payments',
  // NOTE: 'fees' has NO local table in the sibling's contract — the fee
  // repository enqueues writes (push works; 'fees' is RPC-whitelisted)
  // but keeps reads remote (documented in fee_repository.dart).
  'staff': 'staff',
  'darja_sections': 'darja_sections',
  'library_books': 'library_books',
  'book_issues': 'book_issues',
  'accounts': 'accounts',
  'transactions': 'transactions',
  'income': 'income',
  'expenses': 'expenses',
  'refunds': 'refunds',
  'discounts': 'discounts',
  'scholarships': 'scholarships',
  'invoice_items': 'invoice_items',
};

/// Server table per queue entity name (differs only for attendance).
const Map<String, String> _serverTables = {
  'students': 'students',
  'classes': 'classes',
  'darjas': 'darjas',
  'attendance': 'attendance',
  'exams': 'exams',
  'results': 'results',
  'announcements': 'announcements',
  'invoices': 'invoices',
  'payments': 'payments',
  'staff': 'staff',
  'darja_sections': 'darja_sections',
  'library_books': 'library_books',
  'book_issues': 'book_issues',
  'accounts': 'accounts',
  'transactions': 'transactions',
  'income': 'income',
  'expenses': 'expenses',
  'refunds': 'refunds',
  'discounts': 'discounts',
  'scholarships': 'scholarships',
  'invoice_items': 'invoice_items',
};

/// Entities pulled from the server (all have local tables).
///
/// Reads for the newly-added entities ('staff', 'darja_sections',
/// 'library_books', 'book_issues', 'accounts', 'transactions', 'income',
/// 'expenses', 'refunds', 'discounts', 'scholarships', 'invoice_items')
/// INTENTIONALLY stay remote: their server tables may lack the
/// `server_version` watermark column and migration 016 was never applied
/// here, so there is no watermark to pull against. The local tables are
/// the write-cache + queue support. Pull for them can be enabled once
/// staging is green.
const List<String> _pullEntities = [
  'students',
  'classes',
  'darjas',
  'attendance',
  'exams',
  'results',
  'announcements',
  'invoices',
  'payments',
];

/// Decision for a NORMAL (non-financial) entity conflict once the server
/// row is known to exist. Mirrors the branch inside
/// [SyncEngine._handleConflict]; extracted for unit testing.
enum NormalConflictDecision { takeServer, rebaseAndRetry }

/// True when a conflicted entity must be parked in `sync_conflicts` and
/// NEVER overwrite server data. The server's `financial` flag in the RPC
/// response is authoritative; the client-side [financialEntities] set
/// covers a missing flag. Mirrors the predicate inside
/// [SyncEngine._handleConflict]; extracted for unit testing.
@visibleForTesting
bool isFinancialConflict({
  required bool serverFinancialFlag,
  required String entity,
}) =>
    serverFinancialFlag || financialEntities.contains(entity);

/// Pure decision rule for normal-entity conflicts. Mirrors the branch
/// inside [SyncEngine._handleConflict]; extracted for unit testing.
///
///   * server newer (`updated_at`) → take the server row;
///   * local newer, timestamps tied, or server time unknown → rebase the
///     local op onto the fresh `base_revision` and retry the RPC exactly
///     once;
///   * local time unknown → take the server row.
@visibleForTesting
NormalConflictDecision decideNormalConflict({
  required DateTime? serverUpdatedAt,
  required DateTime? localUpdatedAt,
}) {
  if (localUpdatedAt == null ||
      (serverUpdatedAt != null && serverUpdatedAt.isAfter(localUpdatedAt))) {
    return NormalConflictDecision.takeServer;
  }
  return NormalConflictDecision.rebaseAndRetry;
}

/// Queue ops that count as conflicts from the RPC.
const Set<String> _conflictReasons = {
  'conflict',
  'already_exists',
  'deleted',
};

const int _claimBatchSize = 25;
const int _maxRetries = 5;
const int _baseBackoffMs = 5000;
const int _claimLeaseMs = 10 * 60 * 1000;
const int _pullPageSize = 500;
const int _pullMaxPages = 20;

const _uuid = Uuid();

/// Milliseconds since epoch, UTC — the timestamp format of the local DB.
int _nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

/// ISO-8601 UTC string — the timestamp format inside sync payloads and
/// for conflict recency comparison ("latest valid revision wins").
String _nowIso() => DateTime.now().toUtc().toIso8601String();

// ─────────────────────────────────────────────
// Public models / events
// ─────────────────────────────────────────────

/// Lifecycle events emitted by the engine (broadcast).
enum SyncEvent {
  /// A local write was enqueued — UI counters should refresh.
  localChanged,

  /// A push pass finished (rows may still be pending/failed).
  pushCompleted,

  /// A pull pass finished.
  pullCompleted,

  /// A full push→pull cycle finished.
  syncCompleted,
}

/// One row of `sync_conflicts` (unresolved items for review).
///
/// The sibling's table has no operation/reason/resolution columns; those
/// travel as `_op`, `_reason`, `_financial`, `_resolution`, `_resolved_at`
/// keys inside [localPayload] and are stripped by [cleanLocalPayload]
/// before any retry.
class SyncConflict {
  final int id;
  final String tenantId;
  final String entity;
  final String entityId;
  final Map<String, dynamic> localPayload;
  final Map<String, dynamic>? serverPayload;
  final int serverRevision;
  final bool resolved;
  final int createdAtMs;

  const SyncConflict({
    required this.id,
    required this.tenantId,
    required this.entity,
    required this.entityId,
    required this.localPayload,
    this.serverPayload,
    required this.serverRevision,
    required this.resolved,
    required this.createdAtMs,
  });

  /// String form of the integer PK, for UI keys.
  String get conflictId => id.toString();

  String get operation => '${localPayload['_op'] ?? 'update'}';
  String get reason => '${localPayload['_reason'] ?? 'conflict'}';
  bool get isFinancial => localPayload['_financial'] == true;
  String get status => resolved ? 'resolved' : 'unresolved';

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true)
          .toLocal();

  /// Payload safe to re-enqueue (review metadata stripped).
  Map<String, dynamic> get cleanLocalPayload => {
        for (final e in localPayload.entries)
          if (!e.key.startsWith('_')) e.key: e.value,
      };

  static Map<String, dynamic>? _decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return null;
    }
  }

  factory SyncConflict.fromRow(Map<String, dynamic> r) {
    return SyncConflict(
      id: (r['id'] as num).toInt(),
      tenantId: (r['tenant_id'] ?? '') as String,
      entity: (r['entity'] ?? '') as String,
      entityId: (r['entity_id'] ?? '') as String,
      localPayload:
          _decode(r['local_payload_json'] as String?) ?? const {},
      serverPayload: _decode(r['server_payload_json'] as String?),
      serverRevision: (r['server_revision'] as num?)?.toInt() ?? 0,
      resolved: ((r['resolved'] as num?)?.toInt() ?? 0) == 1,
      createdAtMs: (r['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}

// ─────────────────────────────────────────────
// Small SQL builder (NULL-safe: emits NULL literals, never null Variables)
// ─────────────────────────────────────────────

class _ColSet {
  final List<String> cols = [];
  final List<String> holders = [];
  final List<Variable> vars = [];

  void add(String col, Object? v) {
    cols.add(col);
    if (v == null) {
      holders.add('NULL');
    } else {
      holders.add('?');
      vars.add(_toVariable(v));
    }
  }

  String get colList => cols.join(', ');
  String get holderList => holders.join(', ');
}

Variable _toVariable(Object v) {
  if (v is int) return Variable.withInt(v);
  if (v is double) return Variable.withReal(v);
  if (v is bool) return Variable.withBool(v);
  return Variable.withString('$v');
}

// ─────────────────────────────────────────────
// LocalRows — envelope read helpers shared by repositories
// ─────────────────────────────────────────────

/// Read helpers for the envelope tables (`data` JSON + indexed columns).
/// Returned maps carry the raw SQL columns plus the decoded payload under
/// the `_data` key.
class LocalRows {
  LocalRows._();

  static Map<String, dynamic>? _decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _withData(Map<String, dynamic> row) {
    final decoded = _decode(row['data'] as String?) ?? const {};
    return {...row, '_data': decoded};
  }

  static Future<Map<String, dynamic>?> byId(
    AppDatabase db,
    String table,
    String tenantId,
    String id,
  ) async {
    try {
      final rows = await db
          .customSelect(
            'SELECT * FROM $table WHERE id = ? AND tenant_id = ? '
            'AND deleted_at IS NULL LIMIT 1',
            variables: [
              Variable.withString(id),
              Variable.withString(tenantId),
            ],
          )
          .get();
      if (rows.isEmpty) return null;
      return _withData(rows.first.data);
    } catch (_) {
      return null;
    }
  }

  /// Raw SELECT passthrough. The query MUST include a `data` column (or
  /// alias) for the decoded payload.
  static Future<List<Map<String, dynamic>>> query(
    AppDatabase db,
    String sql, [
    List<Variable> variables = const [],
  ]) async {
    try {
      final rows =
          await db.customSelect(sql, variables: variables).get();
      return rows.map((r) => _withData(r.data)).toList();
    } catch (_) {
      return [];
    }
  }
}

// ─────────────────────────────────────────────
// SyncQueue — enqueue helper shared by repositories
// ─────────────────────────────────────────────

/// Static helpers for the `sync_queue` table, used by repositories inside
/// their own write transactions (local upsert + enqueue are atomic).
class SyncQueue {
  SyncQueue._();

  /// Insert a pending op. `operation` is one of create/update/delete (the
  /// engine maps create→insert for the RPC). Callers must invoke this
  /// inside the same transaction as the local row write (crash safety).
  static Future<void> enqueue(
    AppDatabase db, {
    required String tenantId,
    required String entity,
    required String entityId,
    required String operation, // create | update | delete
    required Map<String, dynamic> payload,
    required int baseRevision,
  }) async {
    await db.customInsert(
      'INSERT INTO sync_queue '
      '(operation_id, tenant_id, entity, entity_id, operation, '
      ' payload_json, base_revision, created_at, sync_status, '
      ' retry_count, last_error, next_retry_at) '
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, NULL, NULL)",
      variables: [
        Variable.withString(_uuid.v4()),
        Variable.withString(tenantId),
        Variable.withString(entity),
        Variable.withString(entityId),
        Variable.withString(operation),
        Variable.withString(jsonEncode(payload)),
        Variable.withInt(baseRevision),
        Variable.withInt(_nowMs()),
      ],
    );
  }

  /// Whether a local envelope row exists (classifies the op create/update).
  static Future<bool> rowExists(
    AppDatabase db,
    String table,
    String tenantId,
    String id,
  ) async {
    try {
      final rows = await db
          .customSelect(
            'SELECT 1 FROM $table WHERE id = ? AND tenant_id = ? LIMIT 1',
            variables: [
              Variable.withString(id),
              Variable.withString(tenantId),
            ],
          )
          .get();
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Last known server `revision` for a local row (0 when unknown) — the
  /// `base_revision` for the next push of this row.
  static Future<int> currentRevision(
    AppDatabase db,
    String table,
    String tenantId,
    String id,
  ) async {
    try {
      final rows = await db
          .customSelect(
            'SELECT server_revision FROM $table '
            'WHERE id = ? AND tenant_id = ? LIMIT 1',
            variables: [
              Variable.withString(id),
              Variable.withString(tenantId),
            ],
          )
          .get();
      if (rows.isEmpty) return 0;
      return (rows.first.data['server_revision'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

// ─────────────────────────────────────────────
// Internal queue-row view
// ─────────────────────────────────────────────

class _QueueRow {
  final String operationId;
  final String tenantId;
  final String entity;
  final String entityId;
  final String operation; // create | update | delete
  final String payloadJson;
  final int baseRevision;
  final int createdAtMs;
  final String syncStatus;
  final int retryCount;

  _QueueRow({
    required this.operationId,
    required this.tenantId,
    required this.entity,
    required this.entityId,
    required this.operation,
    required this.payloadJson,
    required this.baseRevision,
    required this.createdAtMs,
    required this.syncStatus,
    required this.retryCount,
  });

  factory _QueueRow.fromData(Map<String, dynamic> d) => _QueueRow(
        operationId: (d['operation_id'] ?? '') as String,
        tenantId: (d['tenant_id'] ?? '') as String,
        entity: (d['entity'] ?? '') as String,
        entityId: (d['entity_id'] ?? '') as String,
        operation: (d['operation'] ?? '') as String,
        payloadJson: (d['payload_json'] ?? '{}') as String,
        baseRevision: (d['base_revision'] as num?)?.toInt() ?? 0,
        createdAtMs: (d['created_at'] as num?)?.toInt() ?? 0,
        syncStatus: (d['sync_status'] ?? '') as String,
        retryCount: (d['retry_count'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> get payload {
    try {
      return Map<String, dynamic>.from(jsonDecode(payloadJson) as Map);
    } catch (_) {
      return const {};
    }
  }

  /// The RPC wants 'insert', the queue stores 'create'.
  String get rpcOp => operation == 'create' ? 'insert' : operation;
}

// ─────────────────────────────────────────────
// SyncEngine
// ─────────────────────────────────────────────

class SyncEngine {
  SyncEngine({required AppDatabase db, required String tenantId})
      : _db = db,
        _tenantId = tenantId;

  final AppDatabase _db;
  final String _tenantId;

  String get tenantId => _tenantId;

  final _events = StreamController<SyncEvent>.broadcast();

  /// Broadcast lifecycle events (see [SyncEvent]).
  Stream<SyncEvent> get events => _events.stream;

  final _lastSyncAt = StreamController<DateTime?>.broadcast();

  /// Emits the wall-clock time of the last completed [syncNow].
  Stream<DateTime?> get lastSyncAt => _lastSyncAt.stream;
  DateTime? _lastSyncValue;

  /// Latest value of [lastSyncAt] (null until the first completed sync).
  DateTime? get lastSyncValue => _lastSyncValue;

  StreamSubscription<dynamic>? _connectivitySub;
  bool _started = false;
  bool _syncRunning = false;
  bool _disposed = false;

  // ── lifecycle ──────────────────────────────────────────────

  /// Fire-and-forget wrapper: logs failures to the file log instead of
  /// letting them escape as uncaught async errors (which would surface the
  /// crash screen for a background sync hiccup).
  void _fireAndForget(Future<void> task, String name) {
    unawaited(task.then((_) {}, onError: (Object e, StackTrace st) {
      AppLogger().error('sync.$name failed',
          error: e, stackTrace: st, context: {'tenant_id': _tenantId});
    }));
  }

  /// Subscribe to connectivity changes and reclaim stale claims.
  /// Idempotent. Called by [syncEngineProvider] on creation.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    // Crash safety: rows left 'in_progress' by a dead process (lease
    // expired) go back to 'pending'.
    _fireAndForget(_reclaimStaleClaims(), 'reclaimStaleClaims');
    // Version-tolerant connectivity listener (connectivity_plus 5.x emits
    // List<ConnectivityResult>; older versions emit a single value).
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (dynamic event) {
        final results = event is List ? event : [event];
        final online =
            results.any((r) => r != ConnectivityResult.none);
        if (online) _fireAndForget(syncNow(), 'syncNow');
      },
      onError: (Object e, StackTrace st) {
        // Phase 7: classify + log through the error boundary instead of
        // swallowing. No UX change — sync retries on the next trigger.
        ErrorBoundary.handleErrorSimple(e, st, tag: 'sync/connectivity');
      },
    );
  }

  /// Hook point for app-resume: wire to
  /// `WidgetsBindingObserver.didChangeAppLifecycleState(AppLifecycleState.resumed)`.
  void notifyAppResumed() {
    if (!_started || _disposed) return;
    _fireAndForget(syncNow(), 'syncNow');
  }

  /// Repositories call this after a local write + enqueue so UI counters
  /// and streams refresh immediately.
  void notifyLocalChange() {
    if (_disposed) return;
    _events.add(SyncEvent.localChanged);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectivitySub?.cancel();
    _events.close();
    _lastSyncAt.close();
  }

  // ── connectivity ───────────────────────────────────────────

  Future<bool> _isOnline() async {
    try {
      final dynamic result = await Connectivity().checkConnectivity();
      final results = result is List ? result : [result];
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  // ── top-level ──────────────────────────────────────────────

  /// Full cycle: push local ops first, then pull server changes.
  /// No-op when offline or when a cycle is already running.
  ///
  /// Never throws: a background sync hiccup must not surface as an
  /// uncaught async error (crash screen). Failures are logged to the
  /// file log with the tenant id and retried on the next trigger.
  Future<void> syncNow() async {
    if (_syncRunning || _disposed) return;
    if (!await _isOnline()) return;
    _syncRunning = true;
    try {
      await pushOnce();
      await pullOnce();
      _lastSyncValue = DateTime.now();
      if (!_disposed) {
        _lastSyncAt.add(_lastSyncValue);
        _events.add(SyncEvent.syncCompleted);
      }
    } catch (e, st) {
      // Phase 7: classify via the error boundary (taxonomy + health
      // counters + file log) instead of a bare log line. Same UX — the
      // failure is swallowed here and retried on the next trigger.
      ErrorBoundary.logOnly(e, st, tag: 'sync/syncNow');
    } finally {
      _syncRunning = false;
    }
  }

  // ── PUSH ───────────────────────────────────────────────────

  /// Push all due queue rows for the active tenant, FIFO per entity.
  Future<void> pushOnce() async {
    if (!await _isOnline()) return;
    final entities = await _pendingEntities();
    for (final entity in entities) {
      await _claimBatch(entity);
      final rows = await _claimedRows(entity);
      for (final row in rows) {
        await _pushRow(row);
        if (!await _isOnline()) return; // went offline mid-push
      }
    }
    if (!_disposed) _events.add(SyncEvent.pushCompleted);
  }

  /// Entities with due work, oldest-first (drives FIFO-per-entity order).
  /// Includes `failed` rows whose backoff has expired (they re-enter the
  /// queue); `dead_letter` rows are never auto-retried.
  Future<List<String>> _pendingEntities() async {
    final now = _nowMs();
    final rows = await _db
        .customSelect(
          'SELECT entity FROM sync_queue '
          "WHERE tenant_id = ? AND sync_status IN ('pending','failed') "
          'AND (next_retry_at IS NULL OR next_retry_at <= ?) '
          'GROUP BY entity ORDER BY MIN(created_at)',
          variables: [
            Variable.withString(_tenantId),
            Variable.withInt(now),
          ],
        )
        .get();
    return rows.map((r) => (r.data['entity'] ?? '') as String).toList();
  }

  /// Atomically claim up to [_claimBatchSize] due rows for [entity]
  /// (`pending`, plus `failed` rows whose backoff expired), stamping a
  /// 10-minute lease in `next_retry_at` (crash-safety, see [start]).
  Future<void> _claimBatch(String entity) async {
    final now = _nowMs();
    final leaseUntil = now + _claimLeaseMs;
    await _db.customUpdate(
      'UPDATE sync_queue SET sync_status = ?, next_retry_at = ? '
      'WHERE operation_id IN ('
      '  SELECT operation_id FROM sync_queue '
      "  WHERE tenant_id = ? AND entity = ? "
      "  AND sync_status IN ('pending','failed') "
      '  AND (next_retry_at IS NULL OR next_retry_at <= ?) '
      '  ORDER BY created_at LIMIT ?'
      ')',
      variables: [
        Variable.withString('in_progress'),
        Variable.withInt(leaseUntil),
        Variable.withString(_tenantId),
        Variable.withString(entity),
        Variable.withInt(now),
        Variable.withInt(_claimBatchSize),
      ],
    );
  }

  Future<List<_QueueRow>> _claimedRows(String entity) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM sync_queue '
          "WHERE tenant_id = ? AND entity = ? AND sync_status = 'in_progress' "
          'ORDER BY created_at',
          variables: [
            Variable.withString(_tenantId),
            Variable.withString(entity),
          ],
        )
        .get();
    return rows.map((r) => _QueueRow.fromData(r.data)).toList();
  }

  /// Reclaim rows whose claim lease expired (previous process died mid-push).
  Future<void> _reclaimStaleClaims() async {
    final now = _nowMs();
    await _db.customUpdate(
      'UPDATE sync_queue SET sync_status = ?, next_retry_at = NULL '
      "WHERE tenant_id = ? AND sync_status = 'in_progress' "
      'AND next_retry_at IS NOT NULL AND next_retry_at < ?',
      variables: [
        Variable.withString('pending'),
        Variable.withString(_tenantId),
        Variable.withInt(now),
      ],
    );
  }

  /// Push one claimed row through the `sync_apply` RPC.
  ///
  /// ORDERING RULE: file bytes must reach the bucket BEFORE any DB row
  /// referencing the future public URL is pushed. A queue row carrying a
  /// `_pending_upload_id` payload key is not releasable until its upload
  /// is done — the RPC must never see a URL the server cannot resolve yet.
  Future<void> _pushRow(_QueueRow row) async {
    final uploadId = row.payload['_pending_upload_id'];
    if (uploadId is String && uploadId.isNotEmpty) {
      if (!await _ensureUploadDone(uploadId)) {
        // Upload not complete: keep the row queued with backoff.
        await _recordFailure(row, 'pending upload not complete');
        return;
      }
    }
    final result = await _callSyncApply(
      entity: row.entity,
      entityId: row.entityId,
      baseRevision: row.baseRevision,
      payload: _rpcPayload(row),
      op: row.rpcOp,
    );
    if (result == null) {
      // Transport / timeout / went-offline: backoff, keep queued.
      await _recordFailure(row, 'transport error');
      return;
    }

    if (result['ok'] == true) {
      final newRev =
          (result['new_revision'] as num?)?.toInt() ?? row.baseRevision;
      await _markDone(row, newRev);
      return;
    }
    final reason = '${result['reason'] ?? 'unknown'}';
    if (reason == 'not_found' || reason == 'already_deleted') {
      // Row is gone remotely (deleted, or an update/delete for a missing
      // or already-tombstoned row): converge by dropping the local row
      // and completing the op.
      await _convergeRowDeleted(row);
      return;
    }
    if (_conflictReasons.contains(reason)) {
      await _handleConflict(row, result);
      return;
    }
    await _recordFailure(row, 'server: $reason');
  }

  /// Call the RPC. Returns the decoded JSONB map, or null on
  /// transport/timeout failure. Param names are the function's `p_*`
  /// argument names (PostgREST binds by name).
  Future<Map<String, dynamic>?> _callSyncApply({
    required String entity,
    required String entityId,
    required int baseRevision,
    required Map<String, dynamic> payload,
    required String op, // insert | update | delete
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final raw = await SupabaseService.client
          .rpc('sync_apply', params: {
            'p_entity': entity,
            'p_entity_id': entityId,
            'p_base_revision': baseRevision,
            'p_payload': payload,
            'p_op': op,
          })
          .timeout(timeout);
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return {'ok': false, 'reason': 'bad_rpc_shape'};
    } catch (_) {
      return null;
    }
  }

  /// The payload actually sent to the RPC: engine-local metadata keys
  /// (everything starting with '_', e.g. `_pending_upload_id`) are
  /// stripped — the server must never see them.
  static Map<String, dynamic> _rpcPayload(_QueueRow row) {
    final payload = Map<String, dynamic>.from(row.payload);
    payload.removeWhere((k, _) => k.startsWith('_'));
    return payload;
  }

  /// Ensures the storage upload behind [uploadId] has completed.
  ///
  /// Returns true when the `pending_uploads` row is missing or already
  /// `done` (nothing to wait for); performs the storage op
  /// (`upload`: `uploadBinary` with upsert; `delete`: `remove`) and marks
  /// the row `done` on success; on any error marks it `failed` with
  /// `retry_count + 1` and returns false.
  Future<bool> _ensureUploadDone(String uploadId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM pending_uploads WHERE id = ? LIMIT 1',
          variables: [Variable.withString(uploadId)],
        )
        .get();
    if (rows.isEmpty) return true; // unknown upload: nothing to wait for
    final data = rows.first.data;
    if ('${data['status']}' == 'done') return true;

    final op = '${data['op']}';
    final bucket = '${data['bucket']}';
    final destPath = '${data['dest_path']}';
    final localPath = data['local_path'] as String?;
    try {
      if (op == 'upload') {
        if (localPath == null || localPath.isEmpty) {
          throw StateError('pending upload $uploadId has no local_path');
        }
        final bytes = await File(localPath).readAsBytes();
        await SupabaseService.client.storage
            .from(bucket)
            .uploadBinary(
              destPath,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
      } else if (op == 'delete') {
        await SupabaseService.client.storage.from(bucket).remove([destPath]);
      } else {
        throw StateError('unknown pending upload op: $op');
      }
      await _db.customUpdate(
        "UPDATE pending_uploads SET status = 'done', error = NULL "
        'WHERE id = ?',
        variables: [Variable.withString(uploadId)],
      );
      return true;
    } catch (e) {
      final attempts = ((data['retry_count'] as num?)?.toInt() ?? 0) + 1;
      await _db.customUpdate(
        'UPDATE pending_uploads SET status = ?, retry_count = ?, error = ? '
        'WHERE id = ?',
        variables: [
          Variable.withString('failed'),
          Variable.withInt(attempts),
          Variable.withString('$e'),
          Variable.withString(uploadId),
        ],
      );
      return false;
    }
  }

  /// Success: mark the queue row done AND stamp the local envelope's
  /// `server_revision` in the SAME transaction (crash safety).
  Future<void> _markDone(_QueueRow row, int newRevision) async {
    final table = _localTables[row.entity];
    await _db.transaction(() async {
      await _completeQueueRow(row.operationId);
      if (table != null) {
        // Entities without a local table (e.g. 'fees') skip this step.
        await _db.customUpdate(
          'UPDATE $table SET server_revision = ? '
          'WHERE id = ? AND tenant_id = ?',
          variables: [
            Variable.withInt(newRevision),
            Variable.withString(row.entityId),
            Variable.withString(row.tenantId),
          ],
        );
      }
    });
  }

  Future<void> _completeQueueRow(String operationId) async {
    await _db.customUpdate(
      "UPDATE sync_queue SET sync_status = 'done', last_error = NULL, "
      'next_retry_at = NULL WHERE operation_id = ?',
      variables: [Variable.withString(operationId)],
    );
  }

  Future<void> _parkQueueRow(String operationId, String message) async {
    await _db.customUpdate(
      "UPDATE sync_queue SET sync_status = 'dead_letter', last_error = ?, "
      'next_retry_at = NULL WHERE operation_id = ?',
      variables: [
        Variable.withString(message),
        Variable.withString(operationId),
      ],
    );
  }

  /// Server reports the row gone: drop the local envelope row (if any)
  /// and complete the queue op — both sides converge on "deleted".
  Future<void> _convergeRowDeleted(_QueueRow row) async {
    final table = _localTables[row.entity];
    await _db.transaction(() async {
      if (table != null) {
        await _db.customStatement(
          'DELETE FROM $table WHERE id = ? AND tenant_id = ?',
          [
            Variable.withString(row.entityId),
            Variable.withString(row.tenantId),
          ],
        );
      }
      await _completeQueueRow(row.operationId);
    });
  }

  /// Failure: exponential backoff — 5s, 10s, 20s, 40s — then dead_letter
  /// after the 5th failure. Dead letters are surfaced via
  /// `pendingSyncCountProvider`.
  Future<void> _recordFailure(_QueueRow row, String error) async {
    final failures = row.retryCount + 1;
    if (failures >= _maxRetries) {
      await _db.customUpdate(
        "UPDATE sync_queue SET sync_status = 'dead_letter', "
        'retry_count = ?, last_error = ?, next_retry_at = NULL '
        'WHERE operation_id = ?',
        variables: [
          Variable.withInt(failures),
          Variable.withString(error),
          Variable.withString(row.operationId),
        ],
      );
      return;
    }
    final delayMs = _baseBackoffMs * (1 << (failures - 1)); // 5s,10s,20s,40s
    final nextRetry = _nowMs() + delayMs;
    await _db.customUpdate(
      "UPDATE sync_queue SET sync_status = 'failed', retry_count = ?, "
      'last_error = ?, next_retry_at = ? WHERE operation_id = ?',
      variables: [
        Variable.withInt(failures),
        Variable.withString(error),
        Variable.withInt(nextRetry),
        Variable.withString(row.operationId),
      ],
    );
  }

  // ── conflict handling (mission §23, per 016_sync.sql) ─────────

  /// Conflict-resolution rules (documented per mission §23):
  ///
  /// The RPC conflict payload is `{ok:false, reason, server_revision,
  /// server_row, financial}` where `financial` is authoritative (the
  /// server's own entity list). `server_revision` is the server row's
  /// current optimistic-concurrency `revision` (NOT `server_version`).
  ///
  /// FINANCIAL entities — on ANY conflict: write a `sync_conflicts` row
  /// and NEVER overwrite server data. The local row is left untouched
  /// (dirty-flagged for review via the conflict record); the queue row is
  /// parked as `dead_letter` so push never retries it automatically.
  ///
  /// NORMAL entities — "latest valid revision wins":
  ///   1. If the server row exists and `server.updated_at` is NEWER than
  ///      the local change → take the server row (apply locally, queue → done).
  ///   2. Otherwise (local is newer or timestamps tie) → rebase the local
  ///      op onto the fresh `base_revision` (= `server_revision`) and
  ///      retry the RPC exactly ONCE.
  ///   3. If the retry still conflicts → park in `sync_conflicts`.
  ///   4. If the server row is gone (`deleted` reason / null row) → take
  ///      the server state: drop the local row, queue → done.
  Future<void> _handleConflict(
      _QueueRow row, Map<String, dynamic> rpc) async {
    final reason = '${rpc['reason'] ?? 'conflict'}';
    final serverFinancial = rpc['financial'] == true;
    final isFinancial = isFinancialConflict(
        serverFinancialFlag: serverFinancial, entity: row.entity);
    Map<String, dynamic>? serverRow = rpc['server_row'] is Map
        ? Map<String, dynamic>.from(rpc['server_row'] as Map)
        : null;
    final serverRevision = (rpc['server_revision'] as num?)?.toInt() ?? 0;

    if (isFinancial) {
      await _db.transaction(() async {
        await _insertConflict(row, serverRow, serverRevision,
            reason: reason, financial: true);
        await _parkQueueRow(
            row.operationId, 'financial conflict — held for review');
      });
      return;
    }

    // ── normal entity ──
    serverRow ??= await _fetchServerRow(row);
    if (serverRow == null || reason == 'deleted') {
      // Server deleted it (or it never existed there): take the server
      // state — drop the local envelope row, complete the op.
      await _convergeRowDeleted(row);
      return;
    }

    final serverUpdatedAt = _parseTime(serverRow['updated_at']);
    final localUpdatedAt = _parseTime(row.payload['updated_at']) ??
        DateTime.fromMillisecondsSinceEpoch(row.createdAtMs, isUtc: true);

    final decision = decideNormalConflict(
        serverUpdatedAt: serverUpdatedAt, localUpdatedAt: localUpdatedAt);
    if (decision == NormalConflictDecision.takeServer) {
      // Server is newer (or local time unknown) → take the server row.
      await _db.transaction(() async {
        await _applyServerRow(row.entity, serverRow!);
        await _completeQueueRow(row.operationId);
      });
      return;
    }

    // Local is newer (or tie) → rebase onto the fresh base_revision and
    // retry the RPC exactly once.
    final retry = await _callSyncApply(
      entity: row.entity,
      entityId: row.entityId,
      baseRevision: serverRevision,
      payload: _rpcPayload(row),
      op: row.rpcOp,
    );
    if (retry != null && retry['ok'] == true) {
      final newRev =
          (retry['new_revision'] as num?)?.toInt() ?? serverRevision;
      await _markDone(row, newRev);
      return;
    }
    if (retry == null) {
      await _recordFailure(row, 'rebase transport error');
      return;
    }
    // Retry still rejected → park for human review.
    Map<String, dynamic>? latest = retry['server_row'] is Map
        ? Map<String, dynamic>.from(retry['server_row'] as Map)
        : await _fetchServerRow(row);
    final latestRev =
        (retry['server_revision'] as num?)?.toInt() ?? serverRevision;
    await _db.transaction(() async {
      await _insertConflict(row, latest, latestRev,
          reason: 'conflict_after_rebase', financial: false);
      await _parkQueueRow(row.operationId,
          'conflict persisted after rebase — held for review');
    });
  }

  /// Fetch the authoritative server row for a conflicted entity
  /// (fallback when the RPC omits `server_row`).
  Future<Map<String, dynamic>?> _fetchServerRow(_QueueRow row) async {
    final serverTable = _serverTables[row.entity];
    if (serverTable == null) return null;
    try {
      final res = await SupabaseService.client
          .from(serverTable)
          .select()
          .eq('tenant_id', row.tenantId)
          .eq('id', row.entityId)
          .maybeSingle()
          .timeout(const Duration(seconds: 30));
      if (res == null) return null;
      return Map<String, dynamic>.from(res as Map);
    } catch (_) {
      return null;
    }
  }

  /// Park a conflict for human review. Review metadata (`_op`, `_reason`,
  /// `_financial`) is encoded inside `local_payload_json` — the sibling's
  /// table has no dedicated columns for it.
  Future<void> _insertConflict(
    _QueueRow row,
    Map<String, dynamic>? serverRow,
    int serverRevision, {
    required String reason,
    required bool financial,
  }) async {
    final localWithMeta = {
      ...row.payload,
      '_op': row.operation,
      '_reason': reason,
      '_financial': financial,
    };
    final cs = _ColSet()
      ..add('tenant_id', row.tenantId)
      ..add('entity', row.entity)
      ..add('entity_id', row.entityId)
      ..add('local_payload_json', jsonEncode(localWithMeta))
      ..add('server_payload_json',
          serverRow == null ? '' : jsonEncode(serverRow))
      ..add('server_revision', serverRevision)
      ..add('created_at', _nowMs())
      ..add('resolved', 0);
    await _db.customInsert(
      'INSERT INTO sync_conflicts (${cs.colList}) VALUES (${cs.holderList})',
      variables: cs.vars,
    );
  }

  // ── conflict review actions (used by conflict_review_screen.dart) ──

  Future<SyncConflict?> _getConflict(int id) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM sync_conflicts WHERE id = ? AND tenant_id = ? '
          'LIMIT 1',
          variables: [
            Variable.withInt(id),
            Variable.withString(_tenantId),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    return SyncConflict.fromRow(rows.first.data);
  }

  /// "Keep server": discard the local change, apply the fresh server row
  /// locally, resolve the conflict and complete the parked queue row.
  Future<void> resolveConflictKeepServer(int conflictId) async {
    final conflict = await _getConflict(conflictId);
    if (conflict == null || conflict.resolved) return;
    final serverTable =
        _serverTables[conflict.entity] ?? conflict.entity;
    Map<String, dynamic>? serverRow;
    try {
      final res = await SupabaseService.client
          .from(serverTable)
          .select()
          .eq('tenant_id', _tenantId)
          .eq('id', conflict.entityId)
          .maybeSingle()
          .timeout(const Duration(seconds: 30));
      if (res != null) {
        serverRow = Map<String, dynamic>.from(res as Map);
      }
    } catch (_) {/* treat as deleted */}
    final table = _localTables[conflict.entity];
    await _db.transaction(() async {
      if (table != null) {
        if (serverRow != null) {
          await _applyServerRow(conflict.entity, serverRow);
        } else {
          // Server row deleted remotely → drop the local row too.
          await _db.customStatement(
            'DELETE FROM $table WHERE id = ? AND tenant_id = ?',
            [
              Variable.withString(conflict.entityId),
              Variable.withString(_tenantId),
            ],
          );
        }
      }
      await _db.customUpdate(
        "UPDATE sync_queue SET sync_status = 'done', last_error = NULL, "
        'next_retry_at = NULL '
        "WHERE tenant_id = ? AND entity = ? AND entity_id = ? "
        "AND sync_status <> 'done'",
        variables: [
          Variable.withString(_tenantId),
          Variable.withString(conflict.entity),
          Variable.withString(conflict.entityId),
        ],
      );
      await _markConflictResolved(conflict, 'kept_server');
    });
    notifyLocalChange();
  }

  /// "Retry local as new revision": re-enqueue the local payload with a
  /// fresh base_revision. NON-FINANCIAL entities only — financial conflicts
  /// must be corrected through the finance reversal flow.
  Future<void> resolveConflictRetryLocal(int conflictId) async {
    final conflict = await _getConflict(conflictId);
    if (conflict == null || conflict.resolved) return;
    if (conflict.isFinancial) {
      throw StateError(
          'Financial entity ${conflict.entity}: corrections must go '
          'through the finance reversal flow, not sync retry.');
    }
    int freshBase = conflict.serverRevision;
    if (freshBase == 0) {
      final serverTable =
          _serverTables[conflict.entity] ?? conflict.entity;
      try {
        final res = await SupabaseService.client
            .from(serverTable)
            .select('revision')
            .eq('tenant_id', _tenantId)
            .eq('id', conflict.entityId)
            .maybeSingle()
            .timeout(const Duration(seconds: 30));
        if (res != null) {
          freshBase = ((res as Map)['revision'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {/* keep 0 */}
    }
    await _db.transaction(() async {
      await SyncQueue.enqueue(
        _db,
        tenantId: _tenantId,
        entity: conflict.entity,
        entityId: conflict.entityId,
        operation: conflict.operation,
        payload: conflict.cleanLocalPayload,
        baseRevision: freshBase,
      );
      await _markConflictResolved(conflict, 'retried_local');
    });
    notifyLocalChange();
    _fireAndForget(syncNow(), 'syncNow');
  }

  Future<void> _markConflictResolved(
      SyncConflict conflict, String resolution) async {
    final local = Map<String, dynamic>.from(conflict.localPayload)
      ..['_resolution'] = resolution
      ..['_resolved_at'] = _nowMs();
    await _db.customUpdate(
      'UPDATE sync_conflicts SET resolved = 1, local_payload_json = ? '
      'WHERE id = ? AND tenant_id = ?',
      variables: [
        Variable.withString(jsonEncode(local)),
        Variable.withInt(conflict.id),
        Variable.withString(_tenantId),
      ],
    );
  }

  // ── PULL ───────────────────────────────────────────────────

  /// Pull server changes per entity using `sync_state` watermarks.
  Future<void> pullOnce() async {
    if (!await _isOnline()) return;
    for (final entity in _pullEntities) {
      try {
        await _pullEntity(entity);
      } catch (e, st) {
        // One entity's pull must not abort the others; the watermark only
        // advances inside the transaction that applied the rows.
        // Phase 7: classify + log through the error boundary (same UX).
        ErrorBoundary.handleErrorSimple(e, st, tag: 'sync/pull:$entity');
      }
    }
    if (!_disposed) _events.add(SyncEvent.pullCompleted);
  }

  Future<void> _pullEntity(String entity) async {
    final serverTable = _serverTables[entity]!;
    final startWm = await _getWatermark(entity);
    var liveMax = startWm;

    // Rows the pull side must not clobber: unpushed local work (any
    // non-done queue entry) or rows parked in unresolved conflicts.
    final protected = await _protectedEntityIds(entity);

    // Pass 1: live rows (deleted_at IS NULL), paged by server_version.
    var pages = 0;
    while (pages++ < _pullMaxPages) {
      final raw = await SupabaseService.client
          .from(serverTable)
          .select()
          .eq('tenant_id', _tenantId)
          .gt('server_version', liveMax)
          .isFilter('deleted_at', null)
          .order('server_version')
          .limit(_pullPageSize)
          .timeout(const Duration(seconds: 30));
      final rows = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (rows.isEmpty) break;

      var pageMax = liveMax;
      await _db.transaction(() async {
        for (final r in rows) {
          final id = '${r['id']}';
          if (!protected.contains(id)) {
            await _applyServerRow(entity, r);
          }
          // The watermark advances over ALL fetched rows — even protected
          // ones, which converge via push/review. (Not advancing would
          // re-pull them forever against our own pending writes.)
          pageMax = max(pageMax, _serverVersionOf(r));
        }
        await _setWatermark(entity, pageMax);
      });
      liveMax = pageMax;
      if (rows.length < _pullPageSize) break;
    }

    // Pass 2: tombstones (deleted_at NOT NULL) since the ORIGINAL
    // watermark — interleaved versions are safe because deletes are
    // idempotent and the final watermark is max(live, tombstone).
    var tombMax = startWm;
    pages = 0;
    while (pages++ < _pullMaxPages) {
      final raw = await SupabaseService.client
          .from(serverTable)
          .select('id, server_version')
          .eq('tenant_id', _tenantId)
          .gt('server_version', tombMax)
          .not('deleted_at', 'is', null)
          .order('server_version')
          .limit(_pullPageSize)
          .timeout(const Duration(seconds: 30));
      final tombs = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (tombs.isEmpty) break;
      final table = _localTables[entity]!;
      await _db.transaction(() async {
        for (final t in tombs) {
          final id = '${t['id']}';
          if (!protected.contains(id)) {
            await _db.customStatement(
              'DELETE FROM $table WHERE id = ? AND tenant_id = ?',
              [
                Variable.withString(id),
                Variable.withString(_tenantId),
              ],
            );
          }
          tombMax = max(tombMax, _serverVersionOf(t));
        }
        await _setWatermark(entity, max(liveMax, tombMax));
      });
      if (tombs.length < _pullPageSize) break;
    }
  }

  /// Entity ids the pull side must not touch for [entity].
  Future<Set<String>> _protectedEntityIds(String entity) async {
    final rows = await _db
        .customSelect(
          'SELECT entity_id FROM sync_queue WHERE tenant_id = ? '
          "AND entity = ? AND sync_status <> 'done' "
          'UNION '
          'SELECT entity_id FROM sync_conflicts WHERE tenant_id = ? '
          'AND entity = ? AND resolved = 0',
          variables: [
            Variable.withString(_tenantId),
            Variable.withString(entity),
            Variable.withString(_tenantId),
            Variable.withString(entity),
          ],
        )
        .get();
    return rows.map((r) => '${r.data['entity_id']}').toSet();
  }

  Future<int> _getWatermark(String entity) async {
    final rows = await _db
        .customSelect(
          'SELECT last_server_version FROM sync_state '
          'WHERE entity = ? AND tenant_id = ? LIMIT 1',
          variables: [
            Variable.withString(entity),
            Variable.withString(_tenantId),
          ],
        )
        .get();
    if (rows.isEmpty) return 0;
    return (rows.first.data['last_server_version'] as num?)?.toInt() ?? 0;
  }

  Future<void> _setWatermark(String entity, int watermark) async {
    await _db.customInsert(
      'INSERT INTO sync_state '
      '(entity, tenant_id, last_server_version, last_pull_at) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT(entity, tenant_id) DO UPDATE SET '
      'last_server_version = excluded.last_server_version, '
      'last_pull_at = excluded.last_pull_at',
      variables: [
        Variable.withString(entity),
        Variable.withString(_tenantId),
        Variable.withInt(watermark),
        Variable.withInt(_nowMs()),
      ],
    );
  }

  // ── envelope writes ────────────────────────────────────────

  /// Next local `revision` for an envelope row (starts at 1).
  Future<int> _nextLocalRevision(String table, String id) async {
    try {
      final rows = await _db
          .customSelect(
            'SELECT revision FROM $table WHERE id = ? LIMIT 1',
            variables: [Variable.withString(id)],
          )
          .get();
      if (rows.isEmpty) return 1;
      return ((rows.first.data['revision'] as num?)?.toInt() ?? 0) + 1;
    } catch (_) {
      return 1;
    }
  }

  /// Local-first write of a user edit: upserts the envelope row (indexed
  /// columns + `data` JSON), bumps the local `revision`, refreshes
  /// `updated_at`, and PRESERVES `server_revision` (only a successful push
  /// stamps it) and `deleted_at`.
  ///
  /// Always call inside the same transaction as [SyncQueue.enqueue].
  static Future<void> writeLocalRow(
    AppDatabase db, {
    required String table,
    required String id,
    required String tenantId,
    required Map<String, Object?> indexed,
    required Map<String, Object?> data,
  }) {
    return _writeEnvelope(
      db,
      table: table,
      id: id,
      tenantId: tenantId,
      indexed: indexed,
      data: data,
      preserveServerRevision: true,
      includeDeletedAt: false,
    );
  }

  static Future<int> _localRevisionOf(
      AppDatabase db, String table, String id) async {
    try {
      final rows = await db
          .customSelect(
            'SELECT revision FROM $table WHERE id = ? LIMIT 1',
            variables: [Variable.withString(id)],
          )
          .get();
      if (rows.isEmpty) return 1;
      return ((rows.first.data['revision'] as num?)?.toInt() ?? 0) + 1;
    } catch (_) {
      return 1;
    }
  }

  static Future<void> _writeEnvelope(
    AppDatabase db, {
    required String table,
    required String id,
    required String tenantId,
    required Map<String, Object?> indexed,
    required Map<String, Object?> data,
    required bool preserveServerRevision,
    required bool includeDeletedAt,
    int? updatedAtMs,
    int? serverRevision,
    int? deletedAtMs,
  }) async {
    final rev = await _localRevisionOf(db, table, id);
    final cs = _ColSet()
      ..add('id', id)
      ..add('tenant_id', tenantId);
    for (final e in indexed.entries) {
      cs.add(e.key, e.value);
    }
    cs
      ..add('revision', rev)
      ..add('updated_at', updatedAtMs ?? _nowMs())
      ..add('data', jsonEncode(data));
    if (!preserveServerRevision && serverRevision != null) {
      cs.add('server_revision', serverRevision);
    }
    if (includeDeletedAt) {
      // null emits the NULL literal — clears a stale local tombstone when
      // the server row is live again.
      cs.add('deleted_at', deletedAtMs);
    }
    final sets =
        cs.cols.where((c) => c != 'id').map((c) => '$c = excluded.$c');
    // Columns NOT in the list are never touched: local writes preserve
    // server_revision/deleted_at; pull passes them explicitly.
    await db.customInsert(
      'INSERT INTO $table (${cs.colList}) VALUES (${cs.holderList}) '
      'ON CONFLICT(id) DO UPDATE SET ${sets.join(', ')}',
      variables: cs.vars,
    );
  }

  /// Soft-delete an envelope row locally: sets `deleted_at`, refreshes
  /// `updated_at`, bumps `revision`, and optionally patches the `data`
  /// JSON (e.g. `is_active: false`). The push side sends op `delete`.
  static Future<void> softDeleteLocalRow(
    AppDatabase db, {
    required String table,
    required String id,
    required String tenantId,
    Map<String, Object?>? dataPatch,
  }) async {
    final now = _nowMs();
    Map<String, dynamic> data = {};
    var rev = 1;
    try {
      final rows = await db
          .customSelect(
            'SELECT data, revision FROM $table '
            'WHERE id = ? AND tenant_id = ? LIMIT 1',
            variables: [
              Variable.withString(id),
              Variable.withString(tenantId),
            ],
          )
          .get();
      if (rows.isNotEmpty) {
        try {
          data = Map<String, dynamic>.from(
              jsonDecode(rows.first.data['data'] as String) as Map);
        } catch (_) {/* keep {} */}
        rev = ((rows.first.data['revision'] as num?)?.toInt() ?? 0) + 1;
      }
    } catch (_) {/* keep defaults */}
    if (dataPatch != null) data.addAll(dataPatch);
    await db.customUpdate(
      'UPDATE $table SET deleted_at = ?, updated_at = ?, revision = ?, '
      'data = ? WHERE id = ? AND tenant_id = ?',
      variables: [
        Variable.withInt(now),
        Variable.withInt(now),
        Variable.withInt(rev),
        Variable.withString(jsonEncode(data)),
        Variable.withString(id),
        Variable.withString(tenantId),
      ],
    );
  }

  /// Apply a server row to the local envelope: indexed columns are
  /// best-effort hints (the `data` JSON is authoritative); the local
  /// `revision` counter is preserved; `updated_at`/`deleted_at` mirror the
  /// server's stamps (millis); `server_revision` records the server's
  /// optimistic `revision`.
  ///
  /// No-op for entities without a local table (e.g. `fees`).
  Future<void> _applyServerRow(
      String entity, Map<String, dynamic> row) async {
    final table = _localTables[entity];
    if (table == null) return;
    final id = '${row['id']}';
    final tenant = '${row['tenant_id'] ?? _tenantId}';
    final updatedMs =
        _parseTime(row['updated_at'])?.millisecondsSinceEpoch ?? _nowMs();
    final deletedRaw = row['deleted_at'];
    final deletedMs = deletedRaw == null
        ? null
        : _parseTime(deletedRaw)?.millisecondsSinceEpoch ?? _nowMs();
    await _writeEnvelope(
      _db,
      table: table,
      id: id,
      tenantId: tenant,
      indexed: _envelopeFor(entity, row),
      data: row,
      preserveServerRevision: false,
      includeDeletedAt: true,
      updatedAtMs: updatedMs,
      serverRevision: (row['revision'] as num?)?.toInt(),
      deletedAtMs: deletedMs,
    );
  }

  /// Best-effort extraction of a table's indexed envelope columns from a
  /// server row. Missing/unknown keys become NULL — the `data` JSON stays
  /// the source of truth, these columns only accelerate local queries.
  static Map<String, Object?> _envelopeFor(
      String entity, Map<String, dynamic> row) {
    Object? pick(List<String> keys) {
      for (final k in keys) {
        if (row[k] != null) return row[k];
      }
      return null;
    }

    switch (entity) {
      case 'students':
        return {
          'name': row['name'],
          'roll_no': row['roll_no'],
          'class_id': row['class_id'],
        };
      case 'classes':
        return {
          'name': row['name'],
          'darja_id': row['darja_id'],
        };
      case 'darjas':
        return {
          'name': row['name'],
        };
      case 'attendance':
        return {
          'student_id': row['student_id'],
          'class_id': row['class_id'],
          'date': row['date'],
          'status': row['status'],
        };
      case 'invoices':
        return {
          'student_id': row['student_id'],
          'status': row['status'],
          'total': pick(['total', 'amount_due', 'grand_total']),
        };
      case 'payments':
        return {
          'student_id': row['student_id'],
          'invoice_id': row['invoice_id'],
          'amount': pick(['amount', 'amount_paid']),
        };
      case 'exams':
        return {
          'name': row['name'],
          'class_id': row['class_id'],
        };
      case 'results':
        return {
          'exam_id': row['exam_id'],
          'student_id': row['student_id'],
          'marks': pick(['marks_obtained', 'marks']),
        };
      case 'announcements':
        return {
          'title': row['title'],
          'audience': pick(['audience', 'target']),
        };
      default:
        return const {};
    }
  }

  // ── small helpers ──────────────────────────────────────────

  /// Server `server_version` (BIGINT pull watermark).
  static int _serverVersionOf(Map<String, dynamic> row) =>
      (row['server_version'] as num?)?.toInt() ?? 0;

  static DateTime? _parseTime(dynamic v) {
    if (v == null) return null;
    if (v is int) {
      // Epoch millis (defensive: some payloads may already be numeric).
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    }
    try {
      return DateTime.parse('$v');
    } catch (_) {
      return null;
    }
  }
}
