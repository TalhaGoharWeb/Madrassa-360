/// فیس ریپوزیٹری
/// Fee Repository — QUEUE-FIRST (Phase 5 offline-first sync).
///
/// DOCUMENTED EXCEPTION: the sibling worker's Drift contract
/// (`lib/data/local/app_database.dart`) defines NO local `fees` table, so
/// reads cannot come from Drift. Until a `fees` table is added to the
/// contract, reads stay remote (Supabase) exactly as before. Writes,
/// however, are offline-safe: every write enqueues a `sync_queue` row
/// (entity `fees`) and opportunistically triggers [SyncEngine.syncNow];
/// the engine is the only writer to the server (via the `sync_apply` RPC).
/// Direct Supabase writes are FORBIDDEN in this repository.
///
/// Coordinator follow-up: add a `fees` Drift table (+ server `server_version`
/// / `deleted_at` columns) and this repository becomes fully local-first
/// with no signature changes.
///
/// Conflict policy for `fees`: the mission §23 financial list names
/// invoices/payments/transactions/refunds. `fees` is NOT in that list, so it
/// follows the NORMAL rule (latest valid revision wins, rebase-and-retry
/// once). If the product team wants fee rows under the financial
/// never-overwrite rule, add `'fees'` to `financialEntities` in
/// sync_engine.dart — one line, no other changes.
///
/// Op classification: with no local `fees` table the repo cannot tell a new
/// fee from an existing one, so every upsert enqueues `create` (mapped to
/// `insert` by the engine). If the row already exists the RPC returns
/// `already_exists`, and the engine's normal-entity conflict path rebases
/// onto the fresh base_revision and retries as an update — exactly once.
/// `sync_apply` ignores `base_revision` on insert, so this is safe.
///
/// Public method signatures are IDENTICAL to the previous implementation.

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/app_database.dart' hide SyncQueue;
import '../../core/sync/sync_engine.dart';
import '../../core/services/supabase_service.dart';
import '../models/fee.dart';

// ─────────────────────────────────────────────
// Interface (unchanged)
// ─────────────────────────────────────────────

abstract class IFeeRepository {
  Future<List<Fee>> getAllFees({required String tenantId});
  Future<List<Fee>> getFeesByStudent(String studentId,
      {required String tenantId});

  /// [month] is in 'YYYY-MM' format, e.g. '2026-01'
  Future<List<Fee>> getFeesByMonth(String month, {required String tenantId});
  Future<Fee> upsertFee(Fee fee, {required String tenantId});
  Future<void> deleteFee(String id, {required String tenantId});
}

// ─────────────────────────────────────────────
// Queue-first implementation
// ─────────────────────────────────────────────

class LocalFeeRepository implements IFeeRepository {
  LocalFeeRepository(this._db, this._engine);

  final AppDatabase _db;

  /// Null when logged out / no active tenant — writes still enqueue
  /// locally and sync later; the opportunistic trigger is skipped.
  final SyncEngine? _engine;

  SupabaseClient get _client => SupabaseService.client;

  static const _select = '*, students(name, roll_no)';

  // ── Reads: REMOTE (documented exception — no local fees table) ──

  @override
  Future<List<Fee>> getAllFees({required String tenantId}) async {
    final response = await _client
        .from('fees')
        .select(_select)
        .eq('tenant_id', tenantId)
        .order('due_date', ascending: false);
    return (response as List)
        .map((row) => Fee.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Fee>> getFeesByStudent(String studentId,
      {required String tenantId}) async {
    final response = await _client
        .from('fees')
        .select(_select)
        .eq('tenant_id', tenantId)
        .eq('student_id', studentId)
        .order('due_date', ascending: false);
    return (response as List)
        .map((row) => Fee.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Fee>> getFeesByMonth(String month,
      {required String tenantId}) async {
    final response = await _client
        .from('fees')
        .select(_select)
        .eq('tenant_id', tenantId)
        .eq('month', month)
        .order('due_date', ascending: false);
    return (response as List)
        .map((row) => Fee.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // ── Writes: enqueue only (offline-safe), engine pushes ────────

  @override
  Future<Fee> upsertFee(Fee fee, {required String tenantId}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    // No local table → no local base revision and no existence check.
    // Always enqueue `create` (see header): the engine converts the
    // already_exists conflict into an update via one rebase-and-retry.
    await SyncQueue.enqueue(
      _db,
      tenantId: tenantId,
      entity: 'fees',
      entityId: fee.id,
      operation: 'create',
      payload: {
        ...fee.toJson(),
        'id': fee.id,
        'tenant_id': tenantId,
        'updated_at': now,
      },
      baseRevision: 0,
    );

    _engine?.notifyLocalChange();
    unawaited(_engine?.syncNow() ?? Future.value());
    return fee;
  }

  @override
  Future<void> deleteFee(String id, {required String tenantId}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await SyncQueue.enqueue(
      _db,
      tenantId: tenantId,
      entity: 'fees',
      entityId: id,
      operation: 'delete',
      payload: {'id': id, 'tenant_id': tenantId, 'updated_at': now},
      baseRevision: 0,
    );

    _engine?.notifyLocalChange();
    unawaited(_engine?.syncNow() ?? Future.value());
  }
}
