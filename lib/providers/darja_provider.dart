/// درجہ فراہم کنندہ
/// Darja Provider — LOCAL-FIRST (Phase 5 offline-first sync).
///
/// `loadAll()` stays REMOTE (Supabase reads, with the `_defaults`
/// fallback). All writes (createDarja / updateDarja / deleteDarja /
/// createSection / deleteSection) go to the local Drift envelope
/// tables (`darjas`, `darja_sections`) + a `sync_queue` row in the
/// SAME transaction via [SyncEngine.writeLocalRow] /
/// [SyncEngine.softDeleteLocalRow] + [SyncQueue.enqueue], then
/// opportunistically trigger [SyncEngine.syncNow]. The sync engine is
/// the only writer to the server (via the `sync_apply` RPC).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/sync_providers.dart';
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
      final db = _ref.read(appDatabaseProvider);
      final engine = _ref.read(syncEngineProvider);
      final id = d.id ?? const Uuid().v4();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final data = {...d.toJson(), 'id': id, 'tenant_id': tenantId};
      final exists =
          await SyncQueue.rowExists(db, 'darjas', tenantId, id);
      final baseRev = exists
          ? await SyncQueue.currentRevision(db, 'darjas', tenantId, id)
          : 0;

      await db.transaction(() async {
        await SyncEngine.writeLocalRow(
          db,
          table: 'darjas',
          id: id,
          tenantId: tenantId,
          indexed: {
            'name': d.nameEnglish.isNotEmpty ? d.nameEnglish : d.nameUrdu,
          },
          data: data,
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'darjas',
          entityId: id,
          operation: exists ? 'update' : 'create',
          payload: {...data, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      state = state.copyWith(darjas: [...state.darjas, Darja.fromJson(data)]);
      return null;
    } catch (e) {
      // Local write is the source of truth — only reach here on a
      // genuine local failure.
      state = state.copyWith(error: e.toString());
      return e.toString();
    }
  }

  Future<String?> updateDarja(Darja d) async {
    if (d.id == null) return null;
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) return 'No active tenant';
    try {
      final db = _ref.read(appDatabaseProvider);
      final engine = _ref.read(syncEngineProvider);
      final id = d.id!;
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final data = {...d.toJson(), 'id': id, 'tenant_id': tenantId};
      final baseRev =
          await SyncQueue.currentRevision(db, 'darjas', tenantId, id);

      await db.transaction(() async {
        await SyncEngine.writeLocalRow(
          db,
          table: 'darjas',
          id: id,
          tenantId: tenantId,
          indexed: {
            'name': d.nameEnglish.isNotEmpty ? d.nameEnglish : d.nameUrdu,
          },
          data: data,
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'darjas',
          entityId: id,
          operation: 'update',
          payload: {...data, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      state = state.copyWith(
          darjas: state.darjas.map((x) => x.id == id ? Darja.fromJson(data) : x).toList());
      return null;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return e.toString();
    }
  }

  Future<void> deleteDarja(String id) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      state = state.copyWith(error: 'No active tenant');
      return;
    }
    try {
      final db = _ref.read(appDatabaseProvider);
      final engine = _ref.read(syncEngineProvider);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final baseRev =
          await SyncQueue.currentRevision(db, 'darjas', tenantId, id);

      await db.transaction(() async {
        await SyncEngine.softDeleteLocalRow(
          db,
          table: 'darjas',
          id: id,
          tenantId: tenantId,
          dataPatch: {'is_active': false},
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'darjas',
          entityId: id,
          operation: 'delete',
          payload: {'id': id, 'tenant_id': tenantId, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      state = state.copyWith(
          darjas: state.darjas.where((d) => d.id != id).toList());
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<String?> createSection(DarjaSection s) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) return 'No active tenant';
    try {
      final db = _ref.read(appDatabaseProvider);
      final engine = _ref.read(syncEngineProvider);
      final id = s.id ?? const Uuid().v4();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final data = {...s.toJson(), 'id': id, 'tenant_id': tenantId};
      final exists =
          await SyncQueue.rowExists(db, 'darja_sections', tenantId, id);
      final baseRev = exists
          ? await SyncQueue.currentRevision(
              db, 'darja_sections', tenantId, id)
          : 0;

      await db.transaction(() async {
        await SyncEngine.writeLocalRow(
          db,
          table: 'darja_sections',
          id: id,
          tenantId: tenantId,
          indexed: {'darja_id': s.darjaId},
          data: data,
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'darja_sections',
          entityId: id,
          operation: exists ? 'update' : 'create',
          payload: {...data, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      state = state.copyWith(
          sections: [...state.sections, DarjaSection.fromJson(data)]);
      return null;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return e.toString();
    }
  }

  Future<void> deleteSection(String id) async {
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
          db, 'darja_sections', tenantId, id);

      await db.transaction(() async {
        await SyncEngine.softDeleteLocalRow(
          db,
          table: 'darja_sections',
          id: id,
          tenantId: tenantId,
          dataPatch: {'is_active': false},
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'darja_sections',
          entityId: id,
          operation: 'delete',
          payload: {'id': id, 'tenant_id': tenantId, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      state = state.copyWith(
          sections: state.sections.where((s) => s.id != id).toList());
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  List<DarjaSection> sectionsForDarja(String darjaId) =>
      state.sections.where((s) => s.darjaId == darjaId).toList();
}

final darjaProvider =
    StateNotifierProvider<DarjaNotifier, DarjaState>((ref) => DarjaNotifier(ref));

final darjaListProvider = Provider<List<Darja>>(
    (ref) => ref.watch(darjaProvider).darjas);
