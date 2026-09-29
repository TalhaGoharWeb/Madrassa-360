/// مالیاتی نظارے — صرف پڑھنے والی اڈاپٹر پرت
/// Financial views — the READ-ONLY adapter boundary for the unified
/// finance experience (Phase 9).
///
/// The underlying databases are NOT merged: student fees live in the
/// `fees` table ([fee_repository.dart]) and the invoice → payment →
/// receipt → ledger flow lives in the finance tables
/// ([finance_repository.dart]). These views adapt both into one coherent
/// UI language — [FeeRecordView], [InvoiceView], [PaymentView],
/// [LedgerEntryView], [OutstandingBalanceView] and the aggregated
/// [FinanceHubOverview] — without changing any persistence schema or
/// money behavior.
///
/// Pure Dart (no Flutter imports) so the aggregation logic is unit
/// testable. The UI layer maps [FinancialChipKind] onto
/// [M360StatusChip]; currency always goes through [formatPK] (Pakistani
/// grouping, whole rupees) — one format on every financial surface.

import '../../../core/utils/money_format.dart';
import '../../../data/models/fee.dart';
import '../../../data/models/finance.dart';

/// '2026-09' → 'ستمبر 2026'. Passes anything unparseable through unchanged.
String monthLabelUrdu(String yearMonth) {
  final parts = yearMonth.split('-');
  if (parts.length != 2) return yearMonth;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (y == null || m == null || m < 1 || m > 12) return yearMonth;
  const months = [
    'جنوری',
    'فروری',
    'مارچ',
    'اپریل',
    'مئی',
    'جون',
    'جولائی',
    'اگست',
    'ستمبر',
    'اکتوبر',
    'نومبر',
    'دسمبر',
  ];
  return '${months[m - 1]} $y';
}

/// Canonical chip semantics for every financial surface. The UI layer
/// maps these onto [M360StatusChip] — never invents its own colors.
enum FinancialChipKind {
  /// ادا شدہ (green).
  paid,

  /// جزوی ادائیگی (amber).
  partial,

  /// واجب الادا / جاری (orange).
  due,

  /// بقایا (red).
  overdue,

  /// مسودہ (grey).
  draft,

  /// حتمی (teal).
  posted,

  /// منسوخ (red).
  cancelled,
}

extension FinancialChipKindX on FinancialChipKind {
  String get urduLabel {
    switch (this) {
      case FinancialChipKind.paid:
        return 'ادا شدہ';
      case FinancialChipKind.partial:
        return 'جزوی ادائیگی';
      case FinancialChipKind.due:
        return 'واجب الادا';
      case FinancialChipKind.overdue:
        return 'بقایا';
      case FinancialChipKind.draft:
        return 'مسودہ';
      case FinancialChipKind.posted:
        return 'حتمی';
      case FinancialChipKind.cancelled:
        return 'منسوخ';
    }
  }
}

/// Presentation view over one [Fee] row (the `fees` table).
class FeeRecordView {
  const FeeRecordView(this.fee);

  final Fee fee;

  String get monthLabel => monthLabelUrdu(fee.month);
  double get remaining => fee.remaining;
  bool get isFullyPaid => fee.remaining <= 0;

  /// Past-due by status, or unpaid past its due date.
  bool get isOverdue {
    if (fee.status == FeeStatus.pastDue) return true;
    if (isFullyPaid) return false;
    final due = DateTime.tryParse(fee.dueDate);
    if (due == null) return false;
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day).isAfter(due);
  }

  FinancialChipKind get chipKind {
    if (isFullyPaid) return FinancialChipKind.paid;
    // Past-due by date counts as overdue even before the DB flips the
    // row status — the chip must agree with [isOverdue].
    if (isOverdue) return FinancialChipKind.overdue;
    switch (fee.status) {
      case FeeStatus.paid:
        return FinancialChipKind.paid;
      case FeeStatus.partial:
        return FinancialChipKind.partial;
      case FeeStatus.pending:
        return FinancialChipKind.due;
      case FeeStatus.pastDue:
        return FinancialChipKind.overdue;
    }
  }

  double get progress =>
      fee.amountDue > 0 ? (fee.amountPaid / fee.amountDue).clamp(0.0, 1.0) : 0.0;

  String get amountDueLabel => formatPK(fee.amountDue);
  String get amountPaidLabel => formatPK(fee.amountPaid);
  String get remainingLabel => formatPK(remaining);
}

