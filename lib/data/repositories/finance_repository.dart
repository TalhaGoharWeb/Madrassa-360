/// فنانس ریپوزیٹری — LOCAL-FIRST (Phase 5 offline-first sync).
///
/// Tenant-scoped access for the invoice → payment → receipt → ledger
/// flow. Every query is scoped with an explicit [tenantId] (the provider
/// reads it from `currentTenantIdProvider` and bails when null — RLS is
/// the server-side backstop).
///
/// State-machine notes (enforced DB-side by RLS + triggers):
///  * inserts are always `draft`; posting is a separate status update
///    (draft → posted for payments/ledger; draft → approved → posted for
///    income/expenses/refunds);
///  * posted/void rows are immutable — no client update/delete path exists
///    for them; corrections are reversal entries (refunds / void invoices /
///    reversing ledger rows);
///  * audit rows are written by DB triggers (public.finance_audit()).
///
/// Offline-first contract (Phase 5):
///  * **READS remain remote** (Supabase selects below) — the local finance
///    tables (`accounts`, `transactions`, `income`, `expenses`, `invoices`,
///    `invoice_items`, `payments`, `refunds`, `discounts`, `scholarships`)
///    are write-cache + queue support until pull is enabled.
///  * **WRITES go to Drift + a `sync_queue` row in the SAME transaction**
///    via [SyncEngine.writeLocalRow] / [SyncEngine.softDeleteLocalRow] +
///    [SyncQueue.enqueue], then opportunistically trigger
///    [SyncEngine.syncNow]. Direct Supabase writes are FORBIDDEN — the
///    sync engine is the only writer to the server (via the `sync_apply`
///    RPC).
///  * Multi-step flows mirror the server sequence as separate local+queue
///    ops (FIFO per entity preserves order; server triggers fire
///    identically when the ops land).
///  * Posted financial rows converge via sync; server-computed fields
///    (receipt_number, invoice totals, ledger auto-entries, allocations)
///    only appear AFTER the row syncs — the local model returned by a
///    write reflects what was stored locally, not the server's computed
///    values.
///  * New rows use client-generated UUIDs ([Uuid.v4]) — the server ids
///    are UUID type and the RPC requires valid UUID or empty.
///
/// Public method signatures are IDENTICAL to the previous Supabase
/// implementation.

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart';
import '../../core/notifications/notification_triggers.dart';
import '../../core/sync/sync_engine.dart';
import '../models/finance.dart';
import '../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────
// Interface (unchanged)
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

  /// Full flow: insert draft → post. Returns the LOCAL posted payment —
  /// `receipt_number` is filled by the DB trigger and only appears after
  /// the row syncs (see the doc comment at the top of this file).
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
// Local-first implementation
// ─────────────────────────────────────────────

class LocalFinanceRepository implements IFinanceRepository {
  LocalFinanceRepository(this._db, this._engine);

  final AppDatabase _db;

  /// Null when logged out / no active tenant — writes still enqueue
  /// locally and sync later; the opportunistic trigger is skipped.
  final SyncEngine? _engine;

  /// Reads stay on the server until pull is enabled (see file doc).
  SupabaseClient get _client => SupabaseService.client;

  String get _nowIso => DateTime.now().toUtc().toIso8601String();

  String _newId() => const Uuid().v4();

  /// Indexed envelope columns per finance table (matches the sibling's
  /// Drift schema; everything not listed keeps an empty map).
  Map<String, Object?> _indexedFor(
      String table, Map<String, dynamic> row) {
    switch (table) {
      case 'accounts':
        return {'code': row['code']};
      case 'discounts':
      case 'invoice_items':
        return {'invoice_id': row['invoice_id']};
      case 'scholarships':
        return {'student_id': row['student_id']};
      default:
        return const {};
    }
  }

  void _notify() {
    _engine?.notifyLocalChange();
    unawaited(_engine?.syncNow() ?? Future.value());
  }

