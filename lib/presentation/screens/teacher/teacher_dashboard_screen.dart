import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/teacher_portal_provider.dart';

/// استاد ڈیش بورڈ
/// Teacher Dashboard Screen
///
/// Phase 4: the schedule and headcount are driven by the teacher's
/// `teacher_class_assignments` (tenant-scoped) — never a global list.
class TeacherDashboardScreen extends StatelessWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final user = ref.watch(currentUserProvider);
      final teacherName = user?.name ?? 'استاد';
      return Scaffold(
        appBar: AppBar(
          title: Text(AppStrings.dashboard),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Card
              _buildWelcomeCard(teacherName),
              const SizedBox(height: 16),

              // Quick Stats Grid (headcount = assigned classes only)
              _buildQuickStats(ref),
              const SizedBox(height: 16),

              // Today's Schedule Card (assigned classes only)
              _buildTodayScheduleCard(ref),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildWelcomeCard(String teacherName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'السلام علیکم',
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      teacherName,
                      style: AppTypography.headingSmall.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(WidgetRef ref) {
    // Headcount across the teacher's assigned classes (tenant-scoped).
    // The other two cards are Phase-5 placeholders (still static).
    final studentCount = ref.watch(teacherStudentCountProvider).valueOrNull;
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.people,
            label: 'کل طلباء',
            value: studentCount == null ? '—' : '$studentCount',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.check_circle,
            label: 'آج حاضر',
            value: '23',
            color: AppColors.present,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.assignment,
            label: 'زیر التواء',
            value: '3',
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTypography.headingSmall.copyWith(color: color),
          ),
          Text(
            label,
            style: AppTypography.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTodayScheduleCard(WidgetRef ref) {
    // Watched here (during the outer Consumer's build), not inside a
    // nested builder — ref.watch is only legal in Consumer/provider scope.
    final assignmentsAsync = ref.watch(teacherAssignmentsProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'آج کا شیڈول',
                style: AppTypography.titleMedium,
              ),
            ],
          ),
          const Divider(height: 24),
          // Phase 4: only classes assigned to this teacher (tenant-scoped).
          assignmentsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(
              'شیڈول لوڈ کرنے میں خطا',
              style: AppTypography.bodySmall,
            ),
            data: (assignments) {
              if (assignments.isEmpty) {
                return Text(
                  'کوئی جماعت تفویض نہیں',
                  style: AppTypography.bodySmall,
                );
              }
              return Column(
                children: assignments.map((a) {
                  final label = a.subject.isEmpty
                      ? a.className
                      : '${a.className} - ${a.subject}';
                  return _buildScheduleItem(label, a.academicYear ?? '');
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleItem(String subject, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject, style: AppTypography.bodyMedium),
                Text(time, style: AppTypography.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
