/// اعلانات فراہم کنندہ
/// Announcement Provider — LOCAL-FIRST (Phase 5 offline-first sync).
///
/// `load()` stays REMOTE (Supabase read). All writes (create / delete /
/// togglePin) go to the local Drift envelope table (`announcements`) +
/// a `sync_queue` row in the SAME transaction via
/// [SyncEngine.writeLocalRow] / [SyncEngine.softDeleteLocalRow] +
/// [SyncQueue.enqueue], then opportunistically trigger
/// [SyncEngine.syncNow]. The sync engine is the only writer to the
/// server (via the `sync_apply` RPC).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/sync_providers.dart';
import '../data/models/announcement.dart';
import '../core/notifications/notification_triggers.dart';

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
  AnnouncementNotifier(this._ref) : super(const AnnouncementState());
  final Ref _ref;
  final _client = SupabaseService.client;

  /// [madrasaId] is DEPRECATED (kept for signature compatibility; Phase 8
  /// removes it). Tenant scoping is mandatory via [currentTenantIdProvider].
  Future<void> load({String? madrasaId}) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      state = state.copyWith(isLoading: false, announcements: const []);
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final q = _client.from('announcements').select().eq('tenant_id', tenantId) as dynamic;
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
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) return 'No active tenant';
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final db = _ref.read(appDatabaseProvider);
      final engine = _ref.read(syncEngineProvider);
      final id = a.id ?? const Uuid().v4();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final data = {...a.toJson(), 'id': id, 'tenant_id': tenantId};
      final exists =
          await SyncQueue.rowExists(db, 'announcements', tenantId, id);
      final baseRev = exists
          ? await SyncQueue.currentRevision(
              db, 'announcements', tenantId, id)
          : 0;

      await db.transaction(() async {
        await SyncEngine.writeLocalRow(
          db,
          table: 'announcements',
          id: id,
          tenantId: tenantId,
          indexed: {'title': a.title, 'audience': a.target.name},
          data: data,
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'announcements',
          entityId: id,
          operation: exists ? 'update' : 'create',
          payload: {...data, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      // Local-first notification — best-effort.
      try {
        await NotificationTriggers.onAnnouncementPosted(
          db,
          tenantId: tenantId,
          announcementId: id,
          title: a.title,
          body: a.body,
        );
      } catch (_) {}

      state = state.copyWith(
        isLoading: false,
        announcements: [Announcement.fromJson(data), ...state.announcements],
      );
      return null;
    } catch (e) {
      // Local write is the source of truth — only reach here on a
      // genuine local failure.
      state = state.copyWith(isLoading: false, error: e.toString());
      return e.toString();
    }
  }

  Future<void> delete(String id) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      state = state.copyWith(error: 'No active tenant');
      return;
    }
    try {
      final db = _ref.read(appDatabaseProvider);
      final engine = _ref.read(syncEngineProvider);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final baseRev = await SyncQueue.currentRevision(
          db, 'announcements', tenantId, id);

      await db.transaction(() async {
        await SyncEngine.softDeleteLocalRow(
          db,
          table: 'announcements',
          id: id,
          tenantId: tenantId,
          dataPatch: {'is_active': false},
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'announcements',
          entityId: id,
          operation: 'delete',
          payload: {'id': id, 'tenant_id': tenantId, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      state = state.copyWith(
        announcements:
            state.announcements.where((a) => a.id != id).toList());
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> togglePin(Announcement a) async {
    if (a.id == null) return;
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      state = state.copyWith(error: 'No active tenant');
      return;
    }
    try {
      final db = _ref.read(appDatabaseProvider);
      final engine = _ref.read(syncEngineProvider);
      final id = a.id!;
      final updated = a.copyWith(isPinned: !a.isPinned);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final data = {...updated.toJson(), 'id': id, 'tenant_id': tenantId};
      final baseRev = await SyncQueue.currentRevision(
          db, 'announcements', tenantId, id);

      await db.transaction(() async {
        await SyncEngine.writeLocalRow(
          db,
          table: 'announcements',
          id: id,
          tenantId: tenantId,
          indexed: {'title': updated.title, 'audience': updated.target.name},
          data: data,
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'announcements',
          entityId: id,
          operation: 'update',
          payload: {...data, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      state = state.copyWith(
        announcements: state.announcements
            .map((x) => x.id == id ? updated : x).toList(),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

final announcementProvider =
    StateNotifierProvider<AnnouncementNotifier, AnnouncementState>(
        (ref) => AnnouncementNotifier(ref));

final announcementListProvider = Provider<List<Announcement>>(
    (ref) => ref.watch(announcementProvider).announcements);