/// One student's outstanding fee balance, aggregated from [Fee] rows.
///
/// Derived entirely from the existing fee repository — no new table.
class OutstandingBalanceView {
  const OutstandingBalanceView({
    required this.studentId,
    required this.studentName,
    required this.studentClass,
    required this.records,
  });

  final String studentId;
  final String studentName;
  final String studentClass;

  /// The student's unpaid fee rows, oldest month first.
  final List<Fee> records;

  double get totalDue => records.fold(0.0, (s, f) => s + f.amountDue);
  double get totalPaid => records.fold(0.0, (s, f) => s + f.amountPaid);
  double get remaining => totalDue - totalPaid;
  int get monthCount => records.length;
  int get overdueCount =>
      records.where((f) => FeeRecordView(f).isOverdue).length;

  /// Earliest unpaid row — the collection flow starts here.
  Fee? get oldestUnpaid {
    for (final f in records) {
      if (f.remaining > 0) return f;
    }
    return null;
  }

  String get remainingLabel => formatPK(remaining);

  /// Groups unpaid fee rows by student. Students with nothing outstanding
  /// are excluded. Sorted by remaining balance, largest first.
  static List<OutstandingBalanceView> aggregate(List<Fee> fees) {
    final byStudent = <String, List<Fee>>{};
    for (final f in fees) {
      if (f.remaining <= 0) continue;
      byStudent.putIfAbsent(f.studentId, () => []).add(f);
    }
    final views = <OutstandingBalanceView>[];
    for (final entry in byStudent.entries) {
      final records = entry.value
        ..sort((a, b) => a.month.compareTo(b.month));
      final first = records.first;
      views.add(OutstandingBalanceView(
        studentId: entry.key,
        studentName: first.studentName,
        studentClass: first.studentClass,
        records: records,
      ));
    }
    views.sort((a, b) => b.remaining.compareTo(a.remaining));
    return views;
  }
}

/// Presentation view over one [Invoice] (the finance backend).
class InvoiceView {
  const InvoiceView(this.invoice);

  final Invoice invoice;

  String get numberLabel => invoice.invoiceNumber ?? '—';
  String get studentLabel =>
      (invoice.studentName?.isNotEmpty ?? false) ? invoice.studentName! : '—';
  String get monthLabel => invoice.billingMonth == null
      ? '—'
      : monthLabelUrdu(invoice.billingMonth!);
  String get totalLabel => formatPK(invoice.total);
  String get balanceLabel => formatPK(invoice.balanceDue);

  FinancialChipKind get chipKind {
    switch (invoice.status) {
      case InvoiceStatus.draft:
        return FinancialChipKind.draft;
      case InvoiceStatus.issued:
        return FinancialChipKind.due;
      case InvoiceStatus.partiallyPaid:
        return FinancialChipKind.partial;
      case InvoiceStatus.paid:
        return FinancialChipKind.paid;
      case InvoiceStatus.overdue:
        return FinancialChipKind.overdue;
      case InvoiceStatus.cancelled:
      case InvoiceStatus.voided:
        return FinancialChipKind.cancelled;
    }
  }

  /// Only drafts may be deleted (posted rows are DB-immutable).
  bool get canDelete => invoice.status == InvoiceStatus.draft;
  bool get canIssue => invoice.status == InvoiceStatus.draft;
  bool get canCancel =>
      invoice.status == InvoiceStatus.issued ||
      invoice.status == InvoiceStatus.partiallyPaid ||
      invoice.status == InvoiceStatus.overdue;
}

/// Presentation view over one [Payment] (the finance backend).
class PaymentView {
  const PaymentView(this.payment);

  final Payment payment;

  String get methodLabel => payment.method.urduLabel;
  String get receiptLabel => payment.receiptNumber ?? '—';
  String get studentLabel =>
      (payment.studentName?.isNotEmpty ?? false) ? payment.studentName! : '—';
  String get amountLabel => formatPK(payment.amount);

  FinancialChipKind get chipKind {
    switch (payment.status) {
      case DocStatus.draft:
        return FinancialChipKind.draft;
      case DocStatus.approved:
        return FinancialChipKind.due;
      case DocStatus.posted:
        return FinancialChipKind.posted;
      case DocStatus.voided:
        return FinancialChipKind.cancelled;
    }
  }

  /// Only drafts may be deleted (posted rows are DB-immutable).
  bool get canDelete => payment.status == DocStatus.draft;
}

/// Presentation view over one [LedgerTransaction] (the finance backend).
class LedgerEntryView {
  const LedgerEntryView(this.entry);

