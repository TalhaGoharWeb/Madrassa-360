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
/// Recomputes when the fee rows or the finance state change. When the
/// finance ledger has not loaded yet the ledger totals read as zero —
/// the dashboard shows the fee side first and fills in the rest.
final financeHubOverviewProvider =
    FutureProvider<FinanceHubOverview>((ref) async {
  final fees = await ref.watch(allFeesProvider.future);
  final finance = ref.watch(financeProvider);
  return FinanceHubOverview.compute(
    fees: fees,
    payments: finance.payments,
    postedIncome: finance.totalIncome,
    postedExpense: finance.totalExpense,
  );
});

/// Outstanding balances per student, derived from the fee rows.
final outstandingBalancesProvider =
    FutureProvider<List<OutstandingBalanceView>>((ref) async {
  final fees = await ref.watch(allFeesProvider.future);
  return OutstandingBalanceView.aggregate(fees);
});
