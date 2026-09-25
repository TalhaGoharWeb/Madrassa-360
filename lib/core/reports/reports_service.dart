/// رپورٹنگ سروس
/// Facade for the offline-first reporting engine.
///
/// One entry point for PDF generation, CSV export and XLSX export.
/// All data comes from the local Drift database; branding from the
/// offline tenant-settings cache. No network access anywhere in this
/// path — safe to call with zero connectivity.

import 'dart:typed_data';

import '../data/local/app_database.dart';
import 'data/report_data.dart';
import 'documents/admin_reports.dart';
import 'documents/student_documents.dart';
import 'documents/student_reports.dart';
import 'export/csv_export.dart';
import 'export/excel_export.dart';
import 'export/tabular_data.dart';
import 'report_branding.dart';
import 'report_catalog.dart';
import 'report_context.dart';
import 'report_params.dart';
import 'urdu_pdf.dart';

/// Builds a PDF for [reportId] with [params].
///
/// Throws [ArgumentError] for unknown ids. Reports that need a student
/// (or exam) that isn't in the local DB still return a valid PDF with a
/// clean "not found" notice — never an exception, never mock data.
class ReportsService {
  ReportsService(this._db);

  final AppDatabase _db;

  Future<ReportContext> _context(
      String reportId, ReportParams params) async {
    final branding =
        await loadReportBranding(_db, params.tenantId);
    return ReportContext(
      data: ReportData(_db),
      branding: branding,
      urdu: UrduPdf(),
      params: params,
      definition: ReportCatalog.byId(reportId),
    );
  }

  Future<Uint8List> generatePdf(
      String reportId, ReportParams params) async {
    final ctx = await _context(reportId, params);
    switch (reportId) {
      // ── student documents ──
      case 'admission_form':
        return StudentDocuments.admissionForm(ctx);
      case 'student_id_card':
        return StudentDocuments.idCard(ctx);
      case 'character_certificate':
        return StudentDocuments.characterCertificate(ctx);
      case 'transfer_certificate':
        return StudentDocuments.transferCertificate(ctx);
      // ── student reports ──
      case 'result_card':
        return StudentReports.resultCard(ctx);
      case 'attendance_report':
        return StudentReports.attendanceReport(ctx);
      case 'fee_statement':
        return StudentReports.feeStatement(ctx);
      // ── admin reports ──
      case 'student_register':
        return AdminReports.studentRegister(ctx);
      case 'teacher_register':
        return AdminReports.teacherRegister(ctx);
      case 'attendance_summary':
        return AdminReports.attendanceSummary(ctx);
      case 'fee_collection':
        return AdminReports.feeCollection(ctx);
      case 'outstanding_fees':
        return AdminReports.outstandingFees(ctx);
      case 'income_expense':
        return AdminReports.incomeExpense(ctx);
      case 'exam_results':
        return AdminReports.examResults(ctx);
      case 'academic_performance':
        return AdminReports.academicPerformance(ctx);
      default:
        throw ArgumentError('Unknown report id: $reportId');
    }
  }

  /// CSV text (UTF-8 with BOM) for tabular reports.
  ///
  /// Throws [StateError] when the report is not tabular.
  Future<String> generateCsv(
      String reportId, ReportParams params) async {
    final ctx = await _context(reportId, params);
    if (!ctx.definition.tabular) {
      throw StateError('Report $reportId has no tabular export.');
    }
    final tables = await TabularData.build(reportId, ctx);
    if (tables == null) {
      throw StateError('Report $reportId has no tabular export.');
    }
    return CsvExport.build(tables);
  }

  /// XLSX bytes for tabular reports.
  ///
  /// Throws [StateError] when the report is not tabular.
  Future<Uint8List> generateXlsx(
      String reportId, ReportParams params) async {
    final ctx = await _context(reportId, params);
    if (!ctx.definition.tabular) {
      throw StateError('Report $reportId has no tabular export.');
    }
    final tables = await TabularData.build(reportId, ctx);
    if (tables == null) {
      throw StateError('Report $reportId has no tabular export.');
    }
    final bytes =
        ExcelExport.build(tables, branding: ctx.branding);
    return Uint8List.fromList(bytes);
  }
}
