# Backup & Restore — one-file offline tenant backup

Phase 6 · worker 3/4. Every madrasa can save its **complete** data in **one
single file**, with **zero internet** required. Pakistan has severe internet
problems, so offline is a hard requirement, not a feature.

## 1. Architecture — why one file

The local Drift database is already a single SQLite file per tenant
(`<appSupport>/Madrassa360/madrassa360.db`, see
`lib/data/local/database_provider.dart`). A backup is therefore not an
export format to invent — it is a **checkpointed copy of that file** with a
`_backup_manifest` table written **into the copy**. The backup is literally
one `.db` file a madrasa can keep on a USB stick, email to itself, or file
away — and it opens in any SQLite browser.

### Manifest design

`_backup_manifest(key TEXT PRIMARY KEY, value TEXT NOT NULL)` rows:

| key | value |
|---|---|
| `tenant_id` | UUID of the owning tenant |
| `exported_at` | UTC ISO-8601 timestamp |
| `app_version` | e.g. `1.0.0+1` (mirrors pubspec `version:`) |
| `schema_version` | drift `schemaVersion` (currently `1`) |
| `row_counts` | JSON: `{ "students": 412, … }` for all 26 user tables |
| `data_sha256` | SHA-256 over the data (see below) |

The checksum is **deterministic**: for every user table (discovered from
`sqlite_master`, name order), every row in `rowid` order, every column
JSON-encoded with sorted keys. The manifest table itself is excluded —
the hash covers exactly what existed *before* the manifest was written,
which is what `verifyBackup` recomputes. Table discovery is dynamic, so
the manifest survives future schema migrations without a table list to
maintain.

### Code map

| Piece | Location |
|---|---|
| Service (create/verify/restore/list/delete, cloud enqueue) | `lib/core/backup/backup_service.dart` |
| UI (backup now, verify, typed-confirm restore, list, cloud status) | `lib/presentation/screens/admin/backup_screen.dart` |
| Server-side export (Master Admin offboarding/support) | `supabase/functions/export-tenant/index.ts` |
| Dependency | `crypto: ^3.0.7` (pure Dart, SDK `^3.4.0` — fits app's `^3.5.0`; verified via pub.dev API 2026-09-25). SHA-256 only; nothing here does encryption or key management. |

## 2. How to back up

**In the app** (admin → Backup screen): tap *Backup now*. Steps performed
by `BackupService.createBackup()`:

1. `PRAGMA wal_checkpoint(TRUNCATE)` on the live DB — flushes the WAL
   into the main file. **Without this, recent writes living only in the
   `-wal` sidecar would be silently missing from the copy.** This is the
   single most important line in the backup path.
2. File-copy `madrassa360.db` →
   `<appSupport>/Madrassa360/backups/madrassa360-backup-<tenantId>-<UTC timestamp>.db`
   (a custom `destinationDir` may be passed instead — e.g. a USB mount).
3. Open the copy, compute per-table row counts + data SHA-256, write
   `_backup_manifest` into the copy, close it.
4. Optionally enqueue a cloud copy (default on) — see §5.

All steps are local; no network is touched.

## 3. How to verify

`verifyBackup(path)` **never trusts the file**:

1. File exists, ≥ 100 bytes, starts with the `SQLite format 3` magic.
2. Opens it with `PRAGMA query_only = ON` — SQLite itself refuses writes
   on this connection, so a hostile file cannot be modified *or* modify us.
3. `_backup_manifest` exists with all six required keys.
4. `schema_version` equals the app's current schema version (policy: same
   version only — restores across schema versions need an explicit
   migration path, never silent acceptance).
5. Per-table row counts recomputed and compared.
6. Data SHA-256 recomputed and compared.

Returns `BackupVerification(valid, reasons, manifest)` — structured, never
throws for a bad file. The UI's *Verify* button shows the reasons.

## 4. How to restore — safety rules

`restoreBackup(path, confirmationToken:)` enforces, **in the service**
(not just the UI):

1. `confirmationToken` must equal `BackupService.restoreConfirmationPhrase`
   (`'RESTORE'`, case-sensitive). The UI makes the user *type* it.
