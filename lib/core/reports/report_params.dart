/// رپورٹ پیرامیٹرز
/// Report parameters + catalog model — Phase 6 reporting engine.
///
/// Every report is generated from the LOCAL Drift database only
/// (offline-first). [ReportParams] carries the tenant scope plus the
/// optional filters the hub screen collects.

/// Report families shown as tabs in the hub.
enum ReportCategory {
  student, // طلبہ — per-student documents & statements
  admin, // انتظامیہ — registers & summaries
}

/// Filter + generation parameters for one report run.
class ReportParams {
  final String tenantId;
  final String? studentId;
  final String? classId;
  final String? darjaId;
  final String? examId;
  final DateTime? from; // inclusive, date part only
  final DateTime? to; // inclusive, date part only

  const ReportParams({
    required this.tenantId,
    this.studentId,
    this.classId,
    this.darjaId,
    this.examId,
    this.from,
    this.to,
  });

  /// `YYYY-MM-DD` or null.
  static String? _d(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  String? get fromIso => _d(from);
  String? get toIso => _d(to);

  bool get hasDateRange => from != null || to != null;
}

/// Static catalog entry for one report.
class ReportDefinition {
  final String id;
  final String titleEn;
  final String titleUr;
  final String descriptionEn;
  final String descriptionUr;
  final ReportCategory category;
  final bool needsStudent;
  final bool needsClass;
  final bool needsDarja;
  final bool needsExam;
  final bool needsDateRange;

  /// True when CSV/XLSX export is meaningful (tabular data).
  final bool tabular;

  const ReportDefinition({
    required this.id,
    required this.titleEn,
    required this.titleUr,
    required this.descriptionEn,
    required this.descriptionUr,
    required this.category,
    this.needsStudent = false,
    this.needsClass = false,
    this.needsDarja = false,
    this.needsExam = false,
    this.needsDateRange = false,
    this.tabular = false,
  });
}
