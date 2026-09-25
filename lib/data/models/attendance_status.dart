/// حاضری کی حالت
/// Attendance Status Enum
enum AttendanceStatus {
  present,  // حاضر - Green
  absent,   // غیر حاضر - Red
  leave,    // چھٹی - Yellow/Amber
  late,     // تاخیر سے حاضر - Blue (Phase 5: teacher attendance selector)
}

/// Extension for AttendanceStatus to get Urdu labels and colors
extension AttendanceStatusExtension on AttendanceStatus {
  String get urduLabel {
    switch (this) {
      case AttendanceStatus.present:
        return 'حاضر';
      case AttendanceStatus.absent:
        return 'غیر حاضر';
      case AttendanceStatus.leave:
        return 'چھٹی';
      case AttendanceStatus.late:
        return 'تاخیر';
    }
  }

  /// Get the next status in cycle: Present -> Absent -> Leave -> Late -> Present
  AttendanceStatus get next {
    switch (this) {
      case AttendanceStatus.present:
        return AttendanceStatus.absent;
      case AttendanceStatus.absent:
        return AttendanceStatus.leave;
      case AttendanceStatus.leave:
        return AttendanceStatus.late;
      case AttendanceStatus.late:
        return AttendanceStatus.present;
    }
  }
}
