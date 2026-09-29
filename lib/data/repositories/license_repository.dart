/// پلیٹ فارم لائسنس آپریشنز
/// Platform-admin license operations against public.licenses.
///
/// STATUS VOCABULARY — the single source of truth is the CHECK constraint
/// in supabase/migrations/011_licensing.sql:
///   CHECK (status IN ('trial','active','grace_period','expired','suspended','cancelled'))
///
/// There is NO 'revoked' status. "Revoking" a license = setting
/// status='cancelled' (the closest valid state) + a log_audit() entry.
/// Platform admins hold RLS `FOR ALL` on public.licenses, so both
/// operations below are REAL direct updates — no revoke/extend RPC or
/// Edge Function exists. Every write is followed by a verify-read and a
/// log_audit() RPC entry; a write that does not persist throws instead of
/// reporting success.

import 'package:supabase_flutter/supabase_flutter.dart';

/// The exact CHECK vocabulary from 011_licensing.sql — the ONLY statuses a
/// license row can hold. UI filters and tests must consume this list, never
/// a hand-written copy (a previous screen shipped a bogus 'revoked'
/// filter that matched zero rows).
const licenseStatusVocabulary = [
  'trial',
  'active',
  'grace_period',
  'expired',
  'suspended',
  'cancelled',
];

/// Filter chips: 'all' plus the real vocabulary.
const licenseStatusFilters = ['all', ...licenseStatusVocabulary];

/// Urdu label for each valid status.
String licenseStatusUrdu(String status) {
  switch (status) {
    case 'trial':
      return 'آزمائشی';
    case 'active':
      return 'فعال';
    case 'grace_period':
      return 'مہلت';
    case 'expired':
      return 'میعاد ختم';
    case 'suspended':
      return 'معطل';
    case 'cancelled':
      return 'منسوخ';
    default:
      return status;
  }
}

/// One license row with its joined tenant + plan names.
class LicenseRecord {
  final String id;
  final String? tenantId;
  final String? planId;
  final String status;
  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final int? maxUsers;
  final int? maxStudents;
  final List<String> enabledModules;
  final String? tenantName;
  final String? tenantCode;
  final String? planName;

  const LicenseRecord({
    required this.id,
    required this.tenantId,
    required this.planId,
    required this.status,
    required this.issuedAt,
    required this.expiresAt,
    required this.maxUsers,
    required this.maxStudents,
    required this.enabledModules,
    required this.tenantName,
    required this.tenantCode,
    required this.planName,
  });

  factory LicenseRecord.fromJson(Map<String, dynamic> json) {
    final tenant = json['tenants'] as Map<String, dynamic>?;
    final plan = json['license_plans'] as Map<String, dynamic>?;
    final modules = json['enabled_modules'];
    return LicenseRecord(
      id: (json['id'] as String?) ?? '',
      tenantId: json['tenant_id'] as String?,
      planId: json['plan_id'] as String?,
      status: (json['status'] as String?) ?? 'unknown',
      issuedAt: _parseTime(json['issued_at']),
      expiresAt: _parseTime(json['expires_at']),
      maxUsers: json['max_users'] as int?,
      maxStudents: json['max_students'] as int?,
      enabledModules:
          modules is List ? [for (final m in modules) m.toString()] : const [],
      tenantName: tenant?['name'] as String?,
      tenantCode: tenant?['tenant_code'] as String?,
      planName: plan?['name'] as String?,
    );
  }

  bool get isCancelled => status == 'cancelled';

  static DateTime? _parseTime(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}

/// Thrown when a license write does not persist or the audit entry fails.
class LicenseOperationException implements Exception {
  final String message;
  const LicenseOperationException(this.message);

  @override
  String toString() => 'LicenseOperationException: $message';
}

/// Real license writes for platform admins (MasterAdminGuard callers).
///
/// All methods throw [LicenseOperationException] on failure — callers must
/// surface it as an honest error, never as success.
class LicenseRepository {
  LicenseRepository(this._client);

  final SupabaseClient _client;

