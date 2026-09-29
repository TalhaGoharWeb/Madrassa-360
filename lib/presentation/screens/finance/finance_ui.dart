/// مالیاتی UI معاونین
/// Shared finance UI helpers — one mapping from the pure-Dart
/// [FinancialChipKind] to the canonical [M360StatusChip], used by every
/// finance tab so chips stay identical across fees, invoices, payments,
/// ledger and expenses.

import 'package:flutter/material.dart';

import '../../../core/design/m360.dart';
import '../../../data/models/finance.dart';
import '../../viewmodels/finance/financial_views.dart';

/// The single canonical chip for a financial chip kind.
M360StatusChip financeChip(FinancialChipKind kind) {
  switch (kind) {
    case FinancialChipKind.paid:
      return const M360StatusChip.fee(fee: M360FeeStatus.paid);
    case FinancialChipKind.partial:
      return const M360StatusChip.fee(fee: M360FeeStatus.partial);
    case FinancialChipKind.due:
      return const M360StatusChip.fee(fee: M360FeeStatus.due);
    case FinancialChipKind.overdue:
      return const M360StatusChip.fee(fee: M360FeeStatus.overdue);
    case FinancialChipKind.draft:
      return const M360StatusChip(status: M360Status.draft);
    case FinancialChipKind.posted:
      return const M360StatusChip(status: M360Status.complete);
    case FinancialChipKind.cancelled:
      return const M360StatusChip(status: M360Status.cancelled);
  }
}

/// Chip for a finance document lifecycle status (draft → posted).
M360StatusChip docStatusChip(DocStatus status) {
  switch (status) {
    case DocStatus.draft:
      return const M360StatusChip(status: M360Status.draft);
    case DocStatus.approved:
      return const M360StatusChip(status: M360Status.pending);
    case DocStatus.posted:
      return const M360StatusChip(status: M360Status.complete);
    case DocStatus.voided:
      return const M360StatusChip(status: M360Status.cancelled);
  }
}

/// Section header used by the finance hub tabs.
class FinanceSectionHeader extends StatelessWidget {
  const FinanceSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            M360TertiaryButton(
              label: actionLabel!,
              onPressed: onAction,
            ),
        ],
      ),
    );
  }
}
