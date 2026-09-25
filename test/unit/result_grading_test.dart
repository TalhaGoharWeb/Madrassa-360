// Result-grading unit tests.
//
// Implementation files under test:
//   lib/data/models/result.dart                 (SubjectResult/StudentResult percentage + grade)
//   lib/core/reports/data/report_models.dart   (ExamOutcome.percentage, assignDensePositions)
//
// Grade bands (Urdu labels) are defined identically in both model classes:
//   >=90 الف+ | >=80 الف | >=70 ب | >=60 ج | >=50 د | else فیل
//
// Position uses dense ranking via the extracted assignDensePositions()
// helper (same algorithm ReportData.examOutcomes runs against the DB).

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/reports/data/report_models.dart';
import 'package:madrasa_360/data/models/result.dart';

SubjectResult _subject(double obtained, double total) => SubjectResult(
      id: 'r1',
      tenantId: 't1',
      examId: 'e1',
      studentId: 's1',
      subject: 'Quran',
      marksObtained: obtained,
      totalMarks: total,
    );

StudentResult _studentResult(List<SubjectResult> subjects) => StudentResult(
      examId: 'e1',
      examName: 'Test',
      examDate: '2026-09-01',
      studentId: 's1',
      studentName: 'Test',
      className: 'Darja 1',
      subjects: subjects,
    );

ExamOutcome _outcome(String id, double obtained,
    {bool hasMarks = true}) {
  final o = ExamOutcome(studentId: id, studentName: id);
  o.obtained = obtained;
  o.total = 100;
  o.hasMarks = hasMarks;
  return o;
}

void main() {
  group('SubjectResult percentage + grade bands', () {
    test('percentage is obtained/total * 100', () {
      expect(_subject(45, 50).percentage, 90.0);
    });

    test('grade band boundaries (inclusive lower bounds)', () {
      expect(_subject(90, 100).grade, 'الف+');
      expect(_subject(89.99, 100).grade, 'الف');
      expect(_subject(80, 100).grade, 'الف');
      expect(_subject(79.99, 100).grade, 'ب');
      expect(_subject(70, 100).grade, 'ب');
      expect(_subject(69.99, 100).grade, 'ج');
      expect(_subject(60, 100).grade, 'ج');
      expect(_subject(59.99, 100).grade, 'د');
      expect(_subject(50, 100).grade, 'د');
      expect(_subject(49.99, 100).grade, 'فیل');
      expect(_subject(0, 100).grade, 'فیل');
    });

    test('zero total marks -> 0 percent -> فیل (no division crash)', () {
      final s = _subject(0, 0);
      expect(s.percentage, 0);
      expect(s.grade, 'فیل');
    });

    test('JSON round-trip preserves marks', () {
      final s = _subject(75, 100);
      final back = SubjectResult.fromJson({
        'id': 'r1',
        'tenant_id': 't1',
        'exam_id': 'e1',
        'student_id': 's1',
        'subject': 'Quran',
        'marks_obtained': 75,
        'total_marks': 100,
      });
      expect(back.marksObtained, 75);
      expect(back.totalMarks, 100);
      expect(back.percentage, s.percentage);
      expect(back.grade, s.grade);
    });
  });

  group('StudentResult aggregation', () {
    test('totals fold across subjects', () {
      final r = _studentResult([
        _subject(80, 100),
        _subject(45, 50),
        _subject(30, 50),
      ]);
      expect(r.totalObtained, 155);
      expect(r.totalMarks, 200);
      expect(r.percentage, 77.5);
      expect(r.grade, 'ب');
    });

    test('no subjects -> 0 percent -> فیل', () {
      final r = _studentResult([]);
      expect(r.totalObtained, 0);
      expect(r.totalMarks, 0);
      expect(r.percentage, 0);
      expect(r.grade, 'فیل');
    });

    test('distinction aggregate hits الف+', () {
      final r = _studentResult([_subject(95, 100), _subject(92, 100)]);
      expect(r.grade, 'الف+');
    });
  });

  group('ExamOutcome.percentage', () {
    test('null when total is zero or negative', () {
      final o = ExamOutcome(studentId: 's1', studentName: 's1');
      expect(o.percentage, isNull);
    });

    test('obtained/total * 100 otherwise', () {
      final o = _outcome('s1', 170)..total = 200;
      expect(o.percentage, 85.0);
    });
  });

  group('assignDensePositions (dense ranking)', () {
    test('orders by obtained marks descending', () {
      final a = _outcome('a', 90);
      final b = _outcome('b', 70);
      final c = _outcome('c', 80);
      assignDensePositions([a, b, c]);
      expect(a.position, 1);
      expect(c.position, 2);
      expect(b.position, 3);
    });

    test('ties share a rank and the next rank is dense (1,1,2)', () {
      final a = _outcome('a', 90);
      final b = _outcome('b', 90);
      final c = _outcome('c', 80);
      assignDensePositions([a, b, c]);
      expect(a.position, 1);
      expect(b.position, 1);
      expect(c.position, 2);
    });

    test('students without usable marks stay unranked (position 0)', () {
      final a = _outcome('a', 90);
      final ghost = _outcome('ghost', 0, hasMarks: false);
      assignDensePositions([a, ghost]);
      expect(a.position, 1);
      expect(ghost.position, 0);
    });

    test('empty list and single student', () {
      assignDensePositions(const []);
      final solo = _outcome('solo', 55);
      assignDensePositions([solo]);
      expect(solo.position, 1);
    });

    test('all tied -> all rank 1', () {
      final outs =
          List.generate(4, (i) => _outcome('s$i', 75));
      assignDensePositions(outs);
      expect(outs.every((o) => o.position == 1), isTrue);
    });
  });
}
