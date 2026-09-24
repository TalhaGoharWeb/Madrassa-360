/// اعلانات فراہم کنندہ
/// Announcement Provider

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/supabase_service.dart';
import '../data/models/announcement.dart';

class AnnouncementState {
  final List<Announcement> announcements;
  final bool isLoading;
  final String? error;

  const AnnouncementState({
    this.announcements = const [],
    this.isLoading = false,
    this.error,
  });

  AnnouncementState copyWith({
    List<Announcement>? announcements,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) => AnnouncementState(
    announcements: announcements ?? this.announcements,
    isLoading:     isLoading     ?? this.isLoading,
    error:         clearError ? null : (error ?? this.error),
  );
}

class AnnouncementNotifier extends StateNotifier<AnnouncementState> {
  AnnouncementNotifier() : super(const AnnouncementState());
  final _client = SupabaseService.client;

  Future<void> load({String? madrasaId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var q = _client.from('announcements').select();
      if (madrasaId != null) q = q.eq('madrasa_id', madrasaId) as dynamic;
      final rows = await q.order('created_at', ascending: false);
      state = state.copyWith(
        isLoading: false,
        announcements: rows.map<Announcement>((r) => Announcement.fromJson(r)).toList(),
      );
    } on PostgrestException {
      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<String?> create(Announcement a) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _client.from('announcements').insert(a.toJson()).select().single();
      state = state.copyWith(
        isLoading: false,
        announcements: [Announcement.fromJson(data), ...state.announcements],
      );
      return null;
    } catch (_) {
      final opt = Announcement(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: a.title, body: a.body, target: a.target,
        isPinned: a.isPinned, madrasaId: a.madrasaId,
        postedByName: a.postedByName,
        createdAt: DateTime.now(),
      );
      state = state.copyWith(
        isLoading: false,
        announcements: [opt, ...state.announcements],
      );
      return null;
    }
  }

  Future<void> delete(String id) async {
    try { await _client.from('announcements').delete().eq('id', id); } catch (_) {}
    state = state.copyWith(
      announcements: state.announcements.where((a) => a.id != id).toList());
  }

  Future<void> togglePin(Announcement a) async {
    final updated = a.copyWith(isPinned: !a.isPinned);
    try {
      await _client.from('announcements')
          .update({'is_pinned': updated.isPinned}).eq('id', a.id!);
    } catch (_) {}
    state = state.copyWith(
      announcements: state.announcements
          .map((x) => x.id == a.id ? updated : x).toList(),
    );
  }
}

final announcementProvider =
    StateNotifierProvider<AnnouncementNotifier, AnnouncementState>(
        (_) => AnnouncementNotifier());

final announcementListProvider = Provider<List<Announcement>>(
    (ref) => ref.watch(announcementProvider).announcements);
