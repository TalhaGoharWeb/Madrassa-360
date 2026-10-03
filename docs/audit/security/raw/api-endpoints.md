# API Endpoint Security Audit — Madrassa-360

**Date:** 2026-10-03 · **Branch:** `redesign/ux-v2` · **Scope:** full API surface (PostgREST + RPC + Edge Functions)
**Method:** static analysis of `supabase/migrations/001–028`, `supabase/functions/*`, and the Flutter client's
server-call sites. Read-only; no code modified. Adversarial model: attacker holds a valid low-privilege
tenant account + the anon key, and can call any endpoint directly (curl), bypassing the app.

---

## 1. Endpoint inventory

Conventions: AUTHENTICATION is `JWT (anon key)` for PostgREST/RPC (Supabase Auth JWT, RLS applies unless
a `SECURITY DEFINER` function bypasses it) and `Bearer JWT` for Edge Functions (verified via
`auth.getUser()` server-side). RATE LIMIT is `none` everywhere unless noted — **no application-level
rate limiting exists on any endpoint** (only Supabase platform-level caps). PostgREST default page size
is 1000 rows when the client omits `limit`.

### A. PostgREST — `METHOD /rest/v1/<table>`

~55 tables are auto-exposed. They fall into five authorization models:

| # | Table group | Tables | Read rule | Write rule |
|---|---|---|---|---|
| A1 | 13 legacy business tables | `darjas, classes, students, staff, attendance, fees, exams, results, announcements, darja_sections, library_books, book_issues, finance_transactions` | tenant member (`<t>_select_tenant`, 007) | tenant member; fee delete requires `fees.delete` (027, unseeded → fail-closed) |
| A2 | 13 finance tables | `accounts, fee_structures, fee_items, invoices, invoice_items, payments, payment_allocations, refunds, discounts, scholarships, expenses, income, transactions` | tenant member **+ permission code** (e.g. `fees.view`, 014) | tenant member **+ permission code** (e.g. `fees.create` + `status='draft'` for invoices, 014) |
| A3 | Tenant platform tables | `tenants` (select: own tenants; update: `settings.update`), `tenant_settings`, `tenant_modules`, `tenant_memberships`, `tenant_roles`, `tenant_role_permissions`, `roles`, `role_permissions`, `permissions`, `user_permissions` (write: `roles.assign`), `permission_scopes`, `permission_delegations`, `licenses`, `license_plans`, `modules_catalog`, `tenant_subscriptions`, `platform_config`, `student_guardians`, `teacher_class_assignments` | scoped (member/admin/permission) | scoped |
| A4 | Cross-tenant / privileged | `platform_admins` (FOR ALL: `is_platform_admin()`), `super_admins`, `user_accounts` (select: **any active member of any tenant**), `app_roles` (select: any authenticated), `audit_logs` (select: platform admin or tenant admin of that tenant; insert: `log_audit` RPC only), `profiles` (own / shared-tenant / platform), `madrasas` (own tenant), `devices`, `device_sessions`, `notifications` (own/tenant), `notification_preferences`, `notification_device_tokens` (own only) | see findings | see findings |
| A5 | Internal | `schema_migrations` | RLS state UNKNOWN statically — verify no SELECT policy leaks ledger (low value) | — |

Storage (also HTTP API surface): buckets `student-photos`, `staff-photos`, `documents` (private,
tenant-path-bound policies, 008) and `tenant-logos` (public read, tenant-bound writes, 024).
`tenant-exports` bucket is referenced by `export-tenant` but **created by no migration** (broken).

### B. RPC — `POST /rest/v1/rpc/<function>` (all require authenticated JWT unless noted)

