/// رپورٹ ڈیٹا ماڈلز
/// Plain data holders for the reporting engine. All populated from the
/// local Drift database — see report_data.dart.

/// A student with the fields reports need (typed columns + data JSON).
class ReportStudent {
  final String id;
  final String name;
  final String? rollNo;
  final String? classId;
  final String? className;
  final String? darjaName;
  final String? fatherName;
  final String? dateOfBirth;
  final String? dateOfAdmit;
  final String? phone;
  final String? address;

  const ReportStudent({
    required this.id,
    required this.name,
    this.rollNo,
    this.classId,
    this.className,
    this.darjaName,
    this.fatherName,
    this.dateOfBirth,
    this.dateOfAdmit,
    this.phone,
    this.address,
  });
}

class ReportClass {
  final String id;
  final String name;
  final String? darjaId;
  final String? darjaName;
  const ReportClass({
    required this.id,
    required this.name,
    this.darjaId,
    this.darjaName,
  });
}

class ReportDarja {
  final String id;
  final String name;
  const ReportDarja({required this.id, required this.name});
}

class ReportExam {
  final String id;
  final String name;
  final String? classId;
  final String? className;
  final String? examDate;
  const ReportExam({
    required this.id,
    required this.name,
    this.classId,
    this.className,
    this.examDate,
  });
}

class ReportStaff {
  final String id;
  final String name;
  final String? designation;
  final String? phone;
  const ReportStaff({
    required this.id,
    required this.name,
    this.designation,
    this.phone,
  });
}

/// One attendance mark. Status ∈ present | absent | leave | late.
class AttendanceMark {
  final String studentId;
  final String date; // YYYY-MM-DD
  final String status;
  const AttendanceMark({
    required this.studentId,
    required this.date,
    required this.status,
  });
}

/// Aggregated attendance for one student.
class AttendanceSummary {
  final String studentId;
  final String studentName;
  final String? rollNo;
  int present = 0;
  int absent = 0;
  int leave = 0;
  int late = 0;

  /// Statuses outside present/absent/leave/late. Never counted as
  /// present — unknown data must not inflate attendance.
  int unknown = 0;

  AttendanceSummary({
    required this.studentId,
    required this.studentName,
    this.rollNo,
  });

  int get marked => present + absent + leave + late + unknown;

  /// (present + late) / marked — late counts as attended. Unknown
  /// statuses lower the percentage honestly instead of being
  /// silently counted as present.
  double? get percentage =>
      marked == 0 ? null : (present + late) * 100.0 / marked;
}

class ReportInvoice {
  final String id;
  final String studentId;
  final String? invoiceNumber;
  final String? billingMonth;
  final String? issueDate;
  final String? dueDate;
  final String status;
  final double total;
  final double amountPaid;
  final double discountTotal;

  const ReportInvoice({
    required this.id,
    required this.studentId,
    this.invoiceNumber,
    this.billingMonth,
    this.issueDate,
    this.dueDate,
    required this.status,
    required this.total,
    this.amountPaid = 0,
    this.discountTotal = 0,
  });

  double get balanceDue => total - amountPaid - discountTotal;
}

class ReportPayment {
  final String id;
  final String? studentId;
  final String? invoiceId;
  final double amount;
  final String? paymentDate;
  final String? method;
  final String? notes;

  const ReportPayment({
    required this.id,
    this.studentId,
    this.invoiceId,
    required this.amount,
    this.paymentDate,
    this.method,
    this.notes,
  });
}

class ReportInvoiceItem {
  final String description;
  final double amount;
  const ReportInvoiceItem({required this.description, required this.amount});
}

/// One exam result row (per subject).
class ReportResult {
  final String examId;
  final String studentId;
  final String subject;

  /// Null when the DB row has no usable marks — never presented as 0.
  final double? obtained;
  final double? totalMarks;

  const ReportResult({
    required this.examId,
    required this.studentId,
    required this.subject,
    this.obtained,
    this.totalMarks,
  });

  /// Only rows with both values (and a positive total) feed totals,
  /// percentages and rankings.
  bool get usable =>
      obtained != null && totalMarks != null && totalMarks! > 0;

  double? get percent =>
      usable ? obtained! * 100.0 / totalMarks! : null;
}

/// Aggregated exam outcome for one student.
class ExamOutcome {
  final String studentId;
  final String studentName;
  final String? rollNo;
  double obtained = 0;
  double total = 0;
  int position = 0;

  /// False when no usable marks exist for this student in the exam —
  /// such students are left unranked (position 0) rather than ranked
  /// on synthetic zeroes.
  bool hasMarks = false;

  ExamOutcome({
    required this.studentId,
    required this.studentName,
    this.rollNo,
  });

  double? get percentage => total <= 0 ? null : obtained * 100.0 / total;
}

/// Assigns dense-ranking positions (1-based) by [ExamOutcome.obtained],
/// descending, over the students with [ExamOutcome.hasMarks] == true.
/// Students without usable marks keep position 0 (unranked).
///
/// Extracted from `ReportData.examOutcomes` for unit testing — the
/// algorithm is unchanged (ties share a rank; the next distinct score
/// takes rank+1).
void assignDensePositions(Iterable<ExamOutcome> outcomes) {
  final ranked = outcomes.where((o) => o.hasMarks).toList()
    ..sort((a, b) => b.obtained.compareTo(a.obtained));
  var rank = 0;
  double? last;
  for (final o in ranked) {
    if (last == null || o.obtained < last) {
      rank++;
      last = o.obtained;
    }
    o.position = rank;
  }
}

/// Income or expense ledger entry.
class MoneyEntry {
  final String id;
  final bool isIncome;
  final double? amount; // null when the cached row has no parseable amount
  final String? entryDate; // YYYY-MM-DD
  final String? category;
  final String? description;

  const MoneyEntry({
    required this.id,
    required this.isIncome,
    this.amount,
    this.entryDate,
    this.category,
    this.description,
  });
}

/// Shared grading scale (documented in docs/REPORTING.md).
String gradeFor(double? percentage) {
  if (percentage == null) return '—';
  if (percentage >= 90) return 'A+';
  if (percentage >= 80) return 'A';
  if (percentage >= 70) return 'B';
  if (percentage >= 60) return 'C';
  if (percentage >= 50) return 'D';
  return 'F';
}

String fmtMoney(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
