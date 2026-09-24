/// درجہ فراہم کنندہ
/// Darja Provider — class/level management

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/supabase_service.dart';
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
  DarjaNotifier() : super(const DarjaState());
  final _client = SupabaseService.client;

  Future<void> loadAll({String? madrasaId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var q = _client.from('darjas').select();
      if (madrasaId != null) q = q.eq('madrasa_id', madrasaId) as dynamic;
      final rows = await q.order('order_index');
      final darjas = rows.map<Darja>((r) => Darja.fromJson(r)).toList();

      var sq = _client.from('darja_sections').select();
      if (madrasaId != null) sq = sq.eq('madrasa_id', madrasaId) as dynamic;
      final srows = await sq.order('name_urdu');
      final sections = srows.map<DarjaSection>((r) => DarjaSection.fromJson(r)).toList();

      state = state.copyWith(
        isLoading: false, darjas: darjas, sections: sections);
    } on PostgrestException {
      state = state.copyWith(isLoading: false);
    } catch (_) {
      // seed defaults when table doesn't exist yet
      state = state.copyWith(isLoading: false, darjas: _defaults());
    }
  }

  List<Darja> _defaults() => [
    const Darja(nameUrdu: 'ناظرہ', nameEnglish: 'Nazra', level: 'nazra', orderIndex: 1),
    const Darja(nameUrdu: 'حفظ', nameEnglish: 'Hifz', level: 'hifz', orderIndex: 2),
    const Darja(nameUrdu: 'درجہ اول', nameEnglish: 'Class 1', level: 'dars_e_nizami', orderIndex: 3),
    const Darja(nameUrdu: 'درجہ دوم', nameEnglish: 'Class 2', level: 'dars_e_nizami', orderIndex: 4),
    const Darja(nameUrdu: 'درجہ سوم', nameEnglish: 'Class 3', level: 'dars_e_nizami', orderIndex: 5),
    const Darja(nameUrdu: 'درجہ چہارم', nameEnglish: 'Class 4', level: 'dars_e_nizami', orderIndex: 6),
    const Darja(nameUrdu: 'درجہ پنجم', nameEnglish: 'Class 5', level: 'dars_e_nizami', orderIndex: 7),
    const Darja(nameUrdu: 'تخصص', nameEnglish: 'Takhassus', level: 'takhassus', orderIndex: 8),
  ];

  Future<String?> createDarja(Darja d) async {
    try {
      final data = await _client.from('darjas').insert(d.toJson()).select().single();
      state = state.copyWith(
          darjas: [...state.darjas, Darja.fromJson(data)]);
      return null;
    } catch (_) {
      final opt = Darja(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
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
    try {
      final data = await _client.from('darja_sections').insert(s.toJson()).select().single();
      state = state.copyWith(sections: [...state.sections, DarjaSection.fromJson(data)]);
      return null;
    } catch (_) {
      final opt = DarjaSection(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
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
    StateNotifierProvider<DarjaNotifier, DarjaState>((_) => DarjaNotifier());

final darjaListProvider = Provider<List<Darja>>(
    (ref) => ref.watch(darjaProvider).darjas);
