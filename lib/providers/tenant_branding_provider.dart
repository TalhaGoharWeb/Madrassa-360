/// Tenant branding + module gating — Phase 4 (SaaS transformation).
///
/// [TenantBranding] is the single source of institution identity for the UI.
/// It loads the active tenant's `tenants` row (name, logo, contact) and its
/// `tenant_settings` row (colours, font, language) and exposes them as a
/// plain immutable model. Screens drive app-bar titles, logos, contact info
/// and theme accents from this provider — never from hard-coded constants.
///
/// [tenantModulesProvider] exposes the set of module keys the active tenant
/// has enabled (`tenant_modules`). Navigation (bottom nav, drawer, dashboard
/// cards) must hide/disable anything not in this set.
///
/// Logged-out / null-tenant handling: branding falls back to neutral product
/// defaults ([TenantBranding.fallback]); modules return an empty set and
/// [isModuleEnabledProvider] treats "not loaded yet" as enabled so the UI
/// does not flicker-hide navigation while the tenant is resolving.
/// Permissions are still enforced independently.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────

/// Institution identity + visual settings for the active tenant.
class TenantBranding {
  final String name;
  final String? nameUrdu;
  final String? logoUrl;
  final String? phone;
  final String? email;
  final String? website;
  final String? address;
  final String? city;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final String fontFamily;
  final bool darkModeEnabled;
  final String language;

  const TenantBranding({
    required this.name,
    this.nameUrdu,
    this.logoUrl,
    this.phone,
    this.email,
    this.website,
    this.address,
    this.city,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.fontFamily,
    required this.darkModeEnabled,
    required this.language,
  });

  /// Neutral product defaults used when logged out or when the tenant row
  /// cannot be loaded. Contains no institution identity.
  factory TenantBranding.fallback() => const TenantBranding(
        name: 'مدرسہ 360',
        nameUrdu: 'مدرسہ 360',
        primaryColor: Color(0xFF0E7C5B),
        secondaryColor: Color(0xFF14532D),
        accentColor: Color(0xFFF59E0B),
        fontFamily: 'JameelNooriNastaleeq',
        darkModeEnabled: false,
        language: 'ur',
      );

  /// Builds branding from a `tenants` row joined with its `tenant_settings`
  /// row (settings may be null — column defaults then apply).
  factory TenantBranding.fromRows(
    Map<String, dynamic> tenant,
    Map<String, dynamic>? settings,
  ) {
    final s = settings ?? const <String, dynamic>{};
    return TenantBranding(
      name: (tenant['name'] as String?)?.trim().isNotEmpty == true
          ? (tenant['name'] as String).trim()
          : 'مدرسہ 360',
      nameUrdu: tenant['name_urdu'] as String?,
      logoUrl: tenant['logo_url'] as String?,
      phone: tenant['phone'] as String?,
      email: tenant['email'] as String?,
      website: tenant['website'] as String?,
      address: tenant['address'] as String?,
      city: tenant['city'] as String?,
      primaryColor:
          _parseColor(s['primary_color'] as String?, const Color(0xFF0E7C5B)),
      secondaryColor:
          _parseColor(s['secondary_color'] as String?, const Color(0xFF14532D)),
      accentColor:
          _parseColor(s['accent_color'] as String?, const Color(0xFFF59E0B)),
      fontFamily: (s['font'] as String?)?.trim().isNotEmpty == true
          ? s['font'] as String
          : 'JameelNooriNastaleeq',
      darkModeEnabled: s['dark_mode_enabled'] as bool? ?? false,
      language: (s['language'] as String?) ?? 'ur',
    );
  }

  /// Display name honouring the UI language: Urdu name when available.
  String displayName({bool urdu = true}) {
    if (urdu && nameUrdu != null && nameUrdu!.trim().isNotEmpty) {
      return nameUrdu!.trim();
    }
    return name;
  }

