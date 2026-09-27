/// مدرسے کے لوگو کی خدمت
/// Tenant logo service — upload / remove / toggle for madrassa logos.
///
/// Storage layout: `tenant-logos/<tenant_id>/logo.png` (public bucket).
/// The public URL is stored in `tenants.logo_url`; the owner toggle lives
/// in `tenants.use_logo_on_reports`.
///
/// Offline reports: [report_branding.dart] reads the logo from the local
/// cache `<app-support>/Madrassa360/branding/<tenantId>/logo.png`. This
/// service keeps that cache in sync — caching on upload, clearing on
/// remove or when the owner disables "use on reports".

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/observability/app_logger.dart';
import '../core/services/supabase_service.dart';

/// Supabase Storage bucket for tenant logos (public read).
const String kTenantLogosBucket = 'tenant-logos';

/// Thrown when the caller is not allowed to manage the tenant's logo.
/// (RLS is the real enforcement; this is defense-in-depth.)
class TenantLogoDenied implements Exception {
  final String message;
  const TenantLogoDenied([this.message = 'آپ کو لوگو تبدیل کرنے کی اجازت نہیں ہے']);
  @override
  String toString() => 'TenantLogoDenied: $message';
}

class TenantLogoService {
  final SupabaseClient _client;

  TenantLogoService({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  String _logoPath(String tenantId) => '$tenantId/logo.png';

  /// Public URL for the tenant's logo path (pure local computation).
  String _publicUrl(String tenantId) => _client.storage
      .from(kTenantLogosBucket)
      .getPublicUrl(_logoPath(tenantId));

  /// Local offline cache file for reports (must match report_branding.dart).
  Future<File> _cacheFile(String tenantId) async {
    final support = await getApplicationSupportDirectory();
    return File(
        p.join(support.path, 'Madrassa360', 'branding', tenantId, 'logo.png'));
  }

  /// Upload a new logo for [tenantId].
  ///
  /// Uploads to `tenant-logos/<tenantId>/logo.png` (upsert), stores the
  /// public URL in `tenants.logo_url`, and refreshes the offline report
  /// cache. Returns the public URL.
  Future<String> uploadLogo(String tenantId, XFile image) async {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      throw ArgumentError('خالی تصویر اپ لوڈ نہیں ہو سکتی');
    }

    // 1. Upload (upsert) to storage.
    try {
      await _client.storage.from(kTenantLogosBucket).uploadBinary(
            _logoPath(tenantId),
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/png',
            ),
          );
    } on StorageException catch (e) {
      AppLogger.e('Logo upload failed', e);
      throw TenantLogoDenied('لوگو اپ لوڈ ناکام: ${e.message}');
    }

    // 2. Persist the public URL on the tenant row.
    final url = _publicUrl(tenantId);
    await _client
        .from('tenants')
        .update({'logo_url': url}).eq('id', tenantId);

    // 3. Refresh the offline cache so reports pick it up immediately.
    await _writeCache(tenantId, bytes);

    AppLogger.i('Logo uploaded for tenant $tenantId');
    return url;
  }

  /// Remove the tenant's logo.
  ///
  /// Deletes the storage object, NULLs `tenants.logo_url`, and clears the
  /// offline report cache.
  Future<void> removeLogo(String tenantId) async {
    try {
      await _client.storage
          .from(kTenantLogosBucket)
          .remove([_logoPath(tenantId)]);
    } catch (e) {
      // Best effort — the DB row is the source of truth.
      AppLogger.w('Logo storage delete failed (continuing)', e);
    }

    await _client.from('tenants').update({'logo_url': null}).eq('id', tenantId);
    await _clearCache(tenantId);
    AppLogger.i('Logo removed for tenant $tenantId');
  }

  /// Current logo URL for [tenantId], or null when none is set.
  Future<String?> getLogoUrl(String tenantId) async {
    final row = await _client
        .from('tenants')
        .select('logo_url')
        .eq('id', tenantId)
        .maybeSingle();
    final url = row?['logo_url'] as String?;
    return (url == null || url.trim().isEmpty) ? null : url.trim();
  }

  /// Whether the owner wants the logo on generated reports.
  Future<bool> getUseLogoOnReports(String tenantId) async {
    final row = await _client
        .from('tenants')
        .select('use_logo_on_reports')
        .eq('id', tenantId)
        .maybeSingle();
    // Column defaults TRUE; tolerate pre-migration rows.
    return (row?['use_logo_on_reports'] as bool?) ?? true;
  }

  /// Toggle "use logo on reports".
  ///
  /// Disabling clears the offline cache (reports fall back to the neutral
  /// emblem); enabling re-caches the current logo if one exists.
  Future<void> setUseLogoOnReports(String tenantId, bool use) async {
    await _client
        .from('tenants')
        .update({'use_logo_on_reports': use}).eq('id', tenantId);

    if (use) {
      await ensureLogoCached(tenantId);
    } else {
      await _clearCache(tenantId);
    }
    AppLogger.i('use_logo_on_reports=$use for tenant $tenantId');
  }

  /// Ensure the offline report cache holds the current logo.
  ///
  /// Downloads `logo_url` when set AND `use_logo_on_reports` is true;
  /// otherwise clears the cache. Safe to call on app start / tenant switch.
  /// Never throws — reports must generate even when the network fails.
  Future<void> ensureLogoCached(String tenantId) async {
    try {
      final row = await _client
          .from('tenants')
          .select('logo_url, use_logo_on_reports')
          .eq('id', tenantId)
          .maybeSingle();
      final url = row?['logo_url'] as String?;
      final use = (row?['use_logo_on_reports'] as bool?) ?? true;

      if (!use || url == null || url.trim().isEmpty) {
        await _clearCache(tenantId);
        return;
      }

      final file = await _cacheFile(tenantId);
      if (await file.exists()) return; // already cached

      final response = await _client.storage
          .from(kTenantLogosBucket)
          .download(_logoPath(tenantId));
      await _writeCache(tenantId, response);
    } catch (e) {
      AppLogger.w('ensureLogoCached failed (non-fatal)', e);
    }
  }

  Future<void> _writeCache(String tenantId, Uint8List bytes) async {
    try {
      final file = await _cacheFile(tenantId);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      AppLogger.w('Logo cache write failed (non-fatal)', e);
    }
  }

  Future<void> _clearCache(String tenantId) async {
    try {
      final file = await _cacheFile(tenantId);
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.w('Logo cache clear failed (non-fatal)', e);
    }
  }
}

/// Riverpod access to the service.
final tenantLogoServiceProvider = Provider<TenantLogoService>((ref) {
  return TenantLogoService();
});

/// Current logo URL for a tenant (null = none).
final tenantLogoUrlProvider =
    FutureProvider.family<String?, String>((ref, tenantId) async {
  return ref.watch(tenantLogoServiceProvider).getLogoUrl(tenantId);
});

/// Owner toggle state for a tenant.
final useLogoOnReportsProvider =
    FutureProvider.family<bool, String>((ref, tenantId) async {
  return ref.watch(tenantLogoServiceProvider).getUseLogoOnReports(tenantId);
});
