import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:madrasa_360/core/design/m360.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/attendance_status.dart';
import '../../../data/models/fee.dart';
import '../../../data/models/student.dart';

/// Shared student presentation widgets: avatar, fee badge, attendance badge.
///
/// Pure UI helpers — no providers, no business logic. Used by the student
/// list and the student profile.
///
/// Phase 10 (m360): badges render on [M360Badge.custom] with the EXACT
/// labels, icons and colors the old [StatusBadge] factories used — the
/// admin student list (out of scope) shares these helpers, so the mapping
/// is behavior-preserving.
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
          ? CachedNetworkImageProvider(student.photoUrl!,
              maxWidth: 128, maxHeight: 128) as ImageProvider
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
    FeeStatus.paid => const M360Badge.custom(
        label: 'ادا شدہ',
        color: AppColors.paid,
        icon: Icons.check_circle,
      ),
    FeeStatus.pending => const M360Badge.custom(
        label: 'زیر التواء',
        color: AppColors.pending,
        icon: Icons.schedule,
      ),
    FeeStatus.pastDue => const M360Badge.custom(
        label: 'واجب الادا',
        color: AppColors.pastDue,
        icon: Icons.warning,
      ),
    FeeStatus.partial => const M360Badge.custom(
        label: 'جزوی',
        color: AppColors.warning,
        icon: Icons.hourglass_bottom,
      ),
  };
}

/// Attendance badge from [AttendanceStatus].
Widget attendanceBadge(AttendanceStatus status, {bool compact = false}) {
  return switch (status) {
    AttendanceStatus.present => const M360Badge.custom(
        label: 'حاضر',
        color: AppColors.present,
        icon: Icons.check_circle,
      ),
    AttendanceStatus.absent => const M360Badge.custom(
        label: 'غیر حاضر',
        color: AppColors.absent,
        icon: Icons.cancel,
      ),
    AttendanceStatus.leave => const M360Badge.custom(
        label: 'چھٹی',
        color: AppColors.leave,
        icon: Icons.event_busy,
      ),
    AttendanceStatus.late => const M360Badge.custom(
        label: 'تاخیر',
        color: AppColors.late,
        icon: Icons.schedule,
      ),
  };
}

/// Generic active/inactive status badge for a student.
Widget studentStatusBadge(bool isActive) => M360Badge.custom(
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
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Urdu section heading (Nastaleeq) with gold accent.
///
/// Kept as a shared custom widget (rather than [M360SectionHeader]) because
/// it carries an icon and an arbitrary trailing widget — both used by the
/// admin student list, which is outside the Phase 10 scope.
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