  /// Real license rows (RLS: platform admins see all).
  Future<List<LicenseRecord>> fetchLicenses({String? status}) async {
    if (status != null &&
        status != 'all' &&
        !licenseStatusVocabulary.contains(status)) {
      throw ArgumentError('Invalid license status filter: $status');
    }
    var q = _client.from('licenses').select('''
        id, tenant_id, plan_id, status, issued_at, expires_at,
        max_users, max_students, enabled_modules,
        tenants ( name, tenant_code ),
        license_plans ( name )
      ''');
    if (status != null && status != 'all') q = q.eq('status', status);
    final rows =
        await q.order('expires_at', ascending: true, nullsFirst: false);
    return [
      for (final r in rows)
        LicenseRecord.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Real revoke: UPDATE status='cancelled' + log_audit('license.revoked').
  ///
  /// Throws [LicenseOperationException] when the write does not persist
  /// or the audit entry fails.
  Future<void> revokeLicense(
    LicenseRecord license, {
    String? reason,
  }) async {
    try {
      await _client
          .from('licenses')
          .update({'status': 'cancelled'}).eq('id', license.id);
    } catch (e) {
      throw LicenseOperationException('لائسنس منسوخ نہیں ہو سکا: $e');
    }
    final persisted = await _readStatus(license.id);
    if (persisted != 'cancelled') {
      throw const LicenseOperationException(
        'لائسنس منسوخ نہیں ہوا — ڈیٹا بیس میں تبدیلی محفوظ نہیں ہوئی۔',
      );
    }
    await _logAudit(
      tenantId: license.tenantId,
      action: 'license.revoked',
      entityId: license.id,
      oldData: {'status': license.status},
      newData: {'status': 'cancelled'},
      metadata: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (license.tenantName != null) 'tenant_name': license.tenantName!,
      },
    );
  }

  /// Real extension: UPDATE expires_at + log_audit('license.extended').
  ///
  /// Throws [LicenseOperationException] when the write does not persist
  /// or the audit entry fails.
  Future<void> extendLicense(
    LicenseRecord license,
    DateTime newExpiry, {
    String? note,
  }) async {
    try {
      await _client
          .from('licenses')
          .update({'expires_at': newExpiry.toUtc().toIso8601String()}).eq(
              'id', license.id);
    } catch (e) {
      throw LicenseOperationException('میعاد بڑھائی نہیں جا سکی: $e');
    }
    final persisted = await _readExpiry(license.id);
    if (persisted == null ||
        persisted.difference(newExpiry).abs() > const Duration(seconds: 2)) {
      throw const LicenseOperationException(
        'میعاد بڑھائی نہیں گئی — ڈیٹا بیس میں تبدیلی محفوظ نہیں ہوئی۔',
      );
    }
    await _logAudit(
      tenantId: license.tenantId,
      action: 'license.extended',
      entityId: license.id,
      oldData: {'expires_at': license.expiresAt?.toIso8601String()},
      newData: {'expires_at': newExpiry.toIso8601String()},
      metadata: {
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (license.tenantName != null) 'tenant_name': license.tenantName!,
      },
    );
  }

  Future<String?> _readStatus(String id) async {
    final row = await _client
        .from('licenses')
        .select('status')
        .eq('id', id)
        .maybeSingle();
    return row?['status'] as String?;
  }

  Future<DateTime?> _readExpiry(String id) async {
    final row = await _client
        .from('licenses')
        .select('expires_at')
        .eq('id', id)
        .maybeSingle();
    final v = row?['expires_at'];
    if (v == null) return null;
    return v is DateTime ? v : DateTime.tryParse(v.toString());
  }

  /// Client-safe audit writer (012_audit_logs.sql: SECURITY DEFINER).
  /// [tenantId] may be null for platform-level entries; platform admins
  /// pass the is_tenant_admin() gate for any tenant.
  Future<void> _logAudit({
    required String? tenantId,
    required String action,
    required String entityId,
    required Map<String, Object?> oldData,
    required Map<String, Object?> newData,
    required Map<String, Object?> metadata,
  }) async {
    try {
      await _client.rpc('log_audit', params: {
        'p_tenant_id': tenantId,
        'p_action': action,
        'p_entity': 'license',
        'p_entity_id': entityId,
        'p_old': oldData,
        'p_new': newData,
        'p_metadata': metadata,
      });
    } catch (e) {
      throw LicenseOperationException('آڈٹ اندراج ناکام ہوا: $e');
    }
  }
}
