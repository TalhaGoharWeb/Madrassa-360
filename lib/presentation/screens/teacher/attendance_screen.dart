import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/models/attendance_record.dart';
import '../../../providers/attendance_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../widgets/attendance/student_attendance_tile.dart';
import 'package:intl/intl.dart';

/// استاد حاضری اسکرین
/// Teacher Attendance Screen
/// Implements "Management by Exception" - All students are PRESENT by default
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceState = ref.watch(attendanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.attendanceRegister),
        actions: [
          // Reset Button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(attendanceProvider.notifier).resetToPresent();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'سب کو حاضر کر دیا گیا',
                    style: AppTypography.bodyMedium.copyWith(color: Colors.white),
                  ),
                  backgroundColor: AppColors.present,
                ),
              );
            },
            tooltip: 'سب کو حاضر کریں',
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Card with Date & Statistics
          _buildHeaderCard(context, attendanceState),
          
          // Student List
          Expanded(
            child: attendanceState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildStudentList(context, ref, attendanceState),
          ),
        ],
      ),
      // Save FAB
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'attendance_save_fab',
        onPressed: () => _saveAttendance(context, ref),
        icon: const Icon(Icons.save),
        label: Text(
          AppStrings.saveAttendance,
          style: AppTypography.buttonText,
        ),
      ),
    );
  }

  /// Build header card with date and statistics
  Widget _buildHeaderCard(BuildContext context, AttendanceState state) {
    // Format date in Urdu style
    final dateFormatter = DateFormat('EEEE، d MMMM yyyy', 'ur');
    final formattedDate = dateFormatter.format(state.selectedDate);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Date Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.calendar_today,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'آج کی تاریخ',
                      style: AppTypography.labelMedium,
                    ),
                    Text(
                      formattedDate,
                      style: AppTypography.titleMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          // Statistics Row
          Row(
            children: [
              _buildStatItem(
                label: AppStrings.totalStudents,
                value: '${state.totalCount}',
                color: AppColors.primary,
              ),
              _buildStatItem(
                label: AppStrings.presentCount,
                value: '${state.presentCount}',
                color: AppColors.present,
              ),
              _buildStatItem(
                label: AppStrings.absentCount,
                value: '${state.absentCount}',
                color: AppColors.absent,
              ),
              _buildStatItem(
                label: AppStrings.leaveCount,
                value: '${state.leaveCount}',
                color: AppColors.leave,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build individual stat item
  Widget _buildStatItem({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                value,
                style: AppTypography.titleMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build the student list
  Widget _buildStudentList(
    BuildContext context,
    WidgetRef ref,
    AttendanceState state,
  ) {
    if (state.students.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.noData,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80), // Space for FAB
      itemCount: state.students.length,
      itemBuilder: (context, index) {
        final student = state.students[index];
        return StudentAttendanceTile(
          student: student,
          onTap: () {
            // Toggle attendance status on tap
            ref.read(attendanceProvider.notifier).toggleAttendance(student.id);
          },
        );
      },
    );
  }

  /// Save attendance via the real stack:
  /// AttendanceRecordNotifier → SupabaseAttendanceRepository
  /// (offline fallback via OfflineSyncService). The old in-memory mock
  /// save on AttendanceNotifier has been deleted.
  Future<void> _saveAttendance(BuildContext context, WidgetRef ref) async {
    final state = ref.read(attendanceProvider);
    final tenantId = ref.read(currentTenantIdProvider);
    final teacherId = ref.read(currentUserProvider)?.id;

    String? error;
    if (tenantId == null) {
      error = 'کوئی فعال مدرسہ منتخب نہیں';
    } else if (state.students.isNotEmpty &&
        (state.classId == null || teacherId == null)) {
      error = 'حاضری محفوظ نہیں ہو سکی';
    }

    var success = false;
    if (error == null) {
      final dateStr = state.selectedDate.toIso8601String().substring(0, 10);
      final records = state.students
          .map((s) => AttendanceRecord(
                tenantId: tenantId!,
                studentId: s.id,
                studentName: s.name,
                studentRollNo: s.rollNo,
                studentPhotoUrl: s.photoUrl,
                classId: state.classId ?? '',
                teacherId: teacherId ?? '',
                date: dateStr,
                status: s.status,
              ))
          .toList();
      await ref.read(attendanceRecordNotifierProvider.notifier).save(records);
      final saveState = ref.read(attendanceRecordNotifierProvider);
      success = saveState is! AsyncError;
      if (!success) error = AppStrings.error;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? AppStrings.attendanceSaved : (error ?? AppStrings.error),
            style: AppTypography.bodyMedium.copyWith(color: Colors.white),
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }
}
