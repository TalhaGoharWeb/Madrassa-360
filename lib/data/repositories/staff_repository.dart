/// عملہ ریپوزیٹری
/// Staff Repository — LOCAL-FIRST (Phase 5 offline-first sync).
///
/// Reads stay REMOTE (Supabase) — the staff UI lists come from the
/// server and the photo-upload flow is unchanged. Writes go to the
/// local Drift envelope table (`staff`) + a `sync_queue` row in the
/// SAME transaction via [SyncEngine.writeLocalRow] /
/// [SyncEngine.softDeleteLocalRow] + [SyncQueue.enqueue], then
/// opportunistically trigger [SyncEngine.syncNow]. Direct Supabase
/// writes are FORBIDDEN in this repository — the sync engine is the
/// only writer to the server (via the `sync_apply` RPC).
///
/// Local schema (sibling contract, same envelope pattern as existing
/// tables): `staff(id, tenant_id, name, designation, revision,
/// server_revision, updated_at, deleted_at, data)` — the `data` JSON
/// is authoritative.
///
/// Public method signatures are IDENTICAL to the previous Supabase
/// implementation, except [upsertStaff] gains an optional named
/// [pendingUploadId] that is recorded in the queued payload when a
/// profile-photo upload is pending (consumed by the sync engine /
/// upload worker).

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/app_database.dart' hide SyncQueue;
import '../../core/sync/sync_engine.dart';
import '../models/staff.dart';
import '../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────
// Interface (reads + upsert/delete)
// ─────────────────────────────────────────────

abstract class IStaffRepository {
  Future<List<Staff>> getStaff({required String tenantId});
  Future<Staff?> getStaffById(String id, {required String tenantId});
  Future<Staff> upsertStaff(Staff staff,
      {required String tenantId, String? pendingUploadId});
  Future<void> deleteStaff(String id, {required String tenantId});
}

// ─────────────────────────────────────────────
// Local-first implementation (reads stay remote)
// ─────────────────────────────────────────────

class LocalStaffRepository implements IStaffRepository {
  LocalStaffRepository(this._db, this._engine);

  final AppDatabase _db;

  /// Null when logged out / no active tenant — writes still enqueue
  /// locally and sync later; the opportunistic trigger is skipped.
  final SyncEngine? _engine;

  SupabaseClient get _client => SupabaseService.client;

  // ── Queries (remote — UNCHANGED) ─────────────────────────────

  @override
  Future<List<Staff>> getStaff({required String tenantId}) async {
    final response = await _client
        .from('staff')
        .select()
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('name');
    return (response as List)
        .map((row) => Staff.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Staff?> getStaffById(String id, {required String tenantId}) async {
    final response = await _client
        .from('staff')
        .select()
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Staff.fromJson(response);
  }

  // ── Writes (local + queue, same transaction) ─────────────────

  @override
  Future<Staff> upsertStaff(Staff staff,
      {required String tenantId, String? pendingUploadId}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final exists = await SyncQueue.rowExists(_db, 'staff', tenantId, staff.id);
    final baseRev = exists
        ? await SyncQueue.currentRevision(_db, 'staff', tenantId, staff.id)
        : 0;

    // Server-shaped payload kept in the envelope's data JSON and queued.
    final data = {
      ...staff.toJson(),
      'id': staff.id,
      'tenant_id': tenantId,
    };
    if (pendingUploadId != null) {
      data['_pending_upload_id'] = pendingUploadId;
    }

    await _db.transaction(() async {
      await SyncEngine.writeLocalRow(
        _db,
        table: 'staff',
        id: staff.id,
        tenantId: tenantId,
        indexed: {
          'name': staff.name,
          'designation': staff.designation,
        },
        data: data,
      );

      await SyncQueue.enqueue(
        _db,
        tenantId: tenantId,
        entity: 'staff',
        entityId: staff.id,
        operation: exists ? 'update' : 'create',
        payload: {...data, 'updated_at': nowIso},
        baseRevision: baseRev,
      );
    });

    _engine?.notifyLocalChange();
    unawaited(_engine?.syncNow() ?? Future.value());
    return staff;
  }

  @override
  Future<void> deleteStaff(String id, {required String tenantId}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final baseRev = await SyncQueue.currentRevision(_db, 'staff', tenantId, id);

    await _db.transaction(() async {
      // Soft delete locally: sets deleted_at (epoch millis), refreshes
      // updated_at, bumps revision, and patches the data JSON so the row
      // still reads as inactive until the push completes.
      await SyncEngine.softDeleteLocalRow(
        _db,
        table: 'staff',
        id: id,
        tenantId: tenantId,
        dataPatch: {'is_active': false},
      );

      await SyncQueue.enqueue(
        _db,
        tenantId: tenantId,
        entity: 'staff',
        entityId: id,
        operation: 'delete',
        payload: {'id': id, 'tenant_id': tenantId, 'updated_at': nowIso},
        baseRevision: baseRev,
      );
    });

    _engine?.notifyLocalChange();
    unawaited(_engine?.syncNow() ?? Future.value());
  }
}