| Function | SECURITY DEFINER | Auth check inside | Who may call (grant) | Purpose |
|---|---|---|---|---|
| `sync_apply(TEXT,UUID,INT,JSONB,TEXT)` | YES | `auth.uid()` non-null; `is_platform_admin()` OR `is_tenant_member(tenant)` | authenticated | offline-sync write path, 26 tables |
| `assign_tenant_role(UUID,UUID,TEXT)` | YES | `is_tenant_admin(t)` OR `tenant_has_permission(t,'roles.assign')` | authenticated | grant tenant role |
| `set_user_permission(UUID,UUID,TEXT,TEXT)` | YES | same as above | authenticated | per-user grant/deny override |
| `set_role_permissions(UUID,TEXT[])` | YES | same as above | authenticated | rewrite a role's permission set |
| `create_tenant_role(UUID,TEXT,TEXT,TEXT)` | YES | same as above | authenticated | create tenant role (optionally clone template) |
| `delegate_permission(UUID,UUID,TEXT,TEXT,JSONB,TSTZ)` | YES | caller must hold `roles.assign` **and** hold `p_code` itself; ceiling trigger re-checks | authenticated | temporary delegation |
| `log_audit(UUID,TEXT,TEXT,TEXT,JSONB,JSONB,JSONB)` | YES | platform-level ⇒ platform admin; tenant-level ⇒ tenant admin/owner | authenticated | client-safe audit writer |
| `check_tenant_access(UUID)` | YES | n/a (read-only boolean) | authenticated | membership + not-suspended + not-expired |
| `is_super_admin()` / `is_platform_admin()` / `is_tenant_member(UUID)` / `is_tenant_admin(UUID)` | YES | n/a | authenticated | predicate helpers (also used by RLS) |
| `tenant_has_permission(UUID,TEXT)` | YES | n/a | authenticated | permission predicate |
| `get_my_permissions(UUID)` / `get_my_permissions_detailed(UUID)` / `user_effective_permission(UUID,UUID,TEXT)` / `scope_allows(...)` / `result_class_id(...)` / `user_is_tenant_admin(...)` / `user_code_denied(...)` | YES | n/a (self-scoped reads) | authenticated | permission introspection |
| `finance_refresh_invoice_status(UUID)` / `finance_recalc_invoice(UUID)` | (verify) | UNKNOWN statically | authenticated (presumed) | invoice math |
| `provision_role_templates(UUID)` | (verify) | called by provision-tenant (service role) | — | seed role templates |
| `slugify(TEXT)`, `set_updated_at()`, trigger fns (`finance_post_*`, `finance_fill_*`, `prevent_tenant_id_change`, …) | n/a | trigger context | n/a | not meaningful direct-call targets |

### C. Edge Functions — `POST /functions/v1/<name>`

| Function | Auth | Role | Input | Output | DB access | Rate limit | Security requirements |
|---|---|---|---|---|---|---|---|
| `provision-tenant` | Bearer JWT → `requirePlatformAdmin` | platform admin | tenant fields + `admin:{name,email,password}` | tenant_id, slug, admin_user_id | service role: tenants, settings, modules, subscriptions, licenses, auth admin, role templates, memberships, audit | none | platform-admin only; compensating cleanup on partial failure |
| `manage-tenant` | Bearer JWT → `requirePlatformAdmin` | platform admin | `{tenant_id, action: suspend\|reactivate\|archive, reason?}` | tenant_id, status, changed | service role: tenants, audit_logs | none | platform-admin only; idempotent |
| `manage-users` | Bearer JWT → `resolveCaller` (platform_admins or tenant membership + effective permissions) | platform admin **or** tenant owner/admin **or** holders of `users.view` / `roles.assign` / `users.deactivate` | `{action, …}` 9 actions | user records (email, ban state, tenants) | service role: auth admin API + all user tables | none | rank gates, last-owner protection, audit |
| `export-tenant` | Bearer JWT → `requirePlatformAdmin` | platform admin | `{tenant_id}` | storage path + manifest (no row data) | service role: 21 tables `select("*")` paged | none | platform-admin only; **bucket `tenant-exports` does not exist (broken)** |
| `send-notification` | Bearer JWT → platform admin OR active tenant member | any active member | `{tenant_id, notification_id, user_id?, type, title, …, channels:[push\|email]}` | per-channel status | service role: notifications, memberships, tokens, prefs, auth admin emails | none | member-of-tenant; target must be same-tenant member; idempotent upsert |

---

## 2. Findings

### CRITICAL

#### C1 — `platform_support` can self-promote to `platform_owner` and delete owners via direct PostgREST calls
- **Location:** `supabase/migrations/004_memberships.sql:272-275` (RLS policy `"platform admins only" FOR ALL USING (is_platform_admin())`); client: `lib/presentation/screens/master_admin/platform_users_screen.dart:144,214`.
- **Problem:** The only server-side guard on `platform_admins` is "caller is any platform admin". There is no
  trigger distinguishing `platform_owner` from `platform_support`, and no last-owner backstop in the database.
  The Flutter screen adds client-side last-owner checks and typed confirmation — all bypassable.
