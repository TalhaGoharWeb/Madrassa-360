/// فیس ریپوزیٹری
/// Fee Repository — abstract interface + Mock + Supabase implementations

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fee.dart';
import '../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

abstract class IFeeRepository {
  Future<List<Fee>> getAllFees({required String tenantId});
  Future<List<Fee>> getFeesByStudent(String studentId,
      {required String tenantId});
  /// [month] is in 'YYYY-MM' format, e.g. '2026-01'
  Future<List<Fee>> getFeesByMonth(String month, {required String tenantId});
  Future<Fee> upsertFee(Fee fee, {required String tenantId});
  Future<void> deleteFee(String id, {required String tenantId});
}

// ─────────────────────────────────────────────
// Supabase Implementation
// ─────────────────────────────────────────────

class SupabaseFeeRepository implements IFeeRepository {
  SupabaseClient get _client => SupabaseService.client;

  static const _select =
      '*, students(name, roll_no)';

  @override
  Future<List<Fee>> getAllFees({required String tenantId}) async {
    final response = await _client
        .from('fees')
        .select(_select)
        .eq('tenant_id', tenantId)
        .order('due_date', ascending: false);
    return (response as List)
        .map((row) => Fee.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Fee>> getFeesByStudent(String studentId,
      {required String tenantId}) async {
    final response = await _client
        .from('fees')
        .select(_select)
        .eq('tenant_id', tenantId)
        .eq('student_id', studentId)
        .order('due_date', ascending: false);
    return (response as List)
        .map((row) => Fee.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Fee>> getFeesByMonth(String month,
      {required String tenantId}) async {
    final response = await _client
        .from('fees')
        .select(_select)
        .eq('tenant_id', tenantId)
        .eq('month', month)
        .order('due_date', ascending: false);
    return (response as List)
        .map((row) => Fee.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Fee> upsertFee(Fee fee, {required String tenantId}) async {
    final payload = <String, dynamic>{...fee.toJson(), 'tenant_id': tenantId};
    final response = await _client
        .from('fees')
        .upsert(payload)
        .select(_select)
        .single();
    return Fee.fromJson(response);
  }

  @override
  Future<void> deleteFee(String id, {required String tenantId}) async {
    await _client
        .from('fees')
        .delete()
        .eq('tenant_id', tenantId)
        .eq('id', id);
  }
}
