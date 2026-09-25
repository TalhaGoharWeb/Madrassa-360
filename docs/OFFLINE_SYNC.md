# Offline-First Sync Engine — Madrasa 360 (Phase 5)

> Status: **code-complete, pending staging run** (branch `feature/offline-sync`,
> unpushed). This document is the architecture contract for the Phase 5 sync
> engine. The pre-Phase-5 baseline is `lib/core/services/offline_sync_service.dart`
> (a SharedPreferences JSON queue + connectivity listener); the Drift-backed
> engine described below lives in `lib/core/sync/` (sibling worker) and the
> repositories are being converted to local-first with identical public
> signatures. Nothing here has run against a staging backend yet.

## Architecture

Write path — every mutation is local-first:

```
┌────────────┐   save()    ┌──────────────┐  1 txn   ┌───────────┐
│ Flutter UI │ ──────────▶ │ IRepository  │ ───────▶ │   Drift   │
│ (Riverpod) │             │ (local-first │          │ local DB  │
└────────────┘             │  signature)  │          │ (per-tenant│
      ▲                    └──────┬───────┘          │  tables)  │
      │                           │ enqueue        └─────┬─────┘
      │                           ▼ (same txn)            │ sync_queue row
      │                    ┌──────────────┐               │ status=pending
      │                    │ Sync Engine  │ ◀─────────────┘
      │                    │(per active   │
      │                    │  tenant)     │
      │                    └──────┬───────┘
      │                           │ push (upsert on conflict keys)
      │                           ▼
      │                    ┌──────────────┐
      └────────────────────│   Supabase   │
        pull / realtime     │   (remote)   │
        invalidation        └──────────────┘
```

Read path — Drift is the single source of truth for reads:

```
UI ◀── Repository.get ◀── Drift ◀── pull merge (revision compare)
│                          ▲
└── realtime / manual refresh invalidation
```

Key rule: the UI never talks to the network directly. Repositories write to
Drift and enqueue in the **same transaction**; the engine owns the network.

## Queue schema (`sync_queue` table, Drift)

| Column         | Type        | Purpose |
|----------------|-------------|---------|
| `id`           | UUID, PK    | Stable op identity (idempotency key) |
| `tenant_id`    | TEXT, NOT NULL, indexed | Owner tenant — engine filters on this |
| `entity`       | TEXT        | `attendance`, `fee`, `student`, … |
| `entity_id`    | TEXT        | Local/remote row identity |
| `op`           | TEXT        | `upsert` / `insert` / `update` / `delete` |
| `payload`      | JSON        | Full row to push |
| `base_revision`| INTEGER     | Revision the payload was built on (conflict detect) |
| `status`       | TEXT        | `pending` → `in_progress` → done / `dead_letter` |
| `attempts`     | INTEGER     | Failed push count |
| `next_retry_at`| DATETIME    | Backoff gate for the push loop |
| `last_error`   | TEXT, NULL  | Last failure, for the sync-health screen |
| `created_at` / `updated_at` | DATETIME | Ordering + diagnostics |

Companion table `sync_conflicts`: rows that must never auto-resolve
(financial entities), holding local + remote payloads for manual review.

## Push loop

1. Engine (one instance per **active tenant**) selects the oldest `pending`
   rows with `next_retry_at <= now()` for its `tenant_id`.
2. Marks them `in_progress` **in the same transaction** as the select, so a
   crash between select and push cannot lose or duplicate work.
3. Pushes each payload to Supabase via the repository's upsert on the
   entity's natural conflict key (e.g. `attendance`: `student_id + date`).
4. Success → row deleted. Failure → `attempts + 1`, `next_retry_at` set by
   the retry policy, `last_error` recorded.

Upserts are idempotent on conflict keys, so a retried push can never create
a duplicate row.

## Pull loop

- Triggered on: connectivity restore, Supabase Realtime event for a watched
  table, manual refresh, and a periodic heartbeat while the app is open.
