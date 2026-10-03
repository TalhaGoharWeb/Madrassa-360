# Migration Notes 029–044 — security remediation (2026-10-03)

Branch: `redesign/ux-v2`. All files in `supabase/migrations/`. **Branch files
only — nothing was applied to the live database.**

Where a finding's recommended fix was ambiguous or would break a legitimate
flow visible in the migrations/app, the **safer option was chosen** and is
recorded below.

## Deviations and safer-option decisions

### 029 (SEC-H5, read half)
- Replaced the member-wide `user_accounts` SELECT with platform-admin OR
  holder-of-`users.view`-in-≥1-tenant. A row in the seed data could, in
  principle, belong to a tenant where the viewer holds no `users.view`;
  the per-row correction lands in **039** once `tenant_id` exists.
- **025–028 ledger stamps backfilled here.** Those four migrations never
  self-stamped; the live ledger was reconciled by hand. Without the
  backfill the ledger would falsely report them missing.

### 031 (SEC-M6, permission oracles)
- Revoked EXECUTE on `user_effective_permission`, `user_code_denied`,
  `tenant_has_permission` from `authenticated`/`anon`; re-granted the
  `auth.uid()`-bound `get_my_permissions*` wrappers.
- **Deliberately left granted:** `user_is_tenant_admin`, `scope_allows`,
  `result_class_id` — these take a tenant_id but return booleans/ids, not
  permission contents, and the app's client checks call them. Revoking
  them would break legitimate flows for no oracle gain. Flagged for
  re-review if any of them starts returning permission detail.

### 032 (SEC-C1, sync_apply permission map)
- `sync_required_permission()` covers only **verified permission codes**
  (seeded in 005/019/021). `fees.delete` is not in the seed, so the
  sync path **fails closed**: fee deletes through sync are rejected
  unless the caller is a platform admin. This matches the 027 RLS policy
  (no `fees.delete` grant exists anywhere). The alternative — inventing
  a code mapping for an unseeded permission — would have been a guess.
- Unknown (entity, op) pairs return a reason object
  (`forbidden:missing_permission`), never an exception, so a client
  can't distinguish "unknown entity" from "forbidden" by error shape.
- `scope_allows()` is enforced for results/attendance **only when a
  narrowing scope row exists**; otherwise the permission code is the
  gate. Enforcing scope unconditionally would break every existing
  writer who was never assigned a scope row.

### 033 (SEC-C2/C3, sync_apply correctness)
- Membership check now runs **before** the existence probe, so a
  non-member can no longer learn whether a row exists.
- `already_exists` / `not_found` never include `server_row` for rows
  outside the caller's tenant — closes the exists-vs-forbidden oracle.
- UPDATE and soft-delete use `WHERE id AND revision` +
  `GET DIAGNOSTICS … = ROW_COUNT`, re-reading and returning `conflict`
  on a lost race (per the PL/pgSQL lesson: `FOUND` is unreliable after
  dynamic SQL).

### 034 (SEC-C6/SEC-H16, finance transitions)
- Force-draft triggers bypass via `app.finance_posting='on'` so the
  posting functions can move rows out of draft. The GUC check is a
  string comparison, not a boolean cast.
- Refunds immutability list corrected to `'posted,void'` (was
  `'posted,approved'`).
- `transactions` removed from the sync whitelist; the whitelist array
  was re-derived from the 033 declaration via script to avoid drift.
- JWT-less server flows (service_role) bypass the **approval** gate but
  can never write terminal states directly — the transition guard still
  applies to them.

### 035 (SEC-C5, platform_admins guard)
- `auth.uid() IS NULL` bypass retained for seeds/service_role, but
  service_role is still subject to the last-owner rule (a seed can add
  the first owner; nothing can remove the last one).
- Every change writes an audit row (direct insert into audit_logs —
  `log_audit()` is not used because the trigger fires for
  non-admin writers too).

### 036 (SEC-H1, grant ceilings)
- `tenant_role_rank()` is defined in SQL as the single source of
  truth; the Edge Function keeps its own copy for client-side UX but
  the database is authoritative.

### 037 (SEC-H6, tenants column guard)
- `logo_url` may only be written to the tenant's own
  `tenant-logos/<tenant_id>/` prefix by a `settings.update` holder;
  anything else is platform-admin-only.

### 038 (SEC-H6, suspension enforcement)
- **Split-brain fixed:** `manage-tenant` writes the `status` string, so
  the `suspended` boolean is now **derived** from `status` by trigger
  (`tenants_sync_suspension_flag`) — one source of truth, readable both
  ways. `check_tenant_access()` and `is_tenant_member()` read the same
  status string + `expires_at`.
