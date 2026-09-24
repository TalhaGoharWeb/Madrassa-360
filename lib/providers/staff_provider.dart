/// عملہ پروائیڈر
/// Staff Provider — repository-backed state management

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/staff.dart';
import '../data/repositories/staff_repository.dart';
import '../core/services/supabase_service.dart';

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
  final repo = ref.watch(staffRepositoryProvider);
  return repo.getStaff();
});

// ─────────────────────────────────────────────
// Single Staff Member
// ─────────────────────────────────────────────

final staffByIdProvider =
    FutureProvider.family<Staff?, String>((ref, staffId) async {
  final repo = ref.watch(staffRepositoryProvider);
  return repo.getStaffById(staffId);
});

// ─────────────────────────────────────────────
// Staff Mutations Notifier
// ─────────────────────────────────────────────

class StaffNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<Staff> save(Staff staff) async {
    final repo = ref.read(staffRepositoryProvider);
    final saved = await repo.upsertStaff(staff);
    ref.invalidate(allStaffProvider);
    return saved;
  }

  Future<void> delete(String staffId) async {
    final repo = ref.read(staffRepositoryProvider);
    await repo.deleteStaff(staffId);
    ref.invalidate(allStaffProvider);
  }

  /// Upload a profile photo to Supabase Storage and return the public URL.
  Future<String?> uploadPhoto(String staffId, XFile photo) async {
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
      final existing = await repo.getStaffById(staffId);
      if (existing != null) {
        await repo.upsertStaff(existing.copyWith(photoUrl: url));
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
