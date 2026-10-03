# Tenant-Isolation Audit — Madrassa-360

**Date:** 2026-10-03 · **Scope:** `~/workspace/madrassa-redesign-fix`, branch `redesign/ux-v2`
**Method:** read-only static analysis of `supabase/migrations/` (001–028), `supabase/functions/`
(5 Edge Functions), and the Flutter app (`lib/`). Threat model: **Tenant A's malicious admin
with a valid JWT + the anon key**. Tenant isolation is treated as a critical security boundary.
Rule applied throughout: tenant identity must be **derived from `auth.uid()`** (via
`tenant_memberships` / `user_effective_permission` / `check_tenant_access()`), never from a
client-supplied `tenant_id`.

**Verification caveat:** findings are from static analysis of the migration files and app code.
Anything marked "verify live" should be re-asserted against the live project
(`ffhsrnkvjjedvclfwgmr`) before remediation is declared complete.

---

## CRITICAL findings

### C1. `sync_apply` enforces membership only — the entire RBAC permission model is bypassed
- **Location:** `supabase/migrations/016_sync.sql` (`public.sync_apply`, `SECURITY DEFINER`,
  executable by PUBLIC/authenticated — no GRANT/REVOKE in the migration, so default PUBLIC
  execute applies)
- **Problem:** For `insert`, `update`, and `delete`, the function checks only
  `public.is_platform_admin() OR public.is_tenant_member(v_tenant)`. It **never calls
  `tenant_has_permission()`**. Every RLS policy on the 26 whitelisted tables gates writes
  behind permission codes (`students.create`, `attendance.mark`, `fees.collect`,
  `finance.approve`, …), but `sync_apply` bypasses RLS entirely (SECURITY DEFINER) and
  re-implements authorization as membership-only.
- **Why it matters:** The offline-first Flutter app performs ALL writes through `sync_apply`
  (see `lib/core/sync/sync_engine.dart`). Any active tenant member — including the low-privilege
  `parent` and `student` template roles — can write to any table in their tenant.
- **Exploit scenario:** Tenant A onboards a parent account (or the attacker registers one).
  With the parent JWT they call
  `rpc('sync_apply', {p_entity:'invoices', p_op:'update', p_entity_id:<any invoice id>,
  p_base_revision:<current>, p_payload:{amount_paisa: 1}})`.
  Membership check passes (they are a member of tenant A). No permission check exists, so the
  invoice amount is rewritten. Same path allows: creating students, marking attendance for any
  class, posting expenses, soft-deleting any row (`p_op:'delete'` needs no permission either),
  and — via `update` — flipping `status` columns (`draft→approved→posted`) because the
  UPDATE column whitelist excludes `tenant_id`/`revision` but **not** `status`, `amount`,
  `parent_user_id`, etc.
- **Recommended fix:** Inside `sync_apply`, map `(entity, op)` → required permission code and
  enforce `public.tenant_has_permission(v_tenant, <code>)` for every branch (insert/update/delete),
  mirroring the RLS policies. Add `status`-transition rules equivalent to the 014 policies
  (draft-only edits). Add regression tests: parent-role JWT attempting each op must fail.

### C2. `tenants_member_update` allows self-unsuspension and license tampering (mass assignment)
- **Location:** `supabase/migrations/027_user_accounts_app_roles.sql` lines 186–196
  (policy `tenants_member_update` on `public.tenants`); columns added in
  `023_super_admin.sql` (`suspended`, `suspension_reason`, `suspended_at`, `expires_at`,
  `admin_message`, `admin_message_at`)
- **Problem:** The policy gates UPDATE on `is_tenant_member(id) AND tenant_has_permission(id,
  'settings.update')` but restricts **no columns**. RLS cannot do column-level grants, so any
  holder of `settings.update` (a normal tenant admin) can PATCH any column of their tenant row.
- **Why it matters:** `check_tenant_access()` (023) denies app access when `t.suspended` is true
  or `expires_at` passed — this is the platform's enforcement lever for billing/suspension.