  /// Generic create/update: envelope upsert + queue row in ONE transaction,
  /// returns the LOCAL model (server converges on sync).
  Future<T> _save<T>({
    required String table,
    required String id,
    required String tenantId,
    required Map<String, dynamic> data,
    required T Function(Map<String, dynamic>) fromData,
  }) async {
    final exists = await SyncQueue.rowExists(_db, table, tenantId, id);
    final baseRev =
        await SyncQueue.currentRevision(_db, table, tenantId, id);
    final nowIso = _nowIso;
    final row = <String, dynamic>{
      ...data,
      'id': id,
      'tenant_id': tenantId,
    };
    await _db.transaction(() async {
      await SyncEngine.writeLocalRow(
        _db,
        table: table,
        id: id,
        tenantId: tenantId,
        indexed: _indexedFor(table, row),
        data: row,
      );
      await SyncQueue.enqueue(
        _db,
        tenantId: tenantId,
        entity: table,
        entityId: id,
        operation: exists ? 'update' : 'create',
        payload: {...row, 'updated_at': nowIso},
        baseRevision: baseRev,
      );
    });
    _notify();
    return fromData(row);
  }

  /// Status transition on a document table: merge {'status': to, ...?extra}
  /// into the existing local row's data and enqueue the update. When no
  /// local row exists, the update still enqueues with a minimal payload
  /// (baseRevision 0) so the server converges.
  Future<Map<String, dynamic>> _transition({
    required String table,
    required String id,
    required String tenantId,
    required String to,
    Map<String, dynamic>? extra,
  }) async {
    final nowIso = _nowIso;
    final existing = await LocalRows.byId(_db, table, tenantId, id);
    final previous =
        (existing?['_data'] as Map<String, dynamic>?) ?? const {};
    final row = <String, dynamic>{
      ...previous,
      ...?extra,
      'id': id,
      'tenant_id': tenantId,
      'status': to,
    };
    final baseRev = existing == null
        ? 0
        : (existing['server_revision'] as num?)?.toInt() ?? 0;
    await _db.transaction(() async {
      await SyncEngine.writeLocalRow(
        _db,
        table: table,
        id: id,
        tenantId: tenantId,
        indexed: _indexedFor(table, row),
        data: row,
      );
      await SyncQueue.enqueue(
        _db,
        tenantId: tenantId,
        entity: table,
        entityId: id,
        operation: 'update',
        payload: {...row, 'updated_at': nowIso},
        baseRevision: baseRev,
      );
    });
    _notify();
    return row;
  }

  /// Soft-delete a draft document locally + enqueue the delete.
  Future<void> _deleteDraft({
    required String table,
    required String id,
    required String tenantId,
  }) async {
    final nowIso = _nowIso;
    final baseRev =
        await SyncQueue.currentRevision(_db, table, tenantId, id);
    await _db.transaction(() async {
      await SyncEngine.softDeleteLocalRow(
        _db,
        table: table,
        id: id,
        tenantId: tenantId,
      );
      await SyncQueue.enqueue(
        _db,
        tenantId: tenantId,
        entity: table,
        entityId: id,
        operation: 'delete',
        payload: {'id': id, 'tenant_id': tenantId, 'updated_at': nowIso},
        baseRevision: baseRev,
      );
    });
    _notify();
  }

