import 'package:flutter/material.dart';
import 'package:al_markaz_al_islami/core/constants/app_colors.dart';
import 'package:al_markaz_al_islami/core/constants/app_typography.dart';
import 'package:al_markaz_al_islami/data/models/student_model.dart';
import 'package:al_markaz_al_islami/data/models/attendance_status.dart';

/// طالب علم حاضری ٹائل
/// Student Attendance Tile Widget
/// Displays student info with tap-to-toggle attendance status
class StudentAttendanceTile extends StatelessWidget {
  final MockStudent student;
  final VoidCallback onTap;

  const StudentAttendanceTile({
    super.key,
    required this.student,
    required this.onTap,
  });

  /// Get background color based on attendance status
  Color get _statusColor {
    switch (student.status) {
      case AttendanceStatus.present:
        return AppColors.present;
      case AttendanceStatus.absent:
        return AppColors.absent;
      case AttendanceStatus.leave:
        return AppColors.leave;
    }
  }

  /// Get light background color for the tile
  Color get _tileBgColor {
    switch (student.status) {
      case AttendanceStatus.present:
        return AppColors.present.withOpacity(0.1);
      case AttendanceStatus.absent:
        return AppColors.absent.withOpacity(0.1);
      case AttendanceStatus.leave:
        return AppColors.leave.withOpacity(0.1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: _tileBgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _statusColor.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Status Indicator Circle
                _buildStatusIndicator(),
                const SizedBox(width: 12),
                
                // Student Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Student Name
                      Text(
                        student.name,
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Father's Name & Roll No
                      Row(
                        children: [
                          Text(
                            'بن ${student.fatherName}',
                            style: AppTypography.bodySmall,
                          ),
                          const SizedBox(width: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'رول: ${student.rollNo}',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Status Badge
                _buildStatusBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build the circular status indicator on the left
  Widget _buildStatusIndicator() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _statusColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _statusColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: _buildStatusIcon(),
      ),
    );
  }

  /// Build icon based on status
  Widget _buildStatusIcon() {
    IconData icon;
    switch (student.status) {
      case AttendanceStatus.present:
        icon = Icons.check;
        break;
      case AttendanceStatus.absent:
        icon = Icons.close;
        break;
      case AttendanceStatus.leave:
        icon = Icons.event_busy;
        break;
    }
    return Icon(icon, color: Colors.white, size: 24);
  }

  /// Build the status badge on the right
  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _statusColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        student.status.urduLabel,
        style: AppTypography.labelMedium.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
