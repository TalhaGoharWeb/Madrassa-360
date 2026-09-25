/// طلباء پروائیڈر
/// Student Provider — repository-backed state management

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/student.dart';
import '../data/repositories/student_repository.dart';
import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';

// ─────────────────────────────────────────────
// Repository Provider
// ─────────────────────────────────────────────

final studentRepositoryProvider = Provider<IStudentRepository>((ref) {
  return SupabaseStudentRepository();
});

// ─────────────────────────────────────────────
// All Students
// ─────────────────────────────────────────────

final allStudentsProvider = FutureProvider<List<Student>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Student>[];
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getAllStudents(tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Students by Class (family provider keyed by classId)
// ─────────────────────────────────────────────

final studentsByClassProvider =
    FutureProvider.family<List<Student>, String>((ref, classId) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Student>[];
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getStudentsByClass(classId, tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Students by Darja (family provider keyed by darjaId)
// ─────────────────────────────────────────────

final studentsByDarjaProvider =
    FutureProvider.family<List<Student>, String>((ref, darjaId) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Student>[];
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getStudentsByDarja(darjaId, tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Single Student (family provider keyed by studentId)
// ─────────────────────────────────────────────

final studentByIdProvider =
    FutureProvider.family<Student?, String>((ref, studentId) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return null;
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getStudentById(studentId, tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Student Mutations Notifier
// ─────────────────────────────────────────────

class StudentNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<Student> save(Student student) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) throw StateError('No active tenant');
    final repo = ref.read(studentRepositoryProvider);
    final saved = await repo.upsertStudent(student, tenantId: tenantId);
    // Invalidate relevant caches
    ref.invalidate(allStudentsProvider);
    ref.invalidate(studentsByClassProvider(student.classId));
    ref.invalidate(studentsByDarjaProvider(student.darjaId));
    return saved;
  }

  Future<void> delete(String studentId) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) throw StateError('No active tenant');
    final repo = ref.read(studentRepositoryProvider);
    final student = await repo.getStudentById(studentId, tenantId: tenantId);
    await repo.deleteStudent(studentId, tenantId: tenantId);
    ref.invalidate(allStudentsProvider);
    if (student != null) {
      ref.invalidate(studentsByClassProvider(student.classId));
      ref.invalidate(studentsByDarjaProvider(student.darjaId));
    }
  }

  /// Upload a profile photo to Supabase Storage and return the public URL.
  /// Saves the URL back onto the Student record.
  Future<String?> uploadPhoto(String studentId, XFile photo) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) return null;
    try {
      final bytes = await photo.readAsBytes();
      final ext = photo.name.split('.').last.toLowerCase();
      final path = 'students/$studentId.$ext';
      await SupabaseService.client.storage
          .from('student-photos')
          .uploadBinary(path, bytes,
              fileOptions: const FileOptions(upsert: true));
      final url = SupabaseService.client.storage
          .from('student-photos')
          .getPublicUrl(path);
      // Persist photo_url on the student record
      final repo = ref.read(studentRepositoryProvider);
      final existing = await repo.getStudentById(studentId, tenantId: tenantId);
      if (existing != null) {
        await repo.upsertStudent(existing.copyWith(photoUrl: url),
            tenantId: tenantId);
        ref.invalidate(allStudentsProvider);
      }
      return url;
    } catch (_) {
      return null;
    }
  }
}

final studentNotifierProvider =
    AsyncNotifierProvider<StudentNotifier, void>(StudentNotifier.new);
