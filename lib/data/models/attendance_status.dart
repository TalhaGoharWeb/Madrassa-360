/// حاضری کی حالت
/// Attendance Status Enum
enum AttendanceStatus {
  present,  // حاضر - Green
  absent,   // غیر حاضر - Red
  leave,    // چھٹی - Yellow/Amber
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
    }
  }

  /// Get the next status in cycle: Present -> Absent -> Leave -> Present
  AttendanceStatus get next {
    switch (this) {
      case AttendanceStatus.present:
        return AttendanceStatus.absent;
      case AttendanceStatus.absent:
        return AttendanceStatus.leave;
      case AttendanceStatus.leave:
        return AttendanceStatus.present;
    }
  }
}
