// Phase 9 financial-IA view-model unit tests.
//
// Implementation files under test:
//   lib/presentation/viewmodels/finance/financial_views.dart
//   lib/core/utils/money_format.dart (formatPK)
//
// HONESTY NOTE — these tests cover pure-Dart presentation adapters and
// aggregation math only. The adapters read real backend models
// ([Fee], [Invoice], [Payment], [LedgerTransaction], [ExpenseEntry]) and
// never invent rows: [OutstandingBalanceView.aggregate] skips fully-paid
// fees, [InvoiceView]/[PaymentView]/[LedgerEntryView]/[ExpenseView]
// surface only backend lifecycle states, and [FinanceHubOverview.compute]
// never synthesizes totals. Deletion rules ([canDelete], [canCancel],
// [canIssue]) mirror the backend: drafts can be discarded; posted rows
// are immutable history. There is no backend delete for expenses at
// all — voiding is the archive equivalent.
//
// Destructive-confirmation UI itself (showM360ConfirmDialog) is a widget
// concern; what IS tested here is the gating logic that decides which
// actions exist at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/utils/money_format.dart';
import 'package:madrasa_360/data/models/fee.dart';
import 'package:madrasa_360/data/models/finance.dart';
import 'package:madrasa_360/presentation/viewmodels/finance/financial_views.dart';

Fee _fee({
  String id = 'f1',
  String studentId = 's1',
  String studentName = 'احمد خان',
  String studentClass = 'درجہ اول',
  String month = '2026-09',
  double amountDue = 1000,
  double amountPaid = 0,
  String dueDate = '2026-09-10',
  String? paidDate,
  FeeStatus status = FeeStatus.pending,
}) =>
    Fee(
      id: id,
      tenantId: 'tenant-1',
      studentId: studentId,
      studentName: studentName,
      studentClass: studentClass,
      month: month,
      amountDue: amountDue,
      amountPaid: amountPaid,
      dueDate: dueDate,
      paidDate: paidDate,
      status: status,
    );

LedgerTransaction _ledger({
  required LedgerKind kind,
  required double amount,
  DocStatus status = DocStatus.posted,
  String? description,
}) =>
    LedgerTransaction(
      tenantId: 'tenant-1',
      entryDate: DateTime(2026, 9, 5),
      kind: kind,
      amount: amount,
      status: status,
      description: description,
    );

ExpenseEntry _expense({
  String category = 'بجلی',
  double amount = 5000,
  String? description = 'بجلی کا بل',
  DocStatus status = DocStatus.draft,
}) =>
    ExpenseEntry(
      tenantId: 'tenant-1',
      category: category,
      amount: amount,
      expenseDate: DateTime(2026, 9, 3),
      description: description,
      status: status,
    );

Invoice _invoice({
  InvoiceStatus status = InvoiceStatus.draft,
  double total = 2000,
  String? invoiceNumber = 'INV-1',
}) =>
    Invoice(
      tenantId: 'tenant-1',
      studentId: 's1',
      studentName: 'احمد خان',
      invoiceNumber: invoiceNumber,
      billingMonth: '2026-09',
      issueDate: DateTime(2026, 9, 1),
      dueDate: DateTime(2026, 9, 10),
      total: total,
      balanceDue: total,
      status: status,
    );

Payment _payment({
  double amount = 1000,
  DocStatus status = DocStatus.posted,
  String? receiptNumber = 'RCPT-1',
}) =>
    Payment(
      tenantId: 'tenant-1',
      studentId: 's1',
      studentName: 'احمد خان',
      amount: amount,
      paymentDate: DateTime(2026, 9, 4),
      status: status,
      receiptNumber: receiptNumber,
    );

