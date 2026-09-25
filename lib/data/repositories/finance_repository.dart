/// فنانس ریپوزیٹری — Phase 4 finance rebuild (014_finance.sql)
/// Tenant-scoped Supabase access for the invoice → payment → receipt →
/// ledger flow. Every query is scoped with an explicit [tenantId]
/// (the provider reads it from `currentTenantIdProvider` and bails when
/// null — RLS is the server-side backstop).
///
/// State-machine notes (enforced DB-side by RLS + triggers):
///  * inserts are always `draft`; posting is a separate status update
///    (draft → posted for payments/ledger; draft → approved → posted for
///    income/expenses/refunds);
///  * posted/void rows are immutable — no client update/delete path exists
///    for them; corrections are reversal entries (refunds / void invoices /
///    reversing ledger rows);
///  * audit rows are written by DB triggers (public.finance_audit()).

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/finance.dart';
import '../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

abstract class IFinanceRepository {
  // accounts
  Future<List<Account>> getAccounts({required String tenantId});
  Future<Account> createAccount(Account a, {required String tenantId});
  Future<Account> updateAccount(Account a, {required String tenantId});
  Future<void> deleteAccount(String id, {required String tenantId});

  // ledger
  Future<List<LedgerTransaction>> getLedger(
      {required String tenantId, int limit = 200});
  Future<LedgerTransaction> createLedgerDraft(LedgerTransaction e,
      {required String tenantId});
  Future<LedgerTransaction> postLedgerEntry(String id,
      {required String tenantId});
  Future<void> deleteLedgerDraft(String id, {required String tenantId});

  // income / expenses (draft → approved → posted)
  Future<List<IncomeEntry>> getIncome({required String tenantId});
  Future<IncomeEntry> createIncome(IncomeEntry e,
      {required String tenantId});
  Future<IncomeEntry> transitionIncome(String id, DocStatus to,
      {required String tenantId, String? actorId});

  Future<List<ExpenseEntry>> getExpenses({required String tenantId});
  Future<ExpenseEntry> createExpense(ExpenseEntry e,
      {required String tenantId});
  Future<ExpenseEntry> transitionExpense(String id, DocStatus to,
      {required String tenantId, String? actorId});

  /// Full flow: draft → approved → posted (single call for the UI).
  Future<IncomeEntry> recordIncome(IncomeEntry e,
      {required String tenantId, required String actorId});
  Future<ExpenseEntry> recordExpense(ExpenseEntry e,
      {required String tenantId, required String actorId});

  // invoices
  Future<List<Invoice>> getInvoices({required String tenantId,
      String? studentId, InvoiceStatus? status});
  Future<Invoice> getInvoice(String id, {required String tenantId});
  Future<Invoice> createInvoice(Invoice inv, List<InvoiceItem> items,
      {required String tenantId});
  Future<Invoice> transitionInvoice(String id, InvoiceStatus to,
      {required String tenantId});
  Future<void> deleteInvoiceDraft(String id, {required String tenantId});

  // payments (draft → posted; posting auto-creates ledger + allocation)
  Future<List<Payment>> getPayments({required String tenantId,
      String? studentId});
  Future<Payment> getPayment(String id, {required String tenantId});

  /// Full flow: insert draft → post. Returns the posted payment
  /// (receipt_number is filled by the DB trigger).
  Future<Payment> recordPayment(Payment p, {required String tenantId});
  Future<void> deletePaymentDraft(String id, {required String tenantId});
  Future<List<PaymentAllocation>> getAllocationsForPayment(String paymentId,
      {required String tenantId});

  // refunds (draft → approved → posted; posting reverses the ledger)
  Future<List<Refund>> getRefunds({required String tenantId});
  Future<Refund> createRefund(Refund r, {required String tenantId});
  Future<Refund> transitionRefund(String id, DocStatus to,
      {required String tenantId, String? actorId});
  Future<void> deleteRefundDraft(String id, {required String tenantId});

  // discounts / scholarships / fee structures
  Future<List<Discount>> getDiscounts({required String tenantId,
      String? invoiceId});
  Future<Discount> createDiscount(Discount d, {required String tenantId});
  Future<Discount> applyDiscount(String id, {required String tenantId});
  Future<void> deleteDiscountDraft(String id, {required String tenantId});

  Future<List<Scholarship>> getScholarships({required String tenantId,
      String? studentId});
  Future<Scholarship> createScholarship(Scholarship s,
      {required String tenantId});
  Future<Scholarship> updateScholarship(Scholarship s,
      {required String tenantId});

