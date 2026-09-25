/// عملہ ریپوزیٹری
/// Staff Repository — abstract interface + Mock + Supabase implementations

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/staff.dart';
import '../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

abstract class IStaffRepository {
  Future<List<Staff>> getStaff({required String tenantId});
  Future<Staff?> getStaffById(String id, {required String tenantId});
  Future<Staff> upsertStaff(Staff staff, {required String tenantId});
  Future<void> deleteStaff(String id, {required String tenantId});
}

// ─────────────────────────────────────────────
// Supabase Implementation
// ─────────────────────────────────────────────

class SupabaseStaffRepository implements IStaffRepository {
  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<List<Staff>> getStaff({required String tenantId}) async {
    final response = await _client
        .from('staff')
        .select()
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('name');
    return (response as List)
        .map((row) => Staff.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Staff?> getStaffById(String id,
      {required String tenantId}) async {
    final response = await _client
        .from('staff')
        .select()
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Staff.fromJson(response);
  }

  @override
  Future<Staff> upsertStaff(Staff staff, {required String tenantId}) async {
    final payload = <String, dynamic>{...staff.toJson(), 'tenant_id': tenantId};
    final response = await _client
        .from('staff')
        .upsert(payload)
        .select()
        .single();
    return Staff.fromJson(response);
  }

  @override
  Future<void> deleteStaff(String id, {required String tenantId}) async {
    await _client
        .from('staff')
        .update({'is_active': false})
        .eq('tenant_id', tenantId)
        .eq('id', id);
  }
}
