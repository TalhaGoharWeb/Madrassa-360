/// والدین پورٹل پروائیڈرز
/// Parent Portal Providers — link-table + tenant scoped (Phase 4).
///
/// Every provider here bails out (returns []) when
/// [currentTenantIdProvider] is null — the client never queries unscoped.
/// All rows are filtered by `tenant_id` AND by the guardian link
/// (`public.student_guardians`, migration 015), so a parent only ever
/// sees their own children. RLS is the server-side enforcement point;
/// these filters are the client-side companion.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';
import '../data/models/announcement.dart';
import '../data/models/attendance_record.dart';
import '../data/models/attendance_status.dart';
import '../data/models/fee.dart';
import '../data/models/result.dart';
import '../data/models/student.dart';
import 'auth_provider.dart';

/// Arguments for scoped attendance reads.
class ParentAttendanceArgs {
  /// The child whose attendance is read (must be the caller's own child).
  final String studentId;

  /// How many trailing days to fetch (0 = today only).
  final int days;

  const ParentAttendanceArgs({required this.studentId, this.days = 30});

  @override
  bool operator ==(Object other) =>
      other is ParentAttendanceArgs &&
      other.studentId == studentId &&
      other.days == days;

  @override
  int get hashCode => Object.hash(studentId, days);
}

// ─────────────────────────────────────────────
// Guardian link → own children
// ─────────────────────────────────────────────

/// Student ids linked to the signed-in guardian inside the active tenant
/// (via `public.student_guardians`). [] when logged out or tenant-less —
/// callers must never fall back to the legacy `parent_user_id` column or
/// to an unscoped query.
final parentChildIdsProvider = FutureProvider<List<String>>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  final tenantId = ref.watch(currentTenantIdProvider);
  if (userId == null || tenantId == null) return <String>[];

  try {
    final rows = await SupabaseService.client
        .from('student_guardians')
        .select('student_id')
        .eq('guardian_user_id', userId)
        .eq('tenant_id', tenantId);
    return (rows as List)
        .map((r) => (r as Map<String, dynamic>)['student_id'] as String)
        .toList();
  } catch (_) {
    return <String>[];
  }
});

/// The parent's own children (tenant-scoped, link-scoped).
final parentChildrenProvider = FutureProvider<List<Student>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  final childIds = await ref.watch(parentChildIdsProvider.future);
  if (tenantId == null || childIds.isEmpty) return <Student>[];

  try {
    final rows = await SupabaseService.client
        .from('students')
        .select()
        .eq('tenant_id', tenantId)
        .inFilter('id', childIds)
        .order('roll_no');
    return (rows as List)
        .map((r) => Student.fromJson(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return <Student>[];
  }
});

// ─────────────────────────────────────────────
// Scoped child data
// ─────────────────────────────────────────────

/// Fee records for the parent's own children only.
final parentFeesProvider = FutureProvider<List<Fee>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  final childIds = await ref.watch(parentChildIdsProvider.future);
  if (tenantId == null || childIds.isEmpty) return <Fee>[];

  try {
    final rows = await SupabaseService.client
        .from('fees')
        .select()
        .eq('tenant_id', tenantId)
        .inFilter('student_id', childIds)
        .order('month', ascending: false);
    return (rows as List)
        .map((r) => Fee.fromJson(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return <Fee>[];
  }
});

/// Exam result rows for the parent's own children only.
final parentResultsProvider = FutureProvider<List<SubjectResult>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  final childIds = await ref.watch(parentChildIdsProvider.future);
  if (tenantId == null || childIds.isEmpty) return <SubjectResult>[];

  try {
    final rows = await SupabaseService.client
        .from('results')
        .select()
        .eq('tenant_id', tenantId)
        .inFilter('student_id', childIds);
    return (rows as List)
        .map((r) => SubjectResult.fromJson(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return <SubjectResult>[];
  }
});

/// Attendance records for one of the parent's own children.
/// The [ParentAttendanceArgs.studentId] is re-checked against the
/// guardian link — a forged id that isn't the caller's child returns [].
final parentAttendanceProvider = FutureProvider.family<List<AttendanceRecord>,
    ParentAttendanceArgs>((ref, args) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  final childIds = await ref.watch(parentChildIdsProvider.future);
  if (tenantId == null || !childIds.contains(args.studentId)) {
    return <AttendanceRecord>[];
  }

  try {
    final since = DateTime.now().subtract(Duration(days: args.days));
    final from = since.toIso8601String().substring(0, 10);
    final rows = await SupabaseService.client
        .from('attendance')
        .select()
        .eq('tenant_id', tenantId)
        .eq('student_id', args.studentId)
        .gte('date', from)
        .order('date', ascending: false);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return AttendanceRecord(
        id: m['id'] as String?,
        tenantId: (m['tenant_id'] ?? '') as String,
        studentId: m['student_id'] as String,
        studentName: (m['student_name'] as String?) ?? '',
        studentRollNo: (m['student_roll_no'] as String?) ?? '',
        studentPhotoUrl: m['student_photo_url'] as String?,
        classId: (m['class_id'] ?? '') as String,
        teacherId: (m['teacher_id'] ?? '') as String,
        date: (m['date'] ?? '') as String,
        status: _parseAttendanceStatus(m['status'] as String?),
        note: m['note'] as String?,
      );
    }).toList();
  } catch (_) {
    return <AttendanceRecord>[];
  }
});

/// Parse the DB status string (same mapping as the attendance repository).
AttendanceStatus _parseAttendanceStatus(String? s) {
  switch (s) {
    case 'absent':
      return AttendanceStatus.absent;
    case 'leave':
      return AttendanceStatus.leave;
    case 'present':
    default:
      return AttendanceStatus.present;
  }
}

/// Announcements for the parent portal: tenant-scoped, limited to targets
/// a parent may see (`all`, `parents`). The parent role holds
/// `notifications.view`, so RLS permits these rows server-side too.
final parentAnnouncementsProvider =
    FutureProvider<List<Announcement>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Announcement>[];

  try {
    final rows = await SupabaseService.client
        .from('announcements')
        .select()
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Announcement.fromJson(r as Map<String, dynamic>))
        .where((a) =>
            a.target == AnnouncementTarget.all ||
            a.target == AnnouncementTarget.parents)
        .toList();
  } catch (_) {
    return <Announcement>[];
  }
});