- Fetches remote changes since `last_pull_at` (per entity, per tenant),
  compares revisions, and merges into Drift:
  - remote newer → apply remote, drop any superseded local state;
  - local newer (unpushed edit) → keep local, leave the queue row pending;
  - equal → no-op.
- After merge, the relevant Riverpod providers are invalidated so the UI
  re-reads from Drift.

## Conflict rules

- **Normal entities** (attendance, students, profiles, …): **latest valid
  revision wins**. Revision = `max(updated_at, revision counter)`; ties break
  toward the server timestamp. Loser is overwritten; the winner's revision is
  recorded so the decision is auditable.
- **Financial entities** (fees, payments, salaries — anything that moves
  money): **never overwrite**. On a revision mismatch the engine copies both
  payloads into `sync_conflicts` (status `needs_review`), keeps the local
  value untouched, and surfaces the conflict in the manual review screen.
  Resolution is a human decision: keep local, take remote, or merge — then
  the resolution itself is enqueued as a new revision.

## Retry policy

- Exponential backoff with ±20% jitter: **2s → 8s → 32s → 2min → 8min**.
- After **5 failed attempts** the row moves to `dead_letter`: it stops being
  retried automatically and appears in the sync-health screen with its
  `last_error`. From there the user (or support) can retry manually or
  discard it. Dead-letter rows are never silently dropped.

## Crash-safety story

- **Transactional enqueue:** the Drift write and the `sync_queue` insert
  happen in one transaction. A crash can never produce a local write without
  its queue row (lost update) or a queue row without its local write
  (phantom push).
- **`in_progress` reclaim:** on engine start, any row still `in_progress`
  from a previous (killed) process is reset to `pending` after a short grace
  period, with `attempts` unchanged. Combined with idempotent upserts, this
  means a force-stop mid-push is always safe to replay.
- **Logout/restart:** queue rows persist in Drift; the engine simply resumes
  where it left off.

## Multi-tenant behavior

- Every queue row carries `tenant_id`; the engine's push/pull queries always
  filter on the active tenant from `currentTenantIdProvider`.
- Drift tables are tenant-scoped in every repository query (RLS enforces it
  server-side; the client filter is the companion).
- Queue rows for other tenants are invisible to the engine instance — they
  wait untouched until their tenant becomes active.

## Logout / tenant switch

- The engine **stops** on logout and on tenant switch: timers cancelled,
  Realtime subscriptions closed, the per-tenant push/pull loop torn down.
- The queue **persists per tenant** in Drift — logout does not wipe it.
  Signing back in (or switching back) restarts the engine for that tenant,
  which reclaims `in_progress` rows and drains the queue.
- `TenantContext.clear()` / `switchTenant()` are the single choke points;
  the engine observes `activeTenantIdProvider` and reacts to changes.

## How to test offline mode — checklist

1. **Seed:** sign in, open a class's attendance (loads roster into Drift).
2. **Go offline:** airplane mode → the orange banner
   `آف لائن: ہم آہنگی کے منتظر ریکارڈز: N` appears. Mark statuses, save →
   snackbar `آف لائن محفوظ — انٹرنیٹ بحال ہوتے ہی خودکار ہم آہنگی ہو جائے گی`.
3. **Crash mid-queue:** force-stop the app → relaunch → rows still `pending`,
   none duplicated, banner count unchanged.
4. **Reconnect:** airplane mode off → queue drains, Supabase rows match the
   teacher's marks, banner clears.
5. **Conflict (normal):** edit the same attendance on two devices offline →
   reconnect both → latest revision wins, single row in Supabase.
6. **Conflict (financial):** same drill on a fee record → no overwrite; entry
   appears in the manual review screen (`sync_conflicts`).
7. **Retry:** point the app at an unreachable host → 5 attempts with backoff
   → row becomes `dead_letter` → manual retry from sync-health works.
8. **Tenant switch:** queue items for tenant A stay untouched while tenant B
   is active and syncing.
9. **Logout:** queue persists; sign back in → engine resumes and drains.
10. **Future-date guard:** attendance date picker refuses future dates
    (server rejects them too).
