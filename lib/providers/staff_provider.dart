/// عملہ پروائیڈر
/// Staff Provider — repository-backed state management

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../data/models/staff.dart';
import '../data/repositories/staff_repository.dart';
import '../data/repositories/storage_repository.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/sync_providers.dart';
import '../core/services/tenant_context.dart';

// ─────────────────────────────────────────────
// Repository Provider
// ─────────────────────────────────────────────

final staffRepositoryProvider = Provider<IStaffRepository>((ref) {
  return LocalStaffRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncEngineProvider),
  );
});

// ─────────────────────────────────────────────
// All Staff
// ─────────────────────────────────────────────

final allStaffProvider = FutureProvider<List<Staff>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Staff>[];
  final repo = ref.watch(staffRepositoryProvider);
  return repo.getStaff(tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Single Staff Member
// ─────────────────────────────────────────────

final staffByIdProvider =
    FutureProvider.family<Staff?, String>((ref, staffId) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return null;
  final repo = ref.watch(staffRepositoryProvider);
  return repo.getStaffById(staffId, tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Staff Mutations Notifier
// ─────────────────────────────────────────────

class StaffNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<Staff> save(Staff staff) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) throw StateError('No active tenant');
    final repo = ref.read(staffRepositoryProvider);
    final saved = await repo.upsertStaff(staff, tenantId: tenantId);
    ref.invalidate(allStaffProvider);
    return saved;
  }

  Future<void> delete(String staffId) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) throw StateError('No active tenant');
    final repo = ref.read(staffRepositoryProvider);
    await repo.deleteStaff(staffId, tenantId: tenantId);
    ref.invalidate(allStaffProvider);
  }

  /// Stage a profile photo for upload and point the staff record at its
  /// future public URL (offline-first): the bytes are staged locally and
  /// queued in `pending_uploads`; the local 'staff' row is updated via the
  /// repository with `_pending_upload_id` so the engine uploads the bytes
  /// BEFORE pushing the row. Returns the (future) public URL.
  Future<String?> uploadPhoto(String staffId, XFile photo) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) return null;
    try {
      final ext = photo.name.split('.').last.toLowerCase();
      const bucket = 'staff-photos';
      // Tenant-prefixed destination aligns with the {tenant_id}/ storage
      // policy (the old path lacked the tenant prefix).
      final destPath = '$tenantId/staff/$staffId.$ext';
      final File staged = await PendingUploadQueue.stageFile(
          tenantId, photo, '$staffId.$ext');
      final db = ref.read(appDatabaseProvider);
      final uploadId = await PendingUploadQueue.enqueueUpload(
        db,
        tenantId: tenantId,
        stagedFile: staged,
        bucket: bucket,
        destPath: destPath,
      );
      final url = PendingUploadQueue.publicUrl(bucket, destPath);
      final repo = ref.read(staffRepositoryProvider);
      final existing = await repo.getStaffById(staffId, tenantId: tenantId);
      if (existing != null) {
        await repo.upsertStaff(existing.copyWith(photoUrl: url),
            tenantId: tenantId, pendingUploadId: uploadId);
        ref.invalidate(allStaffProvider);
      }
      return url;
    } catch (_) {
      return null;
    }
  }
}

final staffNotifierProvider =
    AsyncNotifierProvider<StaffNotifier, void>(StaffNotifier.new);