- **Why it matters:** Platform admins are the highest privilege tier (they can suspend tenants, export all
  data, manage users). A support-tier admin is one raw HTTP call away from full ownership.
- **Attack scenario:** A `platform_support` user (legitimately onboarded for helpdesk) runs
  `PATCH /rest/v1/platform_admins?user_id=eq.<own-uuid>` with `{"role":"platform_owner"}` using the anon key
  and their own JWT → RLS passes (`is_platform_admin()` true) → they are now platform owner. Alternatively
  `DELETE /rest/v1/platform_admins?role=eq.platform_owner` removes all owners → permanent administrative
  lockout / denial of administration.
- **Fix:** Add a `BEFORE INSERT OR UPDATE OR DELETE` trigger on `platform_admins`: (a) only a current
  `platform_owner` may change `role` to/from `platform_owner` or delete an owner row; (b) refuse to delete
  or demote the last `platform_owner`; (c) audit the change. Route the Flutter screen through the
  `manage-users` `set_platform_role` action (which already enforces owner-only + last-admin) instead of
  direct table writes, so there is exactly one privileged path.

#### C2 — `sync_apply`: any tenant member can write financial tables, bypassing permission codes
- **Location:** `supabase/migrations/016_sync.sql:203+` (as revised by `027_user_accounts_app_roles.sql:241+`).
- **Problem:** `sync_apply` is `SECURITY DEFINER` (bypasses RLS) and its only authorization is
  `is_platform_admin() OR is_tenant_member(tenant_id)`. The fine-grained permission codes that RLS enforces
  on direct access (`fees.create`, `fees.collect`, `finance.approve`, …) are explicitly **not** checked here
  ("remain enforced by RLS on direct table access, not by this RPC" — 016 header). The app's write path goes
  through `sync_apply` (`lib/core/sync/sync_engine.dart:857`), so the permission layer is dead for writes.
- **Why it matters:** A teacher with only attendance rights can insert `payments`, `refunds`, `discounts`,
  `expenses`, or `invoices` rows for their tenant — fabricating financial records the UI would never offer them.
- **Attack scenario:** Attacker with a low-privilege teacher account calls
  `POST /rest/v1/rpc/sync_apply` with `p_entity='refunds'`, `p_op='insert'`, payload
  `{tenant_id:'<own-tenant>', amount: 50000, …}` → membership check passes → row written with a real
  receipt number from the sequence. The finance immutability guard only protects *final* rows, not creation.
- **Fix:** Per-table (entity, op) → required permission-code map inside `sync_apply`, checked via
  `tenant_has_permission(v_tenant, code)` before any write (fail closed on unknown entity). E.g.
  `payments/invoices/refunds/discounts/expenses/income` inserts require `fees.create`/`finance.record`;
  updates require the matching manage code. Keep the membership check as the floor, permission as the gate.
  Add regression tests calling `sync_apply` as a permission-less member and asserting rejection.

### HIGH

#### H1 — `assign_tenant_role` lets a `roles.assign` holder grant `tenant_owner` (including to self)
- **Location:** `supabase/migrations/020_role_ux_rls.sql:580-608`.
- **Problem:** Authorization is `is_tenant_admin(t) OR tenant_has_permission(t,'roles.assign')` with no rank
  ceiling and no self-grant prohibition. The 019 `tenant_memberships_validate_role` trigger only validates that
  the key is an active role — `tenant_owner` is a valid key. The rank gate exists only in the `manage-users`
  Edge Function (`assignRoleGate`), not in the RPC every client can call directly.
- **Attack scenario:** A user holding `roles.assign` (e.g. via a custom HR role) calls
  `rpc('assign_tenant_role', {p_tenant_id, p_user_id: <self>, p_role_key:'tenant_owner'})` → 200 → full
  tenant ownership. Two-step variant: `create_tenant_role` (clone of a powerful template) then assign.
- **Fix:** In the RPC, replicate the Edge Function's rank rule: non-owner callers may not assign `tenant_owner`
  (or any role at/above their own); forbid self-assignment of `tenant_owner` unless caller is platform admin.
  Preferably extract the rank table into SQL so both paths share one source of truth.

