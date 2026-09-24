/// فیس ماڈل (Supabase)
/// Fee model — maps to the public.fees table

/// حاضری کی حالت — Fee payment status (mirrors DB CHECK constraint)
enum FeeStatus { paid, partial, pending, pastDue }

extension FeeStatusX on FeeStatus {
  String get urduLabel {
    switch (this) {
      case FeeStatus.paid:    return 'ادا شدہ';
      case FeeStatus.partial: return 'جزوی';
      case FeeStatus.pending: return 'زیر التواء';
      case FeeStatus.pastDue: return 'واجب الادا';
    }
  }

  /// Maps Supabase snake_case value to enum.
  static FeeStatus fromString(String? s) {
    switch (s) {
      case 'paid':     return FeeStatus.paid;
      case 'partial':  return FeeStatus.partial;
      case 'past_due': return FeeStatus.pastDue;
      default:         return FeeStatus.pending;
    }
  }

  String get dbValue {
    switch (this) {
      case FeeStatus.paid:    return 'paid';
      case FeeStatus.partial: return 'partial';
      case FeeStatus.pending: return 'pending';
      case FeeStatus.pastDue: return 'past_due';
    }
  }
}

/// One fee record per student per month.
class Fee {
  final String id;
  final String studentId;
  final String studentName;   // joined from students
  final String studentClass;  // joined from students → classes
  final String month;         // 'YYYY-MM'
  final double amountDue;
  final double amountPaid;
  final String dueDate;       // ISO date 'YYYY-MM-DD'
  final String? paidDate;
  final FeeStatus status;     // GENERATED ALWAYS in DB; read-only

  const Fee({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.studentClass,
    required this.month,
    required this.amountDue,
    required this.amountPaid,
    required this.dueDate,
    this.paidDate,
    required this.status,
  });

  double get remaining => amountDue - amountPaid;

  factory Fee.fromJson(Map<String, dynamic> json) {
    final student = json['students'] as Map<String, dynamic>?;
    final studentClass =
        (student?['classes'] as Map<String, dynamic>?)?['name'] as String? ?? '';

    return Fee(
      id:           json['id'] as String,
      studentId:    json['student_id'] as String,
      studentName:  student?['name'] as String? ?? '',
      studentClass: studentClass,
      month:        json['month'] as String,
      amountDue:    (json['amount_due'] as num).toDouble(),
      amountPaid:   (json['amount_paid'] as num).toDouble(),
      dueDate:      json['due_date'] as String,
      paidDate:     json['paid_date'] as String?,
      status:       FeeStatusX.fromString(json['status'] as String?),
    );
  }

  /// For INSERT/UPDATE — only writable columns.
  Map<String, dynamic> toJson() => {
    'student_id':  studentId,
    'month':       month,
    'amount_due':  amountDue,
    'amount_paid': amountPaid,
    'due_date':    dueDate,
    'paid_date':   paidDate,
  };

  Fee copyWith({double? amountPaid, String? paidDate}) {
    return Fee(
      id: id,
      studentId: studentId,
      studentName: studentName,
      studentClass: studentClass,
      month: month,
      amountDue: amountDue,
      amountPaid: amountPaid ?? this.amountPaid,
      dueDate: dueDate,
      paidDate: paidDate ?? this.paidDate,
      status: status, // recalculated by DB; irrelevant for local copy
    );
  }
}
