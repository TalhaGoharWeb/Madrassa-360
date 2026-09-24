/// طلباء پروائیڈر
/// Student Provider — repository-backed state management

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/student.dart';
import '../data/repositories/student_repository.dart';
import '../core/services/supabase_service.dart';

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
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getAllStudents();
});

// ─────────────────────────────────────────────
// Students by Class (family provider keyed by classId)
// ─────────────────────────────────────────────

final studentsByClassProvider =
    FutureProvider.family<List<Student>, String>((ref, classId) async {
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getStudentsByClass(classId);
});

// ─────────────────────────────────────────────
// Students by Darja (family provider keyed by darjaId)
// ─────────────────────────────────────────────

final studentsByDarjaProvider =
    FutureProvider.family<List<Student>, String>((ref, darjaId) async {
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getStudentsByDarja(darjaId);
});

// ─────────────────────────────────────────────
// Single Student (family provider keyed by studentId)
// ─────────────────────────────────────────────

final studentByIdProvider =
    FutureProvider.family<Student?, String>((ref, studentId) async {
  final repo = ref.watch(studentRepositoryProvider);
  return repo.getStudentById(studentId);
});

// ─────────────────────────────────────────────
// Student Mutations Notifier
// ─────────────────────────────────────────────

class StudentNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<Student> save(Student student) async {
    final repo = ref.read(studentRepositoryProvider);
    final saved = await repo.upsertStudent(student);
    // Invalidate relevant caches
    ref.invalidate(allStudentsProvider);
    ref.invalidate(studentsByClassProvider(student.classId));
    ref.invalidate(studentsByDarjaProvider(student.darjaId));
    return saved;
  }

  Future<void> delete(String studentId) async {
    final repo = ref.read(studentRepositoryProvider);
    final student = await repo.getStudentById(studentId);
    await repo.deleteStudent(studentId);
    ref.invalidate(allStudentsProvider);
    if (student != null) {
      ref.invalidate(studentsByClassProvider(student.classId));
      ref.invalidate(studentsByDarjaProvider(student.darjaId));
    }
  }

  /// Upload a profile photo to Supabase Storage and return the public URL.
  /// Saves the URL back onto the Student record.
  Future<String?> uploadPhoto(String studentId, XFile photo) async {
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
      final existing = await repo.getStudentById(studentId);
      if (existing != null) {
        await repo.upsertStudent(existing.copyWith(photoUrl: url));
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
