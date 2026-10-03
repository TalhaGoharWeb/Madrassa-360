# Performance Audit — Madrassa-360 (production)

**Scope:** `~/workspace/madrassa-redesign-fix`, branch `redesign/ux-v2`, Flutter 3.47.4,
offline-first (Drift/SQLite + `sync_apply` RPC sync engine), targets Android + Windows.
**Method:** read-only static analysis with measured artifact data (APK contents, font glyph
counts). No code modified. All proposed optimizations preserve business behavior.

**Reference device for impact estimates:** low-end Android (2-3 GB RAM, 3G/4G, 300-600 ms RTT).

---

## Ranked findings

### HIGH

#### H-P1 — Sync push is strictly sequential: one HTTPS round-trip per row
- **Location:** `lib/core/sync/sync_engine.dart:710-724` (`pushOnce`), `802-846` (`_pushRow`),
  `848-870` (`_callSyncApply`); claim batch `_claimBatchSize = 25` (line 238).
- **Problem:** Every queued row is pushed with its own `sync_apply` RPC, awaited one at a time.
  Marking attendance for a 60-student class = 60 sequential HTTPS round-trips, plus a
  `Connectivity().checkConnectivity()` platform-channel call per row (line 716).
- **Why it matters:** At 300-600 ms RTT, one attendance save costs 20-60 s of radio time.
  On flaky networks the batch rarely completes; rows sit `in_progress` until the 10-minute
  lease expires; battery and mobile data drain is severe.
- **Symptom:** "Sync never finishes" after attendance/fee entry on slow networks.
- **Fix:** Add a batch RPC (`sync_apply_batch(jsonb[])`) applying N rows in one server
  transaction, or push with bounded concurrency (4-6 in flight) preserving per-entity FIFO.
  Check connectivity once per batch, not per row.

#### H-P2 — Full sync cycle fires on every connectivity flap and every app resume
- **Location:** `lib/core/sync/sync_engine.dart:625-642` (connectivity listener),
  `644-648` (`notifyAppResumed`), `685-708` (`syncNow`), `1307-1330` (`pullOnce`).
- **Problem:** Any connectivity change to online triggers `syncNow()` = push + pull of
  9 entities x 2 passes (live + tombstones) = 18+ sequential HTTPS requests minimum, each
  `.select()`ing all columns, even when nothing changed. Mobile networks flap
  (WiFi/cell handoffs), so this can fire repeatedly within minutes.
- **Why it matters:** ~18 round-trips of pure overhead per flap on a quiet database;
  seconds of radio time and battery each; server load scales with device count, not data.
- **Symptom:** Battery drain, constant "syncing" indicator, UI sluggishness on resume.
- **Fix:** Debounce connectivity-triggered syncs (ignore re-triggers within 60-120 s of a
  completed cycle); add a cheap "max server_version per tenant" probe to skip pull passes
  with no changes; back off after consecutive empty cycles.

#### H-P3 — Student list re-aggregates ALL fees inside `build()` on every keystroke
- **Location:** `lib/presentation/screens/admin/student_list_screen.dart:183-184`
  (`_feeStatusByStudent(ref)` in `build()`), `:461-471` (O(fees) Dart loop),
  `:98` (search `onChanged: (_) => setState(() {})`).
- **Problem:** Every rebuild — including each search keystroke — iterates the entire fee
  table in Dart on the UI thread to derive per-student fee status, then re-filters students.
- **Why it matters:** O(fees + students) UI-thread work per keystroke; input lag grows
  linearly with tenant history and never gets faster.
- **Symptom:** Search field stutters as the fee book grows.
- **Fix:** Memoize into a derived provider (e.g. `feeStatusByStudentProvider` watching
  `allFeesProvider`) so it recomputes only when fee data changes.

