/// نتائج پروائیڈر
/// Result Provider — repository-backed state management

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/services/tenant_context.dart';
import '../core/sync/sync_providers.dart';
import '../data/models/result.dart';
import '../data/repositories/result_repository.dart';

// ─────────────────────────────────────────────
// Repository Provider
// ─────────────────────────────────────────────

final resultRepositoryProvider = Provider<IResultRepository>((ref) {
  return LocalResultRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncEngineProvider),
  );
});

// ─────────────────────────────────────────────
// All Exams
// ─────────────────────────────────────────────

final allExamsProvider = FutureProvider<List<Exam>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Exam>[];
  final repo = ref.watch(resultRepositoryProvider);
  return repo.getExams(tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Results for a specific exam (keyed by examId)
// ─────────────────────────────────────────────

final examResultsProvider =
    FutureProvider.family<List<StudentResult>, String>((ref, examId) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <StudentResult>[];
  final repo = ref.watch(resultRepositoryProvider);
  return repo.getExamResults(examId, tenantId: tenantId);
});

// ─────────────────────────────────────────────
// All student results (flat list across all exams)
// Loads each exam's results sequentially; suitable for small data sets.
// ─────────────────────────────────────────────

final allResultsProvider = FutureProvider<List<StudentResult>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <StudentResult>[];
  final exams = await ref.watch(allExamsProvider.future);
  final repo = ref.watch(resultRepositoryProvider);
  final results = <StudentResult>[];
  for (final exam in exams) {
    final examResults = await repo.getExamResults(exam.id, tenantId: tenantId);
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
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <SubjectResult>[];
  final repo = ref.watch(resultRepositoryProvider);
  return repo.getStudentSubjectResults(
    studentId: key.studentId,
    examId: key.examId,
    tenantId: tenantId,
  );
});

// ─────────────────────────────────────────────
// Result Mutations Notifier
// ─────────────────────────────────────────────

class ResultNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<SubjectResult> save(SubjectResult result) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) throw StateError('No active tenant');
    final repo = ref.read(resultRepositoryProvider);
    final saved = await repo.upsertResult(result, tenantId: tenantId);
    ref.invalidate(allExamsProvider);
    ref.invalidate(allResultsProvider);
    ref.invalidate(examResultsProvider(result.examId));
    return saved;
  }

  /// Creates an exam header (exam wizard step 1). Returns the created
  /// [Exam]; throws when there is no active tenant.
  Future<Exam> createExam({
    required String name,
    String? classId,
    required String examDate,
    required int totalMarks,
  }) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) throw StateError('No active tenant');
    final repo = ref.read(resultRepositoryProvider);
    final exam = Exam(
      id: const Uuid().v4(),
      tenantId: tenantId,
      name: name,
      classId: classId,
      examDate: examDate,
      totalMarks: totalMarks,
    );
    final created = await repo.createExam(exam, tenantId: tenantId);
    ref.invalidate(allExamsProvider);
    return created;
  }
}

final resultNotifierProvider =
    AsyncNotifierProvider<ResultNotifier, void>(ResultNotifier.new);
