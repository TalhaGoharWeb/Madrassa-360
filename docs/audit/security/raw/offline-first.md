# Offline-First Audit — Madrassa-360

**Date:** 2026-10-03 · **Branch:** `redesign/ux-v2`
**Scope:** end-to-end offline-first behavior: `lib/core/sync/sync_engine.dart` (1809 lines),
`lib/data/local/` (Drift/SQLite), `lib/data/repositories/storage_repository.dart`
(`PendingUploadQueue`), `lib/core/sync/sync_providers.dart`, `lib/main.dart` bootstrap,
`lib/core/services/supabase_service.dart`, `lib/core/security/safe_download.dart`.
**Method:** static code analysis (no device/network harness). Findings already covered by
sibling audits (sequential per-row push, full sync on every connectivity flap, wall-clock
conflict resolution, dead-letter queue with no auto-retry, unreachable conflict-review UI)
are referenced, not re-litigated.

**Verification note (2026-10-03, post security-fix wave):** every finding below was
re-checked against the current tree (security migrations 029–046, Edge Function and
auth/session hardening applied). All verdicts and the conflict-resolution table stand
as written; the `resolveConflictKeepServer` over-completion (§13) is confirmed at
`sync_engine.dart:1267-1315` in the current code.

**Bar:** every sync operation must be retryable, idempotent where appropriate, observable,
recoverable. Never silently lose user data.

---

## Scenario verdicts

### 1. First launch without internet — RISK
- **Location:** `lib/main.dart:102-117` (`_bootstrap`), `lib/core/services/supabase_service.dart:53-69`.
- **Problem:** `_bootstrap()` awaits `StorageService.init()`, `SupabaseService.init()`,
  then `openDatabase()`. `Supabase.initialize` itself performs no network I/O, and the
  gotrue background-refresh stream has an `onError` handler, so a dead network does not
  hang bootstrap — but there is **no offline bootstrap path for a new user**: login
  requires the network, and no cached session exists, so the app is unusable until
  connectivity returns. There is no "continue offline / demo" affordance and no explicit
  UX explaining that first login needs internet.
- **Scenario:** school clerk installs the app at a madrassa with no signal → stuck at
  login with a generic network error, no guidance.
- **Fix:** add an explicit first-launch offline state (Urdu explanation + retry), and
  consider a time-boxed offline grace mode only if product approves it.

### 2. Intermittent connectivity — RISK
- **Location:** `lib/core/sync/sync_engine.dart:700-716` (`start()` connectivity listener),
  `pushOnce()` per-entity `_isOnline()` checks.
- **Problem:** every "online" event fires a full `syncNow()` with **no debounce** (also
  flagged in the performance audit). Worse, `_isOnline()` uses `Connectivity`
  (network-interface state, not real internet): on a captive portal / dead-DNS Wi-Fi it
  reports online, and every queued row then burns a **30-second RPC timeout**
  (`_callSyncApply`, sync_engine.dart:918-940) sequentially — 25 claimed rows ≈ 12.5
  minutes of futile radio use per cycle, with no circuit breaker.
- **Scenario:** flapping mobile data → repeated full push+pull cycles, battery drain,
  and multi-minute sync stalls on Wi-Fi with no real internet.
- **Fix:** debounce the connectivity trigger (60–120 s), add a cheap
  server-reachability probe before a push batch, and a circuit breaker that backs off
  the whole cycle after N consecutive transport failures.

### 3. Offline writes — SAFE (with a caveat)
- **Location:** `sync_engine.dart:520-560` (`SyncQueue.enqueueAll`), `writeLocalRow`.
- **Problem:** repositories enqueue inside the same transaction as the local envelope
  write (documented contract) — crash-safe and FIFO per entity via `created_at`.
  **Caveat:** cross-entity causal order is only *best-effort*: `_pendingEntities`
  orders entities by `MIN(created_at)`, so an invoice created at T2 referencing a
  student created at T1 pushes after the student — but interleaved multi-entity
  sequences are not strictly causally ordered. A child row can reach `sync_apply`
  before its parent if entity batches interleave, failing server-side FK checks and
  dead-lettering.
- **Fix:** document the ordering guarantee as "FIFO per entity, best-effort across
  entities"; consider a dependency hint (`_parent_upload_id`-style gate already exists
  for uploads — extend the pattern to parent rows).

### 4. Reconnect — SAFE
- Connectivity listener + `notifyAppResumed()` drain the queue; FIFO per entity is
  preserved; failed rows with expired backoff re-enter. No finding beyond §2's
  debounce/timeout issues.

