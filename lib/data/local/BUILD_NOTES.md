# Local Database — Build Notes (Phase 5)

Hand-written Drift schema + DAOs for the offline-first sync engine.
**This code has NOT been compiled, analyzed, or tested** — the Flutter/Dart
toolchain is unavailable in this environment. Run the checklist below on a
dev machine (or CI) with the real toolchain before merging.

## 1. Dependencies

Added to `pubspec.yaml` (existing dependencies untouched):

| Package | Version | Why this line |
|---|---|---|
| `drift` | `^2.31.0` | Highest drift whose SDK constraint (`>=3.5.0 <4.0.0`) fits this app's `sdk: ^3.5.0`. `drift >= 2.33` needs Dart `>=3.10` + `sqlite3 ^3.x`, which cannot pair with `sqlite3_flutter_libs`. Verified via pub.dev 2026-09-25. |
| `sqlite3_flutter_libs` | `^0.5.41` | Ships native SQLite for Windows/macOS/Linux/Android/iOS (`>=2.12.0 <4.0.0`). **Do not** take `0.6.0+eol` — that release requires Dart 3.10 and ships no native implementation. `^0.5.41` matches `drift 2.31.x`'s `sqlite3 ^2.6.0` line. |
| `path_provider` | `^2.1.5` | Per-OS app-data dir (`^3.4.0` SDK constraint). `2.1.6` needs Dart `^3.10.0`. |
| `path` | `^1.9.0` | `join()` for the DB file path. |
| `drift_dev` (dev) | `^2.31.0` | Generator; must track the `drift` minor version. |
| `build_runner` (dev) | `^2.10.0` | Build system. Its `analyzer ^8.0.0` line intersects `drift_dev 2.31.0`'s `analyzer >=8.1.0 <11.0.0`. |

Caveat: `build_runner ^2.10.0` declares `SDK ^3.7.0`, so **codegen itself must
run on a machine with Dart >= 3.7** even though the app's own SDK floor is
3.5. This is the normal pattern (dev-only dependency); it does not affect
the app's runtime SDK range.

## 2. Codegen

From the repo root:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

(On Dart >= 3.7 without the `flutter` wrapper, `dart run build_runner build
--delete-conflicting-outputs` works too.)

Expected generated output:

- `lib/data/local/app_database.g.dart` — the ONLY generated file. It contains
  the table classes (`$StudentsTable`, …), data classes (`LocalStudent`, …),
  companions (`StudentsCompanion`, …), DAO mixins (`_$StudentsDaoMixin`, …)
  and `_$AppDatabase`.

All tables, DAOs and data classes live in `lib/data/local/app_database.dart`,
so nothing else should appear. If you split DAOs into separate files later,
each file gets its own `.g.dart` — the `part`/`part of` wiring must match.

## 3. Schema summary

`schemaVersion = 1`. Every business table (`students`, `classes`, `darjas`,
`attendance_records`, `invoices`, `payments`, `exams`, `results`,
`announcements`) has:

- `id TEXT PRIMARY KEY`
- `tenant_id TEXT NOT NULL`
- `revision INTEGER NOT NULL DEFAULT 1`, `server_revision INTEGER NULL`
- `updated_at INTEGER NOT NULL`, `deleted_at INTEGER NULL` (epoch millis)
- `data TEXT NOT NULL DEFAULT '{}'` (JSON blob for flexible server columns)
- indexed pragmatic columns (see the `indexes` getters in the table classes)

Deliberately absent: any `dirty` flag. The `sync_queue` table is the source
of truth for pending pushes.

Sync tables:

- `sync_queue` — `operation_id` PK; `tenant_id`, `entity`, `entity_id`;
  `operation` with `CHECK (operation IN ('create','update','delete'))`;
  `sync_status` with
  `CHECK (sync_status IN ('pending','in_progress','failed','done','dead_letter'))`
  and `DEFAULT 'pending'`; `retry_count`, `last_error`, `next_retry_at`
  (epoch millis, NULL = due immediately / not scheduled).