#### H-P4 — APK is 107 MB: 3 ABIs shipped + 37 MB of un-subset fonts (measured)
- **Location:** `build/app/outputs/flutter-apk/app-release.apk` (107,029,599 bytes);
  `assets/fonts/`; `.github/workflows/build-android.yaml:119` (no `--split-per-abi`).
- **Problem (measured from the APK):**
  - Native libs ship for 3 ABIs (arm64-v8a, armeabi-v7a, x86_64): `libflutter.so` ~11.7 MB
    + `libapp.so` ~13.4 MB + `libsqlite3.so` ~1.7 MB per ABI = ~80 MB uncompressed.
    Two ABIs are dead weight on any device (x86_64 is emulator-only).
  - Fonts: `JameelNooriNastaleeq-v4.ttf` 24.8 MB (40,164 glyphs), the so-called
    "Kasheeda-subset" 12.8 MB (25,061 glyphs — not a real subset), Naskh 0.4 MB.
    A proper Urdu/Arabic/Latin subset (~2k glyphs) would be ~1-2 MB per font.
- **Why it matters:** 107 MB download on metered connections; slower installs; users on
  low-storage devices cannot install. Estimated achievable: ~35 MB per-ABI APK
  (arm64-only + subset fonts), a ~65% reduction.
- **Symptom:** "App too big to download/install" complaints; slow CI artifact handling.
- **Fix:** (1) `flutter build apk --split-per-abi` for direct installs (keep the AAB for
  Play, which already splits). (2) Subset both Nastaleeq fonts to the app's character
  inventory with fonttools `pyftsubset` (keep full fonts in repo for PDF/report use if
  needed, ship subsets in the app bundle). Verify Nastaleeq redistribution license
  before subsetting (already an open item from the 2026-10-01 audit).

#### H-P5 — Dashboard loads ALL fees to compute one number
- **Location:** `lib/providers/dashboard_data_provider.dart:43-50` (`todayCollectionProvider`);
  also `:183-196` in `lib/presentation/viewmodels/finance/finance_overview_provider.dart`
  and `outstandingBalancesProvider` (aggregate over all fees).
- **Problem:** `todayCollectionProvider` awaits `allFeesProvider` (every fee row, full JSON
  deserialization) then filters to today in Dart. Same shape for finance-hub aggregates.
- **Why it matters:** O(all fees) deserialization for a single dashboard number; cost grows
  with history. `todayCollectionProvider` is a FutureProvider so it runs once per
  invalidation, but each run is a full-table Dart scan.
- **Symptom:** Dashboard slow to paint as fee history grows.
- **Fix:** SQL-side aggregation: `SELECT SUM(amount_paid) FROM fees WHERE paid_date = ?`
  (local Drift for the offline path; the dashboard is local-first). Same for outstanding
  balances (GROUP BY student_id).

#### H-P6 — N+1 provider fan-out on dashboards
- **Location:** `lib/providers/dashboard_data_provider.dart:56-66`
  (`examsWithoutResultsProvider`: one `examResultsProvider(exam.id)` await per exam);
  `:72-88` (`teacherTodayAttendanceStatusProvider`: one full attendance query per class).
- **Problem:** N exams -> N sequential provider instantiations + N queries; C classes ->
  C full attendance fetches. Each `FutureProvider.family` is a separate async unit with
  its own overhead.
- **Why it matters:** A teacher with 6 classes triggers 6 full attendance-table scans;
  an exam list of 20 triggers 20 result queries — all sequential awaits.
- **Symptom:** Dashboard cards populate one-by-one with visible stagger.
- **Fix:** Single aggregate queries: exams with zero results via one LEFT JOIN /
  NOT EXISTS query; attendance-done flags via one `SELECT class_id, COUNT(*) ... GROUP BY`.

### MEDIUM

#### M-P1 — `saveAttendance` issues ~5 sequential SQLite statements per student
- **Location:** `lib/data/repositories/attendance_repository.dart:150-191`;
  `SyncQueue.rowExists` / `currentRevision` (`sync_engine.dart:475-522`),
  `SyncEngine._localRevisionOf` + `_writeEnvelope` (`1463-1530`).