  /// One-line location string, e.g. "قصور، پنجاب". Empty when unknown.
  String get locationLine {
    final parts = [
      if (address != null && address!.trim().isNotEmpty) address!.trim(),
      if (city != null && city!.trim().isNotEmpty) city!.trim(),
    ];
    return parts.join('، ');
  }

  bool get hasLogo => logoUrl != null && logoUrl!.trim().isNotEmpty;
  bool get hasContact =>
      (phone != null && phone!.trim().isNotEmpty) ||
      (email != null && email!.trim().isNotEmpty);

  /// Parses '#RRGGBB' / 'RRGGBB' / '#AARRGGBB'; falls back on any bad input.
  static Color _parseColor(String? hex, Color fallback) {
    if (hex == null) return fallback;
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return fallback;
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }
}

// ─────────────────────────────────────────────
// Branding provider
// ─────────────────────────────────────────────

/// Branding for the active tenant. Falls back to neutral product defaults
/// when logged out or when the rows cannot be read.
final tenantBrandingProvider = FutureProvider<TenantBranding>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return TenantBranding.fallback();

  final client = SupabaseService.client;
  final results = await Future.wait([
    client
        .from('tenants')
        .select(
            'name, name_urdu, logo_url, phone, email, website, address, city')
        .eq('id', tenantId)
        .maybeSingle(),
    client
        .from('tenant_settings')
        .select(
            'language, primary_color, secondary_color, accent_color, font, dark_mode_enabled')
        .eq('tenant_id', tenantId)
        .maybeSingle(),
  ]);

  final tenantRow = results[0];
  if (tenantRow == null) return TenantBranding.fallback();
  return TenantBranding.fromRows(tenantRow, results[1]);
});

// ─────────────────────────────────────────────
// Module gating
// ─────────────────────────────────────────────

/// Keys of the modules the active tenant has enabled (from
/// `tenant_modules`). Empty when logged out. On read failure it also
/// returns empty, so module-gated navigation fails closed (hides the
/// module) rather than leaking unlicensed UI — callers distinguish
/// "still loading" (`valueOrNull == null`, no filtering) from
/// "loaded/failed" (filtering applies).
final tenantModulesProvider = FutureProvider<Set<String>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <String>{};
  try {
    final rows = await SupabaseService.client
        .from('tenant_modules')
        .select('module')
        .eq('tenant_id', tenantId)
        .eq('enabled', true);
    return <String>{
      for (final r in (rows as List))
        (r as Map<String, dynamic>)['module'] as String
    };
  } catch (_) {
    // Offline / RLS hiccup: fail closed for gating decisions made
    // through buildNavTabs (which requires a non-null set), but do not
    // crash the UI.
    return <String>{};
  }
});

/// Applies a tenant's brand colours to a [ThemeData].
///
/// Used by the app root so the whole app (app bars, buttons, FABs,
/// colour scheme) follows the active tenant's branding. Typography is
/// intentionally untouched — Jameel Noori Nastaleeq stays the UI font.
extension TenantBrandedTheme on ThemeData {
  ThemeData withTenantBranding(TenantBranding branding) {
    return copyWith(
      colorScheme: colorScheme.copyWith(
        primary: branding.primaryColor,
        onPrimary: Colors.white,
        secondary: branding.secondaryColor,
        onSecondary: Colors.white,
        tertiary: branding.accentColor,
      ),
      appBarTheme: appBarTheme.copyWith(
        backgroundColor: branding.primaryColor,
      ),
      floatingActionButtonTheme: floatingActionButtonTheme.copyWith(
        backgroundColor: branding.accentColor,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: branding.primaryColor,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

/// Whether [module] is enabled for the active tenant.
///
/// Returns `true` while the module set is still loading (or the user is
/// logged out) so navigation does not flicker-hide during tenant
/// resolution. Pass an explicitly loaded set to [buildNavTabs]-style
/// helpers instead when a fail-closed decision is required.
final isModuleEnabledProvider = Provider.family<bool, String>((ref, module) {
  final modules = ref.watch(tenantModulesProvider).valueOrNull;
  if (modules == null) return true; // still loading — don't hide yet
  return modules.contains(module);
});