#### H2 — `set_user_permission` / direct `user_permissions` writes allow self-grant of any permission
- **Location:** `supabase/migrations/020_role_ux_rls.sql:677-712` (RPC); policy `"role managers write user_permissions"`
  (`020:463-467`, `USING/WITH CHECK` = `is_tenant_admin(t)` OR `tenant_has_permission(t,'roles.assign')`).
- **Problem:** No ceiling: a `roles.assign` holder can `INSERT`/`UPDATE` `user_permissions` granting
  **themselves** any code (`finance.approve`, `users.manage`, …) — via RPC or raw PostgREST. `delegate_permission`
  has a ceiling trigger (`permission_delegations_ceiling`); `user_permissions` has none (only an audit trigger).
- **Attack scenario:** Teacher with `roles.assign` calls `rpc('set_user_permission',
  {p_tenant_id, p_user_id:<self>, p_code:'finance.approve', p_effect:'grant'})` → 200 → can now approve
  financial transactions tenant-wide.
- **Fix:** Add a `BEFORE INSERT OR UPDATE` trigger on `user_permissions`: (a) forbid grants where
  `user_id = created_by` (no self-grant) unless caller is platform admin; (b) forbid granting codes the
  grantor does not effectively hold (mirror `delegation_ceiling_check`); (c) keep the RPC and the RLS policy
  consistent with the trigger so there is one rule.

#### H3 — `set_role_permissions` enables privilege build-up chained with H1
- **Location:** `supabase/migrations/020_role_ux_rls.sql:611-675`.
- **Problem:** A `roles.assign` holder can add **any** permission code to **any** role in their tenant
  (the only backstop is "don't remove the last `roles.assign`"). Combined with H1 (assign any role to anyone),
  a `roles.assign` holder can manufacture an omnipotent role and take it.
- **Fix:** Same rank/ceiling treatment as H1/H2: callers may only grant codes they themselves hold
  (unless platform admin), and may not modify the `tenant_owner` role's permission set.

#### H4 — `user_accounts` readable cross-tenant by every active member
- **Location:** `supabase/migrations/027_user_accounts_app_roles.sql:93-101`.
- **Problem:** `FOR SELECT USING (is_platform_admin() OR EXISTS (active membership in ANY tenant))` — the table
  has no `tenant_id`, so **any teacher/parent in any tenant can `SELECT *` all user accounts**: names + emails
  of every user across all tenants (acknowledged as a known limitation in the migration header).
- **Attack scenario:** Attacker enrolls (or is legitimately) a low-privilege user in tenant A, then scrapes
  `GET /rest/v1/user_accounts?select=name,email` → harvests the full cross-tenant user directory for
  phishing / social engineering.
- **Fix (short term):** Restrict SELECT to `is_platform_admin()` OR holders of `users.view`/`users.update` in
  ≥1 tenant (the user-management audience), not every member. (Long term: add `tenant_id` or a
  `user_account_tenants` mapping table and scope per-row.)

#### H5 — Zero rate limiting on every endpoint; expensive operations are unauthenticated-cost-free to invoke
- **Location:** all Edge Functions (`supabase/functions/*/index.ts`); all RPCs; PostgREST (platform caps only).
- **Problem:** No per-endpoint throttling. `export-tenant` does a full 21-table scan + in-memory assembly;
  `send-notification` fans out up to 2000 sequential FCM calls + up to 200 `auth.admin.getUserById` calls;
  `manage-users:list_users` does N+1 `getUserById` calls. Any authenticated caller (even low-privilege, for
  `send-notification`) can repeatedly trigger these → compute/egress cost, function timeouts, and effective DoS.
  Login brute-force likewise has no application-level throttle (Supabase Auth platform limits only).
- **Attack scenario:** Attacker with a throwaway tenant-member account loops `send-notification` broadcasts
  → thousands of FCM/Resend invocations per minute on the project's bill; or loops `export-tenant`
  (if they compromise a platform-admin token) → repeated full-table scans.
- **Fix:** Add a shared Edge Function middleware: per-caller (JWT sub) token-bucket limits, stricter for
  expensive actions (export: e.g. 5/hour; send-notification broadcast: e.g. 30/min; manage-users: 120/min),
  returning `429` with `Retry-After`. For RPCs, add a lightweight `rate_limit_check()` SECURITY DEFINER
  function backed by a `rate_limit_buckets` table, called at the top of mutating RPCs. Log 429s structurally.

### MEDIUM