2. `verifyBackup(path)` must pass — corrupt/foreign/wrong-schema files are
   rejected before anything is touched.
3. `manifest.tenant_id` must equal the current session's tenant —
   **cross-tenant restore is blocked**.
4. The live DB is WAL-checkpointed, then copied to a timestamped
   **pre-restore snapshot**
   (`madrassa360-pre-restore-<tenantId>-<ts>.db`, never overwritten). The
   live DB is never deleted without this copy existing.
5. The live connection is closed, stale `-wal`/`-shm`/`-journal` sidecars
   removed, the backup copied over the live path, then re-opened via
   `openDatabase()` and `PRAGMA integrity_check` run.
6. **Any failure after step 4 rolls back** from the pre-restore copy and
   re-opens it; if even the rollback fails, the error names the pre-restore
   path for manual recovery.

After a restore the caller **must rebuild the `appDatabaseProvider`
override** (or restart the app) — the old override points at the closed
connection. The Backup screen shows a restart prompt and does not touch
the DB until restart.

## 5. Cloud copy behavior (best-effort)

When online, the backup file is uploaded to the Supabase Storage bucket
**`tenant-backups`** (provisioned by platform ops) at
`{tenant_id}/backups/<fileName>`. Implementation reuses the Phase-5
`pending_uploads` machinery (`PendingUploadQueue.enqueueUpload`); the sync
engine's existing retry/upload path performs the bytes upload with upsert
on the next online window. The backup file itself is referenced directly
as `local_path` — no staging copy needed.

Contract, stated plainly:

- The **local file is the source of truth**; the cloud copy is a
  convenience for device loss / multi-device admins.
- Enqueueing works fully offline (it's just a DB row); upload happens
  whenever connectivity returns.
- Cloud status per backup (`pending` / `uploading` / `failed` / `done` /
  none) is read from the local `pending_uploads` table — the list screen
  works offline.
- A `failed` cloud copy never blocks local restore; re-enqueue from the
  backup list.

## 6. Master Admin export (`export-tenant`)

Server-side (Deno Edge Function, service role from env secrets only),
guarded by `requirePlatformAdmin` — platform admins only:

- `POST /functions/v1/export-tenant` with `{ tenant_id }`.
- Paginates all 21 tenant-scoped server tables, writes **one JSONL file**
  to the `tenant-exports` bucket at `exports/{tenant_id}/{timestamp}.jsonl`.
  Line 1 is the manifest (format, tenant_id, exported_at, schema_version,
  per-table counts, SHA-256 over the row lines); lines 2..n are
  `{ table, row }` objects — self-verifying like the local manifest.
- **The response never contains row data** — only `bucket`, `storage_path`,
  and the manifest. Every export is audit-logged (`tenant.export`).
- Scaling note: rows are collected in memory (paginated reads). Fine for
  a support/offboarding tool; not a hot path. A streaming rewrite is the
  documented follow-up if a tenant outgrows memory.

Deploy: `supabase functions deploy export-tenant` (bucket `tenant-exports`
must exist; service-role secrets per `supabase/functions/README.md`).

## 7. Disaster-recovery checklist

**Madrasa loses its device / database corrupts:**

1. Install the app on a working machine, sign in to the same tenant.
2. Obtain the latest `.db` backup (USB, email, or the cloud copy — download
   `tenant-backups/{tenant_id}/backups/<file>` from the Supabase dashboard
   as Master Admin if the madrasa has nothing local).
3. Admin → Backup → place the file where the app can see it (default
   backups dir), tap *Verify* — must report valid.
4. Tap *Restore*, type `RESTORE`, confirm.
5. Restart the app when prompted. The pre-restore snapshot remains in the
   backups dir as a second safety net — do not delete it until the madrasa
   confirms the data.
6. If the app fails to start after restore: the rollback already ran
   automatically; check the backups dir for the newest
   `madrassa360-pre-restore-*.db` and contact support with the exact error.

**Whole-platform disaster (Supabase down):** every tenant's data lives in
its local `.db` files; the app keeps working offline (Phase 5 sync engine
holds the queue). Backups taken during the outage verify and restore
normally — no server round-trip is involved at any step.
