// Fee-calculation unit tests.
//
// Implementation files under test:
//   lib/data/models/finance.dart               (Invoice/Discount/Scholarship/Payment enums + JSON)
//   lib/providers/finance_provider.dart        (FinanceState.totalIncome/totalExpense/balance)
//   lib/core/reports/data/report_models.dart   (ReportInvoice.balanceDue)
//
// HONESTY NOTE — what is NOT tested here and why: the client performs NO
// invoice-total, discount-application or payment-allocation arithmetic.
// Those numbers are computed server-side by DB triggers when queue rows
// land (see the header of lib/data/repositories/finance_repository.dart:
// "server-computed fields (receipt_number, invoice totals, ledger
// auto-entries, allocations) only appear AFTER the row syncs").
// InvoiceItem.lineTotal is likewise server-computed. What IS tested is
// every real client-side money formula that exists:
//   * FinanceState aggregation over the posted ledger,
//   * ReportInvoice.balanceDue (the read-side outstanding-balance formula),
//   * enum <-> DB value mappings the write path depends on,
//   * model JSON round-trips for totals-bearing documents.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/reports/data/report_models.dart';
import 'package:madrasa_360/data/models/finance.dart';
import 'package:madrasa_360/providers/finance_provider.dart';

LedgerTransaction _entry({
  required LedgerKind kind,
  required double amount,
  DocStatus status = DocStatus.posted,
}) =>
    LedgerTransaction(
      tenantId: 'tenant-1',
      entryDate: DateTime(2026, 9, 1),
      kind: kind,
      amount: amount,
      status: status,
    );

