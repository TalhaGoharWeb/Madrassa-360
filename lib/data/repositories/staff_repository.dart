/// عملہ ریپوزیٹری
/// Staff Repository — abstract interface + Mock + Supabase implementations

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/staff.dart';
import '../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

abstract class IStaffRepository {
  Future<List<Staff>> getStaff();
  Future<Staff?> getStaffById(String id);
  Future<Staff> upsertStaff(Staff staff);
  Future<void> deleteStaff(String id);
}

// ─────────────────────────────────────────────
// Supabase Implementation
// ─────────────────────────────────────────────

class SupabaseStaffRepository implements IStaffRepository {
  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<List<Staff>> getStaff() async {
    final response = await _client
        .from('staff')
        .select()
        .eq('is_active', true)
        .order('name');
    return (response as List)
        .map((row) => Staff.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Staff?> getStaffById(String id) async {
    final response = await _client
        .from('staff')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Staff.fromJson(response);
  }

  @override
  Future<Staff> upsertStaff(Staff staff) async {
    final response = await _client
        .from('staff')
        .upsert(staff.toJson())
        .select()
        .single();
    return Staff.fromJson(response);
  }

  @override
  Future<void> deleteStaff(String id) async {
    await _client
        .from('staff')
        .update({'is_active': false})
        .eq('id', id);
  }
}
