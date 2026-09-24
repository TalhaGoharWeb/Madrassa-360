/// فیس ریپوزیٹری
/// Fee Repository — abstract interface + Mock + Supabase implementations

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fee.dart';
import '../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

abstract class IFeeRepository {
  Future<List<Fee>> getAllFees();
  Future<List<Fee>> getFeesByStudent(String studentId);
  /// [month] is in 'YYYY-MM' format, e.g. '2026-01'
  Future<List<Fee>> getFeesByMonth(String month);
  Future<Fee> upsertFee(Fee fee);
  Future<void> deleteFee(String id);
}

// ─────────────────────────────────────────────
// Supabase Implementation
// ─────────────────────────────────────────────

class SupabaseFeeRepository implements IFeeRepository {
  SupabaseClient get _client => SupabaseService.client;

  static const _select =
      '*, students(name, roll_no)';

  @override
  Future<List<Fee>> getAllFees() async {
    final response = await _client
        .from('fees')
        .select(_select)
        .order('due_date', ascending: false);
    return (response as List)
        .map((row) => Fee.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Fee>> getFeesByStudent(String studentId) async {
    final response = await _client
        .from('fees')
        .select(_select)
        .eq('student_id', studentId)
        .order('due_date', ascending: false);
    return (response as List)
        .map((row) => Fee.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Fee>> getFeesByMonth(String month) async {
    final response = await _client
        .from('fees')
        .select(_select)
        .eq('month', month)
        .order('due_date', ascending: false);
    return (response as List)
        .map((row) => Fee.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Fee> upsertFee(Fee fee) async {
    final response = await _client
        .from('fees')
        .upsert(fee.toJson())
        .select(_select)
        .single();
    return Fee.fromJson(response);
  }

  @override
  Future<void> deleteFee(String id) async {
    await _client.from('fees').delete().eq('id', id);
  }
}