- **Problem:** Per student: existence SELECT, revision SELECT, local-revision SELECT,
  envelope upsert, queue INSERT — ~5 round-trips through the async bridge, 300 statements
  for a 60-student class. (Inside one transaction, so correctness is fine; it's pure waste.)
- **Why it matters:** 100-300 ms of UI-thread-adjacent work per save on low-end devices;
  also called from UI event handlers.
- **Symptom:** Brief UI freeze when saving attendance for large classes.
- **Fix:** Single multi-row upsert for envelopes + single multi-row INSERT for the queue
  (or one `INSERT ... SELECT`); compute revisions with one `SELECT id, revision ... WHERE
  id IN (...)`.

#### M-P2 — No composite `(tenant_id, server_version)` index for sync pull queries
- **Location:** pull query `lib/core/sync/sync_engine.dart:1334-1342`
  (`.eq('tenant_id').gt('server_version').order('server_version').limit(500)`);
  indexes in `supabase/migrations/009_tenant_indexes.sql` (tenant-only) and
  `014_finance.sql` (56 indexes, none on `(tenant_id, server_version)`).
- **Problem:** Every pull page sorts by `server_version` without an index that supports
  the filter+order; Postgres sorts the tenant's rows on each of the 18 queries per cycle.
- **Why it matters:** Fine at hundreds of rows; at tens of thousands of attendance/payment
  rows per tenant, every sync cycle pays a sort. Cheap to fix server-side.
- **Symptom:** Sync pull latency grows with tenant history.
- **Fix:** `CREATE INDEX ... ON <table> (tenant_id, server_version)` for each of the 9+
  pulled tables (migration).

#### M-P3 — Raw `NetworkImage` in lists: no cache, full-res decode at 52 px
- **Location:** `lib/presentation/screens/students/student_widgets.dart:31-32`
  (`StudentAvatar`), `lib/presentation/screens/admin/staff_list_screen.dart:661`,
  `lib/presentation/screens/students/student_dialogs.dart:697`,
  `lib/presentation/screens/auth/tenant_picker_screen.dart:121`.
  `cached_network_image` is a dependency but used in exactly one place
  (`lib/core/widgets/tenant_logo.dart:40`).
- **Problem:** Every list scroll re-downloads and re-decodes full-resolution photos to
  render a 52 px avatar; no disk/memory cache, no downscaling.
- **Why it matters:** Scroll jank, repeated mobile-data use, image-decode GC pressure on
  2 GB devices.
- **Symptom:** Student/staff lists stutter while scrolling; data usage climbs.
- **Fix:** Use `CachedNetworkImage` with `memCacheWidth`/`memCacheHeight` sized to the
  display (e.g. 128 px) everywhere avatars render.

#### M-P4 — Bootstrap is fully sequential before first frame
- **Location:** `lib/main.dart:104-131` (`_bootstrap`): `StorageService.init()` ->
  `SupabaseService.init()` (asset .env read + SDK init) -> `openDatabase()`
  (SQLite open + drift migration) -> orientations -> `runApp`.
- **Problem:** Independent initializations are awaited in series; first frame waits for all
  of them, including disk I/O (SharedPreferences, SQLite open/migrate) and SDK init.
- **Why it matters:** Adds hundreds of ms (potentially seconds on slow storage) to cold
  start; the user stares at the OS splash longer.
- **Symptom:** Slow cold start, worse on low-end devices.
- **Fix:** `Future.wait` the independent inits (storage, dotenv load, DB open can overlap;
  keep Supabase init ordered only where needed); show first frame earlier and finish
  non-critical init behind the auth gate. Measure with `flutter run --trace-startup`.

#### M-P5 — `todayCollection`-style patterns also hit finance overview (see H-P5)
- Covered under H-P5; listed here for the consolidation pass to avoid double-counting.

### LOW

#### L-P1 — `google_fonts` is an unused dependency
- **Location:** `pubspec.yaml` (`google_fonts: ^6.1.0`); zero imports in `lib/`, `test/`,
  `integration_test/`.
- **Problem:** Pure pubspec clutter. (Dart tree-shaking drops unimported pure-Dart packages,
  so APK impact is nil — this is hygiene, not size.)
- **Fix:** Remove from `pubspec.yaml`.

#### L-P2 — Dead `OfflineSyncService` still in the tree
- **Location:** `lib/core/services/offline_sync_service.dart` (`init()` never called;
  `main.dart:114` documents it as retired).
- **Problem:** Dead code ships; a future reader may wire it up and double-sync.
- **Fix:** Delete the file (already covered by the 2026-10-01 dead-code pass pattern).

#### L-P3 — RLS per-row function overhead is negligible at current scale
- **Location:** `is_tenant_member()` / `tenant_has_permission()` — `STABLE`,
  `SECURITY DEFINER`, index-backed EXISTS subqueries (`004_memberships.sql:205-262`).
- **Problem (non-problem):** Functions evaluate per row, but each is a single indexed
  lookup; Postgres plans it once per query. Not a bottleneck until very large tenants.
- **Fix:** None needed; revisit if a tenant exceeds ~100k rows per table.

#### L-P4 — Pull uses `.select()` (all columns incl. `data` JSON)
- **Location:** `lib/core/sync/sync_engine.dart:1336`.
- **Problem:** Full envelope rows are fetched by design (offline-first needs the whole row).
  Accepted trade-off; the tombstone pass correctly selects only `id, server_version`.
- **Fix:** None.

---

## Measurement plan (before/after)

| Metric | How to measure | Target signal |
|---|---|---|
| Cold start to first frame | `flutter run --trace-startup` / DevTools timeline | Reduce via M-P4 |
| Attendance save -> push complete (60 students, throttled 3G) | Stopwatch on `saveAttendance` + sync badge clear; Chrome DevTools network on desktop | H-P1: 20-60 s -> <5 s |
| Sync cycle request count (quiet DB) | Supabase API logs / proxy count per `syncNow()` | H-P2: 18+ -> <5 when idle |
| Search keystroke latency (5k fees) | DevTools CPU profile on student list screen | H-P3: per-keystroke O(fees) -> O(1) cached |
| APK size | `flutter build apk --split-per-abi` + `unzip -l` | H-P4: 107 MB -> ~35 MB (arm64) |
| Dashboard paint (10k fees) | DevTools timeline on dashboard open | H-P5/H-P6: full-table scans -> aggregate queries |
| Scroll jank (student list, 500 rows) | DevTools performance overlay, shader/jank counters | M-P3: NetworkImage -> cached+resized |
| Local write batch (60 attendance rows) | Stopwatch around `saveAttendance` | M-P1: ~300 stmts -> 2-3 stmts |

## Quick wins vs structural work

**Quick wins (hours, no architecture change):**
1. H-P4 (b): `--split-per-abi` in `build-android.yaml` — one-line change, ~50% smaller
   direct-install APK immediately.
2. H-P3: memoize fee-status aggregation in a derived provider.
3. M-P3: swap `NetworkImage` -> `CachedNetworkImage(memCacheWidth: 128)` in lists.
4. L-P1/L-P2: remove unused dependency and dead service.
5. M-P2: add `(tenant_id, server_version)` indexes (one migration).
6. M-P5: check connectivity once per push batch.

**Structural (days, needs design + testing):**
1. H-P1: batch `sync_apply` RPC or bounded-concurrency push.
2. H-P2: sync debounce + server-side change probe.
3. H-P4 (a): font subsetting pipeline (verify license first) — biggest single size win.
4. H-P5/H-P6/M-P1: SQL-side aggregations and batched local writes.
5. M-P4: parallelized bootstrap behind the auth gate.
