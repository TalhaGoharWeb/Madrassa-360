/// Tenant branding → offline report cache sync.
///
/// [tenantBrandingProvider] loads the live `tenants` / `tenant_settings`
/// rows from Supabase; the reporting engine ([loadReportBranding]) reads
/// branding from the LOCAL `tenant_settings_cache` + logo file so
/// certificates, fee receipts, papers and other documents generate fully
/// offline. This provider bridges the two: whenever branding resolves
/// from the network it persists the payload (and downloads the logo
/// bytes) into the offline cache.
///
/// Kept in a separate file because `report_branding.dart` already imports
/// `tenant_branding_provider.dart` — importing it back from the provider
/// file would be a dependency cycle.
///
/// Watched once from the app root ([main.dart]) so the sync stays alive
/// for the whole session.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/reports/report_branding.dart';
import '../core/services/tenant_context.dart';
import '../data/local/database_provider.dart';
import 'tenant_branding_provider.dart';

/// Side-effect-only provider: keep the offline report branding cache warm.
///
/// Watch it once (app root). It does nothing until [tenantBrandingProvider]
/// yields a value, then fire-and-forget persists that branding for
/// offline document generation. Failures are swallowed inside
/// [cacheReportBranding] — the cache is best-effort.
final tenantBrandingCacheSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<TenantBranding>>(
    tenantBrandingProvider,
    (previous, next) {
      final branding = next.valueOrNull;
      if (branding == null || next.isLoading || next.hasError) return;
      final tenantId = ref.read(currentTenantIdProvider);
      if (tenantId == null || tenantId.isEmpty) return;
      // Skip the neutral fallback (logged-out / unloadable tenant) so we
      // never overwrite a real madrassa's cached branding with defaults.
      if (previous?.valueOrNull == branding) return;
      unawaited(
        cacheReportBranding(ref.read(appDatabaseProvider), tenantId, branding),
      );
    },
    fireImmediately: true,
  );
});