### 5. Duplicate synchronization — RISK
- **Location:** `sync_engine.dart:793-810` (`_claimBatch`, 10-minute lease),
  `_reclaimStaleClaims` (runs **only** on `start()`).
- **Problem (a) — same `operation_id` twice:** the claim lease prevents double-claim
  within a process, and a server-side PK makes re-insert return `already_exists` →
  converges via the conflict path. Acceptable.
- **Problem (b) — same *logical* op twice (double-tap / retry):** each tap mints a
  new queue row with a new UUID `entity_id` → two `payments` rows → **double charge**.
  No idempotency key exists (also flagged in the database audit, H-2/H-3). This is the
  dangerous duplicate.
- **Problem (c) — lease window:** a push batch that runs longer than the 10-minute
  lease (25 rows × 30 s timeouts) while the app *restarts* causes the new process to
  reclaim and re-push rows the old process may still be pushing (if the old process
  wasn't actually dead, e.g. isolate survived). Re-push converges via
  `already_exists`, but for financial entities it parks a spurious "financial
  conflict — held for review" (user-visible friction for a successful payment).
- **Fix:** idempotency keys on payments/expenses/income (DB partial unique index,
  client-generated key per user intent); shorten the effective worst-case push batch
  or extend the lease heartbeat while a batch is actively progressing.

### 6. Conflicting edits — RISK (rules exist; clock-skew flaw)
- **Location:** `sync_engine.dart:238-250` (`decideNormalConflict`), `1099-1185`
  (`_handleConflict`), `isFinancialConflict`.
- **Problem:** the rules *are* explicit and documented (see "Conflict-resolution
  rules" below), but normal-entity resolution compares **wall-clock `updated_at`**
  across devices. A device with a fast clock silently wins every conflict
  (sibling database audit H-5). The revision counter — the correct arbiter — is
  available but unused for the decision.
- **Scenario:** clerk A's phone clock is 10 minutes fast; clerk B's correct edit to
  the same student is silently discarded as "server is older".
- **Fix:** decide on `revision`/`server_revision` ordering, not wall-clock time;
  keep `updated_at` only as a tiebreak display hint.

### 7. Deleted records — SAFE
- Tombstones (`deleted_at`) propagate via pull pass 2; `not_found`/`already_deleted`
  converge by dropping the local row (`_convergeRowDeleted`); protected-ids guard
  prevents pull from clobbering unpushed local work; un-delete clears the local
  tombstone. No resurrect-on-sync bug found.

### 8. Partially completed operations — RISK
- **Location:** `sync_engine.dart:1003-1020` (`_markDone` — transactional, good),
  `793-810` (claim), `start()` (reclaim).
- **Problem:** `_markDone` is correctly transactional (queue `done` + `server_revision`
  stamp in one Drift transaction). **But:** if the push *loop itself* dies
  (exception escaping `_pushRow`, e.g. a DB error in `_markDone`), rows are left in
  `in_progress` and **nothing reclaims them until the next app start** —
  `_pendingEntities` only selects `pending`/`failed`, and `_reclaimStaleClaims`
  runs exclusively in `start()`. An app that stays alive after a push-loop crash
  wedges those rows indefinitely (badge keeps showing them, they never move).
- **Scenario:** transient SQLite `database is locked`/disk-full error mid-batch →
  rows stuck `in_progress` for the rest of the session despite connectivity.
- **Fix:** reclaim expired leases at the start of every `pushOnce()` (cheap single
  UPDATE), not only on engine start; also reclaim on `syncNow()` entry.

### 9. App restart during sync — RISK
- **Location:** `sync_engine.dart:693-699` (`start()` → `_reclaimStaleClaims`).
- **Problem (a) — lease-window delay:** kill at T, restart at T+5 min → the 10-minute
  lease hasn't expired → rows stay `in_progress` for the whole session; they only
  move on a *later* restart after T+10 min. Users see a stuck sync badge with no
  explanation.
- **Problem (b) — crash between RPC success and `_markDone`:** the row is resent on
  restart → `already_exists` → for **financial** entities this parks a spurious
  "financial conflict — held for review" and dead-letters a *successful* payment.
  Not data loss, but a real-world friction/false-alarm path (payment succeeded,
  user told it needs review).
- **Fix:** (a) reclaim on every `pushOnce` (see §8); on start, reclaim rows whose
  lease expired *or* whose owning process is known-dead is impossible — instead
  shorten the lease to ~2 min and heartbeat it while a batch is active. (b) on
  `already_exists` for a row the client just pushed, prefer "mark done, adopt
  server revision" over the financial-conflict park when the server row matches the
  pushed payload.

### 10. Token expiration while offline — RISK
- **Location:** `sync_engine.dart:918-940` (`_callSyncApply` catches *all*
  exceptions → `null` → `'transport error'`), `1042-1070` (`_recordFailure`).
- **Problem:** a 401 from an expired token is indistinguishable from a network
  blip: it burns one of 5 backoff retries as "transport error", and if the SDK's
  background refresh hasn't completed, 5 consecutive 401s → **dead_letter with a
  misleading message** — the user is never told to re-authenticate. There is no
  explicit "wait for session refresh before pushing" or re-login prompt on
  persistent 401.
- **Scenario:** token expires during a long offline stretch; on reconnect the first
  pushes 401 while refresh is still in flight → after 5 failures the ops park as
  dead letters labeled "transport error"; clerk thinks the network is broken.
- **Fix:** distinguish auth failures from transport failures (401/403 → do not
  consume retries; trigger a session-refresh wait, then retry; on persistent 401,
  surface "please log in again" instead of dead-lettering).

### 11. Database corruption — BROKEN
- **Location:** `lib/data/local/database_provider.dart:40-48` (`openDatabase`).
- **Problem:** `NativeDatabase.createInBackground(file)` is opened with **no
  integrity check, no corruption detection, no automatic recovery**. A corrupt
  SQLite file (killed mid-checkpoint, bad SD card, disk-full write) surfaces as
  scattered query failures — and `LocalRows`/`SyncQueue` helpers **swallow
  exceptions and return empty defaults** (`catch (_) return null/[]/0`), so the
  app presents an *empty-looking* database rather than an error. The user may
  keep working (creating rows that can never push against a broken local store)
  while the real dataset is unreadable.
- **Scenario:** device storage fills mid-checkpoint → DB corrupt → app opens
  showing zero students/fees; clerk re-enters data; on reinstall, everything is
  gone with no warning it was ever broken.
- **Fix:** run `PRAGMA integrity_check` on open (background isolate); on failure,
  quarantine the file, surface an explicit Urdu "local data damaged" state with
  options (restore from backup via `backup_service.dart`, or wipe-and-resync from
  server), and **never** silently present an empty DB. The existing
  `backup_service.dart` gives a restore path to wire this to.

### 12. Failed uploads / failed downloads — RISK
- **Location:** `lib/data/repositories/storage_repository.dart`
  (`PendingUploadQueue`), `sync_engine.dart:958-1011` (`_ensureUploadDone`),
  `lib/core/security/safe_download.dart`.
- **Problem (a) — orphaned delete jobs:** `enqueueDelete` has **zero callers**;
  worse, nothing except a queue row carrying `_pending_upload_id` ever drives
  `pending_uploads` — a delete job (or any upload job without a dependent queue
  row) is never executed. Latent dead path.
- **Problem (b) — staged-file disk leak:** `stageFile` copies into
  `<appSupport>/Madrassa360/uploads/<tenantId>/` and **nothing ever deletes staged
  files** after a successful upload. Unbounded growth on the device.
- **Problem (c) — give-up behavior:** an upload that can never succeed (staged
  file deleted from disk → `readAsBytes` throws every time) burns the *queue
  row's* 5 retries → dead_letter; the `pending_uploads` row stays `failed`
  forever with an unbounded `retry_count` column that nothing caps.
- **Problem (d) — downloads:** `SafeDownload` (new, good: https-only, SSRF guard,
  5 MB streaming cap) covers branding fetches; student/staff photos still use raw
  `NetworkImage` with no size cap on decode (perf audit) and fail silently.
- **Fix:** drive `pending_uploads` with an independent sweeper (not only via
  dependent queue rows); delete staged files on upload success; cap upload
  retries with a terminal state + user-visible error; route photo fetches through
  a capped downloader.

### 13. Silent data loss in conflict review — HIGH (new)
- **Location:** `sync_engine.dart:1300-1318` (`resolveConflictKeepServer`).
- **Problem:** "Keep server" marks **ALL** non-done queue rows for that
  `(tenant_id, entity, entity_id)` as `done` — not just the conflicted op. If the
  user edited the row *after* the conflict was parked (a newer op sitting in the
  queue), that newer local edit is marked done **without ever being pushed**.
  Silent loss of the user's latest change.
- **Scenario:** payment conflicts → parked; clerk corrects the amount locally
  (new queued op); manager reviews and taps "keep server" → the correction is
  discarded, marked synced, and never sent.
- **Fix:** only complete the specific `operation_id` tied to the conflict (store
  it in the conflict record); leave newer queued ops untouched.

---

## Conflict-resolution rules (as implemented — the explicit contract)

| # | Conflict type | Rule | Where enforced |
|---|---|---|---|
| 1 | Any conflict on a **financial** entity (`invoices, payments, transactions, refunds, accounts, income, expenses, discounts, scholarships, invoice_items` — server `financial` flag authoritative, client `financialEntities` fallback) | **Never overwrite server data.** Park in `sync_conflicts`, queue row → `dead_letter` (no auto-retry). Manual review only; "retry local" is refused for financial entities. | `sync_engine.dart:_handleConflict`, `isFinancialConflict`; review via `conflict_review_screen.dart` |
| 2 | Normal entity, server `updated_at` newer than local | **Take server.** Apply server row locally, queue row → done. | `_handleConflict` → `decideNormalConflict` → `takeServer` |
| 3 | Normal entity, local newer or timestamps tied, server time unknown | **Rebase + retry once.** Re-push with `base_revision = server_revision`; if it still conflicts → park in `sync_conflicts`. | `_handleConflict` rebase branch |
| 4 | Normal entity, local time unknown | Take server (fail toward server). | `decideNormalConflict` (`localUpdatedAt == null` → takeServer) |
| 5 | Server row gone (`deleted` reason / null row) | **Take server state.** Drop local row, queue row → done. | `_handleConflict`, `_convergeRowDeleted` |
| 6 | `not_found` / `already_deleted` on push | Converge: drop local row, complete op. | `_pushRow` → `_convergeRowDeleted` |
| 7 | `already_exists` on insert | Treated as conflict (rule 2/3/1 by entity type). | `_conflictReasons`, `_handleConflict` |
| 8 | Transport/timeout failure | **Not a conflict.** Exponential backoff 5s→10s→20s→40s, 5 attempts → `dead_letter` (surfaced in badge, manual retry via review). | `_recordFailure`, `_callSyncApply` → null |
| 9 | Crash between RPC success and `_markDone` | Resend on restart; converges via rules 7/2 (normal) or parks as financial conflict (rule 1). | `_reclaimStaleClaims`, `_markDone` transaction |
| 10 | Pull vs unpushed local work | Pull **never clobbers**: rows with non-done queue entries or unresolved conflicts are skipped (protected ids); watermark still advances. | `_protectedEntityIds`, `_pullEntity` |

**Known flaw in the rules:** rule 2/3's "newer" is decided by **wall-clock `updated_at`**,
so a skewed device clock decides conflicts. The `revision` counter should be the
arbiter (sibling database audit H-5).

---

## Prioritized fixes (offline track)

1. **HIGH** — `resolveConflictKeepServer` must complete only the conflict's own
   `operation_id`, never all queued ops for the entity (silent data loss,
   §13). Store the `operation_id` in the conflict record.
2. **HIGH** — DB corruption: `PRAGMA integrity_check` on open + quarantine /
   explicit damaged-state UX + restore-from-backup path (§11). Never present an
   empty DB silently.
3. **MEDIUM** — reclaim expired `in_progress` leases at the start of every
   `pushOnce()`, not only on engine start (§8); shorten lease / heartbeat it.
4. **MEDIUM** — distinguish 401/403 from transport errors: don't burn retries on
   auth failures; wait for refresh, then prompt re-login on persistent 401 (§10).
5. **MEDIUM** — idempotency keys for payments/expenses/income (client-generated per
   user intent + DB partial unique index) — kills double-charge on double-tap and
   retry (§5b; also sibling DB audit H-2/H-3).
6. **MEDIUM** — decide normal-entity conflicts on `revision`, not wall-clock
   `updated_at` (§6).
7. **MEDIUM** — drive `pending_uploads` with an independent sweeper; delete staged
   files after successful upload; cap upload retries with a terminal user-visible
   state (§12).
8. **LOW** — debounce the connectivity-triggered full sync; add a reachability
   probe + circuit breaker for dead-DNS Wi-Fi (§2).
9. **LOW** — restart-within-lease delay: heartbeat the claim lease while a batch is
   active so a live-but-slow push isn't reclaimed (§9a).
10. **LOW** — first-launch-offline UX: explicit "login needs internet" state (§1).

## What's solid (do not regress)
- Transactional `_markDone` (queue done + `server_revision` stamp atomic).
- Crash-safe claim/reclaim design (10-min lease, reclaimed on start).
- Enqueue-inside-write-transaction (local row + queue row atomic).
- Pull watermark advances transactionally with applied rows; protected-ids guard.
- Tombstone propagation both directions; un-delete clears local tombstones.
- Upload-before-URL ordering rule (`_pending_upload_id` gate).
- Dead letters and conflicts are observable (`pendingSyncCountProvider`,
  `syncConflictsProvider`, `lastSyncAtProvider`).
- Row-level idempotency via PK on re-push after crash (`already_exists`
  convergence).