#### M1 — `manage-users:update_user` permits arbitrary `app_metadata` writes; client trusts `app_metadata.role`
- **Location:** `supabase/functions/manage-users/index.ts` (`handleUpdateUser` passes `app_metadata` through);
  `lib/data/repositories/auth_repository.dart:78` (`AppUser.fromSupabase` prefers `app_metadata['role']`).
- **Problem:** A tenant admin can set any `app_metadata` (e.g. `{"role":"superAdmin"}`) on any user they manage
  (self-mutation is blocked, but a second colluding account is not). The client builds `AppUser.role` from
  that value. Server-side enforcement uses `platform_admins`/`tenant_memberships` (safe), so this is
  client-side role confusion, not data access — but it can unlock admin UI surfaces and mislead audit.
- **Fix:** Allowlist `app_metadata` keys in `handleUpdateUser` (deny `role` and any auth-adjacent keys, or
  strip `app_metadata` from non-platform callers entirely); change the client to resolve role from
  `tenant_memberships`/permissions only.

#### M2 — Logo upload to a public bucket has no server-side file validation
- **Location:** `lib/services/tenant_logo_service.dart:58-75`; `supabase/migrations/024_tenant_logos.sql`.
- **Problem:** The 5 MB limit and PNG assumption are client-side only; the storage policy checks tenancy, not
  content. A `settings.update` holder calling the storage API directly can upload arbitrary bytes of any size
  to `tenant-logos/<tenant_id>/logo.png` (public URL, predictable path) — storage abuse / content spoofing on
  official documents (the logo prints on reports). `contentType` is forced to `image/png` by the client, but
  a direct API caller controls it.
- **Fix:** Validate server-side: either a `BEFORE INSERT` trigger on `storage.objects` for this bucket
  checking magic bytes/size via `length()`, or move logo upload behind a small Edge Function that verifies
  PNG/JPEG magic bytes, dimensions, and size before writing with the service role.

#### M3 — Unbounded list queries (no pagination caps in the app)
- **Location:** e.g. `lib/data/repositories/finance_repository.dart:594` (`getPayments`: no `.limit()`,
  plus a `students(name)` embed); similar patterns across repositories (only ~14 `.limit(` call sites in `lib/`).
- **Problem:** RLS scopes rows to the tenant, but a large tenant's full `payments`/`students`/`attendance`
  table is returned in one response — slow, memory-heavy, and a full-dataset scrape in a single request.
  (PostgREST caps at 1000 rows by default, which bounds the worst case but still permits cheap paging scrapes.)
- **Fix:** Add `.limit()` + keyset pagination (`.lt('created_at', cursor)` / `.range()`) to every list query;
  never rely on the client to stop paging.

#### M4 — Fee collection has no idempotency key (double-charge on retry races)
- **Location:** `lib/data/repositories/finance_repository.dart:616` (`recordPayment`: client-UUID insert, then
  sync); `sync_apply` insert path (`016`).
- **Problem:** Retry-with-same-UUID is safe (`already_exists`), but two offline devices (or a double-tap racing
  two local inserts with different UUIDs) can post two payments against one invoice. No server-side
  overpayment guard was found in `finance_post_payment`.
- **Fix:** Add an idempotency column (e.g. `client_ref` UNIQUE per tenant) on `payments`; on conflict return
  the existing row. Add a trigger guard refusing payments that would overpay a non-draft invoice beyond its
  balance, or at minimum surface overpayment in `finance_recalc_invoice`.

#### M5 — Wildcard CORS on privileged Edge Functions
- **Location:** `supabase/functions/_shared/guard.ts:14-19` (`Access-Control-Allow-Origin: *` on every response).
- **Problem:** Any website can read responses from `provision-tenant`, `manage-users`, etc. Token theft via
  CSRF doesn't apply (Bearer header, not cookies), but `*` is still over-permissive for admin endpoints and
  defeats any future cookie-based session hardening.
- **Fix:** Restrict `Allow-Origin` to the app's origins (or reflect-and-validate against an allowlist env var).

#### M6 — No request body size limit in Edge Functions
- **Location:** `supabase/functions/_shared/guard.ts` (`readJsonBody` reads unbounded JSON; `send-notification`
  accepts unbounded `data` object).
- **Fix:** Enforce a max body size (e.g. 256 KB; 1 MB for `provision-tenant`) in `readJsonBody` via
  `Content-Length` check + a bounded reader; return `413`.

