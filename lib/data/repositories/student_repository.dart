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
  Future<List<Student>> getAllStudents({required String tenantId});
  Future<List<Student>> getStudentsByClass(String classId,
      {required String tenantId});
  Future<List<Student>> getStudentsByDarja(String darjaId,
      {required String tenantId});
  Future<Student?> getStudentById(String id, {required String tenantId});
  Future<Student> upsertStudent(Student student, {required String tenantId});
  Future<void> deleteStudent(String id, {required String tenantId});
}

// ─────────────────────────────────────────────
// Supabase Implementation
// ─────────────────────────────────────────────

class SupabaseStudentRepository implements IStudentRepository {
  SupabaseClient get _client => SupabaseService.client;

  static const _select = '*, darjas(name), classes(name)';

  // ── Cache helpers ──────────────────────────────────────────

  static String _cacheKey(String tenantId, String suffix) =>
      'cache_students_${tenantId}_$suffix';

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
  Future<List<Student>> getAllStudents({required String tenantId}) async {
    final key = _cacheKey(tenantId, 'all');
    try {
      final response = await _client
          .from('students')
          .select(_select)
          .eq('tenant_id', tenantId)
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
  Future<List<Student>> getStudentsByClass(String classId,
      {required String tenantId}) async {
    final key = _cacheKey(tenantId, 'class_$classId');
    try {
      final response = await _client
          .from('students')
          .select(_select)
          .eq('tenant_id', tenantId)
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
  Future<List<Student>> getStudentsByDarja(String darjaId,
      {required String tenantId}) async {
    final key = _cacheKey(tenantId, 'darja_$darjaId');
    try {
      final response = await _client
          .from('students')
          .select(_select)
          .eq('tenant_id', tenantId)
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
  Future<Student?> getStudentById(String id,
      {required String tenantId}) async {
    final response = await _client
        .from('students')
        .select(_select)
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Student.fromJson(response);
  }

  @override
  Future<Student> upsertStudent(Student student,
      {required String tenantId}) async {
    final payload = <String, dynamic>{...student.toJson(), 'tenant_id': tenantId};
    final response = await _client
        .from('students')
        .upsert(payload)
        .select(_select)
        .single();
    return Student.fromJson(response);
  }

  @override
  Future<void> deleteStudent(String id, {required String tenantId}) async {
    await _client
        .from('students')
        .update({'is_active': false})
        .eq('tenant_id', tenantId)
        .eq('id', id);
  }
}