- `sync_conflicts` — autoincrement `id`; local vs server payload JSON;
  `resolved` flag.
- `sync_state` — composite PK `(entity, tenant_id)`; pull watermark
  `last_server_version` + `last_pull_at`.
- `tenant_settings_cache` — PK `tenant_id`; payload JSON + `cached_at`.

### CHECK-constraint note

The `CHECK` clauses are spelled via `ColumnBuilder.customConstraint()`,
which **replaces** drift's generated constraint clause — so `NOT NULL` and
the `DEFAULT 'pending'` are written out explicitly in the custom string.
If codegen/analysis disagrees with this behavior on your toolchain version,
the fallback is: drop `customConstraint`, keep a plain `.withDefault(...)`
column, and enforce the allowed values in `SyncQueueDao.enqueue` (the
`validOperations` / `pendingStatuses` lists are already there for this).

## 4. DAO surface (per entity DAO)

`upsert` · `getById(id, tenantId)` · `listByTenant(tenantId)` ·
`watchByTenant(tenantId)` · `markClean(id, tenantId)` (+ targeted offline
queries: `AttendanceRecordsDao.listByClassAndDate`,
`InvoicesDao.listByStudent`, `ResultsDao.listByExam`).

`markClean` copies the row's current `revision` into `server_revision`
(transactionally); it never touches the queue.

`SyncQueueDao`: `enqueue`, transactional `enqueueInTransaction` (local change
+ queue row in one transaction), `claimNextBatch` (FIFO claim per entity,
flips to `in_progress` atomically), `markDone`, `purgeDone`,
`markFailed` (exponential backoff 1m → 24h, dead-letters after 8 attempts),
`deadLetter`, `pendingCount(tenantId)`, `listStuck`/`reclaimStuck`
(crash recovery for rows stranded `in_progress`).

`SyncStateDao`: `getWatermark` / `setWatermark` / `clearTenant`.
`SyncConflictDao`: `record` / `listOpen` / `resolve` / `clearTenant`.
`TenantSettingsDao`: `getPayload` / `setPayload` / `clear`.

Every query that touches business or queue data filters by `tenant_id` —
there is no cross-tenant path.

## 5. Provider

`lib/data/local/database_provider.dart`:

- `openDatabase()` — memoized singleton; opens
  `<app-support>/Madrassa360/madrassa360.db` via `NativeDatabase.createInBackground`.
- `databaseFile()` — resolves/creates the directory (exported for tooling).
- `appDatabaseProvider` — Riverpod `Provider<AppDatabase>`; override with the
  opened instance in `main()`, or with `AppDatabase(NativeDatabase.memory())`
  in tests.
- `closeDatabase()` — closes + forgets the singleton; call on logout and
  between tests, then invalidate/rebuild the provider override.

## 6. CI / Windows checklist

- [ ] `flutter pub get` resolves with no version conflicts (see §1).
- [ ] `flutter pub run build_runner build --delete-conflicting-outputs`
      succeeds; `app_database.g.dart` appears and nothing else is generated.
- [ ] `flutter analyze` passes with no errors.
- [ ] `flutter test` passes (suggested: override `appDatabaseProvider` with
      an in-memory DB; exercise `enqueueInTransaction`, `claimNextBatch`
      atomicity, `markFailed` backoff, `pendingCount` tenant isolation).
- [ ] `flutter build windows` succeeds; `sqlite3.dll` is bundled next to the
      exe by `sqlite3_flutter_libs` (no manual DLL copying).
- [ ] `flutter run -d windows`: app starts, DB file is created at
      `%APPDATA%\...\Madrassa360\madrassa360.db` (verify with
      `databaseFile()` / a debug log) — never under Program Files.
- [ ] Logout path calls `closeDatabase()`; reopening afterwards works.
- [ ] Crash-recovery: rows stranded `in_progress` are reclaimed by
      `reclaimStuck` on next sync start.

## 7. Schema evolution

Bump `schemaVersion` and add an `onUpgrade` step in `AppDatabase.migration`
for every future schema change — never ship a destructive recreate against
a database that holds an unsynced queue.