#### M7 — Verbose error messages leak internals
- **Location:** `lib/presentation/screens/master_admin/platform_users_screen.dart:151,214`
  (`'Insert failed: $e'` shows raw PostgREST errors); `export-tenant`/`manage-tenant` return
  `Could not read ${table}: ${error.message}` / `Could not load tenant: …` (500s with DB detail);
  `manage-users` returns raw `error.message` on create/update/delete failures.
- **Fix:** Map to stable error codes client-side (`error: "db_error"`, generic message); log the detail
  server-side only (see §3.6).

#### M8 — `manage-users:list_users` does N+1 Auth-admin lookups before paginating
- **Location:** `supabase/functions/manage-users/index.ts` (`handleListUsers`).
- **Problem:** Fetches **all** tenant memberships, then `auth.admin.getUserById` per user, then slices for
  pagination. Slow for large tenants; a timing side channel for user enumeration.
- **Fix:** Page at the membership level first (limit/offset on the membership query), then resolve only the
  page's users; or maintain a materialized `user_accounts`-style directory.

#### M9 — Legacy `supabase/01_schema.sql…06_rbac.sql` would destroy tenant isolation if re-run
- **Location:** `supabase/01_schema.sql`, `02_rls.sql` (documented as history in `docs/DATABASE.md`).
- **Problem:** `02_rls.sql` contains role-based, tenant-blind policies (e.g. `USING (auth.role()='authenticated')`).
  Nothing stops an operator from re-running them and silently dropping tenant isolation.
- **Fix:** Move them to `supabase/_archive/` (or add a `DO $$ BEGIN RAISE EXCEPTION` guard header) so they
  cannot be executed accidentally.

#### M10 — `export-tenant` is broken: `tenant-exports` bucket is never created
- **Location:** `supabase/functions/export-tenant/index.ts:60`; no migration creates the bucket.
- **Problem:** Every export fails at upload time (functionality bug), and the failure path returns storage
  internals to the caller.
- **Fix:** Add a migration creating the private `tenant-exports` bucket with platform-admin-only storage
  policies; verify who can read the exported files (currently: nobody — which is fail-closed but useless).

### LOW

- **L1** — Password minimum of 6 chars in `manage-users` (`handleCreateUser`/`handleUpdateUser`). Matches the
  Supabase default but is weak for admin-created accounts. Raise to 10+ and reject breached/common passwords
  for privileged roles.
- **L2** — `send-notification` email fan-out caps at 200 recipients while push goes to 2000; sequential per-token
  FCM calls risk function timeouts on large tenants. Batch via FCM multicast (500 tokens/request).
- **L3** — `provision-tenant` is not idempotent: a retried request after a timeout creates a duplicate tenant
  (compensating cleanup only runs on caught failures). Add an idempotency key (e.g. unique `slug` is already
  409-guarded — document "retry with the same slug").
- **L4** — Audit writes in `manage-users` are best-effort `catch{}` (silent audit gaps). Queue failed audits
  for retry instead of dropping them.
- **L5** — Inconsistent status codes: `send-notification` returns `400` for "user_id is not a member"
  (authorization-flavored input error); prefer `422`/`404` consistently and document the code table.
- **L6** — `get_my_permissions*` / `user_effective_permission` are callable by any authenticated user with
  arbitrary `p_user_id` — they only reveal permission metadata, but `user_effective_permission(t, other_user, code)`
  lets anyone probe another user's permission set (minor information disclosure; acceptable for members,
  consider restricting `p_user_id` to `auth.uid()` except for `roles.assign` holders).

### Deliberately NOT findings (verified safe)

- `finance_post_payment/refund/expense_income` are **trigger** functions, not callable RPCs.
- Doc-number generation uses sequences (`028`) — atomic, no duplicate-number race.
- `sync_apply` whitelists entities via `CASE` (no SQL injection through `p_entity`); dynamic SQL uses `%I`
  quoting; server-managed columns (`id/tenant_id/revision/server_version/deleted_at/created_at/updated_at`,
  plus `updated_by` since 027) are excluded from client writes; `search_path = public` is set on all
  `SECURITY DEFINER` functions reviewed.
- No `service_role` key, private key, or cloud credential in the repo (separately verified).
- `.env` is gitignored; only `.env.example` is committed; the app reads `SUPABASE_URL`/`SUPABASE_ANON_KEY`
  from env (anon key is public by design).
