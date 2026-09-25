// Attendance-percentage unit tests.
//
// Implementation files under test:
//   lib/core/reports/data/report_models.dart   (AttendanceSummary.percentage)
//   lib/data/models/attendance_status.dart     (AttendanceStatus cycle + labels)
//
// The weighting rule lives in AttendanceSummary.percentage:
//   (present + late) / marked * 100, where marked includes unknown
// statuses. Late counts as attended; leave and absent do not; unknown
// statuses lower the percentage honestly instead of inflating it.
//
// HONESTY NOTE: the per-mark -> counter aggregation switch lives in
// ReportData.attendanceSummary (lib/core/reports/data/report_data.dart)
// and needs a live Drift database, so it is NOT covered here — only the
// pure model formula and the status enum are.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/reports/data/report_models.dart';
import 'package:madrasa_360/data/models/attendance_status.dart';

AttendanceSummary _summary({
  int present = 0,
  int absent = 0,
  int leave = 0,
  int late = 0,
  int unknown = 0,
}) {
  final s = AttendanceSummary(studentId: 's1', studentName: 'Test');
  s.present = present;
  s.absent = absent;
  s.leave = leave;
  s.late = late;
  s.unknown = unknown;
  return s;
}

void main() {
  group('AttendanceSummary.percentage weighting', () {
    test('all present -> 100', () {
      expect(_summary(present: 20).percentage, 100.0);
    });

    test('no marks at all -> null (not 0, not a crash)', () {
      expect(_summary().percentage, isNull);
      expect(_summary().marked, 0);
    });

    test('late counts as attended', () {
      // 8 present + 2 late out of 10 marked -> 100
      expect(_summary(present: 8, late: 2).percentage, 100.0);
    });

    test('absent and leave lower the percentage', () {
      // 15 present out of 20 marked (3 absent, 2 leave) -> 75
      expect(_summary(present: 15, absent: 3, leave: 2).percentage, 75.0);
    });

    test('unknown statuses are counted in the denominator, never as present',
        () {
      // 9 present + 1 unknown out of 10 marked -> 90, not 100
      final s = _summary(present: 9, unknown: 1);
      expect(s.marked, 10);
      expect(s.percentage, 90.0);
    });

    test('all unknown -> 0, honestly reflecting missing data', () {
      expect(_summary(unknown: 5).percentage, 0.0);
    });

    test('fractional percentages are exact doubles', () {
      // 2 of 3 -> 66.666...
      final p = _summary(present: 2, absent: 1).percentage!;
      expect(p, closeTo(66.666666, 0.0001));
    });

    test('marked counts every category exactly once', () {
      final s = _summary(present: 5, absent: 2, leave: 1, late: 1, unknown: 1);
      expect(s.marked, 10);
      // (5 + 1) / 10
      expect(s.percentage, 60.0);
    });
  });

  group('AttendanceStatus cycle + labels', () {
    test('next() cycles present -> absent -> leave -> late -> present', () {
      expect(AttendanceStatus.present.next, AttendanceStatus.absent);
      expect(AttendanceStatus.absent.next, AttendanceStatus.leave);
      expect(AttendanceStatus.leave.next, AttendanceStatus.late);
      expect(AttendanceStatus.late.next, AttendanceStatus.present);
    });

    test('urdu labels are the documented four', () {
      expect(AttendanceStatus.present.urduLabel, 'حاضر');
      expect(AttendanceStatus.absent.urduLabel, 'غیر حاضر');
      expect(AttendanceStatus.leave.urduLabel, 'چھٹی');
      expect(AttendanceStatus.late.urduLabel, 'تاخیر');
    });
  });
}