void main() {
  group('formatPK — Pakistani grouping', () {
    test('groups lakh/crore style', () {
      expect(formatPK(1000), '1,000 روپے');
      expect(formatPK(100000), '1,00,000 روپے');
      expect(formatPK(1500000), '15,00,000 روپے');
      expect(formatPK(0), '0 روپے');
    });
  });

  group('monthLabelUrdu', () {
    test('maps known month codes', () {
      expect(monthLabelUrdu('2026-09'), 'ستمبر 2026');
      expect(monthLabelUrdu('2026-01'), 'جنوری 2026');
      expect(monthLabelUrdu('2026-12'), 'دسمبر 2026');
    });

    test('falls back to the raw code for unknown input', () {
      expect(monthLabelUrdu('abc'), 'abc');
      expect(monthLabelUrdu(''), '');
    });
  });

  group('FinancialChipKind Urdu labels', () {
    test('every kind has a non-empty Urdu label', () {
      for (final kind in FinancialChipKind.values) {
        expect(kind.urduLabel, isNotEmpty);
      }
      expect(FinancialChipKind.paid.urduLabel, 'ادا شدہ');
      expect(FinancialChipKind.draft.urduLabel, 'مسودہ');
      expect(FinancialChipKind.cancelled.urduLabel, 'منسوخ');
    });
  });

  group('FeeRecordView', () {
    test('fully paid fee maps to paid chip and zero remaining', () {
      final view = FeeRecordView(_fee(
        amountDue: 1000,
        amountPaid: 1000,
        status: FeeStatus.paid,
      ));
      expect(view.chipKind, FinancialChipKind.paid);
      expect(view.remainingLabel, '0 روپے');
      expect(view.progress, 1.0);
    });

    test('partial payment maps to partial chip', () {
      final view = FeeRecordView(_fee(
        amountDue: 1000,
        amountPaid: 400,
        status: FeeStatus.partial,
        dueDate: '2099-12-31',
      ));
      expect(view.chipKind, FinancialChipKind.partial);
      expect(view.remainingLabel, formatPK(600));
      expect(view.progress, closeTo(0.4, 0.0001));
    });

    test('partial payment past its due date maps to overdue chip', () {
      final view = FeeRecordView(_fee(
        amountDue: 1000,
        amountPaid: 400,
        status: FeeStatus.partial,
        dueDate: '2026-09-10',
      ));
      expect(view.chipKind, FinancialChipKind.overdue);
    });

    test('past dueDate maps to overdue chip, future to due', () {
      // 2026-09-10 is always in the past of a 2026-09-29 run.
      final overdue = FeeRecordView(_fee(
        dueDate: '2026-09-10',
        status: FeeStatus.pending,
      ));
      expect(overdue.chipKind, FinancialChipKind.overdue);

      final future = FeeRecordView(_fee(
        dueDate: '2099-12-31',
        status: FeeStatus.pending,
      ));
      expect(future.chipKind, FinancialChipKind.due);
    });

    test('exposes fee identity and month label', () {
      final view = FeeRecordView(_fee(month: '2026-09'));
      expect(view.fee.studentName, 'احمد خان');
      expect(view.fee.studentClass, 'درجہ اول');
      expect(view.monthLabel, 'ستمبر 2026');
      expect(view.amountDueLabel, '1,000 روپے');
    });
  });

  group('OutstandingBalanceView.aggregate', () {
    test('groups unpaid fees by student and sorts by amount', () {
      final fees = [
        _fee(id: 'f1', studentId: 's1', amountPaid: 0),
        _fee(id: 'f2', studentId: 's1', amountPaid: 200),
        _fee(id: 'f3', studentId: 's2', amountPaid: 0, amountDue: 5000),
      ];
      final result = OutstandingBalanceView.aggregate(fees);
      expect(result.length, 2);
      // highest balance first
      expect(result.first.studentId, 's2');
      expect(result.first.remaining, 5000);
      expect(result.last.remaining, 1800);
      expect(result.last.monthCount, 2);
      expect(result.last.studentClass, 'درجہ اول');
    });

    test('fully paid fees contribute nothing and are skipped', () {
      final result = OutstandingBalanceView.aggregate([
        _fee(
            id: 'f1',
            amountDue: 1000,
            amountPaid: 1000,
            status: FeeStatus.paid),
      ]);
      expect(result, isEmpty);
    });

    test('empty input yields empty output — never invented rows', () {
      expect(OutstandingBalanceView.aggregate([]), isEmpty);
    });
  });

  group('InvoiceView lifecycle rules', () {
    test('draft can be issued and deleted, not cancelled', () {
      final view = InvoiceView(_invoice(status: InvoiceStatus.draft));
      expect(view.chipKind, FinancialChipKind.draft);
      expect(view.canIssue, isTrue);
      expect(view.canDelete, isTrue);
      expect(view.canCancel, isFalse);
    });

    test('issued can be cancelled but not edited or deleted', () {
      final view = InvoiceView(_invoice(status: InvoiceStatus.issued));
      expect(view.canIssue, isFalse);
      expect(view.canDelete, isFalse);
      expect(view.canCancel, isTrue);
    });

    test('cancelled invoice offers no actions', () {
      final view = InvoiceView(_invoice(status: InvoiceStatus.cancelled));
      expect(view.chipKind, FinancialChipKind.cancelled);
      expect(view.canIssue || view.canDelete || view.canCancel, isFalse);
    });

    test('surfaces real backend fields only', () {
      final view = InvoiceView(_invoice(total: 2500));
      expect(view.numberLabel, 'INV-1');
      expect(view.studentLabel, 'احمد خان');
      expect(view.totalLabel, '2,500 روپے');
      expect(view.monthLabel, 'ستمبر 2026');
    });
  });

  group('PaymentView deletion rules', () {
    test('only draft payments can be discarded', () {
      expect(PaymentView(_payment(status: DocStatus.draft)).canDelete, isTrue);
      expect(
          PaymentView(_payment(status: DocStatus.posted)).canDelete, isFalse);
    });

    test('posted payment maps to posted chip with real fields', () {
      final view = PaymentView(_payment(amount: 2500));
      expect(view.chipKind, FinancialChipKind.posted);
      expect(view.amountLabel, '2,500');
      expect(view.methodLabel, isNotEmpty);
      expect(view.receiptLabel, 'RCPT-1');
      expect(view.studentLabel, 'احمد خان');
    });
  });

  group('LedgerEntryView', () {
    test('blank description falls back to category label', () {
      final view = LedgerEntryView(_ledger(
        kind: LedgerKind.income,
        amount: 1000,
        description: '  ',
      ));
      expect(view.title, isNotEmpty);
    });

    test('real description is used as title', () {
      final view = LedgerEntryView(_ledger(
        kind: LedgerKind.expense,
        amount: 500,
        description: 'چاک بورڈ',
      ));
      expect(view.title, 'چاک بورڈ');
    });

    test('draft deletion only; posted rows immutable', () {
      expect(
        LedgerEntryView(_ledger(kind: LedgerKind.income, amount: 1)).canDelete,
        isFalse,
      );
      expect(
        LedgerEntryView(_ledger(
          kind: LedgerKind.income,
          amount: 1,
          status: DocStatus.draft,
        )).canDelete,
        isTrue,
      );
    });
  });

  group('ExpenseView', () {
    test('status chips and amount/category labels', () {
      final view = ExpenseView(_expense(status: DocStatus.approved));
      expect(view.chipKind, FinancialChipKind.due);
      expect(view.amountLabel, '5,000 روپے');
      expect(view.categoryLabel, 'بجلی');
      expect(view.recipientLabel, '—');
    });

    test('posted expense maps to posted chip', () {
      expect(
        ExpenseView(_expense(status: DocStatus.posted)).chipKind,
        FinancialChipKind.posted,
      );
    });
  });

  group('FinanceHubOverview.compute', () {
    test('aggregates real rows with Pakistani-grouped totals', () {
      final overview = FinanceHubOverview.compute(
        fees: [
          _fee(
            id: 'f1',
            studentId: 's1',
            amountPaid: 1000,
            paidDate: '2026-09-05',
            status: FeeStatus.paid,
          ),
          _fee(
              id: 'f2',
              studentId: 's2',
              amountPaid: 0,
              status: FeeStatus.pending),
        ],
        payments: [_payment()],
        postedIncome: 2000,
        postedExpense: 800,
        now: DateTime(2026, 9, 15),
      );
      // outstanding: only the unpaid f2
      expect(overview.totalOutstanding, 1000);
      // month collection: f1 paid in September
      expect(overview.monthCollected, 1000);
      expect(overview.postedIncome, 2000);
      expect(overview.postedExpense, 800);
      expect(overview.balance, 1200);
      expect(overview.pendingRecords, 1);
      expect(overview.topDues.length, 1);
      expect(overview.recentPayments.length, 1);
    });

    test('empty inputs produce honest zeros', () {
      final overview = FinanceHubOverview.compute(
        fees: [],
        payments: [],
        postedIncome: 0,
        postedExpense: 0,
        now: DateTime(2026, 9, 15),
      );
      expect(overview.totalOutstanding, 0);
      expect(overview.monthCollected, 0);
      expect(overview.balance, 0);
      expect(overview.topDues, isEmpty);
      expect(overview.recentPayments, isEmpty);
    });

    test('top dues are capped at five and sorted by amount', () {
      final fees = List.generate(
        8,
        (i) => _fee(
          id: 'f$i',
          studentId: 's$i',
          studentName: 'طالب $i',
          amountDue: (i + 1) * 1000.0,
        ),
      );
      final overview = FinanceHubOverview.compute(
        fees: fees,
        payments: [],
        postedIncome: 0,
        postedExpense: 0,
        now: DateTime(2026, 9, 15),
      );
      expect(overview.topDues.length, 5);
      expect(overview.topDues.first.remaining, 8000);
      expect(overview.pendingRecords, 8);
    });
  });
}