- `notification_device_tokens` write policy requires `user_id = auth.uid()` — no push-target hijack.
- Finance direct-table RLS is permission-code-aware (`fees.view/create/...`), so the A2 table group is
  correctly gated for direct access — the gap is only the `sync_apply` bypass (C2).
- `assign_tenant_role`/`set_user_permission` RPCs and the `manage-users` function both refuse to strand a
  tenant without an owner (last-owner backstops present) — the missing piece is the rank ceiling (H1–H3),
  not the floor.

---

## 3. Implementation guidance (concrete, for the fix phase)

### 3.1 Centralized authorization middleware (Edge Functions)
Add to `_shared/guard.ts`:
```ts
// composable pipeline: authenticate → authorize → rateLimit → sizeLimit → handler
export async function pipeline(req: Request, opts: {
  allow: (ctx: AuthCtx) => boolean | Promise<boolean>;  // role/permission predicate
  rateLimit?: { key: string; max: number; windowSec: number };
  maxBodyBytes?: number;
  handler: (ctx: AuthCtx, body: Record<string, unknown>) => Promise<Response>;
}): Promise<Response>
```
Every function then declares its policy in one place (e.g. `allow: ctx => ctx.isPlatformAdmin`,
or `allow: ctx => holdsPermission(ctx.tenantId, ctx.callerId, 'fees.create')`) instead of ad-hoc checks.
`manage-users`' `resolveCaller` becomes the shared `AuthCtx` builder.

### 3.2 Input validation
- Keep the `isEmail/isUuid/isSlug/isNonEmptyString` helpers; add `isRoleKey`, `isAmount` (finite, ≥ 0,
  ≤ 2 decimals), `isDateISO`.
- Validate **before** authz where cheap (shape), **after** authz where the check needs identity — never skip.
- Reject unknown top-level keys (`Object.keys(body)` allowlist per action) to kill mass-assignment probes.

### 3.3 Rate limiting
- Edge: in-memory token bucket per function instance keyed by `sub` claim is insufficient across isolates —
  use a `rate_limit_buckets` table (`key TEXT, window_start TIMESTAMPTZ, count INT`, PK on `(key, window_start)`)
  with a `SECURITY DEFINER rate_limit_check(p_key, p_max, p_window_sec)` RPC; call it in `pipeline`.
- Return `429` + `Retry-After`; suggested starting budgets: auth-adjacent 60/min, `manage-users` 120/min,
  `send-notification` 30/min (broadcast), `export-tenant` 5/hour, `provision-tenant` 10/hour.

### 3.4 Request size limits
- In `readJsonBody`: check `Content-Length` header first (reject `> max` with `413`); then read with a bounded
  accumulator that aborts past the cap (headers can lie). Default 256 KB; `provision-tenant` 1 MB.

### 3.5 Safe error responses
- Client-facing shape: `{ "error": "<stable_code>", "message": "<generic, localizable>" }` — never DB
  messages, never stack traces (the functions already do this in their catch-alls; extend to the
  `*_failed` branches that currently interpolate `error.message`).
- Log the full detail server-side with a correlation id echoed back (`error: "internal", request_id`).

### 3.6 Structured logging
- Replace `console.error("[manage-users] unhandled error:", msg)` with JSON lines:
  `{"ts","fn":"manage-users","action","caller": sub-hash,"tenant_id","code","latency_ms","request_id"}`.
- Never log: passwords, JWTs, FCM/Resend keys, PII beyond hashed user ids. Keep the audit_logs table as the
  durable trail; function logs are the operational trail.

### 3.7 Output filtering
- PostgREST: prefer explicit `.select("id,name,…")` over `select("*")` (the app already does this in most
  repositories — extend to `export-tenant`'s manifest and any `select("*")` in functions).
- Never expose: `auth.users` columns, `created_by` internal UUIDs to non-admins where avoidable, storage
  object internals, sequence counters. `user_accounts.email` to non-user-managers (see H4).

---

## 4. Endpoint coverage statement

Inventoried: 55 PostgREST table groups (A1–A5), 20 RPCs, 5 Edge Functions (9 `manage-users` actions).
Not directly testable statically: `finance_refresh_invoice_status` / `finance_recalc_invoice` / 
...[truncated 123 chars]