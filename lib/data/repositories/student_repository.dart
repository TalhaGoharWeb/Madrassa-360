/// طلباء ریپوزیٹری
/// Student Repository — abstract interface + Mock + Supabase implementations

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/student.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/storage_service.dart';

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

abstract class IStudentRepository {
  Future<List<Student>> getAllStudents();
  Future<List<Student>> getStudentsByClass(String classId);
  Future<List<Student>> getStudentsByDarja(String darjaId);
  Future<Student?> getStudentById(String id);
  Future<Student> upsertStudent(Student student);
  Future<void> deleteStudent(String id);
}

// ─────────────────────────────────────────────
// Supabase Implementation
// ─────────────────────────────────────────────

class SupabaseStudentRepository implements IStudentRepository {
  SupabaseClient get _client => SupabaseService.client;

  static const _select = '*, darjas(name), classes(name)';

  // ── Cache helpers ──────────────────────────────────────────

  static String _cacheKey(String suffix) => 'cache_students_$suffix';

  static List<Student> _decodeCache(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Student.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeCache(String key, List rows) async {
    await StorageService.saveString(key, jsonEncode(rows));
  }

  // ── Queries ────────────────────────────────────────────────

  @override
  Future<List<Student>> getAllStudents() async {
    const key = 'cache_students_all';
    try {
      final response = await _client
          .from('students')
          .select(_select)
          .eq('is_active', true)
          .order('roll_no');
      await _writeCache(key, response as List);
      return (response).map((row) => Student.fromJson(row)).toList();
    } catch (_) {
      final cached = _decodeCache(StorageService.getString(key));
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  @override
  Future<List<Student>> getStudentsByClass(String classId) async {
    final key = _cacheKey('class_$classId');
    try {
      final response = await _client
          .from('students')
          .select(_select)
          .eq('class_id', classId)
          .eq('is_active', true)
          .order('roll_no');
      await _writeCache(key, response as List);
      return (response).map((row) => Student.fromJson(row)).toList();
    } catch (_) {
      final cached = _decodeCache(StorageService.getString(key));
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  @override
  Future<List<Student>> getStudentsByDarja(String darjaId) async {
    final key = _cacheKey('darja_$darjaId');
    try {
      final response = await _client
          .from('students')
          .select(_select)
          .eq('darja_id', darjaId)
          .eq('is_active', true)
          .order('roll_no');
      await _writeCache(key, response as List);
      return (response).map((row) => Student.fromJson(row)).toList();
    } catch (_) {
      final cached = _decodeCache(StorageService.getString(key));
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  @override
  Future<Student?> getStudentById(String id) async {
    final response = await _client
        .from('students')
        .select(_select)
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Student.fromJson(response);
  }

  @override
  Future<Student> upsertStudent(Student student) async {
    final response = await _client
        .from('students')
        .upsert(student.toJson())
        .select(_select)
        .single();
    return Student.fromJson(response);
  }

  @override
  Future<void> deleteStudent(String id) async {
    await _client
        .from('students')
        .update({'is_active': false})
        .eq('id', id);
  }
}