- **Exploit scenario:** Tenant A's subscription expires (or platform suspends them for abuse).
  The tenant admin (still holding a valid JWT, `settings.update` permission) issues
  `PATCH /rest/v1/tenants?id=eq.<tenantA> {"suspended": false, "expires_at": "2099-01-01"}`.
  RLS passes. `check_tenant_access()` now returns true. Enforcement defeated without ever
  touching another tenant.
- **Recommended fix:** Add a `BEFORE UPDATE` trigger on `public.tenants` that raises unless
  `public.is_platform_admin()` whenever `OLD.suspended IS DISTINCT FROM NEW.suspended`,
  `OLD.expires_at IS DISTINCT FROM NEW.expires_at`, `OLD.status IS DISTINCT FROM NEW.status`,
  `OLD.admin_message IS DISTINCT FROM NEW.admin_message`, etc. (allow-list: `name`,
  `name_urdu`, `logo_url`, `use_logo_on_reports`, address/contact fields for `settings.update`
  holders). This is intra-tenant privilege containment, and it protects the cross-tenant
  billing boundary.

### C3. `sync_apply` INSERT `already_exists` path returns full rows of any tenant without auth
- **Location:** `supabase/migrations/016_sync.sql`, INSERT branch — the `already_exists`
  check runs **before** `v_tenant` is extracted and before the membership check.
- **Problem:** `EXECUTE … SELECT to_jsonb(t) … WHERE t.id = $1` then
  `RETURN … 'server_row', v_row`. No tenant check precedes the return. The update/delete
  `not_found` path has the same shape (existence oracle without auth), though it returns no row.
- **Why it matters:** Cross-tenant data disclosure for anyone who can learn a row UUID.
- **Exploit scenario:** Attacker (tenant A) learns a UUID of tenant B's student row — e.g. from
  a shared export file, a support ticket, an error message, or the sequential-ID inference in
  M3. They call `sync_apply('students', <B-uuid>, …)` with `p_op='insert'`; the function finds
  the existing row and returns its full JSONB (name, phone, guardian info, …) with no
  membership verification.
- **Recommended fix:** Move the membership check before any row-data return: on `already_exists`,
  resolve the row's tenant and require `is_platform_admin() OR is_tenant_member(row_tenant)`
  before including `server_row`; otherwise return a bare `already_exists` without the row.
  Same for the `not_found` oracle — acceptable to keep, but document it.

---

## HIGH findings

### H1. `madrasas_member_select` tenant scoping is broken (unqualified `id` binds to inner query)
- **Location:** `supabase/migrations/027_user_accounts_app_roles.sql` lines 206–216
- **Problem:** The policy intends per-row scoping —
  `t.tenant_code = 'M-' || upper(substr(replace(madrasas.id::text, '-', ''), 1, 8))`
  (per the comment, and per the `m.id` pattern used in 004/006). As written, the EXISTS
  subquery is `FROM public.tenants t` and the bare `id` resolves to **`t.id`** (innermost scope
  wins in Postgres), not `madrasas.id`. The predicate becomes "exists a tenant whose own code
  matches its own id-derived pattern and the caller is its member" — a property of the
  *tenant*, not the *row*.
- **Why it matters:** For legacy tenants whose `tenant_code` is `M-`+id-derived (the 004
  backfill convention), **any active member can SELECT every row of `public.madrasas`** —
  cross-tenant read of the legacy madrassa table. For new (`T-` random-code) tenants the
  predicate is false, so their reads fail closed (functional break if the app reads `madrasas`).
- **Exploit scenario:** Tenant A (legacy M-code) teacher calls `GET /rest/v1/madrasas` and
  receives all madrassa rows, including tenant B's.
