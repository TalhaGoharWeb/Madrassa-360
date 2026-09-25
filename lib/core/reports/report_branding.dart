/// رپورٹ برانڈنگ (آف لائن)
/// Tenant branding for reports — OFFLINE-FIRST.
///
/// The reporting path must never touch the network, so branding is read
/// from the local `tenant_settings_cache` table (written by the sync
/// layer when connectivity exists), never from Supabase.
///
/// Cache payload contract (see docs/REPORTING.md):
/// ```json
/// {
///   "tenant":   { "name": "...", "name_urdu": "...", "logo_url": "...",
///                 "phone": "...", "email": "...", "address": "...",
///                 "city": "..." },
///   "settings": { "primary_color": "#0E7C5B", "secondary_color": "#14532D",
///                 "accent_color": "#F59E0B", "font": "JameelNooriNastaleeq" }
/// }
/// ```
/// The two maps are exactly what [TenantBranding.fromRows] expects, so any
/// writer that caches those rows keeps reports branded correctly.
///
/// Logo: a remote `logo_url` cannot be fetched offline. Reports use a
/// locally cached logo file when present:
/// `<app-support>/Madrassa360/branding/<tenantId>/logo.png`
/// (the writer that caches tenant settings should also cache the logo
/// bytes there, namespaced per tenant). Otherwise a neutral vector emblem is drawn in the
/// tenant's primary colour — never a broken image, never another
/// tenant's identity.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/app_database.dart';
import '../../providers/tenant_branding_provider.dart';

/// Branding snapshot used by every report header.
class ReportBranding {
  final String name;
  final String? nameUrdu;
  final String? addressLine;
  final String? phone;
  final String? email;
  final Uint8List? logoBytes;
  final Color primary;
  final Color secondary;
  final Color accent;

  const ReportBranding({
    required this.name,
    this.nameUrdu,
    this.addressLine,
    this.phone,
    this.email,
    this.logoBytes,
    required this.primary,
    required this.secondary,
    required this.accent,
  });

  factory ReportBranding.fromTenantBranding(
    TenantBranding b, {
    Uint8List? logoBytes,
  }) {
    return ReportBranding(
      name: b.name,
      nameUrdu: b.nameUrdu,
      addressLine: b.locationLine.isEmpty ? null : b.locationLine,
      phone: b.phone,
      email: b.email,
      logoBytes: logoBytes,
      primary: b.primaryColor,
      secondary: b.secondaryColor,
      accent: b.accentColor,
    );
  }

  /// Neutral product defaults — same values as [TenantBranding.fallback].
  factory ReportBranding.fallback() => const ReportBranding(
        name: 'مدرسہ 360',
        nameUrdu: 'مدرسہ 360',
        primary: Color(0xFF0E7C5B),
        secondary: Color(0xFF14532D),
        accent: Color(0xFFF59E0B),
      );

  bool get hasLogo => logoBytes != null && logoBytes!.isNotEmpty;

  /// Contact line for the header, e.g. "فون: 0300-1234567".
  String? get contactLine {
    final parts = <String>[
      if (phone != null && phone!.trim().isNotEmpty)
        'فون: ${phone!.trim()}',
      if (email != null && email!.trim().isNotEmpty) email!.trim(),
    ];
    return parts.isEmpty ? null : parts.join('   |   ');
  }
}

/// Loads the tenant's branding for reports without any network access.
///
/// Falls back to [ReportBranding.fallback] when the cache is empty or
/// unreadable — the report still generates, just with neutral branding.
Future<ReportBranding> loadReportBranding(
  AppDatabase db,
  String tenantId,
) async {
  try {
    final rows = await db
        .customSelect(
          'SELECT payload FROM tenant_settings_cache '
          'WHERE tenant_id = ? LIMIT 1',
          variables: [Variable.withString(tenantId)],
        )
        .get();
    if (rows.isNotEmpty) {
      final payload = rows.first.data['payload'] as String?;
      if (payload != null && payload.isNotEmpty) {
        final decoded = jsonDecode(payload) as Map<String, dynamic>;
        // Tolerate writers that cache a flat map (tenant keys at top
        // level) instead of the {tenant, settings} envelope.
        final tenantRaw = decoded['tenant'];
        final tenant = tenantRaw is Map
            ? tenantRaw.cast<String, dynamic>()
            : decoded;
        final settings =
            (decoded['settings'] as Map?)?.cast<String, dynamic>();
        final branding = TenantBranding.fromRows(tenant, settings);
        final logo = await _loadCachedLogo(tenantId);
        return ReportBranding.fromTenantBranding(branding, logoBytes: logo);
      }
    }
  } catch (_) {
    // Corrupt cache / missing table: fall through to neutral branding.
  }
  return ReportBranding.fallback();
}

/// Reads the offline-cached logo file, if a previous sync cached it.
///
/// The path is tenant-scoped (`branding/<tenantId>/logo.png`) so one
/// tenant's logo can never leak into another tenant's reports.
/// Null when absent or unreadable — the header then draws a vector emblem.
Future<Uint8List?> _loadCachedLogo(String tenantId) async {
  try {
    final support = await getApplicationSupportDirectory();
    final file = File(p.join(
        support.path, 'Madrassa360', 'branding', tenantId, 'logo.png'));
    if (await file.exists()) return await file.readAsBytes();
  } catch (_) {
    // ignore — emblem fallback
  }
  return null;
}
