/// درجہ فراہم کنندہ
/// Darja Provider — class/level management

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';
import '../data/models/darja.dart';

class DarjaState {
  final List<Darja> darjas;
  final List<DarjaSection> sections;
  final bool isLoading;
  final String? error;

  const DarjaState({
    this.darjas = const [],
    this.sections = const [],
    this.isLoading = false,
    this.error,
  });

  DarjaState copyWith({
    List<Darja>? darjas,
    List<DarjaSection>? sections,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) => DarjaState(
    darjas:    darjas    ?? this.darjas,
    sections:  sections  ?? this.sections,
    isLoading: isLoading ?? this.isLoading,
    error:     clearError ? null : (error ?? this.error),
  );
}

class DarjaNotifier extends StateNotifier<DarjaState> {
  DarjaNotifier(this._ref) : super(const DarjaState());
  final Ref _ref;
  final _client = SupabaseService.client;

  /// [madrasaId] is DEPRECATED (kept for signature compatibility; Phase 8
  /// removes it). Tenant scoping is mandatory via [currentTenantIdProvider].
  Future<void> loadAll({String? madrasaId}) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      state = state.copyWith(isLoading: false, darjas: const [], sections: const []);
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final q = _client.from('darjas').select().eq('tenant_id', tenantId) as dynamic;
      final rows = await q.order('order_index');
      final darjas = rows.map<Darja>((r) => Darja.fromJson(r)).toList();

      final sq = _client.from('darja_sections').select().eq('tenant_id', tenantId) as dynamic;
      final srows = await sq.order('name_urdu');
      final sections = srows.map<DarjaSection>((r) => DarjaSection.fromJson(r)).toList();

      state = state.copyWith(
        isLoading: false, darjas: darjas, sections: sections);
    } on PostgrestException {
      state = state.copyWith(isLoading: false);
    } catch (_) {
      // seed defaults when table doesn't exist yet
      state = state.copyWith(isLoading: false, darjas: _defaults(tenantId));
    }
  }

  List<Darja> _defaults(String tenantId) => [
    Darja(tenantId: tenantId, nameUrdu: 'ناظرہ', nameEnglish: 'Nazra', level: 'nazra', orderIndex: 1),
    Darja(tenantId: tenantId, nameUrdu: 'حفظ', nameEnglish: 'Hifz', level: 'hifz', orderIndex: 2),
    Darja(tenantId: tenantId, nameUrdu: 'درجہ اول', nameEnglish: 'Class 1', level: 'dars_e_nizami', orderIndex: 3),
    Darja(tenantId: tenantId, nameUrdu: 'درجہ دوم', nameEnglish: 'Class 2', level: 'dars_e_nizami', orderIndex: 4),
    Darja(tenantId: tenantId, nameUrdu: 'درجہ سوم', nameEnglish: 'Class 3', level: 'dars_e_nizami', orderIndex: 5),
    Darja(tenantId: tenantId, nameUrdu: 'درجہ چہارم', nameEnglish: 'Class 4', level: 'dars_e_nizami', orderIndex: 6),
    Darja(tenantId: tenantId, nameUrdu: 'درجہ پنجم', nameEnglish: 'Class 5', level: 'dars_e_nizami', orderIndex: 7),
    Darja(tenantId: tenantId, nameUrdu: 'تخصص', nameEnglish: 'Takhassus', level: 'takhassus', orderIndex: 8),
  ];

  Future<String?> createDarja(Darja d) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) return 'No active tenant';
    try {
      final payload = <String, dynamic>{...d.toJson(), 'tenant_id': tenantId};
      final data = await _client.from('darjas').insert(payload).select().single();
      state = state.copyWith(
          darjas: [...state.darjas, Darja.fromJson(data)]);
      return null;
    } catch (_) {
      final opt = Darja(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        tenantId: tenantId,
        nameUrdu: d.nameUrdu, nameEnglish: d.nameEnglish,
        level: d.level, orderIndex: d.orderIndex,
      );
      state = state.copyWith(darjas: [...state.darjas, opt]);
      return null;
    }
  }

  Future<String?> updateDarja(Darja d) async {
    if (d.id == null) return null;
    try {
      await _client.from('darjas').update(d.toJson()).eq('id', d.id!);
    } catch (_) {}
    state = state.copyWith(
        darjas: state.darjas.map((x) => x.id == d.id ? d : x).toList());
    return null;
  }

  Future<void> deleteDarja(String id) async {
    try { await _client.from('darjas').delete().eq('id', id); } catch (_) {}
    state = state.copyWith(
        darjas: state.darjas.where((d) => d.id != id).toList());
  }

  Future<String?> createSection(DarjaSection s) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) return 'No active tenant';
    try {
      final payload = <String, dynamic>{...s.toJson(), 'tenant_id': tenantId};
      final data = await _client.from('darja_sections').insert(payload).select().single();
      state = state.copyWith(sections: [...state.sections, DarjaSection.fromJson(data)]);
      return null;
    } catch (_) {
      final opt = DarjaSection(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        tenantId: tenantId,
        darjaId: s.darjaId, nameUrdu: s.nameUrdu,
      );
      state = state.copyWith(sections: [...state.sections, opt]);
      return null;
    }
  }

  Future<void> deleteSection(String id) async {
    try { await _client.from('darja_sections').delete().eq('id', id); } catch (_) {}
    state = state.copyWith(
        sections: state.sections.where((s) => s.id != id).toList());
  }

  List<DarjaSection> sectionsForDarja(String darjaId) =>
      state.sections.where((s) => s.darjaId == darjaId).toList();
}

final darjaProvider =
    StateNotifierProvider<DarjaNotifier, DarjaState>((ref) => DarjaNotifier(ref));

final darjaListProvider = Provider<List<Darja>>(
    (ref) => ref.watch(darjaProvider).darjas);
