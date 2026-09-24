/// نتائج پروائیڈر
/// Result Provider — repository-backed state management

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/result.dart';
import '../data/repositories/result_repository.dart';

// ─────────────────────────────────────────────
// Repository Provider
// ─────────────────────────────────────────────

final resultRepositoryProvider = Provider<IResultRepository>((ref) {
  return SupabaseResultRepository();
});

// ─────────────────────────────────────────────
// All Exams
// ─────────────────────────────────────────────

final allExamsProvider = FutureProvider<List<Exam>>((ref) async {
  final repo = ref.watch(resultRepositoryProvider);
  return repo.getExams();
});

// ─────────────────────────────────────────────
// Results for a specific exam (keyed by examId)
// ─────────────────────────────────────────────

final examResultsProvider =
    FutureProvider.family<List<StudentResult>, String>((ref, examId) async {
  final repo = ref.watch(resultRepositoryProvider);
  return repo.getExamResults(examId);
});

// ─────────────────────────────────────────────
// All student results (flat list across all exams)
// Loads each exam's results sequentially; suitable for small data sets.
// ─────────────────────────────────────────────

final allResultsProvider = FutureProvider<List<StudentResult>>((ref) async {
  final exams = await ref.watch(allExamsProvider.future);
  final repo = ref.watch(resultRepositoryProvider);
  final results = <StudentResult>[];
  for (final exam in exams) {
    final examResults = await repo.getExamResults(exam.id);
    results.addAll(examResults);
  }
  return results;
});

// ─────────────────────────────────────────────
// Student subject results (keyed by studentId + examId)
// ─────────────────────────────────────────────

class StudentExamKey {
  final String studentId;
  final String examId;
  const StudentExamKey({required this.studentId, required this.examId});

  @override
  bool operator ==(Object other) =>
      other is StudentExamKey &&
      other.studentId == studentId &&
      other.examId == examId;

  @override
  int get hashCode => Object.hash(studentId, examId);
}

final studentSubjectResultsProvider =
    FutureProvider.family<List<SubjectResult>, StudentExamKey>(
        (ref, key) async {
  final repo = ref.watch(resultRepositoryProvider);
  return repo.getStudentSubjectResults(
    studentId: key.studentId,
    examId: key.examId,
  );
});

// ─────────────────────────────────────────────
// Result Mutations Notifier
// ─────────────────────────────────────────────

class ResultNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<SubjectResult> save(SubjectResult result) async {
    final repo = ref.read(resultRepositoryProvider);
    final saved = await repo.upsertResult(result);
    ref.invalidate(allExamsProvider);
    ref.invalidate(allResultsProvider);
    ref.invalidate(examResultsProvider(result.examId));
    return saved;
  }
}

final resultNotifierProvider =
    AsyncNotifierProvider<ResultNotifier, void>(ResultNotifier.new);