void main() {
  group('FinanceState ledger aggregation (posted-only)', () {
    test('totalIncome sums posted income entries', () {
      final state = FinanceState(ledger: [
        _entry(kind: LedgerKind.income, amount: 1000),
        _entry(kind: LedgerKind.income, amount: 2500),
        _entry(kind: LedgerKind.expense, amount: 400),
      ]);
      expect(state.totalIncome, 3500);
    });

    test('drafts are excluded; transfers count as non-income', () {
      final state = FinanceState(ledger: [
        _entry(kind: LedgerKind.income, amount: 1000),
        _entry(kind: LedgerKind.income, amount: 500,
            status: DocStatus.draft), // not real money yet
        _entry(kind: LedgerKind.expense, amount: 300),
        _entry(kind: LedgerKind.expense, amount: 700,
            status: DocStatus.void), // void is final but not posted
        _entry(kind: LedgerKind.transfer, amount: 200),
      ]);
      expect(state.totalIncome, 1000);
      // transfer is not income, so it lands in totalExpense
      expect(state.totalExpense, 500);
      expect(state.balance, 500);
    });

    test('empty ledger yields zero totals', () {
      const state = FinanceState();
      expect(state.totalIncome, 0);
      expect(state.totalExpense, 0);
      expect(state.balance, 0);
    });

    test('balance can go negative (more expense than income)', () {
      final state = FinanceState(ledger: [
        _entry(kind: LedgerKind.income, amount: 100),
        _entry(kind: LedgerKind.expense, amount: 250),
      ]);
      expect(state.balance, -150);
    });

    test('byKind partitions the full ledger (including drafts)', () {
      final state = FinanceState(ledger: [
        _entry(kind: LedgerKind.income, amount: 100),
        _entry(kind: LedgerKind.income, amount: 200,
            status: DocStatus.draft),
        _entry(kind: LedgerKind.expense, amount: 50),
      ]);
      expect(state.byKind(LedgerKind.income).length, 2);
      expect(state.byKind(LedgerKind.expense).length, 1);
    });
  });

  group('ReportInvoice.balanceDue (outstanding balance)', () {
    test('total minus paid minus discount', () {
      const inv = ReportInvoice(
        id: 'i1',
        studentId: 's1',
        status: 'issued',
        total: 5000,
        amountPaid: 2000,
        discountTotal: 500,
      );
      expect(inv.balanceDue, 2500);
    });

    test('fully paid invoice has zero balance', () {
      const inv = ReportInvoice(
        id: 'i1',
        studentId: 's1',
        status: 'paid',
        total: 4500,
        amountPaid: 4500,
      );
      expect(inv.balanceDue, 0);
    });

    test('no payments and no discount -> full total due', () {
      const inv = ReportInvoice(
        id: 'i1',
        studentId: 's1',
        status: 'issued',
        total: 3200,
      );
      expect(inv.balanceDue, 3200);
    });
  });

  group('Invoice JSON + status mapping', () {
    test('totals-bearing fields round-trip through fromJson', () {
      final inv = Invoice.fromJson({
        'id': 'inv-1',
        'tenant_id': 't1',
        'student_id': 's1',
        'issue_date': '2026-09-01',
        'due_date': '2026-09-30',
        'subtotal': 5000,
        'discount_total': 500,
        'tax_total': 0,
        'total': 4500,
        'amount_paid': 2000,
        'balance_due': 2500,
        'status': 'partially_paid',
      });
      expect(inv.subtotal, 5000);
      expect(inv.discountTotal, 500);
      expect(inv.total, 4500);
      expect(inv.amountPaid, 2000);
      expect(inv.balanceDue, 2500);
      expect(inv.status, InvoiceStatus.partiallyPaid);
    });

    test('partially_paid db value round-trips', () {
      expect(InvoiceStatus.partiallyPaid.dbValue, 'partially_paid');
      expect(InvoiceStatusX.fromDb('partially_paid'),
          InvoiceStatus.partiallyPaid);
    });

    test('isFinal covers paid/cancelled/void only', () {
      expect(InvoiceStatus.paid.isFinal, isTrue);
      expect(InvoiceStatus.cancelled.isFinal, isTrue);
      expect(InvoiceStatus.void.isFinal, isTrue);
      expect(InvoiceStatus.issued.isFinal, isFalse);
      expect(InvoiceStatus.partiallyPaid.isFinal, isFalse);
      expect(InvoiceStatus.overdue.isFinal, isFalse);
    });

    test('unknown status string falls back to draft (never crashes)', () {
      expect(InvoiceStatusX.fromDb('bogus'), InvoiceStatus.draft);
      expect(InvoiceStatusX.fromDb(null), InvoiceStatus.draft);
    });
  });

  group('Discount model', () {
    test('percentage vs fixed db values', () {
      expect(DiscountKind.percentage.dbValue, 'percentage');
      expect(DiscountKind.fixed.dbValue, 'fixed');
      expect(DiscountKindX.fromDb('percentage'), DiscountKind.percentage);
      expect(DiscountKindX.fromDb('fixed'), DiscountKind.fixed);
      // unknown -> fixed (the safer default: a bounded amount, not a ratio)
      expect(DiscountKindX.fromDb('bogus'), DiscountKind.fixed);
    });

    test('discount serialises type, value and applied status', () {
      const d = Discount(
        tenantId: 't1',
        invoiceId: 'inv-1',
        discountType: DiscountKind.percentage,
        value: 10,
        status: DiscountStatus.applied,
      );
      final json = d.toJson();
      expect(json['discount_type'], 'percentage');
      expect(json['value'], 10);
      expect(json['status'], 'applied');
      final back = Discount.fromJson(json);
      expect(back.discountType, DiscountKind.percentage);
      expect(back.value, 10);
      expect(back.status, DiscountStatus.applied);
    });
  });

  group('Scholarship model', () {
    test('discountPercent survives a JSON round-trip', () {
      final s = Scholarship(
        tenantId: 't1',
        studentId: 's1',
        name: 'Hifz merit',
        discountPercent: 50,
        startDate: DateTime(2026, 4, 1),
        status: ScholarshipStatus.active,
      );
      final back = Scholarship.fromJson(s.toJson());
      expect(back.discountPercent, 50);
      expect(back.status, ScholarshipStatus.active);
      expect(back.status.urduLabel, 'فعال');
    });
  });

  group('Payment enums', () {
    test('bank_transfer db value is explicit, not the enum name', () {
      expect(PaymentMethod.bankTransfer.dbValue, 'bank_transfer');
      expect(PaymentMethodX.fromDb('bank_transfer'),
          PaymentMethod.bankTransfer);
      expect(PaymentMethod.cash.dbValue, 'cash');
    });

    test('draft is not final; posted and void are', () {
      expect(DocStatus.draft.isFinal, isFalse);
      expect(DocStatus.posted.isFinal, isTrue);
      expect(DocStatus.void.isFinal, isTrue);
    });
  });
}
