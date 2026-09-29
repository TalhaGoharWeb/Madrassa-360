/// آڈٹ لاگ ایکسپورٹ — خالص مددگار
/// Pure helpers for the audit-log CSV/PDF export.
///
/// The export MUST apply the exact same filter params as the on-screen
/// list: [auditExportFilterParams] is a thin wrapper over
/// [auditFilterParams] (the unit-testable helper the list screen already
/// uses) so the export can never silently widen the user's active filters.
///
/// Network/device columns ([auditNetworkColumns]) are derived from the
/// ACTUAL fetched rows — a column is offered only when at least one row's
/// metadata JSON really contains that key. Nothing speculative.

import '../../../core/utils/audit_urdu.dart';

/// Metadata keys that look like network/device info. Offered as export
/// columns only when actually present in the data.
const auditNetworkKeyCandidates = [
  'ip',
  'ip_address',
  'device',
  'device_name',
  'user_agent',
];

/// The exact query constraints for an export, from the screen's active
/// filter state. Identical to the list query by construction.
Map<String, String> auditExportFilterParams({
  String? tenantId,
  String? action,
  String? actorId,
  DateTime? fromDay,
  DateTime? toDay,
}) {
  return auditFilterParams(
    tenantId: tenantId,
    action: action,
    actorId: actorId,
    fromDay: fromDay,
    toDay: toDay,
  );
}

/// Network/device metadata keys actually present in [rows].
///
/// Scans every row's `metadata` map; returns the candidate keys that
/// occur with a non-empty value, in candidate order. Empty when no row
/// carries network/device info — callers must then OMIT those columns.
List<String> auditNetworkColumns(List<Map<String, dynamic>> rows) {
  final present = <String>{};
  for (final row in rows) {
    final md = row['metadata'];
    if (md is Map) {
      for (final key in auditNetworkKeyCandidates) {
        final v = md[key];
        if (v != null && v.toString().trim().isNotEmpty) {
          present.add(key);
        }
      }
    }
  }
  return auditNetworkKeyCandidates.where(present.contains).toList();
}

/// Urdu label for a network metadata key.
String auditNetworkColumnUrdu(String key) {
  switch (key) {
    case 'ip':
    case 'ip_address':
      return 'آئی پی';
    case 'device':
    case 'device_name':
      return 'آلہ';
    case 'user_agent':
      return 'براؤزر/ایپ';
    default:
      return key;
  }
}

/// Export table headers: the fixed base columns plus any real network
/// columns discovered in the data.
List<String> buildAuditExportHeaders(List<String> networkColumns) {
  return [
    'تاریخ و وقت',
    'مدرسہ',
    'صارف',
    'عمل',
    'تفصیل',
    for (final c in networkColumns) auditNetworkColumnUrdu(c),
  ];
}

Map<String, dynamic>? _asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// One export row: [تاریخ و وقت, مدرسہ, صارف, عمل, تفصیل, ...network].
///
/// [actorName] is the resolved display name (may be null → 'نامعلوم').
/// The detail cell is the same human-readable Urdu message the list
/// screen renders — never raw JSON.
List<String> buildAuditExportRow(
  Map<String, dynamic> log, {
  required String? actorName,
  required List<String> networkColumns,
}) {
  final tenant = _asMap(log['tenants']);
  final action = (log['action'] as String?) ?? '';
  final createdAt = log['created_at'];
  DateTime? t;
  if (createdAt is DateTime) {
    t = createdAt;
  } else if (createdAt != null) {
    t = DateTime.tryParse(createdAt.toString());
  }
  final message = auditMessageUrdu(
    action: action,
    actorName: actorName,
    tenantName: tenant?['name'] as String?,
    entity: log['entity'] as String?,
    entityId: log['entity_id'] as String?,
    oldData: _asMap(log['old_data']),
    newData: _asMap(log['new_data']),
    metadata: _asMap(log['metadata']),
  );
  final md = _asMap(log['metadata']) ?? const {};
  return [
    t == null ? '—' : formatAuditDateUrdu(t),
    (tenant?['name'] as String?) ?? 'پلیٹ فارم',
    actorName ?? 'نامعلوم',
    auditActionLabelUrdu(action),
    message,
    for (final c in networkColumns) (md[c]?.toString() ?? '—'),
  ];
}