  Future<List<FeeStructure>> getFeeStructures({required String tenantId});
  Future<List<FeeItem>> getFeeItems(String structureId,
      {required String tenantId});
}

// ─────────────────────────────────────────────
// Supabase implementation
// ─────────────────────────────────────────────

class SupabaseFinanceRepository implements IFinanceRepository {
  SupabaseClient get _client => SupabaseService.client;

  /// Status transition on a document table. [extra] carries e.g.
  /// approved_by. RLS decides whether the transition is legal.
  Future<Map<String, dynamic>> _transition({
    required String table,
    required String id,
    required String tenantId,
    required String to,
    Map<String, dynamic>? extra,
  }) async {
    final payload = <String, dynamic>{'status': to, ...?extra};
    final res = await _client
        .from(table)
        .update(payload)
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .select()
        .single();
    return res as Map<String, dynamic>;
  }

  // ── accounts ──

  @override
  Future<List<Account>> getAccounts({required String tenantId}) async {
    final res = await _client
        .from('accounts')
        .select()
        .eq('tenant_id', tenantId)
        .order('code');
    return (res as List)
        .map((r) => Account.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Account> createAccount(Account a,
      {required String tenantId}) async {
    final res = await _client
        .from('accounts')
        .insert({...a.toJson(), 'tenant_id': tenantId})
        .select()
        .single();
    return Account.fromJson(res);
  }

  @override
  Future<Account> updateAccount(Account a,
      {required String tenantId}) async {
    final res = await _client
        .from('accounts')
        .update(a.toJson())
        .eq('tenant_id', tenantId)
        .eq('id', a.id!)
        .select()
        .single();
    return Account.fromJson(res);
  }

  @override
  Future<void> deleteAccount(String id, {required String tenantId}) async {
    await _client
        .from('accounts')
        .delete()
        .eq('tenant_id', tenantId)
        .eq('id', id);
  }

  // ── ledger ──

  @override
  Future<List<LedgerTransaction>> getLedger(
      {required String tenantId, int limit = 200}) async {
    final res = await _client
        .from('transactions')
        .select()
        .eq('tenant_id', tenantId)
        .order('entry_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return (res as List)
        .map((r) => LedgerTransaction.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<LedgerTransaction> createLedgerDraft(LedgerTransaction e,
      {required String tenantId}) async {
    final res = await _client
        .from('transactions')
        .insert({...e.toJson(), 'tenant_id': tenantId, 'status': 'draft'})
        .select()
        .single();
    return LedgerTransaction.fromJson(res);
  }

  @override
  Future<LedgerTransaction> postLedgerEntry(String id,
      {required String tenantId}) async {
    final res = await _transition(
        table: 'transactions', id: id, tenantId: tenantId, to: 'posted');
    return LedgerTransaction.fromJson(res);
  }

  @override
  Future<void> deleteLedgerDraft(String id,
      {required String tenantId}) async {
    await _client
        .from('transactions')
        .delete()
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .eq('status', 'draft');
  }

  // ── income ──

  @override
  Future<List<IncomeEntry>> getIncome({required String tenantId}) async {
    final res = await _client
        .from('income')
        .select()
        .eq('tenant_id', tenantId)
        .order('received_date', ascending: false);
    return (res as List)
        .map((r) => IncomeEntry.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<IncomeEntry> createIncome(IncomeEntry e,
      {required String tenantId}) async {
    final res = await _client
        .from('income')
        .insert({...e.toJson(), 'tenant_id': tenantId, 'status': 'draft'})
        .select()
        .single();
    return IncomeEntry.fromJson(res);
  }

  @override
  Future<IncomeEntry> transitionIncome(String id, DocStatus to,
      {required String tenantId, String? actorId}) async {
    final extra = to == DocStatus.approved && actorId != null
        ? {'approved_by': actorId}
        : null;
    final res = await _transition(
        table: 'income', id: id, tenantId: tenantId, to: to.dbValue, extra: extra);
    return IncomeEntry.fromJson(res);
  }

  @override
  Future<IncomeEntry> recordIncome(IncomeEntry e,
      {required String tenantId, required String actorId}) async {
    var row = await createIncome(e, tenantId: tenantId);
    row = await transitionIncome(row.id!, DocStatus.approved,
        tenantId: tenantId, actorId: actorId);
    row = await transitionIncome(row.id!, DocStatus.posted,
        tenantId: tenantId);
    return row;
  }

  // ── expenses ──

  @override
  Future<List<ExpenseEntry>> getExpenses({required String tenantId}) async {
    final res = await _client
        .from('expenses')
        .select()
        .eq('tenant_id', tenantId)
        .order('expense_date', ascending: false);
    return (res as List)
        .map((r) => ExpenseEntry.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ExpenseEntry> createExpense(ExpenseEntry e,
      {required String tenantId}) async {
    final res = await _client
        .from('expenses')
        .insert({...e.toJson(), 'tenant_id': tenantId, 'status': 'draft'})
        .select()
        .single();
    return ExpenseEntry.fromJson(res);
  }

  @override
  Future<ExpenseEntry> transitionExpense(String id, DocStatus to,
      {required String tenantId, String? actorId}) async {
    final extra = to == DocStatus.approved && actorId != null
        ? {'approved_by': actorId}
        : null;
    final res = await _transition(
        table: 'expenses', id: id, tenantId: tenantId, to: to.dbValue, extra: extra);
    return ExpenseEntry.fromJson(res);
  }

  @override
  Future<ExpenseEntry> recordExpense(ExpenseEntry e,
      {required String tenantId, required String actorId}) async {
    var row = await createExpense(e, tenantId: tenantId);
    row = await transitionExpense(row.id!, DocStatus.approved,
        tenantId: tenantId, actorId: actorId);
    row = await transitionExpense(row.id!, DocStatus.posted,
        tenantId: tenantId);
    return row;
  }

  // ── invoices ──

  static const _invoiceSelect = '*, students(name)';

  @override
  Future<List<Invoice>> getInvoices({required String tenantId,
      String? studentId, InvoiceStatus? status}) async {
    var q = _client
        .from('invoices')
        .select(_invoiceSelect)
        .eq('tenant_id', tenantId);
    if (studentId != null) q = q.eq('student_id', studentId);
    if (status != null) q = q.eq('status', status.dbValue);
    final res = await q.order('issue_date', ascending: false);
    return (res as List)
        .map((r) => Invoice.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Invoice> getInvoice(String id, {required String tenantId}) async {
    final res = await _client
        .from('invoices')
        .select(_invoiceSelect)
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .single();
    return Invoice.fromJson(res);
  }

  @override
  Future<Invoice> createInvoice(Invoice inv, List<InvoiceItem> items,
      {required String tenantId}) async {
    final res = await _client
        .from('invoices')
        .insert({...inv.toJson(), 'tenant_id': tenantId, 'status': 'draft'})
        .select(_invoiceSelect)
        .single();
    final created = Invoice.fromJson(res);
    if (items.isNotEmpty) {
      await _client.from('invoice_items').insert(items
          .map((i) => {
                ...i.toJson(),
                'tenant_id': tenantId,
                'invoice_id': created.id,
              })
          .toList());
    }
    // Re-read: triggers recomputed subtotal/total server-side.
    return getInvoice(created.id!, tenantId: tenantId);
  }

  @override
  Future<Invoice> transitionInvoice(String id, InvoiceStatus to,
      {required String tenantId}) async {
    final res = await _transition(
        table: 'invoices', id: id, tenantId: tenantId, to: to.dbValue);
    return Invoice.fromJson(res);
  }

  @override
  Future<void> deleteInvoiceDraft(String id,
      {required String tenantId}) async {
    await _client
        .from('invoices')
        .delete()
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .eq('status', 'draft');
  }

  // ── payments ──

  static const _paymentSelect = '*, students(name)';

  @override
  Future<List<Payment>> getPayments({required String tenantId,
      String? studentId}) async {
    var q = _client
        .from('payments')
        .select(_paymentSelect)
        .eq('tenant_id', tenantId);
    if (studentId != null) q = q.eq('student_id', studentId);
    final res = await q.order('payment_date', ascending: false);
    return (res as List)
        .map((r) => Payment.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Payment> getPayment(String id, {required String tenantId}) async {
    final res = await _client
        .from('payments')
        .select(_paymentSelect)
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .single();
    return Payment.fromJson(res);
  }

  @override
  Future<Payment> recordPayment(Payment p,
      {required String tenantId}) async {
    // 1. insert draft (DB trigger fills receipt_number)
    final inserted = await _client
        .from('payments')
        .insert({...p.toJson(), 'tenant_id': tenantId, 'status': 'draft'})
        .select(_paymentSelect)
        .single();
    final draft = Payment.fromJson(inserted);
    // 2. post → trigger creates ledger entry + allocation + invoice update
    await _transition(
        table: 'payments',
        id: draft.id!,
        tenantId: tenantId,
        to: 'posted');
    // 3. re-read the posted row (posted_at filled server-side)
    return getPayment(draft.id!, tenantId: tenantId);
  }

  @override
  Future<void> deletePaymentDraft(String id,
      {required String tenantId}) async {
    await _client
        .from('payments')
        .delete()
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .eq('status', 'draft');
  }

  @override
  Future<List<PaymentAllocation>> getAllocationsForPayment(String paymentId,
      {required String tenantId}) async {
    final res = await _client
        .from('payment_allocations')
        .select()
        .eq('tenant_id', tenantId)
        .eq('payment_id', paymentId);
    return (res as List)
        .map((r) => PaymentAllocation.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // ── refunds ──

  @override
  Future<List<Refund>> getRefunds({required String tenantId}) async {
    final res = await _client
        .from('refunds')
        .select()
        .eq('tenant_id', tenantId)
        .order('refund_date', ascending: false);
    return (res as List)
        .map((r) => Refund.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Refund> createRefund(Refund r, {required String tenantId}) async {
    final res = await _client
        .from('refunds')
        .insert({...r.toJson(), 'tenant_id': tenantId, 'status': 'draft'})
        .select()
        .single();
    return Refund.fromJson(res);
  }

  @override
  Future<Refund> transitionRefund(String id, DocStatus to,
      {required String tenantId, String? actorId}) async {
    final extra = to == DocStatus.approved && actorId != null
        ? {'approved_by': actorId}
        : null;
    final res = await _transition(
        table: 'refunds', id: id, tenantId: tenantId, to: to.dbValue, extra: extra);
    return Refund.fromJson(res);
  }

  @override
  Future<void> deleteRefundDraft(String id,
      {required String tenantId}) async {
    await _client
        .from('refunds')
        .delete()
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .eq('status', 'draft');
  }

  // ── discounts ──

  @override
  Future<List<Discount>> getDiscounts({required String tenantId,
      String? invoiceId}) async {
    var q = _client
        .from('discounts')
        .select()
        .eq('tenant_id', tenantId);
    if (invoiceId != null) q = q.eq('invoice_id', invoiceId);
    final res = await q.order('created_at', ascending: false);
    return (res as List)
        .map((r) => Discount.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Discount> createDiscount(Discount d,
      {required String tenantId}) async {
    final res = await _client
        .from('discounts')
        .insert({...d.toJson(), 'tenant_id': tenantId, 'status': 'draft'})
        .select()
        .single();
    return Discount.fromJson(res);
  }

  @override
  Future<Discount> applyDiscount(String id,
      {required String tenantId}) async {
    final res = await _transition(
        table: 'discounts', id: id, tenantId: tenantId, to: 'applied');
    return Discount.fromJson(res);
  }

  @override
  Future<void> deleteDiscountDraft(String id,
      {required String tenantId}) async {
    await _client
        .from('discounts')
        .delete()
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .eq('status', 'draft');
  }

  // ── scholarships ──

  @override
  Future<List<Scholarship>> getScholarships({required String tenantId,
      String? studentId}) async {
    var q = _client
        .from('scholarships')
        .select('*, students(name)')
        .eq('tenant_id', tenantId);
    if (studentId != null) q = q.eq('student_id', studentId);
    final res = await q.order('created_at', ascending: false);
    return (res as List)
        .map((r) => Scholarship.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Scholarship> createScholarship(Scholarship s,
      {required String tenantId}) async {
    final res = await _client
        .from('scholarships')
        .insert({...s.toJson(), 'tenant_id': tenantId})
        .select('*, students(name)')
        .single();
    return Scholarship.fromJson(res);
  }

  @override
  Future<Scholarship> updateScholarship(Scholarship s,
      {required String tenantId}) async {
    final res = await _client
        .from('scholarships')
        .update(s.toJson())
        .eq('tenant_id', tenantId)
        .eq('id', s.id!)
        .select('*, students(name)')
        .single();
    return Scholarship.fromJson(res);
  }

  // ── fee structures ──

  @override
  Future<List<FeeStructure>> getFeeStructures(
      {required String tenantId}) async {
    final res = await _client
        .from('fee_structures')
        .select()
        .eq('tenant_id', tenantId)
        .order('name');
    return (res as List)
        .map((r) => FeeStructure.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<FeeItem>> getFeeItems(String structureId,
      {required String tenantId}) async {
    final res = await _client
        .from('fee_items')
        .select()
        .eq('tenant_id', tenantId)
        .eq('fee_structure_id', structureId)
        .order('name');
    return (res as List)
        .map((r) => FeeItem.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
