// آڈٹ لاگز — انسانی اردو: mapper unit tests.
//
// Implementation file under test:
//   lib/core/utils/audit_urdu.dart
//
// What IS tested: every action code the codebase can write (70 codes —
// edge functions, finance triggers, role/UX triggers) renders a non-empty
// Urdu sentence that never leaks the raw code; the unknown-code fallback
// stays generic and clean; Asia/Karachi timestamp phrasing; before/after
// diff extraction; the pure filter-param builder (tenant constraint is
// carried verbatim — RLS itself is server-side and not unit-testable).

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/utils/audit_urdu.dart';

void main() {
  group('knownAuditActions inventory', () {
    test('covers all 70 codes (13 edge + 39 finance + 18 role/UX)', () {
      expect(knownAuditActions.length, 70);
      expect(isKnownAuditAction('tenant.provisioned'), isTrue);
      expect(isKnownAuditAction('manage-users.set_platform_role'), isTrue);
      expect(isKnownAuditAction('INSERT_invoices'), isTrue);
      expect(isKnownAuditAction('UPDATE_payments'), isTrue);
      expect(isKnownAuditAction('DELETE_scholarships'), isTrue);
      expect(isKnownAuditAction('tenant_roles.created'), isTrue);
      expect(isKnownAuditAction('user_permissions.deleted'), isTrue);
      expect(isKnownAuditAction('nope.unknown'), isFalse);
    });
  });

  group('auditMessageUrdu — every known code renders clean Urdu', () {
    test('no known code leaks its raw code into the message', () {
      for (final code in knownAuditActions) {
        final msg = auditMessageUrdu(
          action: code,
          actorName: 'احمد',
          tenantName: 'مدرسہ الفلاح',
          newData: const {
            'name': 'الفلاح',
            'email': 'a@example.com',
            'role': 'teacher',
            'active': true,
            'invoice_number': 'INV-00000001',
            'receipt_number': 'RCP-00000001',
          },
          oldData: const {'status': 'active'},
        );
        expect(msg.isNotEmpty, isTrue, reason: code);
        expect(msg.contains(code), isFalse, reason: code);
      }
    });

    test('passive voice when the actor is unknown', () {
      final msg = auditMessageUrdu(action: 'tenant.suspend');
      expect(msg.contains('نے'), isFalse);
      expect(msg.contains('معطل کیا گیا'), isTrue);
    });

    test('active voice names the actor', () {
      final msg = auditMessageUrdu(
        action: 'tenant.provisioned',
        actorName: 'احمد',
        newData: const {'name': 'الفلاح'},
      );
      expect(msg, 'احمد نے مدرسہ «الفلاح» قائم کیا');
    });

    test('set_active reads the new value', () {
      final on = auditMessageUrdu(
        action: 'manage-users.set_active',
        newData: const {'active': true},
      );
      final off = auditMessageUrdu(
        action: 'manage-users.set_active',
        newData: const {'active': false},
      );
      expect(on.contains('فعال کیا گیا'), isTrue);
      expect(off.contains('غیر فعال کیا گیا'), isTrue);
    });

    test('assign_membership renders the role in Urdu', () {
      final msg = auditMessageUrdu(
        action: 'manage-users.assign_membership',
        actorName: 'احمد',
        newData: const {'role': 'teacher'},
      );
      expect(msg.contains('استاد'), isTrue);
      expect(msg.contains('teacher'), isFalse);
    });

    test('finance rows surface invoice / receipt numbers', () {
      final inv = auditMessageUrdu(
        action: 'INSERT_invoices',
        newData: const {'invoice_number': 'INV-00000001'},
      );
      expect(inv.contains('INV-00000001'), isTrue);
      expect(inv.contains('انوائس'), isTrue);
      final pay = auditMessageUrdu(
        action: 'UPDATE_payments',
        oldData: const {'receipt_number': 'RCP-00000002'},
      );
      expect(pay.contains('RCP-00000002'), isTrue);
      expect(pay.contains('اپ ڈیٹ کیا گیا'), isTrue);
    });

    test('role/UX codes render the entity in Urdu', () {
      final msg = auditMessageUrdu(action: 'tenant_roles.deleted');
      expect(msg.contains('کردار'), isTrue);
      expect(msg.contains('حذف کیا گیا'), isTrue);
      final mem = auditMessageUrdu(action: 'tenant_memberships.created');
      expect(mem.contains('رکنیت'), isTrue);
    });
  });

  group('auditMessageUrdu — unknown-code fallback', () {
    test('never renders the raw code', () {
      const weird = 'weird_future_code.v2';
      final withActor = auditMessageUrdu(
          action: weird, actorName: 'احمد', entity: 'invoices');
      expect(withActor.contains(weird), isFalse);
      expect(withActor, 'احمد نے انوائس پر عمل کیا');

      final passive = auditMessageUrdu(action: weird);
      expect(passive.contains(weird), isFalse);
      expect(passive, 'ایک عمل کیا گیا');
    });
  });

  group('auditActionLabelUrdu — filter labels', () {
    test('every known code gets a short label without the raw code', () {
      for (final code in knownAuditActions) {
        final label = auditActionLabelUrdu(code);
        expect(label.isNotEmpty, isTrue, reason: code);
        expect(label.contains(code), isFalse, reason: code);
      }
    });

    test('unknown code falls back to «دیگر عمل»', () {
      expect(auditActionLabelUrdu('zzz_nope'), 'دیگر عمل');
    });
  });

  group('Asia/Karachi timestamps', () {
    test('UTC+5 conversion with Urdu phrasing', () {
      // 09:00 UTC = 14:00 PKT → دوپہر 2:00
      expect(
        formatAuditDateUrdu(DateTime.utc(2026, 9, 26, 9, 0)),
        '26 ستمبر 2026، دوپہر 2:00',
      );
    });

    test('period boundaries follow Karachi wall time', () {
      // 23:30 UTC = 04:30 PKT → رات
      expect(
        formatAuditDateUrdu(DateTime.utc(2026, 9, 26, 23, 30)),
        contains('رات'),
      );
      // 00:30 UTC = 05:30 PKT → صبح
      expect(
        formatAuditDateUrdu(DateTime.utc(2026, 9, 26, 0, 30)),
        contains('صبح'),
      );
      // 15:00 UTC = 20:00 PKT → رات
      expect(
        formatAuditDateUrdu(DateTime.utc(2026, 9, 26, 15, 0)),
        contains('رات'),
      );
    });

    test('karachiDayStartUtc maps a Karachi day to its UTC start', () {
      // 2026-09-26 00:00 PKT = 2026-09-25 19:00 UTC
      expect(
        karachiDayStartUtc(DateTime(2026, 9, 26)),
        DateTime.utc(2026, 9, 25, 19, 0),
      );
    });
  });

  group('auditFieldDiffs — readable before/after', () {
    test('changed fields only; unchanged and noisy keys skipped', () {
      final diffs = auditFieldDiffs(
        {
          'id': 'x',
          'tenant_id': 't',
          'status': 'active',
          'amount': 100,
          'name': 'پرانا',
        },
        {
          'id': 'x',
          'tenant_id': 't',
          'status': 'suspended',
          'amount': 100,
          'name': 'پرانا',
        },
      );
      expect(diffs.length, 1);
      expect(diffs.first.labelUrdu, 'حیثیت');
      expect(diffs.first.oldText, 'active');
      expect(diffs.first.newText, 'suspended');
    });

    test('bools and nulls render readably', () {
      final diffs = auditFieldDiffs(
        {'is_active': true, 'phone': null},
        {'is_active': false, 'phone': '03001234567'},
      );
      final byField = {for (final d in diffs) d.field: d};
      expect(byField['is_active']!.oldText, 'ہاں');
      expect(byField['is_active']!.newText, 'نہیں');
      expect(byField['phone']!.oldText, '—');
    });

    test('insert/delete direction flags', () {
      final ins = auditFieldDiffs(null, {'email': 'a@b.c'}).single;
      expect(ins.isInsert, isTrue);
      final del = auditFieldDiffs({'email': 'a@b.c'}, null).single;
      expect(del.isDelete, isTrue);
    });

    test('unknown field keys are prettified, never raw JSON', () {
      expect(fieldLabelUrdu('some_custom_field'), 'some custom field');
      expect(fieldLabelUrdu('status'), 'حیثیت');
    });

    test('maxFields caps long diffs', () {
      final oldM = {for (var i = 0; i < 20; i++) 'f$i': 'a'};
      final newM = {for (var i = 0; i < 20; i++) 'f$i': 'b'};
      expect(auditFieldDiffs(oldM, newM).length, 8);
      expect(auditFieldDiffs(oldM, newM, maxFields: 3).length, 3);
    });
  });

  group('auditFilterParams — tenant constraint carried verbatim', () {
    test('tenant id is preserved exactly when set', () {
      const tid = '11111111-2222-3333-4444-555555555555';
      final p = auditFilterParams(
        tenantId: tid,
        action: 'INSERT_invoices',
        actorId: 'user-1',
      );
      expect(p['tenant_id'], tid);
      expect(p['action'], 'INSERT_invoices');
      expect(p['user_id'], 'user-1');
    });

    test('unset filters are omitted, never sent as empty', () {
      final p = auditFilterParams();
      expect(p.isEmpty, isTrue);
      expect(auditFilterParams(tenantId: '').containsKey('tenant_id'), isFalse);
    });

    test('date range uses Karachi day boundaries in UTC', () {
      final p = auditFilterParams(
        fromDay: DateTime(2026, 9, 26),
        toDay: DateTime(2026, 9, 27),
      );
      expect(
        p['created_from'],
        DateTime.utc(2026, 9, 25, 19, 0).toIso8601String(),
      );
      expect(
        p['created_to'],
        DateTime.utc(2026, 9, 27, 19, 0).toIso8601String(),
      );
    });
  });

  group('entityUrdu / roleKeyUrdu', () {
    test('known entities and roles map to Urdu', () {
      expect(entityUrdu('invoices'), 'انوائس');
      expect(entityUrdu('tenant_role_permissions'), 'کردار کی اجازت');
      expect(roleKeyUrdu('tenant_admin'), 'ناظم اعلیٰ');
      expect(roleKeyUrdu('accountant'), 'محاسب');
    });

    test('empty input stays empty; unknown input prettified', () {
      expect(entityUrdu(null), isEmpty);
      expect(entityUrdu(''), isEmpty);
      expect(roleKeyUrdu('custom_role_x'), 'custom role x');
    });
  });
}
