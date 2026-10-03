/// محفوظ ڈاؤن لوڈ
/// Safe HTTP download helper (branding/logo fetches).
///
/// `tenants.logo_url` is tenant-writable, so every fetch of it is a fetch
/// of attacker-influenced bytes. This helper enforces:
///   * https only (no cleartext, no exotic schemes),
///   * no private/loopback/link-local hosts (client-side SSRF guard),
///   * a hard byte cap while streaming (OOM guard — the response is never
///     folded unboundedly),
///   * a request timeout.
///
/// Returns the bytes on HTTP 200 within the cap, else null. Never throws.

import 'dart:async';
import 'dart:io';

import '../observability/app_logger.dart';

class SafeDownload {
  SafeDownload._();

  /// Maximum logo/branding download: 5 MB.
  static const int kMaxLogoBytes = 5 * 1024 * 1024;

  /// Fetch [url] safely. Returns null on any policy violation or failure.
  static Future<List<int>?> fetchBytes(
    String url, {
    int maxBytes = kMaxLogoBytes,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.isAbsolute) return null;
    if (uri.scheme != 'https') {
      AppLogger().warning('[SafeDownload] rejected non-https URL',
          context: {'host': uri.host});
      return null;
    }
    if (isPrivateHost(uri.host)) {
      AppLogger().warning('[SafeDownload] rejected private host',
          context: {'host': uri.host});
      return null;
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          AppLogger().warning('[SafeDownload] rejected oversize payload',
              context: {'host': uri.host, 'bytes': bytes.length});
          return null;
        }
      }
      return bytes.isEmpty ? null : bytes;
    } catch (e) {
      AppLogger().warning('[SafeDownload] fetch failed', error: e);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// True for loopback, private (RFC 1918), link-local, and `localhost`
  /// names — targets a branding fetch must never touch.
  /// Public so unit tests can pin the SSRF guard.
  static bool isPrivateHost(String host) {
    final h = host.toLowerCase().trim();
    if (h == 'localhost' || h == '::1') return true;
    // Strip trailing dot / brackets for IPv6 literals.
    final clean = h.endsWith('.') ? h.substring(0, h.length - 1) : h;
    final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
        .firstMatch(clean);
    if (v4 != null) {
      final o = [1, 2, 3, 4].map((i) => int.parse(v4.group(i)!)).toList();
      if (o.any((x) => x > 255)) return true; // malformed → treat as unsafe
      if (o[0] == 10) return true; // 10/8
      if (o[0] == 127) return true; // 127/8 loopback
      if (o[0] == 169 && o[1] == 254) return true; // link-local
      if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true; // 172.16/12
      if (o[0] == 192 && o[1] == 168) return true; // 192.168/16
      if (o[0] == 0) return true; // 0/8
      return false;
    }
    // Non-IP hostnames: block localhost-ish and .local/.internal names.
    if (h.endsWith('.local') ||
        h.endsWith('.internal') ||
        h.endsWith('.localhost')) {
      return true;
    }
    return false;
  }
}
