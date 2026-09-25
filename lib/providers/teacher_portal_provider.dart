/// استاد پورٹل پروائیڈرز
/// Teacher Portal Providers — assignment + tenant scoped (Phase 4).
///
/// A teacher only ever sees the classes they are assigned to
/// (`public.teacher_class_assignments`, migration 015) and the students
/// inside those classes. Every query is tenant-scoped, and every
/// provider bails out (returns []) when [currentTenantIdProvider] is
/// null — never query unscoped. RLS is the server-side enforcement
/// point; these filters are the client-side companion.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';
import '../data/models/student.dart';
import 'auth_provider.dart';

// ─────────────────────────────────────────────
// Models (portal-local; mirror migration 015)
// ─────────────────────────────────────────────

/// One row of `public.teacher_class_assignments` with the class name joined.
class TeacherClassAssignment {
  final String id;
  final String tenantId;
  final String teacherUserId;
  final String classId;
  final String className;
  final String subject;
  final String? academicYear;
  final bool isActive;

  const TeacherClassAssignment({
    required this.id,
    required this.tenantId,
    required this.teacherUserId,
    required this.classId,
    required this.className,
    required this.subject,
    this.academicYear,
    this.isActive = true,
  });

  factory TeacherClassAssignment.fromJson(Map<String, dynamic> json) {
    final cls = json['classes'] as Map<String, dynamic>?;
    return TeacherClassAssignment(
      id: json['id'] as String,
      tenantId: (json['tenant_id'] ?? '') as String,
      teacherUserId: json['teacher_user_id'] as String,
      classId: json['class_id'] as String,
      className: cls?['name'] as String? ?? '',
      subject: (json['subject'] as String?) ?? '',
      academicYear: json['academic_year'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// One row of `public.classes` the teacher is assigned to.
class AssignedClass {
  final String id;
  final String name;
  final String? darjaId;

  const AssignedClass({
    required this.id,
    required this.name,
    this.darjaId,
  });

  factory AssignedClass.fromJson(Map<String, dynamic> json) {
    return AssignedClass(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      darjaId: json['darja_id'] as String?,
    );
  }
}

// ─────────────────────────────────────────────
// Assignments
// ─────────────────────────────────────────────

/// Active class assignments for the signed-in teacher inside the active
/// tenant. [] when logged out or tenant-less.
final teacherAssignmentsProvider =
    FutureProvider<List<TeacherClassAssignment>>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  final tenantId = ref.watch(currentTenantIdProvider);
  if (userId == null || tenantId == null) return <TeacherClassAssignment>[];

  try {
    final rows = await SupabaseService.client
        .from('teacher_class_assignments')
        .select('*, classes(name)')
        .eq('teacher_user_id', userId)
        .eq('tenant_id', tenantId)
        .eq('is_active', true);
    return (rows as List)
        .map((r) =>
            TeacherClassAssignment.fromJson(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return <TeacherClassAssignment>[];
  }
});

/// Ids of the teacher's assigned classes (derived, sync).
final teacherAssignedClassIdsProvider = Provider<List<String>>((ref) {
  final assignments =
      ref.watch(teacherAssignmentsProvider).valueOrNull ?? const [];
  return assignments.map((a) => a.classId).toList();
});

/// Full class rows for the teacher's assignments (tenant-scoped).
final teacherAssignedClassesProvider =
    FutureProvider<List<AssignedClass>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  final classIds = ref.watch(teacherAssignedClassIdsProvider);
  if (tenantId == null || classIds.isEmpty) return <AssignedClass>[];

  try {
    final rows = await SupabaseService.client
        .from('classes')
        .select('id, name, darja_id')
        .eq('tenant_id', tenantId)
        .inFilter('id', classIds)
        .order('name');
    return (rows as List)
        .map((r) => AssignedClass.fromJson(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return <AssignedClass>[];
  }
});

// ─────────────────────────────────────────────
// Students of one assigned class
// ─────────────────────────────────────────────

/// Active students of [classId] — but ONLY when [classId] is one of the
/// teacher's assigned classes (re-checked against the assignment list,
/// so a forged class id returns []).
final teacherClassStudentsProvider =
    FutureProvider.family<List<Student>, String>((ref, classId) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  final assigned = ref.watch(teacherAssignedClassIdsProvider);
  if (tenantId == null || !assigned.contains(classId)) return <Student>[];

  try {
    final rows = await SupabaseService.client
        .from('students')
        .select()
        .eq('tenant_id', tenantId)
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('roll_no');
    return (rows as List)
        .map((r) => Student.fromJson(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return <Student>[];
  }
});

/// Total student headcount across all of the teacher's assigned classes.
final teacherStudentCountProvider = FutureProvider<int>((ref) async {
  final classIds = ref.watch(teacherAssignedClassIdsProvider);
  var total = 0;
  for (final id in classIds) {
    final students = await ref.watch(teacherClassStudentsProvider(id).future);
    total += students.length;
  }
  return total;
});
