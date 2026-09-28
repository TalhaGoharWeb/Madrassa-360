import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/attendance_status.dart';
import '../../../data/models/fee.dart';
import '../../../data/models/student.dart';
import '../../widgets/common/app_widgets.dart';

/// Shared student presentation widgets: avatar, fee badge, attendance badge.
///
/// Pure UI helpers — no providers, no business logic. Used by the student
/// list and the student profile.
class StudentAvatar extends StatelessWidget {
  final Student student;
  final double radius;

  const StudentAvatar({super.key, required this.student, this.radius = 26});

  @override
  Widget build(BuildContext context) {
    final letter = student.name.isNotEmpty ? student.name.substring(0, 1) : '؟';
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      backgroundImage: student.photoUrl != null
          ? NetworkImage(student.photoUrl!) as ImageProvider
          : null,
      child: student.photoUrl == null
          ? Text(
              letter,
              style: AppTypography.labelNastaliq.copyWith(
                fontSize: radius * 0.85,
                color: AppColors.primaryDark,
              ),
            )
          : null,
    );
  }
}

/// Fee-status badge from [FeeStatus].
Widget feeBadge(FeeStatus status, {bool compact = false}) {
  return switch (status) {
    FeeStatus.paid => StatusBadge.paid(),
    FeeStatus.pending => StatusBadge.pending(),
    FeeStatus.pastDue => StatusBadge.pastDue(),
    FeeStatus.partial => StatusBadge(
        label: 'جزوی',
        color: AppColors.warning,
        icon: Icons.hourglass_bottom,
      ),
  };
}

/// Attendance badge from [AttendanceStatus].
Widget attendanceBadge(AttendanceStatus status, {bool compact = false}) {
  return switch (status) {
    AttendanceStatus.present => StatusBadge.present(),
    AttendanceStatus.absent => StatusBadge.absent(),
    AttendanceStatus.leave => StatusBadge.leave(),
    AttendanceStatus.late => StatusBadge(
        label: 'تاخیر',
        color: AppColors.late,
        icon: Icons.schedule,
      ),
  };
}

/// Generic active/inactive status badge for a student.
Widget studentStatusBadge(bool isActive) => StatusBadge(
      label: isActive ? 'فعال' : 'غیر فعال',
      color: isActive ? AppColors.success : AppColors.error,
      icon: isActive ? Icons.check_circle : Icons.block,
    );

/// Gold divider used under section headings.
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      width: 48,
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFC9A227),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Urdu section heading (Nastaleeq) with gold accent.
class SectionHeading extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const SectionHeading({
    super.key,
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.primaryDark, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: AppTypography.titleSmall),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SectionDivider(),
      ],
    );
  }
}
