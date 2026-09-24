/// مالیات فراہم کنندہ
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/supabase_service.dart';
import '../data/models/finance.dart';

class FinanceState {
  final List<FinanceTransaction> transactions;
  final bool isLoading;
  final String? error;
  const FinanceState({
    this.transactions = const [], this.isLoading = false, this.error,
  });
  FinanceState copyWith({
    List<FinanceTransaction>? transactions,
    bool? isLoading, String? error, bool clearError = false,
  }) => FinanceState(
    transactions: transactions ?? this.transactions,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
  );

  double get totalIncome => transactions
      .where((t) => t.type.isIncome)
      .fold(0, (s, t) => s + t.amount);

  double get totalExpense => transactions
      .where((t) => !t.type.isIncome)
      .fold(0, (s, t) => s + t.amount);

  double get balance => totalIncome - totalExpense;
}

class FinanceNotifier extends StateNotifier<FinanceState> {
  FinanceNotifier() : super(const FinanceState());
  final _c = SupabaseService.client;

  Future<void> load({String? madrasaId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var q = _c.from('finance_transactions').select();
      if (madrasaId != null) q = q.eq('madrasa_id', madrasaId) as dynamic;
      final rows = await q.order('date', ascending: false);
      state = state.copyWith(
        isLoading: false,
        transactions:
            rows.map<FinanceTransaction>((r) => FinanceTransaction.fromJson(r)).toList(),
      );
    } catch (_) { state = state.copyWith(isLoading: false); }
  }

  Future<String?> addTransaction(FinanceTransaction t) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _c.from('finance_transactions').insert(t.toJson()).select().single();
      state = state.copyWith(
        isLoading: false,
        transactions: [FinanceTransaction.fromJson(data), ...state.transactions],
      );
      return null;
    } catch (_) {
      final opt = FinanceTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        madrasaId: t.madrasaId, type: t.type,
        amount: t.amount, description: t.description,
        personName: t.personName, date: t.date,
      );
      state = state.copyWith(
        isLoading: false,
        transactions: [opt, ...state.transactions],
      );
      return null;
    }
  }

  Future<void> deleteTransaction(String id) async {
    try { await _c.from('finance_transactions').delete().eq('id', id); } catch (_) {}
    state = state.copyWith(
      transactions: state.transactions.where((t) => t.id != id).toList());
  }

  List<FinanceTransaction> byType(TransactionType type) =>
      state.transactions.where((t) => t.type == type).toList();
}

final financeProvider =
    StateNotifierProvider<FinanceNotifier, FinanceState>((_) => FinanceNotifier());
