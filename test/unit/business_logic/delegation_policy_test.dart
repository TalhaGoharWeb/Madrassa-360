/// Delegation-policy unit tests.
///
/// Implementation file under test:
///   lib/data/delegation_policy.dart (DelegationPolicy.validateCreate,
///                                    DelegationPolicy.delegatableCatalog)
///
/// What is real here: these are the exact pure functions the delegation UI
/// calls before offering the grant screen. They encode the CLIENT-SIDE
/// ceiling pre-check — a user can never be offered a permission they do not
/// themselves hold. The server (`delegate_permission` RPC + the 019
/// `delegation_ceiling_check` trigger) is the real enforcement; these tests
/// pin the client contract so the UI cannot silently widen what it offers
/// (privilege-escalation pre-condition, audit SEC-H1 family).
///
/// No mocks, no widgets: pure Dart in, Urdu refusal out (or null).

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/data/delegation_policy.dart';
import 'package:madrasa_360/data/role_ux_repository.dart';

PermissionInfo _perm(String code) => PermissionInfo(
      id: 'p-$code',
      code: code,
      labelUrdu: code,
      categoryUrdu: 'test',
      sortOrder: 0,
    );

void main() {
  final now = DateTime(2026, 10, 3, 12);

  group('DelegationPolicy.validateCreate — grant ceiling', () {
    test('refuses when the delegator identity is missing', () {
      expect(
        DelegationPolicy.validateCreate(
          selfId: null,
          delegateeId: 'u2',
          codes: {'fees.collect'},
          myCodes: {'fees.collect'},
          now: now,
        ),
        isNotNull,
      );
      expect(
        DelegationPolicy.validateCreate(
          selfId: '',
          delegateeId: 'u2',
          codes: {'fees.collect'},
          myCodes: {'fees.collect'},
          now: now,
        ),
        isNotNull,
      );
    });

    test('refuses self-delegation', () {
      expect(
        DelegationPolicy.validateCreate(
          selfId: 'u1',
          delegateeId: 'u1',
          codes: {'fees.collect'},
          myCodes: {'fees.collect'},
          now: now,
        ),
        isNotNull,
      );
    });

    test('refuses an empty delegatee', () {
      expect(
        DelegationPolicy.validateCreate(
          selfId: 'u1',
          delegateeId: '',
          codes: {'fees.collect'},
          myCodes: {'fees.collect'},
          now: now,
        ),
        isNotNull,
      );
    });

    test('refuses an empty permission set', () {
      expect(
        DelegationPolicy.validateCreate(
          selfId: 'u1',
          delegateeId: 'u2',
          codes: const {},
          myCodes: {'fees.collect'},
          now: now,
        ),
        isNotNull,
      );
    });

    test('refuses codes the delegator does not hold (the ceiling)', () {
      // Attacker shape: hold fees.collect, try to delegate roles.assign.
      final refusal = DelegationPolicy.validateCreate(
        selfId: 'u1',
        delegateeId: 'u2',
        codes: {'fees.collect', 'roles.assign'},
        myCodes: {'fees.collect'},
        now: now,
      );
      expect(refusal, isNotNull);
    });

    test('refuses a single unheld code even among held ones', () {
      expect(
        DelegationPolicy.validateCreate(
          selfId: 'u1',
          delegateeId: 'u2',
          codes: {'attendance.mark', 'finance.approve'},
          myCodes: {'attendance.mark'},
          now: now,
        ),
        isNotNull,
      );
    });

    test('refuses an expiry that is not in the future', () {
      expect(
        DelegationPolicy.validateCreate(
          selfId: 'u1',
          delegateeId: 'u2',
          codes: {'fees.collect'},
          myCodes: {'fees.collect'},
          expiresAt: now.subtract(const Duration(days: 1)),
          now: now,
        ),
        isNotNull,
      );
      expect(
        DelegationPolicy.validateCreate(
          selfId: 'u1',
          delegateeId: 'u2',
          codes: {'fees.collect'},
          myCodes: {'fees.collect'},
          expiresAt: now,
          now: now,
        ),
        isNotNull,
      );
    });

    test('allows a well-formed request within the ceiling', () {
      expect(
        DelegationPolicy.validateCreate(
          selfId: 'u1',
          delegateeId: 'u2',
          codes: {'fees.collect'},
          myCodes: {'fees.collect', 'attendance.mark'},
          expiresAt: now.add(const Duration(days: 30)),
          now: now,
        ),
        isNull,
      );
    });

    test('allows a request with no expiry (open-ended)', () {
      expect(
        DelegationPolicy.validateCreate(
          selfId: 'u1',
          delegateeId: 'u2',
          codes: {'fees.collect'},
          myCodes: {'fees.collect'},
          now: now,
        ),
        isNull,
      );
    });
  });

  group('DelegationPolicy.delegatableCatalog — picker filtering', () {
    final catalog = [
      _perm('fees.collect'),
      _perm('roles.assign'),
      _perm('attendance.mark')
    ];

    test('exposes only codes the delegator holds', () {
      final visible =
          DelegationPolicy.delegatableCatalog(catalog, {'fees.collect'});
      expect(visible.map((p) => p.code), ['fees.collect']);
    });

    test('an unheld powerful code can never appear in the picker', () {
      final visible =
          DelegationPolicy.delegatableCatalog(catalog, {'attendance.mark'});
      expect(visible.any((p) => p.code == 'roles.assign'), isFalse);
    });

    test('empty grant set yields an empty catalog', () {
      expect(DelegationPolicy.delegatableCatalog(catalog, const {}), isEmpty);
    });
  });
}
