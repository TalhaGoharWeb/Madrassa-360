/// عملہ پروائیڈر
/// Staff Provider — repository-backed state management

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/staff.dart';
import '../data/repositories/staff_repository.dart';
import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';

// ─────────────────────────────────────────────
// Repository Provider
// ─────────────────────────────────────────────

final staffRepositoryProvider = Provider<IStaffRepository>((ref) {
  return SupabaseStaffRepository();
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

  /// Upload a profile photo to Supabase Storage and return the public URL.
  Future<String?> uploadPhoto(String staffId, XFile photo) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) return null;
    try {
      final bytes = await photo.readAsBytes();
      final ext = photo.name.split('.').last.toLowerCase();
      final path = 'staff/$staffId.$ext';
      await SupabaseService.client.storage
          .from('staff-photos')
          .uploadBinary(path, bytes,
              fileOptions: const FileOptions(upsert: true));
      final url = SupabaseService.client.storage
          .from('staff-photos')
          .getPublicUrl(path);
      final repo = ref.read(staffRepositoryProvider);
      final existing = await repo.getStaffById(staffId, tenantId: tenantId);
      if (existing != null) {
        await repo.upsertStaff(existing.copyWith(photoUrl: url),
            tenantId: tenantId);
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
