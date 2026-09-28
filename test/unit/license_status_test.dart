// License/subscription status unit tests.
//
// Implementation files under test:
//   supabase/migrations/011_licensing.sql  (documented contract: the
//       CHECK constraint on public.licenses.status — the ONLY place the
//       status vocabulary and its lifecycle are defined)
//   lib/presentation/screens/master_admin/widgets/ma_widgets.dart
//       (MaStatusChip.colorFor — the one pure Dart function that maps
//       license/tenant status strings to UI semantics)
//
// HONESTY NOTE: there is NO Dart license evaluator in the codebase — no
// trial/active/grace_period/expired/suspended/cancelled computation from
// dates exists client-side (lib/presentation/screens/master_admin/
// licenses_screen.dart only displays rows; enforcement is server-side).
// The contract group below pins the documented 011 semantics in code and
// is clearly marked as contract-only, not as coverage of a Dart function.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/presentation/screens/master_admin/widgets/ma_widgets.dart';

void main() {
  group('MaStatusChip.colorFor (real Dart status mapping)', () {
    test('active -> success, trial -> info', () {
      expect(MaStatusChip.colorFor('active'), AppColors.success);
      expect(MaStatusChip.colorFor('trial'), AppColors.info);
    });

    test('suspended -> warning, expired -> error', () {
      expect(MaStatusChip.colorFor('suspended'), AppColors.warning);
      expect(MaStatusChip.colorFor('expired'), AppColors.error);
    });

    test('cancelled -> neutral textSecondary', () {
      expect(MaStatusChip.colorFor('cancelled'), AppColors.textSecondary);
    });

    test('grace_period is NOT explicitly mapped -> falls back to neutral', () {
      // Real behaviour read from the switch: 'grace_period' hits default.
      // If the product wants grace visibly distinct, the switch must grow
      // a case — this test documents the current gap.
      expect(MaStatusChip.colorFor('grace_period'), AppColors.textSecondary);
    });

    test('unknown statuses degrade to neutral, never crash', () {
      expect(MaStatusChip.colorFor('bogus'), AppColors.textSecondary);
      expect(MaStatusChip.colorFor(''), AppColors.textSecondary);
    });
  });

  group(
      'CONTRACT: 011_licensing.sql status vocabulary '
      '(no Dart evaluator exists — documented semantics only)', () {
    // CHECK (status IN ('trial','active','grace_period','expired',
    //                  'suspended','cancelled'))
    const allStatuses = {
      'trial',
      'active',
      'grace_period',
      'expired',
      'suspended',
      'cancelled',
    };

    // Provisioned: the tenant may operate.
    const provisioned = {'trial', 'active', 'grace_period'};

    // Blocked: the tenant may not operate.
    const blocked = {'expired', 'suspended', 'cancelled'};

    test('vocabulary is exactly the six CHECK values', () {
      expect(allStatuses.length, 6);
      expect(
          allStatuses,
          containsAll([
            'trial',
            'active',
            'grace_period',
            'expired',
            'suspended',
            'cancelled'
          ]));
    });

    test('provisioned and blocked partition the vocabulary', () {
      expect(provisioned.intersection(blocked), isEmpty);
      expect(provisioned.union(blocked), allStatuses);
    });

    test('trial is a provisioned status (new tenants start here)', () {
      // 011 + create_madrasa_wizard.dart: new tenants are created with
      // status 'trial'.
      expect(provisioned.contains('trial'), isTrue);
      expect(blocked.contains('trial'), isFalse);
    });

    test('expired/suspended/cancelled never grant access', () {
      for (final s in ['expired', 'suspended', 'cancelled']) {
        expect(provisioned.contains(s), isFalse, reason: s);
        expect(blocked.contains(s), isTrue, reason: s);
      }
    });
  });
}
