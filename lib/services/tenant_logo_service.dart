/// مدرسے کے لوگو کی خدمت
/// Tenant logo service — upload / remove / reports-toggle for madrassa logos.
///
/// Storage layout: `tenant-logos/<tenant_id>/logo.png` (public bucket —
/// a madrassa logo is public-facing identity printed on documents).
/// The public URL is stored in `tenants.logo_url`; the per-madrassa toggle
/// lives in `tenants.use_logo_on_reports` (migration 024).
///
/// Uploads are routed through the hardened `upload-image` Edge Function
/// (JWT + membership + magic-byte/dimension validation server-side); the
/// client never uploads raw bytes to Storage directly.
///
/// Offline reports: [report_branding.dart] draws the logo from the local
/// cache `<app-support>/Madrassa360/branding/<tenantId>/logo.png`. This
/// service keeps that cache in sync — writing on upload, clearing on
/// remove or when the toggle is switched off.
///
/// Auth model: the Edge Function is the real enforcement for uploads;
/// storage RLS (migration 024 policies) gates direct reads/removes.
/// [TenantLogoDenied] is defense-in-depth for the UI layer only.

import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/observability/app_logger.dart';
import '../core/reports/report_branding.dart';
import '../core/security/safe_download.dart';
import '../core/services/supabase_service.dart';

/// Supabase Storage bucket for tenant logos (public read).
const String kTenantLogosBucket = 'tenant-logos';

/// Thrown when the caller is not allowed to manage the tenant's logo.
/// (RLS is the real enforcement; this is defense-in-depth.)
class TenantLogoDenied implements Exception {
  final String message;
  const TenantLogoDenied(
      [this.message = 'آپ کو لوگو تبدیل کرنے کی اجازت نہیں ہے']);
  @override
  String toString() => 'TenantLogoDenied: $message';
}

class TenantLogoService {
  final SupabaseClient _client;

  TenantLogoService({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  String _logoPath(String tenantId) => '$tenantId/logo.png';

  /// Public URL for the tenant's logo path (pure local computation —
  /// no network).
  String publicLogoUrl(String tenantId) => _client.storage
      .from(kTenantLogosBucket)
      .getPublicUrl(_logoPath(tenantId));

  /// Upload a new logo for [tenantId].
  ///
  /// Routes through the hardened `upload-image` Edge Function, which
  /// validates the JWT, tenant membership, magic bytes, dimensions and
  /// size server-side and writes `tenants.logo_url` itself — the client
  /// never uploads raw bytes to Storage directly. Returns the public URL.
  ///
  /// NOTE: requires the `upload-image` function to be deployed; without
  /// it this throws [TenantLogoDenied] with a clear message (no silent
  /// fallback to the unvalidated direct-upload path).
  Future<String> uploadLogo(String tenantId, XFile image) async {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      throw ArgumentError('خالی تصویر اپ لوڈ نہیں ہو سکتی');
    }
    if (bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('تصویر 5MB سے چھوٹی ہونی چاہیے');
    }

    // Route through the hardened Edge Function (server-side validation).
    final Map<String, dynamic>? data;
    try {
      final res = await _client.functions.invoke(
        'upload-image',
        body: {
          'tenant_id': tenantId,
          'kind': 'logo',
          'content_base64': base64Encode(bytes),
        },
      );
      data = res.data as Map<String, dynamic>?;
    } catch (e) {
      AppLogger().error('Logo upload failed', error: e);
      throw TenantLogoDenied('لوگو اپ لوڈ ناکام — سرور اپ ڈیٹ درکار ہے');
    }
    final url = data?['url'] as String?;
    if (data?['ok'] != true || url == null || url.isEmpty) {
      final message = data?['message'] as String?;
      AppLogger().error('Logo upload rejected', error: message);
      throw TenantLogoDenied(
          message?.isNotEmpty == true ? message! : 'لوگو اپ لوڈ ناکام');
    }

    // Refresh the offline cache so reports pick it up immediately.
    await _writeLogoCache(tenantId, bytes);

    AppLogger().info('Logo uploaded for tenant $tenantId');
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
      AppLogger().warning('Logo storage delete failed (continuing)', error: e);
    }

    await _client.from('tenants').update({'logo_url': null}).eq('id', tenantId);
    await _clearLogoCache(tenantId);
    AppLogger().info('Logo removed for tenant $tenantId');
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

  /// Whether the tenant wants its logo drawn on reports/documents.
  Future<bool> getUseLogoOnReports(String tenantId) async {
    final row = await _client
        .from('tenants')
        .select('use_logo_on_reports')
        .eq('id', tenantId)
        .maybeSingle();
    return (row?['use_logo_on_reports'] as bool?) ?? true;
  }

  /// Flip the "use logo on reports" toggle.
  ///
  /// When switched off the offline logo cache is cleared as well, so the
  /// next generated document draws the neutral emblem instead.
  Future<void> setUseLogoOnReports(String tenantId, bool value) async {
    await _client
        .from('tenants')
        .update({'use_logo_on_reports': value}).eq('id', tenantId);
    if (!value) {
      await _clearLogoCache(tenantId);
    } else {
      // Re-seed the cache from the live logo so reports show it at once.
      await refreshLogoCache(tenantId);
    }
    AppLogger().info('use_logo_on_reports=$value for tenant $tenantId');
  }

  /// (Re)download the tenant's live logo into the offline report cache.
  /// No-op when the tenant has no logo URL.
  ///
  /// Security: the URL comes from the `tenants` row (tenant-writable), so
  /// the fetch goes through [SafeDownload] — https only, 5MB cap, no
  /// private/loopback hosts (SSRF/OOM guard).
  Future<void> refreshLogoCache(String tenantId) async {
    final url = await getLogoUrl(tenantId);
    if (url == null) return;
    try {
      final bytes = await SafeDownload.fetchBytes(url);
      if (bytes != null && bytes.isNotEmpty) {
        await _writeLogoCache(tenantId, bytes);
      }
    } catch (e) {
      AppLogger().warning('Logo cache refresh failed (offline ok)', error: e);
    }
  }

  // ── offline cache (paths must match report_branding.dart) ──

  Future<void> _writeLogoCache(String tenantId, List<int> bytes) async {
    try {
      final file = await tenantLogoCacheFile(tenantId);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      AppLogger().warning('Logo cache write failed (continuing)', error: e);
    }
  }

  Future<void> _clearLogoCache(String tenantId) async {
    try {
      final file = await tenantLogoCacheFile(tenantId);
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger().warning('Logo cache clear failed (continuing)', error: e);
    }
  }
}
