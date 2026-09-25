// ════════════════════════════════════════════════════════════════════════════
//  MADRASA 360 — DEPLOYMENT CONFIGURATION (DEPRECATED)
//  ──────────────────────────────────────────────────────────────────────────
//  @deprecated — Institution identity is NO LONGER configured in source
//  code. Since Phase 4, every tenant's name, logo, contact details and
//  colours are loaded at runtime from the `tenants` / `tenant_settings`
//  tables via `tenantBrandingProvider`
//  (lib/providers/tenant_branding_provider.dart).
//
//  This class is kept only as a compile-safe shim for build metadata
//  (app version). Do NOT add institution-specific values here.
// ════════════════════════════════════════════════════════════════════════════

import 'app_config.dart';

/// @deprecated Use [tenantBrandingProvider] for institution identity.
/// Kept for build metadata only; contains no tenant-specific values.
@Deprecated(
    'Institution identity is tenant-driven now. '
    'Use tenantBrandingProvider instead of MadrassaConfig.')
class MadrassaConfig {
  MadrassaConfig._(); // static-only class

  /// App version shown in the About dialog (keep in sync with pubspec.yaml)
  static const String appVersion = AppConfig.appVersion;

  /// Build number (keep in sync with pubspec.yaml)
  static const String appBuildNumber = AppConfig.appBuildNumber;
}
