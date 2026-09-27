// Super Admin service — Tenant model unit tests.
// Pure Dart (no Supabase): verifies defensive parsing, expiry math, and
// the fail-open access snapshot.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/services/super_admin_service.dart';

void main() {
  group('Tenant.fromJson', () {
    test('parses full row', () {
      final t = Tenant.fromJson({
        'id': 't1',
        'name': 'Test Madrasa',
        'name_urdu': 'ٹیسٹ مدرسہ',
        'status': 'active',
        'suspension_reason': null,
        'expires_at': null,
        'admin_message': 'Pay your fees',
        'created_at': '2026-01-01T00:00:00Z',
      }, memberCount: 5);
      expect(t.id, 't1');
      expect(t.displayName, 'ٹیسٹ مدرسہ');
      expect(t.isSuspended, isFalse);
      expect(t.isExpired, isFalse);
      expect(t.isUsable, isTrue);
      expect(t.memberCount, 5);
      expect(t.adminMessage, 'Pay your fees');
    });

    test('derives suspension from status when flag missing', () {
      final t = Tenant.fromJson({'id': 't2', 'status': 'suspended'});
      expect(t.isSuspended, isTrue);
      expect(t.isUsable, isFalse);
    });

    test('explicit is_suspended flag wins over status', () {
      final t = Tenant.fromJson(
          {'id': 't3', 'status': 'active', 'is_suspended': true});
      expect(t.isSuspended, isTrue);
    });

    test('falls back to Latin name when Urdu missing', () {
      final t = Tenant.fromJson({'id': 't4', 'name': 'ABC', 'status': 'x'});
      expect(t.displayName, 'ABC');
    });

    test('expiry math', () {
      final future =
          DateTime.now().add(const Duration(days: 10)).toIso8601String();
      final t = Tenant.fromJson(
          {'id': 't5', 'status': 'active', 'expires_at': future});
      expect(t.isExpired, isFalse);
      expect(t.daysRemaining, greaterThanOrEqualTo(9));
      expect(t.isUsable, isTrue);

      final past =
          DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
      final t2 = Tenant.fromJson(
          {'id': 't6', 'status': 'active', 'expires_at': past});
      expect(t2.isExpired, isTrue);
      expect(t2.isUsable, isFalse);
    });

    test('degrades gracefully on empty row', () {
      final t = Tenant.fromJson({});
      expect(t.id, '');
      expect(t.isSuspended, isFalse);
      expect(t.isExpired, isFalse);
      expect(t.daysRemaining, isNull);
    });
  });

  group('TenantAccessStatus', () {
    test('allowed snapshot is not blocked and has no message', () {
      expect(TenantAccessStatus.allowed.blocked, isFalse);
      expect(TenantAccessStatus.allowed.hasMessage, isFalse);
    });

    test('detects message presence', () {
      const s = TenantAccessStatus(adminMessage: '  hello  ');
      expect(s.hasMessage, isTrue);
      const empty = TenantAccessStatus(adminMessage: '   ');
      expect(empty.hasMessage, isFalse);
    });
  });
}
