// Phase 9: permission_scopes audit rendering tests.
//
// Implementation files under test:
//   lib/core/utils/audit_urdu.dart  (permission_scopes special-case)
//   lib/core/services/scope_policy.dart (scopeTypeUrdu)
//
// The 019 auto-audit trigger writes `permission_scopes.created|updated|
// deleted` rows with the full row JSON in new_data/old_data; these tests
// assert they render as human Urdu naming the scope type, never raw codes.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/utils/audit_urdu.dart';

void main() {
  group('permission_scopes audit rendering', () {
    test('created names the scope type in Urdu', () {
      final msg = auditMessageUrdu(
        action: 'permission_scopes.created',
        actorName: 'مہتمم صاحب',
        newData: {'scope_type': 'classes'},
      );
      expect(msg, contains('اجازت کا دائرہ کار'));
      expect(msg, contains('مقرر کردہ جماعتیں'));
      expect(msg, contains('مقرر کیا'));
      expect(msg, isNot(contains('permission_scopes')));
      expect(msg, isNot(contains('classes')));
    });

    test('updated renders without an actor (passive voice)', () {
      final msg = auditMessageUrdu(
        action: 'permission_scopes.updated',
        newData: {'scope_type': 'students'},
      );
      expect(msg, contains('مخصوص طلبہ'));
      expect(msg, contains('تبدیل کیا گیا'));
      expect(msg, isNot(contains('students')));
    });

    test('deleted reads the scope type from old_data', () {
      final msg = auditMessageUrdu(
        action: 'permission_scopes.deleted',
        actorName: 'ناظم اعلیٰ',
        oldData: {'scope_type': 'classes'},
      );
      expect(msg, contains('مقرر کردہ جماعتیں'));
      expect(msg, contains('ختم کیا'));
    });

    test('missing scope_type falls back to whole-madrasa wording', () {
      final msg = auditMessageUrdu(
        action: 'permission_scopes.created',
        newData: const {},
      );
      expect(msg, contains('پورا مدرسہ'));
    });

    test('scope actions stay in the known-action inventory', () {
      expect(isKnownAuditAction('permission_scopes.created'), isTrue);
      expect(isKnownAuditAction('permission_scopes.updated'), isTrue);
      expect(isKnownAuditAction('permission_scopes.deleted'), isTrue);
      expect(auditActionLabelUrdu('permission_scopes.created'),
          isNot(contains('permission_scopes')));
    });
  });
}
