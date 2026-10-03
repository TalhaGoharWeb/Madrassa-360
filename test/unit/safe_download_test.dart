// SafeDownload unit tests — the SSRF/OOM guard for tenant-controlled URLs.
//
// What is real here: SafeDownload.isPrivateHost, the exact predicate the
// logo/branding fetches consult before opening a connection. A host the
// predicate misses is a client-side SSRF hole (tenants.logo_url is
// tenant-writable).

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/security/safe_download.dart';

void main() {
  group('isPrivateHost', () {
    test('rejects loopback', () {
      expect(SafeDownload.isPrivateHost('127.0.0.1'), isTrue);
      expect(SafeDownload.isPrivateHost('127.0.0.2'), isTrue);
      expect(SafeDownload.isPrivateHost('localhost'), isTrue);
      expect(SafeDownload.isPrivateHost('::1'), isTrue);
    });

    test('rejects RFC 1918 private ranges', () {
      expect(SafeDownload.isPrivateHost('10.0.0.5'), isTrue);
      expect(SafeDownload.isPrivateHost('172.16.0.1'), isTrue);
      expect(SafeDownload.isPrivateHost('172.31.255.255'), isTrue);
      expect(SafeDownload.isPrivateHost('192.168.1.1'), isTrue);
    });

    test('rejects link-local and special ranges', () {
      expect(SafeDownload.isPrivateHost('169.254.10.20'), isTrue);
      expect(SafeDownload.isPrivateHost('0.0.0.0'), isTrue);
    });

    test('rejects .local / .internal names', () {
      expect(SafeDownload.isPrivateHost('printer.local'), isTrue);
      expect(SafeDownload.isPrivateHost('db.internal'), isTrue);
    });

    test('allows public hosts', () {
      expect(SafeDownload.isPrivateHost('example.com'), isFalse);
      expect(SafeDownload.isPrivateHost('8.8.8.8'), isFalse);
      expect(SafeDownload.isPrivateHost('172.15.0.1'), isFalse);
      expect(SafeDownload.isPrivateHost('172.32.0.1'), isFalse);
      expect(SafeDownload.isPrivateHost('projectref.supabase.co'), isFalse);
    });
  });
}