  final LedgerTransaction entry;

  bool get isIncome => entry.isIncome;
  String get amountLabel => formatPK(entry.amount);

  /// Falls back to the category label when there is no description.
  String get title {
    final d = entry.description?.trim() ?? '';
    if (d.isNotEmpty) return d;
    return entry.category.urduLabel;
  }

  FinancialChipKind get statusChip {
    switch (entry.status) {
      case DocStatus.draft:
        return FinancialChipKind.draft;
      case DocStatus.approved:
        return FinancialChipKind.due;
      case DocStatus.posted:
        return FinancialChipKind.posted;
      case DocStatus.voided:
        return FinancialChipKind.cancelled;
    }
  }

  /// Only drafts may be deleted (posted rows are DB-immutable;
  /// corrections go through reversal entries).
  bool get canDelete => entry.status == DocStatus.draft;
}

/// Presentation view over one [ExpenseEntry] (the finance backend).
class ExpenseView {
  const ExpenseView(this.expense);

  final ExpenseEntry expense;

  String get amountLabel => formatPK(expense.amount);
  String get categoryLabel =>
      expense.category.isNotEmpty ? expense.category : 'دیگر';
  String get recipientLabel => expense.recipient ?? '—';

  FinancialChipKind get chipKind {
    switch (expense.status) {
      case DocStatus.draft:
        return FinancialChipKind.draft;
      case DocStatus.approved:
        return FinancialChipKind.due;
      case DocStatus.posted:
        return FinancialChipKind.posted;
      case DocStatus.voided:
        return FinancialChipKind.cancelled;
    }
  }
}

/// The finance dashboard's numbers — computed from the two existing
/// backends, never invented.
///
/// * Fee-side numbers come from the `fees` table rows.
/// * Ledger-side numbers come from posted finance ledger rows.
///
/// "اس ماہ وصولی" uses the same honest heuristic the collection screen
/// has always used: fee rows whose `paid_date` falls in the current
/// month. The [Fee] row only stores the cumulative paid amount and the
/// last paid date, so per-day attribution inside the month is not
/// knowable from the row — the card counts whole rows, exactly as before.
class FinanceHubOverview {
  const FinanceHubOverview({
    required this.totalOutstanding,
    required this.monthCollected,
    required this.pendingRecords,
    required this.overdueRecords,
    required this.postedIncome,
    required this.postedExpense,
    required this.topDues,
    required this.recentPayments,
  });

  /// Sum of remaining balances over all unpaid fee rows.
  final double totalOutstanding;

  /// Fee-register collections whose paid date falls in the current month.
  final double monthCollected;

  /// Fee rows with any remaining balance.
  final int pendingRecords;

  /// Fee rows past due (by status or due date).
  final int overdueRecords;

  /// Posted ledger income (real money in).
  final double postedIncome;

  /// Posted ledger expenses (real money out).
  final double postedExpense;

  double get balance => postedIncome - postedExpense;

  /// Largest outstanding balances, for the "فوری توجہ" list.
  final List<OutstandingBalanceView> topDues;

  /// Newest finance-backend payments, for the activity feed.
  final List<Payment> recentPayments;

  static FinanceHubOverview compute({
    required List<Fee> fees,
    required List<Payment> payments,
    required double postedIncome,
    required double postedExpense,
    DateTime? now,
    int topDuesCount = 5,
    int recentPaymentsCount = 5,
  }) {
    final current = now ?? DateTime.now();
    final monthPrefix =
        '${current.year}-${current.month.toString().padLeft(2, '0')}';

    double outstanding = 0;
    double collected = 0;
    int pending = 0;
    int overdue = 0;
    for (final f in fees) {
      final view = FeeRecordView(f);
      if (f.remaining > 0) {
        outstanding += f.remaining;
        pending++;
        if (view.isOverdue) overdue++;
      }
      if ((f.paidDate ?? '').startsWith(monthPrefix)) {
        collected += f.amountPaid;
      }
    }

    final dues = OutstandingBalanceView.aggregate(fees);
    final recent = payments.toList()
      ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));

    return FinanceHubOverview(
      totalOutstanding: outstanding,
      monthCollected: collected,
      pendingRecords: pending,
      overdueRecords: overdue,
      postedIncome: postedIncome,
      postedExpense: postedExpense,
      topDues: dues.take(topDuesCount).toList(),
      recentPayments: recent.take(recentPaymentsCount).toList(),
    );
  }
}