  // ── accounts (reads: remote) ──

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
    return _save<Account>(
      table: 'accounts',
      id: _newId(),
      tenantId: tenantId,
      data: a.toJson(),
      fromData: Account.fromJson,
    );
  }

  @override
  Future<Account> updateAccount(Account a,
      {required String tenantId}) async {
    return _save<Account>(
      table: 'accounts',
      id: a.id!,
      tenantId: tenantId,
      data: a.toJson(),
      fromData: Account.fromJson,
    );
  }

  @override
  Future<void> deleteAccount(String id, {required String tenantId}) =>
      _deleteDraft(table: 'accounts', id: id, tenantId: tenantId);

  // ── ledger (reads: remote) ──

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
    return _save<LedgerTransaction>(
      table: 'transactions',
      id: _newId(),
      tenantId: tenantId,
      data: {...e.toJson(), 'status': DocStatus.draft.dbValue},
      fromData: LedgerTransaction.fromJson,
    );
  }

  @override
  Future<LedgerTransaction> postLedgerEntry(String id,
      {required String tenantId}) async {
    final row = await _transition(
      table: 'transactions',
      id: id,
      tenantId: tenantId,
      to: DocStatus.posted.dbValue,
    );
    return LedgerTransaction.fromJson(row);
  }

  @override
  Future<void> deleteLedgerDraft(String id,
      {required String tenantId}) async {
    await _deleteDraft(table: 'transactions', id: id, tenantId: tenantId);
  }

  // ── income (reads: remote) ──

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
    return _save<IncomeEntry>(
      table: 'income',
      id: _newId(),
      tenantId: tenantId,
      data: {...e.toJson(), 'status': DocStatus.draft.dbValue},
      fromData: IncomeEntry.fromJson,
    );
  }

  @override
  Future<IncomeEntry> transitionIncome(String id, DocStatus to,
      {required String tenantId, String? actorId}) async {
    final extra = to == DocStatus.approved && actorId != null
        ? {'approved_by': actorId}
        : null;
    final row = await _transition(
      table: 'income',
      id: id,
      tenantId: tenantId,
      to: to.dbValue,
      extra: extra,
    );
    return IncomeEntry.fromJson(row);
  }

  @override
  Future<IncomeEntry> recordIncome(IncomeEntry e,
      {required String tenantId, required String actorId}) async {
    // Mirror the server sequence as separate local+queue ops (FIFO per
    // entity preserves order; server triggers fire identically on sync).
    var row = await createIncome(e, tenantId: tenantId);
    row = await transitionIncome(row.id!, DocStatus.approved,
        tenantId: tenantId, actorId: actorId);
    row = await transitionIncome(row.id!, DocStatus.posted,
        tenantId: tenantId);
    return row;
  }

  // ── expenses (reads: remote) ──

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
    return _save<ExpenseEntry>(
      table: 'expenses',
      id: _newId(),
      tenantId: tenantId,
      data: {...e.toJson(), 'status': DocStatus.draft.dbValue},
      fromData: ExpenseEntry.fromJson,
    );
  }

  @override
  Future<ExpenseEntry> transitionExpense(String id, DocStatus to,
      {required String tenantId, String? actorId}) async {
    final extra = to == DocStatus.approved && actorId != null
        ? {'approved_by': actorId}
        : null;
    final row = await _transition(
      table: 'expenses',
      id: id,
      tenantId: tenantId,
      to: to.dbValue,
      extra: extra,
    );
    return ExpenseEntry.fromJson(row);
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

  // ── invoices (reads: remote) ──

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
    // 1. invoice header (client-generated UUID — the RPC requires valid
    //    UUID or empty; totals recompute server-side via triggers).
    final invoiceId = _newId();
    final invoice = await _save<Invoice>(
      table: 'invoices',
      id: invoiceId,
      tenantId: tenantId,
      data: {
        ...inv.toJson(),
        'status': InvoiceStatus.draft.dbValue,
      },
      fromData: Invoice.fromJson,
    );
    // 2. line items, each its own local+queue op (FIFO per entity keeps
    //    header-before-items order on the wire).
    for (final item in items) {
      await _save<InvoiceItem>(
        table: 'invoice_items',
        id: _newId(),
        tenantId: tenantId,
        data: {
          ...item.toJson(),
          'invoice_id': invoiceId,
        },
        fromData: InvoiceItem.fromJson,
      );
    }
    // Local-first notification — best-effort: a notification failure must
    // never fail the financial write.
    try {
      await NotificationTriggers.onFeeInvoiceCreated(
        _db,
        tenantId: tenantId,
        invoiceId: invoiceId,
        studentId: inv.studentId,
        amount: invoice.total,
      );
    } catch (_) {}
    return invoice;
  }

  @override
  Future<Invoice> transitionInvoice(String id, InvoiceStatus to,
      {required String tenantId}) async {
    final row = await _transition(
      table: 'invoices',
      id: id,
      tenantId: tenantId,
      to: to.dbValue,
    );
    return Invoice.fromJson(row);
  }

  @override
  Future<void> deleteInvoiceDraft(String id,
      {required String tenantId}) async {
    await _deleteDraft(table: 'invoices', id: id, tenantId: tenantId);
  }

  // ── payments (reads: remote) ──

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
    // 1. insert draft locally + enqueue. receipt_number arrives from the
    //    DB trigger on sync — it is NOT in the local model returned here.
    final row = await _save<Payment>(
      table: 'payments',
      id: _newId(),
      tenantId: tenantId,
      data: {...p.toJson(), 'status': DocStatus.draft.dbValue},
      fromData: Payment.fromJson,
    );
    // 2. post locally + enqueue → when this op lands, the server trigger
    //    creates the ledger entry + allocation + invoice update, exactly
    //    as in the old direct-write flow.
    final posted = await _transition(
      table: 'payments',
      id: row.id!,
      tenantId: tenantId,
      to: DocStatus.posted.dbValue,
    );
    // Local-first notification — best-effort: a notification failure must
    // never fail the financial write.
    try {
      await NotificationTriggers.onPaymentReceived(
        _db,
        tenantId: tenantId,
        paymentId: row.id!,
        invoiceId: p.invoiceId,
        studentId: p.studentId ?? '',
        studentName: p.studentName,
        amount: p.amount,
      );
    } catch (_) {}
    return Payment.fromJson(posted);
  }

  @override
  Future<void> deletePaymentDraft(String id,
      {required String tenantId}) async {
    await _deleteDraft(table: 'payments', id: id, tenantId: tenantId);
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

  // ── refunds (reads: remote) ──

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
    return _save<Refund>(
      table: 'refunds',
      id: _newId(),
      tenantId: tenantId,
      data: {...r.toJson(), 'status': DocStatus.draft.dbValue},
      fromData: Refund.fromJson,
    );
  }

  @override
  Future<Refund> transitionRefund(String id, DocStatus to,
      {required String tenantId, String? actorId}) async {
    final extra = to == DocStatus.approved && actorId != null
        ? {'approved_by': actorId}
        : null;
    final row = await _transition(
      table: 'refunds',
      id: id,
      tenantId: tenantId,
      to: to.dbValue,
      extra: extra,
    );
    return Refund.fromJson(row);
  }

  @override
  Future<void> deleteRefundDraft(String id,
      {required String tenantId}) async {
    await _deleteDraft(table: 'refunds', id: id, tenantId: tenantId);
  }

  // ── discounts (reads: remote) ──

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
    return _save<Discount>(
      table: 'discounts',
      id: _newId(),
      tenantId: tenantId,
      data: {...d.toJson(), 'status': DiscountStatus.draft.dbValue},
      fromData: Discount.fromJson,
    );
  }

  @override
  Future<Discount> applyDiscount(String id,
      {required String tenantId}) async {
    final row = await _transition(
      table: 'discounts',
      id: id,
      tenantId: tenantId,
      to: DiscountStatus.applied.dbValue,
    );
    return Discount.fromJson(row);
  }

  @override
  Future<void> deleteDiscountDraft(String id,
      {required String tenantId}) async {
    await _deleteDraft(table: 'discounts', id: id, tenantId: tenantId);
  }

  // ── scholarships (reads: remote) ──

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
    return _save<Scholarship>(
      table: 'scholarships',
      id: _newId(),
      tenantId: tenantId,
      data: s.toJson(),
      fromData: Scholarship.fromJson,
    );
  }

  @override
  Future<Scholarship> updateScholarship(Scholarship s,
      {required String tenantId}) async {
    return _save<Scholarship>(
      table: 'scholarships',
      id: s.id!,
      tenantId: tenantId,
      data: s.toJson(),
      fromData: Scholarship.fromJson,
    );
  }

  // ── fee structures (reads: remote; no local write path in this phase) ──

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
