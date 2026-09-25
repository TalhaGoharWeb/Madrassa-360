/// نتیجہ ماڈل (Supabase)
/// Result models — map to public.exams and public.results tables

// ─────────────────────────────────────────────────────────────
// Subject result (one row in public.results)
// ─────────────────────────────────────────────────────────────

class SubjectResult {
  final String id;
  final String tenantId; // multi-tenant owner (public.tenants) — required
  final String examId;
  final String studentId;
  final String subject;
  final double marksObtained;
  final double totalMarks;

  const SubjectResult({
    required this.id,
    required this.tenantId,
    required this.examId,
    required this.studentId,
    required this.subject,
    required this.marksObtained,
    required this.totalMarks,
  });

  double get percentage => totalMarks > 0 ? (marksObtained / totalMarks) * 100 : 0;

  String get grade {
    if (percentage >= 90) return 'الف+';
    if (percentage >= 80) return 'الف';
    if (percentage >= 70) return 'ب';
    if (percentage >= 60) return 'ج';
    if (percentage >= 50) return 'د';
    return 'فیل';
  }

  factory SubjectResult.fromJson(Map<String, dynamic> json) {
    return SubjectResult(
      id:            json['id'] as String,
      tenantId:      (json['tenant_id'] ?? json['madrasa_id'] ?? '') as String,
      examId:        json['exam_id'] as String,
      studentId:     json['student_id'] as String,
      subject:       json['subject'] as String,
      marksObtained: (json['marks_obtained'] as num).toDouble(),
      totalMarks:    (json['total_marks'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'tenant_id':      tenantId,
    'exam_id':        examId,
    'student_id':     studentId,
    'subject':        subject,
    'marks_obtained': marksObtained,
    'total_marks':    totalMarks,
  };
}

// ─────────────────────────────────────────────────────────────
// Student exam result (aggregated from all subjects for one exam)
// ─────────────────────────────────────────────────────────────

class StudentResult {
  final String examId;
  final String examName;
  final String examDate;
  final String studentId;
  final String studentName;
  final String className;
  final List<SubjectResult> subjects;

  const StudentResult({
    required this.examId,
    required this.examName,
    required this.examDate,
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.subjects,
  });

  double get totalObtained =>
      subjects.fold(0, (sum, s) => sum + s.marksObtained);
  double get totalMarks =>
      subjects.fold(0, (sum, s) => sum + s.totalMarks);
  double get percentage =>
      totalMarks > 0 ? (totalObtained / totalMarks) * 100 : 0;

  String get grade {
    if (percentage >= 90) return 'الف+';
    if (percentage >= 80) return 'الف';
    if (percentage >= 70) return 'ب';
    if (percentage >= 60) return 'ج';
    if (percentage >= 50) return 'د';
    return 'فیل';
  }
}

// ─────────────────────────────────────────────────────────────
// Exam header (one row in public.exams)
// ─────────────────────────────────────────────────────────────

class Exam {
  final String id;
  final String tenantId; // multi-tenant owner (public.tenants) — required
  final String name;
  final String? classId;
  final String examDate;
  final int totalMarks;

  const Exam({
    required this.id,
    required this.tenantId,
    required this.name,
    this.classId,
    required this.examDate,
    required this.totalMarks,
  });

  factory Exam.fromJson(Map<String, dynamic> json) {
    return Exam(
      id:         json['id'] as String,
      tenantId:   (json['tenant_id'] ?? json['madrasa_id'] ?? '') as String,
      name:       json['name'] as String,
      classId:    json['class_id'] as String?,
      examDate:   json['exam_date'] as String,
      totalMarks: json['total_marks'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'tenant_id':  tenantId,
    'name':        name,
    'class_id':    classId,
    'exam_date':   examDate,
    'total_marks': totalMarks,
  };
}
