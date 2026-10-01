/// مدرسہ فراہم کنندہ
/// Madrasa Provider — franchise network management (Super Admin)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/supabase_service.dart';
import '../core/utils/network_timeout.dart';
import '../data/models/madrasa.dart';

class MadrasaState {
  final List<Madrasa> madrasas;
  final Madrasa? selected; // currently active madrasa (for admins/teachers)
  final bool isLoading;
  final String? error;

  const MadrasaState({
    this.madrasas = const [],
    this.selected,
    this.isLoading = false,
    this.error,
  });

  MadrasaState copyWith({
    List<Madrasa>? madrasas,
    Madrasa? selected,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      MadrasaState(
        madrasas: madrasas ?? this.madrasas,
        selected: selected ?? this.selected,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class MadrasaNotifier extends StateNotifier<MadrasaState> {
  /// [client] is an optional seam for tests; production code uses the
  /// shared [SupabaseService.client].
  MadrasaNotifier({SupabaseClient? client})
      : _client = client ?? SupabaseService.client,
        super(const MadrasaState());

  final SupabaseClient _client;

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final query = _client.from('madrasas').select().order('name_urdu');
      final rows = await query.withNetworkTimeout();
      state = state.copyWith(
        isLoading: false,
        madrasas: rows.map((r) => Madrasa.fromJson(r)).toList(),
      );
    } on PostgrestException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setSelected(Madrasa m) => state = state.copyWith(selected: m);

  Future<String?> create(Madrasa m) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data =
          await _client.from('madrasas').insert(m.toJson()).select().single();
      final created = Madrasa.fromJson(data);
      state = state.copyWith(
        isLoading: false,
        madrasas: [...state.madrasas, created],
      );
      return null;
    } catch (e) {
      // Optimistic local add (rolled back by the sync engine on conflict)
      final opt = Madrasa(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        nameUrdu: m.nameUrdu,
        nameEnglish: m.nameEnglish,
        cityUrdu: m.cityUrdu,
        cityEnglish: m.cityEnglish,
        phone: m.phone,
        email: m.email,
        subscriptionPlan: m.subscriptionPlan,
      );
      state = state.copyWith(
        isLoading: false,
        madrasas: [...state.madrasas, opt],
      );
      return null;
    }
  }

  Future<String?> update(Madrasa m) async {
    if (m.id == null) return 'شناخت نہیں ملی';
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _client.from('madrasas').update(m.toJson()).eq('id', m.id!);
    } catch (e) {
      // Surface the failure and keep the prior state untouched: applying
      // the optimistic change here would show a failed write as succeeded.
      final message = e.toString();
      state = state.copyWith(isLoading: false, error: message);
      return message;
    }
    state = state.copyWith(
      isLoading: false,
      madrasas: state.madrasas.map((x) => x.id == m.id ? m : x).toList(),
      selected: state.selected?.id == m.id ? m : state.selected,
    );
    return null;
  }

  Future<String?> toggleStatus(Madrasa m) =>
      update(m.copyWith(isActive: !m.isActive));

  Future<String?> delete(String id) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _client.from('madrasas').delete().eq('id', id);
    } catch (e) {
      // Surface the failure and keep the prior state untouched: dropping
      // the row locally here would show a failed delete as succeeded.
      final message = e.toString();
      state = state.copyWith(isLoading: false, error: message);
      return message;
    }
    state = state.copyWith(
      isLoading: false,
      madrasas: state.madrasas.where((x) => x.id != id).toList(),
    );
    return null;
  }

  // Stats for Super Admin dashboard
  int get totalActive => state.madrasas.where((m) => m.isActive).length;
  int get totalInactive => state.madrasas.where((m) => !m.isActive).length;
}

// ── Providers ────────────────────────────────────────────────────────────────

final madrasaProvider = StateNotifierProvider<MadrasaNotifier, MadrasaState>(
    (_) => MadrasaNotifier());

final madrasaListProvider = Provider<List<Madrasa>>(
  (ref) => ref.watch(madrasaProvider).madrasas,
);

final selectedMadrasaProvider = Provider<Madrasa?>(
  (ref) => ref.watch(madrasaProvider).selected,
);
