/// مالیات فراہم کنندہ — Phase 4 finance rebuild (014_finance.sql)
/// Invoice → payment → receipt → ledger flow. Every query is tenant-scoped
/// via [currentTenantIdProvider]; null (logged out / loading) bails out
/// instead of querying unscoped.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/tenant_context.dart';
import '../data/models/finance.dart';
import '../data/repositories/finance_repository.dart';
import '../core/sync/sync_providers.dart';
import 'auth_provider.dart';

class FinanceState {
  final List<LedgerTransaction> ledger;
  final List<Account> accounts;
  final List<Invoice> invoices;
  final List<Payment> payments;
  final bool isLoading;
  final String? error;

  const FinanceState({
    this.ledger = const [],
    this.accounts = const [],
    this.invoices = const [],
    this.payments = const [],
    this.isLoading = false,
    this.error,
  });

  FinanceState copyWith({
    List<LedgerTransaction>? ledger,
    List<Account>? accounts,
    List<Invoice>? invoices,
    List<Payment>? payments,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearData = false,
  }) =>
      FinanceState(
        ledger: clearData ? const [] : (ledger ?? this.ledger),
        accounts: clearData ? const [] : (accounts ?? this.accounts),
        invoices: clearData ? const [] : (invoices ?? this.invoices),
        payments: clearData ? const [] : (payments ?? this.payments),
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );

  /// Posted ledger only — drafts are not real money yet.
  Iterable<LedgerTransaction> get _posted =>
      ledger.where((e) => e.status == DocStatus.posted);

  double get totalIncome =>
      _posted.where((e) => e.isIncome).fold(0, (s, e) => s + e.amount);

  double get totalExpense =>
      _posted.where((e) => !e.isIncome).fold(0, (s, e) => s + e.amount);

  double get balance => totalIncome - totalExpense;

  List<LedgerTransaction> byKind(LedgerKind kind) =>
      ledger.where((e) => e.kind == kind).toList();
}

class FinanceNotifier extends StateNotifier<FinanceState> {
  FinanceNotifier(this._ref, [IFinanceRepository? repo])
      : _repo = repo ??
            LocalFinanceRepository(_ref.read(appDatabaseProvider),
                _ref.read(syncEngineProvider)),
        super(const FinanceState());

  final Ref _ref;
  final IFinanceRepository _repo;

  String? get _tenantId => _ref.read(currentTenantIdProvider);
  String? get _actorId => _ref.read(authProvider).user?.id;

  Future<void> load() async {
    final tenantId = _tenantId;
    if (tenantId == null) {
      state = state.copyWith(isLoading: false, clearData: true);
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _repo.getLedger(tenantId: tenantId),
        _repo.getAccounts(tenantId: tenantId),
        _repo.getInvoices(tenantId: tenantId),
        _repo.getPayments(tenantId: tenantId),
      ]);
      state = state.copyWith(
        isLoading: false,
        ledger: results[0] as List<LedgerTransaction>,
        accounts: results[1] as List<Account>,
        invoices: results[2] as List<Invoice>,
        payments: results[3] as List<Payment>,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Records income end-to-end: draft → approved → posted.
  /// Returns an error message, or null on success.
  Future<String?> recordIncome({
    required TransactionCategory sourceType,
    String? donorName,
    required double amount,
    String? accountId,
    String? description,
  }) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No active tenant';
    final actorId = _actorId;
    if (actorId == null) return 'Not signed in';
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repo.recordIncome(
        IncomeEntry(
          tenantId: tenantId,
          sourceType: sourceType,
          donorName: donorName,
          amount: amount,
          accountId: accountId ?? _defaultAccountId(),
          receivedDate: DateTime.now(),
          description: description,
          createdBy: actorId,
        ),
        tenantId: tenantId,
        actorId: actorId,
      );
      await load();
      return null;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return e.toString();
    }
  }

  /// Records an expense end-to-end: draft → approved → posted.
  Future<String?> recordExpense({
    required String category,
    String? recipient,
    required double amount,
    String? accountId,
    String? description,
  }) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No active tenant';
    final actorId = _actorId;
    if (actorId == null) return 'Not signed in';
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repo.recordExpense(
        ExpenseEntry(
          tenantId: tenantId,
          category: category,
          recipient: recipient,
          amount: amount,
          accountId: accountId ?? _defaultAccountId(),
          expenseDate: DateTime.now(),
          description: description,
          createdBy: actorId,
        ),
        tenantId: tenantId,
        actorId: actorId,
      );
      await load();
      return null;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return e.toString();
    }
  }

  /// Records a fee payment: draft → posted. The DB trigger fills the
  /// receipt number and creates the ledger entry + invoice allocation.
  Future<String?> recordPayment({
    String? studentId,
    String? invoiceId,
    String? accountId,
    required double amount,
    PaymentMethod method = PaymentMethod.cash,
    String? notes,
  }) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No active tenant';
    final actorId = _actorId;
    if (actorId == null) return 'Not signed in';
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repo.recordPayment(
        Payment(
          tenantId: tenantId,
          studentId: studentId,
          invoiceId: invoiceId,
          accountId: accountId ?? _defaultAccountId(),
          amount: amount,
          paymentDate: DateTime.now(),
          method: method,
          notes: notes,
          createdBy: actorId,
        ),
        tenantId: tenantId,
      );
      await load();
      return null;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return e.toString();
    }
  }

  /// Deletes a DRAFT ledger line. Posted/void rows are immutable
  /// (DB-enforced) — corrections go through reversal entries.
  Future<String?> deleteLedgerDraft(String id) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No active tenant';
    try {
      await _repo.deleteLedgerDraft(id, tenantId: tenantId);
      state = state.copyWith(
          ledger: state.ledger.where((e) => e.id != id).toList());
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  String? _defaultAccountId() =>
      state.accounts.isNotEmpty ? state.accounts.first.id : null;
}

final financeProvider =
    StateNotifierProvider<FinanceNotifier, FinanceState>(
        (ref) => FinanceNotifier(ref));
