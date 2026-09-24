/// نتائج ریپوزیٹری
/// Result Repository — abstract interface + Mock + Supabase implementations

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/result.dart';
import '../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

abstract class IResultRepository {
  Future<List<Exam>> getExams();
  Future<Exam?> getExamById(String id);
  Future<List<StudentResult>> getExamResults(String examId);
  Future<List<SubjectResult>> getStudentSubjectResults({
    required String studentId,
    required String examId,
  });
  Future<SubjectResult> upsertResult(SubjectResult result);
}

// ─────────────────────────────────────────────
// Supabase Implementation
// ─────────────────────────────────────────────

class SupabaseResultRepository implements IResultRepository {
  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<List<Exam>> getExams() async {
    final response = await _client
        .from('exams')
        .select()
        .order('exam_date', ascending: false);
    return (response as List)
        .map((row) => Exam.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Exam?> getExamById(String id) async {
    final response =
        await _client.from('exams').select().eq('id', id).maybeSingle();
    if (response == null) return null;
    return Exam.fromJson(response);
  }

  @override
  Future<List<StudentResult>> getExamResults(String examId) async {
    final exam = await getExamById(examId);
    final response = await _client
        .from('results')
        .select('*, students(name, roll_no, classes(name))')
        .eq('exam_id', examId)
        .order('student_id');

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final row in (response as List)) {
      final r = row as Map<String, dynamic>;
      final sid = r['student_id'] as String;
      grouped.putIfAbsent(sid, () => []).add(r);
    }

    return grouped.entries.map((entry) {
      final rows = entry.value;
      final first = rows.first;
      final student = first['students'] as Map<String, dynamic>? ?? {};
      final classMap = student['classes'] as Map<String, dynamic>? ?? {};
      return StudentResult(
        examId: examId,
        examName: exam?.name ?? '',
        examDate: exam?.examDate ?? '',
        studentId: entry.key,
        studentName: student['name'] as String? ?? '',
        className: classMap['name'] as String? ?? '',
        subjects: rows.map((r) => SubjectResult.fromJson(r)).toList(),
      );
    }).toList();
  }

  @override
  Future<List<SubjectResult>> getStudentSubjectResults({
    required String studentId,
    required String examId,
  }) async {
    final response = await _client
        .from('results')
        .select()
        .eq('student_id', studentId)
        .eq('exam_id', examId);
    return (response as List)
        .map((row) => SubjectResult.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<SubjectResult> upsertResult(SubjectResult result) async {
    final response = await _client
        .from('results')
        .upsert(result.toJson())
        .select()
        .single();
    return SubjectResult.fromJson(response);
  }
}