- **Recommended fix:** Qualify the reference: `replace(madrasas.id::text, '-', '')`. Add a
  cross-tenant negative test (A-member cannot read B's madrasa row).

### H2. `user_accounts` SELECT is cross-tenant: any member of any tenant enumerates all accounts
- **Location:** `supabase/migrations/027_user_accounts_app_roles.sql` — policy
  `user_accounts_select_member`: `USING (is_platform_admin() OR EXISTS (any active membership))`
- **Problem:** `user_accounts` deliberately has **no `tenant_id`** (migration comment), so the
  SELECT policy cannot scope per tenant — and instead scopes to *nothing*: any authenticated
  user with at least one active membership anywhere can `SELECT * FROM user_accounts`.
- **Why it matters:** Full enumeration of every user account in the system: `name`, `email`
  (globally unique), `role_name`, `is_active`, linkage ids — across all tenants. Enables
  targeted phishing and cross-tenant user harvesting.
- **Exploit scenario:** Tenant A teacher: `GET /rest/v1/user_accounts?select=*` → all tenants'
  users.
- **Recommended fix:** Product decision required. Options: (a) restrict SELECT to platform
  admins + tenant admins (via `users.view` effective permission), since the table is an admin
  tool; (b) add a join table `user_account_tenants(account_id, tenant_id)` and scope RLS
  through it. Do not leave the current policy.

### H3. Permission-oracle RPCs are directly callable with arbitrary tenant/user arguments
- **Location:** `supabase/migrations/020_role_ux_rls.sql` lines 860–879 —
  `GRANT EXECUTE … TO authenticated` on `user_effective_permission(UUID,UUID,TEXT)`,
  `user_code_denied(UUID,UUID,TEXT)`, `tenant_has_permission(UUID,TEXT)`
- **Problem:** These SECURITY DEFINER helpers take `p_tenant_id`/`p_user_id` as parameters and
  are granted to `authenticated`. They exist for RLS internals, but any JWT holder can call
  them directly with **arbitrary** tenant and user UUIDs, learning whether user X holds
  permission Y in tenant Z — cross-tenant role/permission reconnaissance. `tenant_has_permission`
  additionally oracles tenant existence + permission-code validity.
- **Why it matters:** Recon for targeted attacks (find the tenant's owners/admins, find who
  holds `settings.update`/`users.create`), and tenant-existence probing.
- **Exploit scenario:** Attacker iterates candidate user UUIDs (harvested via H2) against
  `user_effective_permission(<tenantB>, <user>, 'tenant_owner-equivalent codes')` to map
  tenant B's admin set.
- **Recommended fix:** `REVOKE … FROM authenticated` on the parameterized helpers; expose only
  `auth.uid()`-bound wrappers for legitimate client use (`get_my_permissions` already follows
  this pattern). RLS policies keep working (SECURITY DEFINER).

### H4. `send-notification`: any tenant member can broadcast push+email to the whole tenant
- **Location:** `supabase/functions/send-notification/index.ts` — authorization is
  "platform admin OR active member of the tenant" (lines ~203–219); `user_id: null` in the body
  means tenant-wide broadcast
- **Problem:** No `notifications.send` (or equivalent) permission check. The RLS INSERT policy on
  `notifications` is platform-admin-only, so this function is the sole write path — and it
  authorizes on membership alone.
- **Why it matters:** Any compromised/low-privilege account (parent, student) can send
  arbitrary push notifications and emails to every user of their tenant — phishing inside a
  trusted channel (the app's own notification identity).
- **Exploit scenario:** Attacker with a parent-role account POSTs
  `{tenant_id, notification_id, type, title: "فیس کی ادائیگی", channels: ["push","email"]}`
  with a phishing body to all tenant users.
- **Recommended fix:** Require `tenant_has_permission(tenant_id, 'notifications.send')`
  (via the existing `user_effective_permission` RPC over the service client) for broadcast;
  keep membership check for targeted sends, or require the same permission for all sends.

### H5. No local-database wipe on logout — previous tenant's data persists on device
- **Location:** `lib/providers/auth_provider.dart` `_handleSignedOut()` (clears permission caches
  and tenant choice, but never wipes the Drift database); no wipe/reset found in
  `lib/core/sync/sync_engine.dart`
- **Problem:** The offline-first store (`AppDatabase`, synced rows for students/fees/attendance/…)
  survives logout. On a shared device, the next login (different user, possibly different
  tenant) leaves the previous tenant's data on disk, unencrypted.
- **Why it matters:** Cross-user/cross-tenant data remnant; forensic recovery; also stale rows
  from tenant A remain queryable by code paths that forget a tenant filter.
- **Exploit scenario:** Teacher of tenant A logs out on a shared school tablet; a parent from
  tenant B logs in. Tenant A's synced rows remain in the SQLite file, readable by anyone with
  file access (backup, rooted device, `adb pull`).
- **Recommended fix:** On logout (and on account change), delete and recreate the local database
  file, or at minimum delete all tenant-scoped rows. Add a test asserting zero rows post-logout.

---

## MEDIUM findings

### M1. `student-photos` / `staff-photos` SELECT is membership-only (photo privacy vs row RLS)
- **Location:** `supabase/migrations/008_tenant_storage.sql` — `student_photos_select_tenant`:
  `USING (bucket_id='student-photos' AND is_tenant_member(storage_path_tenant(name)))`
- **Problem:** The `students` table SELECT restricts to `students.view` holders or the child's own
  parent, but the photo bucket lets **any** tenant member fetch **any** student photo by path.
  A parent with no `students.view` can enumerate `{tenant_id}/{student_id}.jpg`-style paths and
  download photos of other families' children. (Path structure determines enumerability —
  verify live; even non-enumerable, direct URLs shared anywhere leak.)
- **Fix:** Mirror the row policy in the storage policy: require `students.view` permission or
  parent-of-the-student (derive student id from path segment).

### M2. Globally sequential invoice/receipt numbers leak cross-tenant volume
- **Location:** `supabase/migrations/028_finance_per_table_doc_triggers.sql` —
  `nextval('public.finance_invoice_seq')`, `finance_receipt_seq` are **global** sequences
- **Problem:** `INV-00000103` observed by tenant A, then `INV-00000105` after their own invoice,
  tells them another tenant issued an invoice in between — business-volume inference across
  tenants. Numbers are also returned in API payloads/exports.
- **Fix:** Per-tenant sequences (e.g. `finance_doc_seq_<tenant>` created at provisioning, or a
  counter table keyed by tenant with `SELECT … FOR UPDATE`), or append a random component.

### M3. `switchTenant()` does not validate membership client-side
- **Location:** `lib/core/services/tenant_context.dart` `switchTenant()` — sets state and
  persists without checking `memberships`; only `init()` validates
- **Problem:** Defense-in-depth gap. A tampered client could set an arbitrary tenant id; server
  RLS currently fails closed (`is_tenant_member` denies), so impact is limited to a broken UI
  state — but the client should never enter an unauthorized tenant context.
- **Fix:** Validate `id` against fresh memberships in `switchTenant()`; refuse + log otherwise.

### M4. Core tables never created in migrations (schema drift)
- **Location:** `students`, `profiles`, `classes`, `staff`, `attendance`, `results`, `exams`,
  `fees`, `darjas`, `library_books`, `book_issues`, `announcements`, `finance_transactions`,
  `madrasas` — referenced by 006/007/009/020/026 but **no `CREATE TABLE` in 001–028**
- **Problem:** The migration set is not self-contained; a fresh project built from migrations
  alone lacks the academic core. Not a live isolation hole (live DB has them), but any
  rebuild/restore or new environment silently diverges — and RLS policies on nonexistent
  tables give false confidence in code review.
- **Fix:** Add a migration that creates the missing tables `IF NOT EXISTS` with the expected
  columns (reconstructed from the demo seed + RLS references), or document the external
  baseline explicitly.

### M5. `check_tenant_access(p_tenant_id)` is a tenant-existence/suspension oracle
- **Location:** `023_super_admin.sql` — granted to `authenticated`, returns boolean for arbitrary
  UUIDs
- **Problem:** Lets anyone probe whether a tenant UUID exists and whether it is suspended/expired.
  UUIDs are unguessable so practical risk is low, but it is cross-tenant information disclosure
  by design.
- **Fix:** Acceptable to keep; document. Optional: rate-limit or require membership for
  non-platform callers.

---

## LOW findings

### L1. `send-notification` client-supplied `notification_id` with `ignoreDuplicates`
- First-writer-wins idempotency key from the client lets a malicious member squat UUIDs to
  block legitimate notifications (minor DoS). Consider server-generated ids or per-tenant
  idempotency scope.

### L2. Realtime posture unverified
- The app uses no Supabase Realtime (offline-first, event-driven re-reads — confirmed: no
  `.channel(` in `lib/`). If the Realtime service is enabled on tables project-wide, direct
  subscribers are still subject to RLS (tenant-scoped). Verify live that `supabase_realtime`
  publication does not expose tables beyond RLS, and consider disabling where unused.

---

## What is already correct (verified)

- **RLS helper root of trust:** `is_platform_admin()`, `is_tenant_member()`, `is_tenant_admin()`
  are `SECURITY DEFINER … SET search_path = public` and derive identity from `auth.uid()` —
  never from client parameters. All per-table tenant policies anchor on these.
- **INSERT tenant binding:** insert policies check `is_tenant_member(NEW.tenant_id)` — a caller
  can only insert into tenants they belong to; no cross-tenant insert via PostgREST.
- **UPDATE `tenant_id` immutability:** `trg_prevent_tenant_id_change` (006) on `students` (and
  `sync_apply` excludes `tenant_id` from its update whitelist) — rows cannot be moved between
  tenants.
- **020 actually replaced the 007 attendance/results policies** (`DROP POLICY IF EXISTS` first) —
  the `scope_allows()` class-scoping is live, not dead code.
- **027 replaced (not duplicated) `fees_delete_tenant`** (`DROP …` before `CREATE`).
- **Edge Functions `export-tenant`, `manage-tenant`, `provision-tenant`, `manage-users`**
  require platform admin (via `requirePlatformAdmin`) or scoped membership+rank checks;
  `tenant_id` in bodies is always cross-checked against the JWT caller's memberships.
- **Storage write path** derives the tenant from the object path's first segment
  (`storage_path_tenant(name)`) and checks membership + permission — correct pattern.
- **`log_audit()`** enforces platform-admin for NULL-tenant entries and tenant-admin for tenant
  entries; `user_id` is forced to `auth.uid()`.
- **`tenant_memberships` SELECT** is self-only (`user_id = auth.uid()`) + tenant/platform admins —
  no cross-tenant membership enumeration for regular users.
- **Global search** (`lib/presentation/widgets/global_search.dart`) and **report/CSV exports**
  operate client-side over the active tenant's already-loaded data — tenant-scoped by
  construction; no server search endpoint exists to abuse.
- **Sync pull** filters `.eq('tenant_id', _tenantId)` client-side, but RLS is the enforcer —
  a tampered `_tenantId` yields zero rows server-side (fail-closed).
- **`TenantContext.init()`** validates the persisted tenant choice against fresh memberships.

---

## (a) TENANT TRUST TABLE

| # | Data path | Tenant derived from auth? | Client-supplied tenant trusted? | Verdict |
|---|---|---|---|---|
| 1 | PostgREST SELECT/INSERT/UPDATE/DELETE on 25+ tenant tables (007/014/020) | ✅ `auth.uid()` → memberships → `tenant_id` | No (RLS re-derives) | **PASS** |
| 2 | `sync_apply` insert/update/delete (016) | ⚠️ membership only — **no permission check** | `tenant_id` from payload for insert (membership-checked) | **FAIL** (C1) |
| 3 | `sync_apply` `already_exists` row return (016) | ❌ none before return | n/a | **FAIL** (C3) |
| 4 | `tenants` UPDATE (027) | ✅ membership+permission | — | **PARTIAL** (C2: no column guard) |
| 5 | `madrasas` SELECT (027) | ❌ broken scoping (`id` binds to `tenants.id`) | — | **FAIL** (H1) |
| 6 | `user_accounts` SELECT (027) | ❌ any-membership = all rows | — | **FAIL** (H2) |
| 7 | `user_effective_permission` / `user_code_denied` / `tenant_has_permission` direct RPC | ❌ arbitrary args, granted to authenticated | Yes (args) | **FAIL** (H3) |
| 8 | `check_tenant_access` / `get_my_permissions*` RPCs | ✅ `auth.uid()` | No | **PASS** (M5 note) |
| 9 | `log_audit()` RPC (012) | ✅ `auth.uid()` + admin checks | `p_tenant_id` verified, not trusted | **PASS** |
| 10 | `send-notification` Edge Function | ⚠️ membership only, no permission | `tenant_id` from body (membership-verified) | **PARTIAL** (H4) |
| 11 | `export-tenant` / `manage-tenant` / `provision-tenant` / `manage-users` | ✅ platform-admin or scoped rank/permission | Verified, not trusted | **PASS** |
| 12 | Storage `tenant-logos` writes (024) | ✅ path segment → membership + `settings.update` | Path chosen by client, tenant re-derived | **PASS** |
| 13 | Storage `student-photos`/`staff-photos` reads (008) | ⚠️ membership only (no `students.view`) | — | **PARTIAL** (M1) |
| 14 | Sync pull / app queries `.eq('tenant_id', …)` | ✅ RLS backstop (fail-closed) | Filter only, not trust | **PASS** |
| 15 | Global search, PDF/CSV exports | ✅ client-side over active-tenant data | n/a | **PASS** |
| 16 | Realtime subscriptions | n/a (unused by app) | — | **VERIFY LIVE** (L2) |
| 17 | Local Drift cache across logout | ❌ no wipe | — | **FAIL** (H5) |
| 18 | Invoice/receipt numbers (028) | ❌ global sequences | — | **PARTIAL** (M2) |
| 19 | `switchTenant()` client context | ⚠️ not validated (server fail-closed) | `id` param | **PARTIAL** (M3) |
| 20 | Background jobs / cron | none found in migrations | — | **PASS** (none) |

---

## (b) Prioritized fix list

1. **C1** — Add per-entity/operation permission enforcement inside `sync_apply` (mirror RLS codes;
   block `status` transitions except via the legal workflow). This single fix closes the largest
   hole: every offline write path.
2. **C2** — `BEFORE UPDATE` trigger on `tenants` protecting `suspended`, `expires_at`, `status`,
   `admin_message*` (platform-admin-only).
3. **C3** — Move tenant-membership check before any `server_row` return in `sync_apply`.
4. **H1** — Qualify `madrasas.id` in `madrasas_member_select`.
5. **H2** — Restrict `user_accounts` SELECT (platform admin + `users.view` holders) or add a
   tenant-link table and scope through it.
6. **H3** — Revoke `authenticated` EXECUTE on parameterized permission helpers; keep
   `auth.uid()`-bound wrappers.
7. **H4** — Require `notifications.send` effective permission in `send-notification`.
8. **H5** — Wipe/recreate the local Drift DB on logout and on account switch.
9. **M1** — Align `student-photos` SELECT policy with the `students` row policy.
10. **M2** — Per-tenant document sequences (or random suffix) for invoice/receipt numbers.
11. **M3** — Validate `switchTenant(id)` against memberships.
12. **M4** — Add the missing `CREATE TABLE` baseline migration for the 14 pre-existing tables.

All fixes are migration/Edge-Function/Dart changes — implement in the branch, test, then apply
migrations to live only with explicit approval (production DB).

---

## (c) Automated cross-tenant isolation test plan

**Fixture setup (test harness, service-role):** create tenants A and B; users:
`a_owner` (tenant_owner of A), `a_parent` (parent role, member of A, minimal permissions),
`b_owner`, `b_teacher` (member of B). Obtain real JWTs per user (sign-in via Auth API).
All negative tests assert **denial / empty results**; positive controls assert the same
operation succeeds intra-tenant.

### DB / RLS boundary (run against live or a staging clone)
1. **Read isolation:** as `a_parent`, `GET /rest/v1/students`, `/invoices`, `/attendance`,
   `/results` → assert zero rows from tenant B (and only permitted rows of A).
2. **Write isolation:** as `a_parent`, `POST /rest/v1/students {tenant_id: B, …}` → 403/empty;
   `PATCH /rest/v1/students?id=eq.<B-student>` → 0 rows affected; `DELETE` → 0 rows.
3. **`tenant_id` move attempt:** `PATCH` own row with `tenant_id: B` → trigger blocks
   (`trg_prevent_tenant_id_change`) — assert error and unchanged row.
4. **`user_accounts`:** as `a_parent`, `GET /rest/v1/user_accounts` → after fix: 403 or only
   own-tenant-visible rows; assert no B-user emails leak (before fix this FAILS — good canary).
5. **`madrasas`:** as `a_parent` (legacy M-code tenant), `GET /rest/v1/madrasas` → assert no rows
   belonging to other madrassas (before fix this FAILS — canary for H1).
6. **RPC oracles:** as `a_parent`, `rpc('user_effective_permission',
   {p_tenant_id: B, p_user_id: <b_owner>, p_code: 'settings.update'})` → after fix: permission
   denied; `rpc('tenant_has_permission', …)` likewise.
7. **`check_tenant_access`:** as `a_parent` with B's id → false; with A's id → true.

### `sync_apply` boundary (the C1/C3 canaries)
8. **Permission bypass:** as `a_parent` (no `students.create`), `rpc('sync_apply',
   {p_entity:'students', p_op:'insert', p_payload:{tenant_id: A, name:'X', …}})` → after fix:
   exception/denied. Repeat for `update` on invoices (amount change) and `delete` on attendance.
9. **Status workflow bypass:** as `a_owner` (has fees.collect but not finance.approve),
   `sync_apply` update setting `invoices.status='approved'` on a draft → denied after fix.
10. **Cross-tenant row oracle:** as `a_owner`, `sync_apply('students', <B-student-uuid>, insert)`
    → after fix: `already_exists` WITHOUT `server_row`, or `not_found`-equivalent; assert no B
    data in response.
11. **Cross-tenant write:** `sync_apply` update/delete with B's row id → `not_found` / membership
    exception; assert B's row unchanged.

### Tenant-row protection (C2)
12. As `a_owner` (has `settings.update`), `PATCH /rest/v1/tenants?id=eq.<A>
    {"suspended": false, "expires_at": "2099-01-01"}` → after fix: trigger raises / columns
    unchanged; legitimate fields (`name`, `logo_url`) still updatable (positive control).

### Edge Functions
13. **send-notification:** as `a_parent` (no `notifications.send`), broadcast to A → 403 after
    fix; as `a_owner` (with permission) → 200. As `a_owner`, send with `tenant_id: B` → 403.
    Targeted send to `user_id` of B's member → 400/403.
14. **export-tenant / manage-tenant:** as `a_owner` → 401/403 (platform-admin only).

### Storage
15. As `a_parent`, `GET` object at `student-photos/<B-tenant>/<photo>` → denied. `PUT` under
    `<B-tenant>/…` → denied. After M1 fix: `GET` of another family's photo within A without
    `students.view` → denied.
16. `tenant-logos`: as `a_parent` (no `settings.update`), `PUT <A>/logo.png` → denied; as
    `a_owner` → allowed; `PUT <B>/logo.png` as `a_owner` → denied.

### App / device
17. **Logout wipe:** seed local DB, logout, assert all tenant tables empty on disk (H5).
18. **Tenant switch:** set tampered tenant id via `switchTenant(<B>)` as A-only user → after fix:
    refused; data providers return [] and no network rows leak (RLS already denies — assert the
    client never enters the context).
19. **Sequence inference:** create invoice in A, read its number; assert it reveals nothing about
    B's invoice count (after M2: per-tenant numbering).

### Where to implement
- DB/RLS/RPC/storage tests: **pgTAP** (`pgTAP` in a staging project) or a Dart integration test
  using the service role for fixtures and per-user JWTs for assertions. Mark every test above
  with the finding id (C1…M5) so regressions map 1:1 to this audit.
- App/device tests: `flutter test` integration tests with a fake per-tenant backend or against
  staging; the logout-wipe test can run with an in-memory Drift database.
- Run the full isolation suite in CI on every migration change (it is the tenant-boundary
  contract).