- **UX carve-out:** members of a suspended tenant can still SELECT their
  own tenant row (to see the suspension message); every other policy
  goes dark through `is_tenant_member()`.

### 039 (SEC-H5, user_accounts.tenant_id)
- **NOT NULL decision:** the column is SET NOT NULL after backfill.
  Backfill order: `linked_staff_id → staff.tenant_id`, then
  `email → auth.users → earliest active membership`. Rows that match
  neither **fail the migration loudly** (transactional rollback) —
  the applier must assign them a tenant and re-run. The alternative
  (leaving it nullable) would have kept the cross-tenant leak open.
- The app's `user_management_provider` inserts without `tenant_id`;
  a BEFORE INSERT trigger fills it when the caller has exactly one
  active tenant. **Multi-tenant managers get a clear error and the
  client must be updated to send `tenant_id`** (follow-up).
- `role_name` is platform-admin-only for writes (forced to `teacher`
  on insert, ignored on update for non-platform callers). This is
  display metadata today, but it must not become a trust anchor.
  Tenant managers creating e.g. a principal account will see the
  display role reset until a platform admin sets it — **client
  follow-up**: send role via `manage-users`, which validates it.

### 040 (SEC-H9, storage)
- `tenant-exports` created PRIVATE with platform-admin-only policies.
  If it already existed as a public manual bucket, it is forced
  private.
- Photo SELECT aligned with row policies: student photos additionally
  readable by the student's parent (`parent_user_id`), staff photos
  require `staff.view`.
- **`documents` bucket dropped.** Verified 2026-10-03: no Flutter or
  Edge Function code references it. Its policies were sound, but
  unused surface is still surface. Deletion is best-effort (never
  fails the migration).

### 041 (SEC-H3, membership writes)
- Tenant callers are SELECT-only; writes are platform-admin-only at
  the RLS layer. Mutations go through `manage-users` (service_role) or
  the hardened RPCs (SECURITY DEFINER, 036 ceilings, 019 last-owner
  backstop). Verified 2026-10-03: the Flutter app performs no direct
  membership writes.

### 042 (validation constraints)
- New CHECKs are **NOT VALID** — they block new bad data immediately
  without failing on dirty legacy rows. Violation-finder queries are
  in the file header; run them, clean up, then `VALIDATE CONSTRAINT`.
- The unconditional legacy uniques on attendance/fees are replaced
  with partial uniques `WHERE deleted_at IS NULL` (soft-deleted rows
  no longer block re-entry).
- `audit_logs.tenant_id` is now `ON DELETE SET NULL` — the audit
  trail outlives the tenant.
- The unique-index creation will fail loudly on live duplicates;
  dedup queries are in the file header.

### 043 (SEC-H12, audit)
- `audit_all_writes()` swallows its own exceptions with a WARNING and
  never blocks the write it observes — an audit outage must not become
  a school-operations outage. Audit gaps will be visible in server
  logs, not silent.
- `log_audit()` uses a **format** allow-list for actions
  (`^[a-z0-9][a-z0-9._-]{1,63}$`), not an enumerated list: the app
  supplies legitimate actions (e.g. `license.revoked`) that an
  enumerated list would break. Payloads are truncated at 64KB with a
  marker, never rejected — the audit row must exist.

### 044 (audit retention)
- Retention function only — **no scheduled job is installed** (a
  migration that silently installs cron jobs is a persistence
  mechanism). The operator schedules it monthly via pg_cron or an
  Edge Function.
- Monthly partitioning was **deliberately deferred**: converting a
  live, FK-referenced table is locking, non-idempotent, and risky;
  batched DELETE is safe on any Postgres at this scale.
- Deletion is final — operators needing long-term archives must add
  an export step to the scheduled job before enabling deletion.

## Apply order and pre-flight

1. Apply 029–044 in order on a staging copy first.
2. Before 039: `SELECT id, email FROM public.user_accounts WHERE tenant_id
   IS NULL;` after backfill — must be empty (039 fails loudly otherwise).
3. Before 042: run the dedup/violation queries in the file header.
4. After 034: verify `app.finance_posting` is not set globally.
5. Client follow-ups required: send `tenant_id` on user_accounts insert
   (039); set `role_name` via manage-users (039); schedule
   `audit_retention()` monthly (044); archive export before enabling
   deletion (044).
