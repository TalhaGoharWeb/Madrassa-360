/// اسناد ریپوزیٹری
/// Certificate repository — isolated boundary for issuance TRACKING
/// (Phase 8).
///
/// SCOPE: certificate GENERATION is real and already works through the
/// existing reporting engine ([ReportsService] +
/// `lib/core/reports/documents/student_documents.dart` — character and
/// transfer certificates). This repository covers only issuance
/// HISTORY (who got which certificate, when, with which serial number).
///
/// BACKEND STATUS: no issuance/serial/verification table exists — see
/// `docs/audit-backend-capabilities.md`. [UnavailableCertificateRepository]
/// is the current implementation: every call throws
/// [BackendUnavailableException] so the UI renders an honest
/// backend-unavailable state for the history tab instead of fake rows.
/// PDF generation itself is unaffected — it runs against the local
/// database through the real report pipeline.

import '../../core/errors/app_exceptions.dart';

/// سند کی قسم — maps 1:1 to real report ids in [ReportCatalog].
enum CertificateType {
  /// کردار سرٹیفکیٹ → report id `character_certificate`
  character('character_certificate', 'کردار سرٹیفکیٹ'),

  /// منتقلی سرٹیفکیٹ → report id `transfer_certificate`
  transfer('transfer_certificate', 'منتقلی سرٹیفکیٹ');

  /// The real report id in [ReportCatalog] / [ReportsService].
  final String reportId;

  /// Urdu label shown in the UI.
  final String labelUr;

  const CertificateType(this.reportId, this.labelUr);
}

/// اجراء کا ریکارڈ — one issuance log row (backend-pending).
class CertificateIssuance {
  final String id;
  final String tenantId;
  final String studentId;
  final String studentName;
  final CertificateType type;
  final String? serialNumber;
  final DateTime issuedAt;
  final String? issuedBy;

  const CertificateIssuance({
    required this.id,
    required this.tenantId,
    required this.studentId,
    required this.studentName,
    required this.type,
    this.serialNumber,
    required this.issuedAt,
    this.issuedBy,
  });
}

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

/// Stable contract for certificate issuance tracking. When the backend
/// exists, [recordIssuance] assigns the serial number server-side and
/// [history] returns the tenant-scoped log.
abstract class CertificateRepository {
  /// Issuance history for the tenant, newest first.
  Future<List<CertificateIssuance>> history(String tenantId);

  /// Next serial number for [type] (server-assigned when backend exists).
  Future<String?> nextSerialNumber(String tenantId, CertificateType type);

  /// Log one issuance after the PDF has been successfully generated.
  Future<CertificateIssuance> recordIssuance(CertificateIssuance issuance);
}

// ─────────────────────────────────────────────
// Current implementation: backend pending
// ─────────────────────────────────────────────

/// Current issuance-tracking implementation. No issuance table exists
/// yet, so every operation throws [BackendUnavailableException]. The
/// certificate GENERATION path (real PDFs via [ReportsService]) does not
/// go through this repository and is fully functional.
class UnavailableCertificateRepository implements CertificateRepository {
  const UnavailableCertificateRepository();

  static const _ex = BackendUnavailableException(
    technicalDetails:
        'certificate issuance table not provisioned (see docs/audit-backend-capabilities.md)',
  );

  @override
  Future<List<CertificateIssuance>> history(String tenantId) async => throw _ex;

  @override
  Future<String?> nextSerialNumber(
          String tenantId, CertificateType type) async =>
      throw _ex;

  @override
  Future<CertificateIssuance> recordIssuance(
          CertificateIssuance issuance) async =>
      throw _ex;
}
