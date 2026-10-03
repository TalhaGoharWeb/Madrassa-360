/// مالیاتی جائزہ فراہم کنندہ
/// Finance overview provider — wires [FinanceHubOverview.compute] to the
/// two existing repository-backed providers.
///
/// * Fee rows → [allFeesProvider] (fee_repository.dart, `fees` table).
/// * Posted ledger totals → [financeProvider] (finance_repository.dart).
///
/// Read-only: every write path stays on the real existing notifiers
/// ([FeeNotifier], [FinanceNotifier]).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/fee_provider.dart';
import '../../../providers/finance_provider.dart';
import 'financial_views.dart';

/// Aggregated finance-dashboard numbers from the two real backends.
///
/// Memoized selector: derives synchronously from [allFeesProvider] (plus
/// the finance state) via [AsyncValue.whenData] — no extra async hop.
/// Recomputes when the fee rows or the finance state change. When the
/// finance ledger has not loaded yet the ledger totals read as zero —
/// the dashboard shows the fee side first and fills in the rest.
final financeHubOverviewProvider =
    Provider<AsyncValue<FinanceHubOverview>>((ref) {
  final finance = ref.watch(financeProvider);
  return ref.watch(allFeesProvider).whenData(
        (fees) => FinanceHubOverview.compute(
          fees: fees,
          payments: finance.payments,
          postedIncome: finance.totalIncome,
          postedExpense: finance.totalExpense,
        ),
      );
});

/// Outstanding balances per student, derived from the fee rows.
/// Memoized selector — same pattern as [financeHubOverviewProvider].
final outstandingBalancesProvider =
    Provider<AsyncValue<List<OutstandingBalanceView>>>((ref) {
  return ref
      .watch(allFeesProvider)
      .whenData((fees) => OutstandingBalanceView.aggregate(fees));
});
