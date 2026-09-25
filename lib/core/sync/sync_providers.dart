/// ─────────────────────────────────────────────────────────────
/// Phase 5 sync wiring — providers that glue the SyncEngine into the app.
///
/// NOTE: no Flutter toolchain is available in this environment, so this
/// file is written carefully but UNCOMPILED. Delimiter balance was checked
/// by script; treat as needing `flutter analyze` before merge.
///
/// Database ownership: [appDatabaseProvider] comes from the sibling's
/// `lib/data/local/database_provider.dart` (worker 2) — `openDatabase()`
/// creates it and `main()` overrides the provider at startup. This file
/// only consumes it.

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database_provider.dart'; // sibling (worker 2): appDatabaseProvider
import '../../core/services/tenant_context.dart'; // real TenantContext API: currentTenantIdProvider (String?, null when logged out)
import 'sync_engine.dart';

/// Re-exported so repository providers can `import 'sync_providers.dart'`
/// and reach both the database and the sync wiring from one place.
export '../../data/local/database_provider.dart';

// ─────────────────────────────────────────────
// Engine lifecycle (recreated on tenant switch)
// ─────────────────────────────────────────────

/// One [SyncEngine] per active tenant. Watching `currentTenantIdProvider`
/// (the real TenantContext API — a Riverpod provider) means the engine is
/// automatically disposed and recreated on tenant switch, so push/pull
/// and conflict review can never touch the wrong tenant's data.
///
/// Null when logged out / no tenant yet — repositories treat a null engine
/// as "enqueue locally, sync later".
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return null;
  final engine = SyncEngine(db: db, tenantId: tenantId);
  engine.start();
  ref.onDispose(engine.dispose);
  return engine;
});

// ─────────────────────────────────────────────
// UI status providers
// ─────────────────────────────────────────────

/// Number of actionable queue rows for the active tenant: pending (incl.
/// failed with a future retry) + in_progress + dead_letter. Dead letters
/// are included deliberately so permanently failed rows surface in the UI
/// badge instead of disappearing silently.
final pendingSyncCountProvider = StreamProvider<int>((ref) async* {
  final db = ref.watch(appDatabaseProvider);
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) {
    yield 0;
    return;
  }

  Future<int> count() async {
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM sync_queue WHERE tenant_id = ? '
          "AND sync_status IN ('pending','in_progress','failed',"
          "'dead_letter')",
          variables: [Variable.withString(tenantId)],
        )
        .get();
    if (rows.isEmpty) return 0;
    return (rows.first.data['n'] as num?)?.toInt() ?? 0;
  }

  // Refresh whenever the engine reports a local change or a cycle ends.
  final engine = ref.watch(syncEngineProvider);
  yield await count();
  final sub = engine?.events.listen((_) async {
    try {
      ref.state = AsyncData(await count());
    } catch (_) {/* provider already disposed */}
  });
  ref.onDispose(sub?.cancel);
});

/// Unresolved sync conflicts for the active tenant (manual review queue).
/// The sibling's `sync_conflicts` table uses `resolved` INT 0/1 (no status
/// column); conflict id is the integer PK.
final syncConflictsProvider =
    StreamProvider<List<SyncConflict>>((ref) async* {
  final db = ref.watch(appDatabaseProvider);
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) {
    yield const [];
    return;
  }

  Future<List<SyncConflict>> load() async {
    final rows = await db
        .customSelect(
          'SELECT * FROM sync_conflicts WHERE tenant_id = ? '
          'AND resolved = 0 ORDER BY created_at DESC',
          variables: [Variable.withString(tenantId)],
        )
        .get();
    return rows.map((r) => SyncConflict.fromRow(r.data)).toList();
  }

  final engine = ref.watch(syncEngineProvider);
  yield await load();
  final sub = engine?.events.listen((_) async {
    try {
      ref.state = AsyncData(await load());
    } catch (_) {/* provider already disposed */}
  });
  ref.onDispose(sub?.cancel);
});

/// When the last successful full sync (push + pull) finished. Emits null
/// until the first completed cycle — suitable for a "Last synced: …"
/// line in a status bar / settings screen.
final lastSyncAtProvider = StreamProvider<DateTime?>((ref) {
  final engine = ref.watch(syncEngineProvider);
  final controller = StreamController<DateTime?>();

  controller.add(engine?.lastSyncValue);
  final sub = engine?.lastSyncAt.listen(
    controller.add,
    onError: controller.addError,
  );
  ref.onDispose(() {
    sub?.cancel();
    controller.close();
  });
  return controller.stream;
});
