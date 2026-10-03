# Consolidated Security Audit — Madrassa-360

**Date:** 2026-10-03 · **Branch:** `redesign/ux-v2` · **Commit audited:** `945dce7` (remote `02c06927`)
**Scope:** Full application security audit — backend (Supabase Postgres/RLS/RPC/triggers/Edge Functions/storage), Flutter app, API surface, auth/authz lifecycle, tenant isolation, file uploads, input validation, business logic, error handling/logging, secrets, dependencies, performance.
**Method:** 14 parallel read-only audit workstreams; findings deduplicated by root cause below. Every finding traces to evidence in `docs/audit/security/raw/`. No application code was modified. No secret values appear in this report.
**Threat model:** attacker holds a valid low-privilege tenant account (e.g. `parent`/`student`) plus the public anon key, and can call any endpoint directly, bypassing the app.

---

## Executive summary — top 10 risks in plain language

1. **Any tenant member can rewrite anything in their tenant.** The offline-sync RPC `sync_apply` — the path *every* app write takes — checks only "are you a member?" and ignores the entire 66-code permission system. A parent's account can fabricate fee receipts, alter exam marks, or delete students. (SEC-C1)
2. **The sync RPC leaks other tenants' rows.** Its "already exists" branch returns full row data *before* checking membership — any authenticated user can probe UUIDs and read other tenants' students, invoices, payments. (SEC-C2)
3. **Money can be invented.** Financial documents can be inserted with `status='posted'`, skipping the posting triggers — ghost receipts with no ledger entry, or invoices flipped to `paid` with zero payment. Approval steps are skippable the same way. (SEC-C6)
4. **Read-only staff can take over accounts.** The `manage-users` function gates credential changes on the *view* permission set, so an HR staffer with `users.view` can reset a tenant admin's email and password. (SEC-C4)
5. **Support-tier platform admins can crown themselves owner** via direct table writes — no database-level distinction between `platform_support` and `platform_owner`. (SEC-C5)
6. **Concurrent payments can double-count.** The payment-posting trigger reads the invoice balance without locking it; two cashiers posting simultaneously over-allocate, and there is no idempotency key to stop double charges. (SEC-H16, SEC-H17)
7. **Tenant admins can un-suspend their own tenant** and poison the tenant row (status, license dates, logo URL) because the tenant-update policy has no column guard; meanwhile "suspension" itself is split across two flags, one of which nothing ever sets. (SEC-H6)
8. **Anyone in a tenant can spam everyone in it.** `send-notification` lets any member broadcast push + email to up to 2,000 members with arbitrary content — a tenant-wide phishing cannon on the institution's identity. (SEC-H4)
9. **Tokens and data sit unencrypted on devices.** Auth tokens live in plaintext SharedPreferences (Android backup enabled by default), and the full offline database survives logout — on shared school devices, the next user inherits everything. (SEC-H11, SEC-H12)
10. **A compromised old key may still work.** Legacy Supabase JWT keys (including service_role) were committed to the repo and scrubbed in 2026-09-25, but dashboard-side revocation was never verified. (SEC-H18)

**Bottom line:** the permission *model* is sound (server-side grant resolution, RLS helpers, rank gates in Edge Functions), but the *write paths* systematically bypass it: `sync_apply`, direct table writes to membership/role tables, and unguarded columns. The fix program is therefore concentrated: enforce authorization inside the write path, not around it.

---

## Severity counts

| Severity | Count |
|---|---|
| CRITICAL | 6 |
| HIGH | 20 |
| MEDIUM | 46 |
| LOW | 38 |
| **Total security findings** | **110** |
| Performance findings (separate section) | 12 (6 high / 4 medium / 2 low) |

Deduplication note: `sync_apply`-without-permissions appeared in 8 of the 14 raw reports; the tenant-row column guard in 3; the token-storage issue in 3; verbose Edge Function errors in 3. Each is listed once below with all affected surfaces noted.

---

## CRITICAL findings

### SEC-C1 — `sync_apply` enforces membership, not permissions: any tenant member can write any of 26 tables
- **File/location:** `supabase/migrations/016_sync.sql:89-91, 203-368` (re-declared in `027_user_accounts_app_roles.sql:241+`); app write path `lib/core/sync/sync_engine.dart:857`.
- **Problem:** The `SECURITY DEFINER` RPC that carries *every* app write (the app's sync engine is documented as "the only writer to the server") checks only `is_platform_admin() OR is_tenant_member(v_tenant)`. It never calls `tenant_has_permission()` and never calls `scope_allows()`. The per-permission RLS policies in 007/014/020 are therefore bypassed on the write path the app actually uses. The migration header documents this as a known deferred item.
- **Why it matters:** The entire role/permission/scope system (66 codes, role templates, delegations, class scopes) is UI-only for writes. Financial and academic record integrity depends on attackers not knowing the RPC name.
- **Attack scenario:** A phished teacher account (permissions: only `attendance.mark`) calls `rpc('sync_apply', {p_entity:'payments', p_op:'insert', p_payload:{tenant_id, amount:100000, status:'posted'}})` → `{"ok": true}`. No `fees.collect` checked, no draft-only rule. Same for `results` (alter any student's marks, scope bypassed), `discounts` (100% discount), `students` (mass soft-delete). No app patching needed — a 20-line script suffices.
- **Recommended fix:** Inside `sync_apply`, map `(p_entity, p_op)` → required permission code and enforce `tenant_has_permission(v_tenant, code)` (fail closed on unknown entity/op); for scoped entities also enforce `scope_allows()`. Return a clear `reason`, not an exception, so the client marks the op failed instead of retrying forever. Long-term, extract a `sync_required_permission(p_entity, p_op)` helper covered by tests.
- **Surfaces:** backend, api-abuse, flutter-app, frontend-untrusted, tenant-isolation, input-validation, api-endpoints, business-logic reports.

### SEC-C2 — `sync_apply` INSERT `already_exists` path returns full rows of any tenant before any membership check
- **File/location:** `supabase/migrations/016_sync.sql` — INSERT branch (`SELECT EXISTS … WHERE id = $1` → returns `'already_exists'` with full `server_row` JSON before the `is_tenant_member(v_tenant)` check).
- **Problem:** Any authenticated user — even with zero tenant memberships — can call `sync_apply('students', <uuid>, 'insert')`. If the UUID exists in *any* tenant, the RPC returns the entire row (names, phones, guardian info, financial data), bypassing RLS and tenant isolation. The update/delete `not_found` path has the same shape as an existence oracle (no row returned).
- **Why it matters:** UUIDs are unguessable but not secret — they leak via shared receipts, exports, logs, error messages. This turns every UUID into a cross-tenant read oracle.
- **Attack scenario:** Attacker harvests one student UUID from a shared fee receipt, then scripts insert-probes across all 26 entities to exfiltrate other tenants' students, invoices, payments.
- **Recommended fix:** Move the membership check before the existence probe; require `p_payload.tenant_id` and verify membership first; on `already_exists`, include `server_row` only if the row's tenant matches the caller's (or caller is platform admin) — otherwise return a bare reason.
- **Surfaces:** database, tenant-isolation reports.

### SEC-C3 — `sync_apply` UPDATE/DELETE has a TOCTOU race: optimistic concurrency is not atomic
- **File/location:** `supabase/migrations/016_sync.sql` — UPDATE and DELETE branches.
- **Problem:** The revision check is a plain `SELECT … INTO`, followed by a *separate* `UPDATE … WHERE t.id = $2` with no revision predicate and no row lock. Two concurrent writers with the same `base_revision` both pass; the second silently overwrites the first. The `bump_revision` trigger still increments, so the lost update is invisible. This defeats the documented contract "update/delete succeed only if server revision EQUALS p_base_revision" — including "financial rows are NEVER silently overwritten."
- **Why it matters:** Silent data loss on concurrent edits, including financial rows.
- **Attack/failure scenario:** Two accountants adjust the same draft invoice concurrently; accountant A's discount is silently lost; money is collected against a corrupted total.
- **Recommended fix:** Predicate the write on the revision: `… WHERE t.id = $2 AND t.revision = $5`, then `GET DIAGNOSTICS v_rows = ROW_COUNT; IF v_rows = 0 THEN RETURN conflict …`. Same for soft-delete. Alternatively `SELECT … FOR UPDATE` before the check.
- **Surfaces:** database report.

### SEC-C4 — `manage-users:update_user` lets read-only staff take over any account
- **File/location:** `supabase/functions/manage-users/index.ts` (`handleUpdateUser` → `canMutateUser(..., "users")` → `callerCan(..., "users")` → `resolveCaller`).
- **Problem:** `update_user` accepts `email`, `password`, `user_metadata`, `app_metadata`, but gates on the `"users"` right, which `callerCan` maps to `userTenants` — populated for anyone holding **`users.view`**. The seeded `hr_incharge` role has `users.view` but not `users.update`. Read permission silently became credential-write on the most sensitive object in the system.
- **Why it matters:** Full account takeover → privilege escalation from a read-only HR role.
- **Attack scenario:** HR staffer calls `manage-users {action:"update_user", user_id:<tenant_admin>, email:"attacker@evil.com", password:"…"}`. `canMutateUser` passes (target not platform admin, not owner, callerRank 0 so rank check skipped). Attacker owns the tenant admin's account; email change needs no verification, so future resets route to the attacker too.
- **Recommended fix:** Gate `update_user` on a write right (`users.update`, falling back to legacy owner/admin rank) — one-line right change. Separately, require email re-verification (or platform-admin approval) for email changes.
- **Surfaces:** api-abuse report.

### SEC-C5 — `platform_support` can self-promote to `platform_owner` via direct PostgREST writes
- **File/location:** `supabase/migrations/004_memberships.sql:272-275` (RLS `"platform admins only" FOR ALL USING (is_platform_admin())`); client `lib/presentation/screens/master_admin/platform_users_screen.dart:144,214`.
- **Problem:** The only server-side guard on `platform_admins` is "caller is any platform admin." No trigger distinguishes `platform_owner` from `platform_support`; no last-owner backstop in the DB. The Flutter screen's last-owner checks and typed confirmations are client-side and bypassable. (`manage-users:set_platform_role` is correctly owner-gated, but the table is directly writable in parallel.)
- **Why it matters:** Platform admins are the highest tier (suspend tenants, export all data). A helpdesk-tier account is one raw HTTP call from full ownership — or from deleting all owners (permanent administrative lockout).
- **Attack scenario:** `platform_support` user runs `PATCH /rest/v1/platform_admins?user_id=eq.<own> {"role":"platform_owner"}` with their JWT → RLS passes → now platform owner. Or `DELETE …?role=eq.platform_owner` → no owners remain.
- **Recommended fix:** `BEFORE INSERT OR UPDATE OR DELETE` trigger on `platform_admins`: only a current `platform_owner` may change `role` to/from `platform_owner` or delete an owner row; refuse to delete/demote the last `platform_owner`; audit the change. Route the Flutter screen through `manage-users:set_platform_role` instead of direct writes so there is exactly one privileged path.
- **Surfaces:** api-endpoints report.

### SEC-C6 — Financial workflow bypass via sync: posted documents without posting, paid invoices without payment, skippable approvals
- **File/location:** `supabase/migrations/016_sync.sql` (INSERT/UPDATE branches — no status validation) + `supabase/migrations/014_finance.sql` posting triggers (`BEFORE UPDATE OF status` only).
- **Problem:** Three related holes on the real write path: (a) `trg_payments_post` / `trg_refunds_post` / `trg_expenses_post` fire only on UPDATE of status — `sync_apply` INSERT accepts any status including `'posted'`, so ghost receipts exist with no ledger entry, no allocation, invoice untouched; `transactions` itself is in the sync whitelist, so ledger rows can be fabricated directly. (b) Invoice `status` is an ordinary writable sync column — RLS deliberately excludes `'paid'/'partially_paid'/'overdue'` from client-writable values (paid is derived by `finance_refresh_invoice_status()`), but sync bypasses RLS: an invoice can be set `paid` with `amount_paid = 0`, permanently (now "final", never editable again). (c) Approval steps are skippable: RLS encodes draft→approved (needs `finance.approve` + `approved_by`) → posted, but sync enforces none of it — a clerk with only `fees.collect` can post a Rs. 200,000 "expense" directly.
- **Why it matters:** The "paid means money was received" invariant — the core of the finance module — is enforced nowhere on the real write path. Books can be corrupted or fabricated without any permission the UI would require.
- **Attack scenario:** Clerk inserts `payments {status:'posted', amount:50000}` via sync → printed receipt looks legitimate → invoice still shows full balance due → student asked to pay again, or clerk pockets cash against a receipt that never hit the ledger. Or flips `invoices.status='paid'` → dues vanish permanently.
- **Recommended fix:** (1) `BEFORE INSERT` trigger on payments/refunds/expenses/income/transactions forcing `NEW.status='draft'` (raise otherwise); (2) remove `transactions` from the `sync_apply` whitelist — the ledger must be writable only by posting triggers; (3) `BEFORE UPDATE OF status` trigger on invoices rejecting direct writes to derived statuses (`paid`, `partially_paid`, `overdue`) — only `finance_refresh_invoice_status()` may set them; (4) a `finance_transition_guard()` trigger per document table encoding the legal graph draft→approved→posted with `finance.approve` enforcement.
- **Surfaces:** business-logic, input-validation reports.

---

## HIGH findings

### SEC-H1 — Role-management RPCs have no grant ceiling: `roles.assign` becomes "become owner"
- **File/location:** `supabase/migrations/020_role_ux_rls.sql` — `assign_tenant_role()` (~:580), `set_role_permissions()` (~:611), `set_user_permission()` (~:677).
- **Problem:** All three require only `is_tenant_admin() OR tenant_has_permission('roles.assign')`, then allow granting *anything*: `assign_tenant_role` can assign `tenant_owner` (no rank check, no self-grant ban — the rank gate exists only in the Edge Function, not the RPC); `set_user_permission` can grant any code to anyone including self without holding it (the 019 delegation trigger has a ceiling; this RPC doesn't); `set_role_permissions` can add any codes to any role.
- **Why it matters:** A custom role with `roles.assign` is a de-facto owner-mint.
- **Attack scenario:** Holder of `roles.assign` calls `assign_tenant_role(tenant, self, 'tenant_owner')` → instant owner. Or `set_user_permission(tenant, self, 'finance.approve', 'grant')` for every code.
- **Recommended fix:** Ceilings: `assign_tenant_role` may not assign `tenant_owner` unless caller is `tenant_owner`, and may not assign a role whose effective permission set exceeds the caller's; `set_user_permission`/`set_role_permissions` may not grant codes the caller does not effectively hold (mirror the 019 delegation ceiling). Extract the rank table into SQL so the RPC and Edge Function share one source of truth.
- **Surfaces:** backend, api-endpoints reports.

### SEC-H2 — `manage-users`: permission-based callers bypass the rank ceiling
- **File/location:** `supabase/functions/manage-users/index.ts` — `canMutateUser()` (~:560), `assignRoleGate()` (~:585).
- **Problem:** The rank ceiling applies only to legacy rank-based callers (`callerRank > 0`). Template-role callers authorized via permission codes (`callerRank === 0`) skip it: a custom-role holder with `users.deactivate` can ban a `tenant_admin` (rank 90); a `roles.assign` holder can assign `tenant_admin` to anyone including themselves (only literal `tenant_owner` is blocked).
- **Why it matters:** A tenant owner can legitimately create a "junior admin" custom role; that junior admin can then deactivate the real admin (lockout/DoS) and promote an accomplice.
- **Attack scenario:** "Office assistant" role with `users.deactivate` + `roles.assign` → `set_active` on the tenant_admin (banned 100 years) → `assign_role tenant_admin` on accomplice → full tenant control.
- **Recommended fix:** Enforce an authority ceiling for permission-based callers too: derive an effective max rank from granted codes (or require a senior code), require caller rank strictly greater than target's rank for mutation and assignment; never allow assigning `tenant_admin` (or any rank ≥ own) without being `tenant_owner`.
- **Surfaces:** backend report.

### SEC-H3 — Direct PostgREST writes to `tenant_memberships` bypass all `manage-users` guards (self-promotion)
- **File/location:** `supabase/migrations/004_memberships.sql` (policy `"tenant admins manage memberships" FOR ALL USING/WITH CHECK (is_tenant_admin(tenant_id))`).
- **Problem:** A `tenant_admin` can INSERT/UPDATE/DELETE `tenant_memberships` directly. `protect_last_owner` (019) stops removing the *last* owner, but nothing stops self-promotion `tenant_admin` → `tenant_owner` via direct UPDATE (WITH CHECK still passes), or granting arbitrary template roles — with no audit row and no rank gates.
- **Why it matters:** The Edge Function's rank ceilings, last-owner protection, and audit trail are optional; the database offers a parallel weaker path.
- **Attack scenario:** Compromised `tenant_admin` runs `PATCH /rest/v1/tenant_memberships?user_id=eq.<self> {role:'tenant_owner'}` → now owner → demote the real owner (trigger stays silent while another owner remains).
- **Recommended fix:** Restrict the RLS policy to SELECT for tenant callers (platform-admin-only writes) and force all membership mutations through `manage-users` / a hardened RPC that keeps the rank gates and audit writes.
- **Surfaces:** api-abuse report.

### SEC-H4 — `send-notification`: any tenant member can broadcast push+email to the whole tenant
- **File/location:** `supabase/functions/send-notification/index.ts` (~:203-219, :330).
- **Problem:** Authorization is only "platform admin OR active member of the tenant" — no permission check (e.g. `notifications.send`) — yet the function sends push (FCM) **and email (Resend)** with fully caller-controlled `title`/`body` to a targeted user or **all active members (up to 2000)**. The 017 migration's own design notes say direct INSERT is platform-admin-only so a compromised token can't spam broadcasts — the Edge Function re-opens exactly that path. Email fan-out puts up to 200 addresses in one Resend `to:` list → recipients see each other's emails (member PII disclosure). Body fields are uncapped (FCM 4KB limit).
- **Why it matters:** Any compromised student/parent account becomes a tenant-wide phishing cannon from the institution's own sender identity, plus direct Resend/FCM cost.
- **Attack scenario:** Stolen parent login → broadcast `{title:"فیس کی آخری تاریخ", body:"pay at evil.example…", channels:["push","email"]}` → every parent gets an official-looking phish.
- **Recommended fix:** Require `notifications.send` effective permission for broadcasts (targeted-to-self stays membership-gated); per-caller rate limit (e.g. 30 broadcasts/hour); send emails per-recipient/BCC; cap `body`/`body_urdu` (~2KB) and validate `data` keys; write every broadcast to `audit_logs`.
- **Surfaces:** api-abuse, backend, tenant-isolation reports.

### SEC-H5 — `user_accounts`: cross-tenant PII read; unscoped writes; no `tenant_id`
- **File/location:** `supabase/migrations/027_user_accounts_app_roles.sql:48-59` (table), `:93-107` (policies).
- **Problem:** The table has no `tenant_id` (migration admits per-row scoping is impossible). `user_accounts_select_member` lets **any active member of any tenant SELECT all rows** — names, emails, phones, role names across all tenants. INSERT/UPDATE/DELETE require holding `users.create/update/deactivate` in ≥1 tenant, but the grant isn't tied to the row's tenant — a user-manager in tenant A can update rows belonging to tenant B, including `role_name` and `is_active` (client-writable via the provider's direct `.update()`).
- **Why it matters:** Cross-tenant personal-data exposure violates the core multi-tenant promise; the write-scope mismatch is a latent escalation primitive (currently cosmetic: `user_effective_permission` and RLS consult only `tenant_memberships`/`tenant_roles`).
- **Attack scenario:** Teacher in tenant A scrapes `GET /rest/v1/user_accounts?select=name,email` → full cross-tenant user directory for spear-phishing; or flips `is_active=false` on another tenant's admin rows to break their user-management UI.
- **Recommended fix:** Add `tenant_id` (nullable → backfill from `linked_staff_id`/memberships → NOT NULL) and scope all four policies per-row. Until then, restrict SELECT to platform admins + `users.view` holders (not every member), and remove `role_name` from the client-writable path.
- **Surfaces:** api-abuse, backend, tenant-isolation, api-endpoints reports.

### SEC-H6 — Tenant enforcement is defective end-to-end: self-unsuspension, column tampering, split-brain suspension
- **File/location:** `supabase/migrations/027_user_accounts_app_roles.sql:186-196` (`tenants_member_update`); `supabase/functions/manage-tenant/index.ts` (writes `tenants.status`); `supabase/migrations/023_super_admin.sql:49,102-121` (`suspended` boolean; `check_tenant_access()` reads it).
- **Problem (two halves):** (a) The UPDATE policy checks membership + `settings.update` but restricts **no columns** — RLS can't do column grants, so any `settings.update` holder can PATCH `status`, `suspended`, `expires_at`, `tenant_code`, `slug`, `logo_url` (arbitrary URL → branding-download OOM/SSRF on every device, see file-uploads H3), `registration_number`. (b) Suspension is split-brain: `manage-tenant` writes the `status` string, but `check_tenant_access()` (the AuthGate RPC) reads the `suspended` boolean, which **nothing ever sets** — and no RLS policy anywhere checks suspension or expiry. A "suspended" tenant keeps full access.
- **Why it matters:** Platform billing/abuse enforcement is defeated by the tenant's own admin, or is simply never enforced at the backend.
- **Attack scenario:** Platform suspends madrassa X (`status='suspended'`). X's admin PATCHes `{status:'active', expires_at:'2099-01-01'}` → RLS passes → enforcement lifted without platform action. Separately, even a correctly-suspended tenant keeps syncing because no RLS policy reads either flag.
- **Recommended fix:** Single source of truth + column guard: `BEFORE UPDATE` trigger on `tenants` rejecting changes to `status`/`suspended`/`expires_at`/`tenant_code`/`slug`/`registration_number`/`admin_message*` unless `is_platform_admin()`; allow-list for `settings.update` holders (`name`, `name_urdu`, contact fields, `use_logo_on_reports`); `logo_url` only writable to the tenant's own storage logo prefix (or written solely by the upload Edge Function). Make `manage-tenant` set the same flag `check_tenant_access()` reads, **and** add a suspension/expiry check to `is_tenant_member()` (or base RLS policies) so RLS enforces it, not just the client gate.
- **Surfaces:** tenant-isolation, file-uploads, backend reports. (Severity note: tenant-isolation rated the column guard CRITICAL; rated HIGH here because exploitation requires an already-privileged tenant admin — the platform-enforcement defeat is the material impact.)

### SEC-H7 — `madrasas_member_select` tenant scoping is broken (unqualified `id` binds to inner query)
- **File/location:** `supabase/migrations/027_user_accounts_app_roles.sql:206-216`.
- **Problem:** The policy intends per-row scoping via `madrasas.id`, but the EXISTS subquery is `FROM public.tenants t` and the bare `id` resolves to **`t.id`** (innermost scope wins). The predicate becomes a property of the tenant, not the row. For legacy tenants with `M-`-derived codes (the 004 backfill convention), **any active member can SELECT every row of `public.madrasas`** — cross-tenant read. For new `T-`-code tenants the predicate is false → reads fail closed (functional break if the app reads `madrasas`).
- **Why it matters:** Cross-tenant data disclosure on the legacy madrassa table, via a one-identifier SQL scoping bug.
- **Attack scenario:** Tenant A (legacy M-code) teacher: `GET /rest/v1/madrasas` → all madrassa rows including tenant B's.
- **Recommended fix:** Qualify the reference (`replace(madrasas.id::text, '-', '')`). Add a cross-tenant negative test (A-member cannot read B's madrasa row).
- **Surfaces:** tenant-isolation report.

### SEC-H8 — Zero rate limiting on every endpoint
- **File/location:** all Edge Functions (`supabase/functions/*/index.ts`); all RPCs; `lib/presentation/screens/auth/login_screen.dart` (no backoff/CAPTCHA).
- **Problem:** No application-level throttling anywhere. Expensive endpoints are cheap to hammer: `manage-users:list_users` (N+1 `auth.admin.getUserById` fan-out), `export-tenant` (21-table scan + in-memory assembly), `send-notification` (up to 2000 sequential FCM calls), `provision-tenant`. Login brute force rests on Supabase platform defaults; no CAPTCHA configured, no client backoff.
- **Why it matters:** Credential stuffing against known staff emails is unimpeded at the app layer; a compromised low-privilege account can burn CPU, Resend/FCM quota, and admin-API rate budget (DoS/cost).
- **Attack scenario:** Attacker scripts password lists against harvested staff emails while looping `send-notification` broadcasts → thousands of FCM/Resend invocations per minute on the project's bill.
- **Recommended fix:** Shared Edge Function middleware: per-caller (JWT sub) token-bucket via a `rate_limit_buckets` table + `rate_limit_check()` SECURITY DEFINER RPC (in-memory per isolate is insufficient on Deno Deploy); budgets e.g. auth-adjacent 60/min, manage-users 120/min, send-notification broadcast 30/min, export-tenant 5/hour; `429` + `Retry-After`. Enable Supabase Auth CAPTCHA (Turnstile) on sign-in; client-side progressive backoff after repeated failures. Log 429s structurally.
- **Surfaces:** api-abuse, api-endpoints reports.

### SEC-H9 — `tenant-exports` bucket is not version-controlled; full-tenant PII exports land at unknown policies
- **File/location:** `supabase/functions/export-tenant/index.ts:60` (`BUCKET = "tenant-exports"`); no `INSERT INTO storage.buckets` in any migration (008 creates only `student-photos`, `staff-photos`, `documents`; 024 creates `tenant-logos`).
- **Problem:** `export-tenant` (platform-admin only — good) writes a JSONL of **every row of 21 tenant tables** to `exports/{tenant_id}/{timestamp}.jsonl` in a bucket with no version-controlled definition. Either exports are broken in production (bucket missing → upload fails), or the bucket was created manually with **unknown, unreviewed storage policies** — a permissive manual policy would expose one tenant's full export to any authenticated user. There is also no in-app download flow (function returns only `storage_path`).
- **Why it matters:** A full-tenant PII/finance dump at predictable paths under unknown access control.
- **Attack scenario:** If the manually created bucket is public or authenticated-read, anyone fetches `exports/<tenant>/<ts>.jsonl` → complete student/staff/finance dataset.
- **Recommended fix:** Migration creating `tenant-exports` as **private** with platform-admin-only storage policies; downloads exclusively via short-lived signed URLs minted after re-checking platform-admin; verify the **live** bucket's actual `public` flag and policies in the dashboard immediately and reconcile.
- **Surfaces:** backend, api-endpoints, file-uploads reports.

### SEC-H10 — File uploads have no server-side validation: arbitrary bytes into public/predictable storage
- **File/location:** `lib/services/tenant_logo_service.dart:60-100` (logo → `tenant-logos` PUBLIC, `<tenant_id>/logo.png`); `lib/providers/student_provider.dart:118-125`, `staff_provider.dart:83-88`, `lib/core/sync/sync_engine.dart:906-910` (photos → private buckets); `supabase/migrations/008_tenant_storage.sql`, `024_tenant_logos.sql` (policies check tenancy only).
- **Problem:** All validation is Dart-client-side and bypassable with a raw Storage API call + valid JWT: logo upload checks only non-empty + ≤5MB client-side, hardcodes `contentType: image/png` regardless of bytes, no magic-byte sniffing; photo uploads take the extension from the picked filename (`photo.name.split('.').last`, `x.svg` → `.svg`) with no `contentType` set, so Supabase infers served content-type from the attacker-controlled extension; **no server-side size cap exists on any upload** (storage RLS cannot inspect object size). Tenant paths are correctly bound (`storage_path_tenant()` fail-closed) — this is purely a content-validation gap.
- **Why it matters:** A `settings.update` holder can upload a PNG decompression bomb to the **public** logo bucket at a predictable URL → every device that generates a report decodes it (tenant-wide OOM DoS), served from the project's trusted domain. An SVG with script stored as a "photo" becomes stored XSS if the buckets are ever made public to fix photo display. Uncapped sizes enable storage-fill/cost abuse by any `students.update` holder.
- **Attack scenario:** Tenant admin POSTs a crafted decompression bomb via raw Storage API → all madrassa devices crash on next report generation, repeatedly; or uploads `evil.svg` as a student photo → served as `image/svg+xml` → script executes in the storage origin for anyone opening it.
- **Recommended fix:** New `upload-image` Edge Function (service role): JWT + permission check (`settings.update`/`students.update`/`staff.update` per target) → magic-byte sniff (PNG/JPEG/WebP only; reject SVG/BMP/TIFF) → server-side size cap (e.g. 5MB logo, 2MB photo) + pixel-dimension cap → **re-encode** (strips polyglots/metadata/bombs) → server-generated filename (never from user input) → fixed `contentType`; the function writes `logo_url`/`photo_url` itself. Route logo + photo flows through it; serve private photos via signed URLs or authed headers, never public buckets. Byte-cap `readJsonBody` (see SEC-M11).
- **Surfaces:** file-uploads, flutter-app, api-endpoints reports. (Severity note: file-uploads rated the logo case CRITICAL; rated HIGH here — exploitation requires a privileged `settings.update`/`students.update` holder — but it is the highest-impact upload issue.)

### SEC-H11 — Auth tokens stored in plaintext SharedPreferences; Android backup enabled by default
- **File/location:** `lib/core/services/supabase_service.dart` (`Supabase.initialize` with no `localStorage` override; `supabase_flutter` 2.12.0 default `SharedPreferencesLocalStorage`); `android/app/src/main/AndroidManifest.xml` (no `android:allowBackup`, defaults `true`).
- **Problem:** Access + long-lived refresh tokens sit unencrypted in SharedPreferences XML. With `allowBackup` unset, `adb backup`/rooted device/malicious restore exfiltrates them; on Windows `%APPDATA%` is user-readable. A stolen refresh token = full account impersonation until expiry/revocation — and password change does not revoke existing refresh tokens by default in GoTrue.
- **Why it matters:** Cheapest full-compromise path on shared/lost devices holding children's PII and financial records.
- **Attack scenario:** Brief physical access to an unlocked staff phone (or a backup image) → copy prefs XML → replay refresh token from attacker's machine → persistent principal session, including platform console if the victim is a platform admin.
- **Recommended fix:** `flutter_secure_storage`-backed `LocalStorage` passed to `Supabase.initialize(authOptions:…)`; `android:allowBackup="false"` (or tight backup-rules XML); on password change/reset, revoke all sessions via `auth.admin.signOut(userId)` server-side.
- **Surfaces:** api-abuse, flutter-app, frontend-untrusted reports.

### SEC-H12 — Full tenant database persists on disk after logout; readable by the next device user
- **File/location:** `lib/providers/auth_provider.dart` (`_handleSignedOut`, :456-478); `lib/data/local/database_provider.dart` (`closeDatabase` only closes, never deletes; called only from restart/backup paths).
- **Problem:** Sign-out clears in-memory state, permission caches, and tenant choice — but **never deletes the Drift SQLite file** (`madrassa360.db`) holding the tenant's entire synced dataset: students, fees, finance, staff PII/salaries, attendance, unsynced queue payloads.
- **Why it matters:** On shared/family devices (common in the target environment), the next device user — or anyone reading app files (root, backup extraction, Windows `%APPDATA%`) — gets the previous tenant's full dataset with no authentication. Combined with unvalidated `switchTenant`, cached rows of *other* tenants are reachable offline.
- **Attack scenario:** Clerk signs out on a shared school computer; next user copies `madrassa360.db` and opens it in any SQLite browser: complete student records, fee/finance history, staff salaries.
- **Recommended fix:** On sign-out, close and **delete** the tenant database file (plus logo/report caches under `Madrassa360/`), or encrypt at rest (SQLCipher) with the key in `flutter_secure_storage` wiped on logout. Add a test asserting zero rows post-logout.
- **Surfaces:** flutter-app, frontend-untrusted, tenant-isolation reports.

### SEC-H13 — Password-reset flow cannot be completed (broken end-to-end)
- **File/location:** `lib/data/repositories/auth_repository.dart:215` (`resetPasswordForEmail` without `redirectTo`); no `app_links` recovery handling; no `PASSWORD_RECOVERY` listener; no set-new-password screen.
- **Problem:** The forgot-password screen sends the reset email, but the recovery link points at the Supabase site URL (no `redirectTo` to the app callback scheme), and the app has no code path to receive a recovery session nor UI to set a new password.
- **Why it matters:** No self-service recovery — a security *driver*: it pushes admins toward insecure workarounds (shared passwords, admin-set weak passwords via `manage-users`).
- **Failure scenario:** A mohtamim forgets their password before fee-collection day; the email link dead-ends; only platform-admin intervention restores access.
- **Recommended fix:** Pass `redirectTo` (app callback scheme) in `resetPasswordForEmail`; handle the recovery deep link (`PASSWORD_RECOVERY` → route to a new SetNewPasswordScreen → `auth.updateUser`); same password policy and error mapping as login.
- **Surfaces:** flutter-app report.

### SEC-H14 — Edge Functions return raw database/driver error messages to API callers
- **File/location:** `supabase/functions/manage-users/index.ts:462,507,564,603,644,827,832`; `export-tenant/index.ts:135`; `send-notification/index.ts:261,367,425`; `provision-tenant/index.ts:405-412` (via `step(name, error.message)`).
- **Problem:** Failure branches interpolate `error.message` from supabase-js/PostgREST into the JSON response (`{error:"update_failed", message: error.message}`, `{error:"db_error", detail: insErr.message}`). PostgREST messages embed table, column, and constraint names (e.g. `duplicate key value violates unique constraint "tenant_memberships_user_id_tenant_id_key"`).
- **Why it matters:** Any tenant admin/member calling these functions can map the internal schema — table/column/constraint names — aiding targeted probing and RLS-policy inference. (The top-level `manage-users` catch and `guard.ts` already use the safe generic pattern — extend it everywhere.)
- **Attack scenario:** Malicious `tenant_admin` repeatedly calls `assign_membership` with crafted role values; constraint-violation messages enumerate valid role keys and exact unique constraints.
- **Recommended fix:** Return stable error codes + generic messages (`{error:"update_failed"}`); log full driver detail server-side with a correlation id echoed back. Add a CI guard rejecting `$e` interpolation into user-facing widgets (mirrors `tool/no_mock_check.dart`).
- **Surfaces:** error-handling, api-endpoints reports.

### SEC-H15 — `app_metadata` mass assignment enables client-side role spoofing
- **File/location:** `supabase/functions/manage-users/index.ts` (`handleCreateUser`, `handleUpdateUser` copy caller `app_metadata` verbatim); consumer `lib/data/repositories/auth_repository.dart:78-80` (`AppUser.fromSupabase` prefers `appMetadata['role']`); sender `lib/providers/user_management_provider.dart:153-163`.
- **Problem:** Any tenant caller can set `app_metadata: {"role": "superAdmin"}`; the client reads `user.appMetadata['role']` **first** to decide `UserRole`, and the app's own provider normalizes sending role inside `app_metadata`.
- **Why it matters (bounded):** Server-side data access consults `tenant_memberships`/`user_effective_permission`/`platform_admins` tables — never `app_metadata` — so this does not escalate at the DB/RPC layer. Impact is client-side: spoofed admin UI surfaces, confused-deputy flows, and a trust anchor the client treats as server-issued but is caller-controlled. Any future code trusting `currentUserRoleProvider` inherits a spoofable root.
- **Attack scenario:** Tenant admin creates a sleeper account with `app_metadata.role="superAdmin"`; the victim client renders the platform-console shell.
- **Recommended fix:** Strip `app_metadata` for non-platform callers (allow-list safe keys like `name` only); server-derive it from resolved role/membership. Client: never resolve role from `appMetadata` — use the server permission RPC only.
- **Surfaces:** api-abuse, backend, api-endpoints, flutter-app reports.

### SEC-H16 — Payment posting over-allocation race: `amount_paid` can exceed invoice total
- **File/location:** `supabase/migrations/014_finance.sql` — `finance_post_payment()` (`BEFORE UPDATE OF status ON public.payments`); same pattern in `finance_post_refund()`.
- **Problem:** Allocation is `SELECT LEAST(NEW.amount, balance_due)` with **no `FOR UPDATE` lock**, then `UPDATE invoices SET amount_paid = amount_paid + v_alloc`. Two concurrent draft→posted transitions read the same stale `balance_due`; both allocate the full amount. `amount_paid` exceeds `total`, `balance_due` goes negative, and **no CHECK forbids it**.
- **Why it matters:** The books show money never received; reports and invoices disagree with reality.
- **Failure scenario:** Invoice Rs. 10,000, balance Rs. 10,000. Two cashiers post Rs. 10,000 within the same second (or double-tap + queued offline op) → `amount_paid` = 20,000, `balance_due` = −10,000, status `paid`.
- **Recommended fix:** `SELECT … FOR UPDATE` on the invoice row before reading `balance_due` (both post and refund paths); add a backstop `CHECK (balance_due >= 0)` / `amount_paid <= total` guard.
- **Surfaces:** database, business-logic reports.

### SEC-H17 — No idempotency on payments/expenses/income: double-submit double-charges
- **File/location:** `supabase/migrations/014_finance.sql` (`payments`, `expenses`, `income` — no idempotency key); `lib/data/repositories/finance_repository.dart:616-620` (`recordPayment` mints a fresh ID per submit; `_saving` guards double-tap only).
- **Problem:** Nothing at the DB level distinguishes "user tapped Collect twice" from two legitimate payments. Retry-after-timeout (sync engine retries up to 5×) or two offline devices can post the same physical cash twice. Sync-engine idempotency is per-ID (`already_exists`), which doesn't help across IDs.
- **Why it matters:** Parents charged twice; ledger double-counts; invoices overpaid (feeds SEC-H16).
- **Failure scenario:** Cashier taps "Collect fee", transient error, taps again → two Rs. 5,000 payments, two receipts, invoice overpaid.
- **Recommended fix:** Client-generated idempotency key per user *intent* (stable across retries of the same sheet session): `ALTER TABLE payments ADD COLUMN idempotency_key TEXT; CREATE UNIQUE INDEX ux_payments_idem ON payments (tenant_id, idempotency_key) WHERE idempotency_key IS NOT NULL;` same for `expenses`, `income`. Server returns the existing row on conflict.
- **Surfaces:** database, business-logic, api-endpoints reports.

### SEC-H18 — Legacy Supabase JWT keys were committed; dashboard revocation unverified
- **File/location:** incident documented in `docs/DEPLOYMENT.md` (§ "Revoke the OLD keys"); scrubbed in-repo 2026-09-25 (full-history scan of all 83 commits confirms no full-length legacy JWT remains on this branch).
- **Problem:** Legacy **anon + service_role** JWT keys were committed at some point. In-repo values are scrubbed, but anyone who cloned while they were present still holds the **service_role** key: full RLS bypass, read/write any tenant, manage Auth users. Scrubbing does not revoke.
- **Why it matters:** A leaked service_role key voids every other control in this audit.
- **Attack scenario:** Attacker with an old clone uses the leaked service_role key against the project URL → dumps all tenants' records, creates a platform admin.
- **Recommended fix (human, Supabase dashboard):** Revoke the old legacy JWT keys; verify they return 401; confirm app + Edge Functions run on the new publishable/secret keys. Check any other remotes/branches that may have carried them.
- **Surfaces:** secrets report. Related rotation owed: DB password pasted in chat 2026-09-26; demo accounts (see SEC-M42).

### SEC-H19 — No audit trail for authentication events, broadcasts, or core-entity deletions
- **File/location:** (absence) `lib/data/repositories/auth_repository.dart`; `supabase/functions/send-notification/index.ts` (zero audit writes); `supabase/migrations/*` (no audit triggers on `students`, `staff`, `attendance`, `results`, `classes`).
- **Problem:** Login failures are logged nowhere in the application; password changes have no distinct event; `send-notification` broadcasts (reachable by any tenant member, SEC-H4) leave no trace; deleting a student or their fee history writes no audit row. The finance/role triggers prove the pattern works — it wasn't extended.
- **Why it matters:** Brute-force attacks are undetectable from the app's own trail; a malicious insider can broadcast phishing to all members or delete records with zero forensic footprint.
- **Attack scenario:** Attacker brute-forces a teacher's password (no CAPTCHA, SEC-H8); `audit_logs` shows nothing — compromise discovered only via dashboard logs the tenant admin cannot see.
- **Recommended fix:** Write `auth.login_failed` / `auth.password_changed` via `log_audit()` from the auth repository (never the password); add `notification.broadcast` audit in `send-notification` (service role); extend the `finance_audit()`-style trigger to core tables (students, staff, attendance, results) — or one generic `audit_all_writes()` trigger.
- **Surfaces:** error-handling report.

### SEC-H20 — Committed `pubspec.lock` is stale and violates `pubspec.yaml`; installs are unfrozen
- **File/location:** `pubspec.lock` (root), `pubspec.yaml:26`; `.github/workflows/*.yaml` (bare `flutter pub get`).
- **Problem:** `pubspec.yaml` constrains `connectivity_plus: ^6.1.5`, but the committed lockfile pins **5.0.2** — unsatisfiable against the current pubspec (last regenerated before the constraint change). Every CI job and build runs unfrozen `flutter pub get`, so pub silently re-resolves: two builds from the same commit can ship different dependency trees.
- **Why it matters:** "Release from an exact CI-green commit" is undermined when the commit doesn't determine the dependency tree; a compromised package release could slip in between CI runs unnoticed.
- **Attack/failure scenario:** A transitive dep's patch release introduces a regression/backdoor between the morning and evening builds from the same commit; nobody can tell from the repo.
- **Recommended fix:** Regenerate the lockfile, commit it, switch all workflows to `flutter pub get --enforce-lockfile`, and add a CI check that the lockfile is in sync.
- **Surfaces:** dependencies report.

---

## MEDIUM findings

### SEC-M1 — Soft-deleted rows still occupy UNIQUE slots: delete→re-add breaks sync permanently
- **Location:** `supabase/01_schema.sql` (`attendance` UNIQUE `(student_id, date)`, `fees` UNIQUE `(student_id, month)`); `supabase/migrations/016_sync.sql` (soft-delete via `deleted_at`, no partial unique indexes).
- **Problem:** 016's contract is soft-delete, but legacy UNIQUE constraints are unconditional. Soft-delete an attendance row, re-mark for the same student+date → re-insert hits UNIQUE violation → `sync_apply` raises → parked as failed → after 5 retries `dead_letter`. The user's correction never syncs, and dead letters are only a badge count (no retry UI).
- **Fix:** Replace with partial unique indexes: `CREATE UNIQUE INDEX ux_attendance_live ON attendance (student_id, date) WHERE deleted_at IS NULL;` (same for `fees`); add a dead-letter review UI with retry/discard.
- **Surfaces:** database report.

### SEC-M2 — Financial-conflict manual review has no reachable UI
- **Location:** `lib/core/sync/conflict_review_screen.dart` (exists, never instantiated; no route).
- **Problem:** 016's safety design for financial tables ("NEVER silently overwritten… client MUST surface for MANUAL review") dead-ends: conflicts park in `sync_conflicts` with no screen to view/resolve them. Local device and server permanently disagree about money with no actionable surfacing.
- **Fix:** Wire `ConflictReviewScreen` into the app shell (sync badge / finance dashboard); persistent banner while unresolved financial conflicts exist; test asserting the route exists.
- **Surfaces:** database report.

### SEC-M3 — Conflict resolution uses wall-clock timestamps: clock skew silently overwrites
- **Location:** `lib/core/sync/sync_engine.dart` — `decideNormalConflict()` compares `serverUpdatedAt` vs `localUpdatedAt`, contradicting 016's revision-based rule.
- **Problem:** A fast-clocked device concludes "local is newer" and overwrites server-newer changes.
- **Fix:** Decide purely on revision (server revision > base ⇒ take server); timestamps for display only.
- **Surfaces:** database report.

### SEC-M4 — `audit_logs.tenant_id ON DELETE CASCADE`: deleting a tenant wipes its audit trail
- **Location:** `supabase/migrations/012_audit_logs.sql:34`.
- **Problem:** The append-only audit backstop is cascade-deleted with the tenant — a malicious tenant admin or mistaken platform operator erases all fraud evidence by deleting the tenant.
- **Fix:** `ON DELETE SET NULL` (keep rows queryable by platform admins) or `ON DELETE RESTRICT` + explicit archive flow. Financial audit rows must outlive the tenant.
- **Surfaces:** database, error-handling reports.

### SEC-M5 — Single-sided ledger: nothing enforces balanced books
- **Location:** `supabase/migrations/014_finance.sql` — `transactions` (flat single-sided rows, `kind` in income/expense/transfer).
- **Problem:** No double-entry invariant; posting bugs (SEC-H16) corrupt books silently.
- **Fix (medium-term):** Per-tenant running-balance guard or periodic reconciliation RPC + test asserting income−expense matches expected cash position; at minimum the `balance_due >= 0` backstop from SEC-H16.
- **Surfaces:** database report.

### SEC-M6 — Permission-oracle RPCs callable with arbitrary tenant/user arguments
- **Location:** `supabase/migrations/020_role_ux_rls.sql:860-879` (`GRANT EXECUTE … TO authenticated` on `user_effective_permission(UUID,UUID,TEXT)`, `user_code_denied`, `tenant_has_permission`).
- **Problem:** SECURITY DEFINER helpers taking `p_tenant_id`/`p_user_id` as parameters are directly callable by any JWT holder with arbitrary UUIDs — cross-tenant role/permission reconnaissance (find owners/admins, who holds `settings.update`) and tenant-existence probing. `get_my_permissions*` with arbitrary `p_user_id` similarly leaks another user's permission set.
- **Fix:** `REVOKE … FROM authenticated` on the parameterized helpers; expose only `auth.uid()`-bound wrappers (`get_my_permissions` already follows this pattern). RLS keeps working (SECURITY DEFINER).
- **Surfaces:** tenant-isolation, api-endpoints reports.

### SEC-M7 — `get_my_permissions()` still grants from the deprecated `profiles.role` branch
- **Location:** `supabase/migrations/020_role_ux_rls.sql:199-262` (last UNION branch reads `profiles.role → roles → role_permissions`); 013 claims the column "fully inert" but declined to touch 020.
- **Problem:** A live second authorization path: dormant today (`profiles_lock_role` trigger blocks writes, `handle_new_user()` forces `'student'`), but if the trigger is ever dropped/bypassed or a platform admin sets an elevated role, permissions silently activate.
- **Fix:** Delete the deprecated branch (fail closed); keep the trigger as defense-in-depth.
- **Surfaces:** backend report.

### SEC-M8 — Core tables have no `CREATE TABLE` in the migration chain; fresh DBs can't rebuild
- **Location:** `supabase/migrations/006_tenant_retrofit.sql` ALTERs tables never created in 001–028 (`students`, `profiles`, `classes`, `staff`, `attendance`, `results`, `exams`, `fees`, `darjas`, `library_books`, `book_issues`, `announcements`, `finance_transactions`, `madrasas`, `devices`, `device_sessions`).
- **Problem:** The chain isn't self-contained: a fresh project (new env, DR, local dev) can't build from migrations alone; RLS policies on nonexistent tables give false confidence in review.
- **Fix:** Add `000_legacy_base_schema.sql` capturing current live DDL (pg_dump --schema-only, reviewed) before 001. Prerequisite for trustworthy backup/restore testing.
- **Surfaces:** backend, tenant-isolation reports.

### SEC-M9 — Session revocation is stored but never enforced ("advisory" only)
- **Location:** `supabase/migrations/018_platform_config.sql` (revocation list in `platform_config`; header documents enforcement as "advisory", no auth hook implements it).
- **Problem:** An admin "revoking" a session writes a record nothing reads at authentication time; compromised sessions stay valid until natural expiry. The revocation list is also world-readable via `platform_config_public_read` (`USING (true)`, 018:149).
- **Fix:** Implement enforcement (Supabase Auth Hook `custom_access_token` or an authorizer) or stop presenting revocation as a security control in the UI.
- **Surfaces:** backend report.

### SEC-M10 — Account enumeration via 409 responses and a dormant login-mapper branch
- **Location:** `supabase/functions/manage-users/index.ts` (`handleCreateUser` → 409 on already-registered email); `provision-tenant/index.ts` (`admin_email_taken` 409); `lib/data/repositories/auth_repository.dart` (`_mapAuthError`: `'یہ اکاؤنٹ موجود نہیں'` branch — dead today since GoTrue returns generic "Invalid login credentials", but a landmine if upstream messages change; `'email not confirmed'` → distinct message reveals existence + correct password).
- **Problem:** Distinct error codes/messages reveal whether an email has an account — a free oracle for targeted phishing.
- **Fix:** Return generic 200/202 ("if the email is new, the account was created") or uniform errors on create paths; collapse all credential failures to one generic message; delete the `'user not found'` branch.
- **Surfaces:** backend, api-abuse, flutter-app reports.

### SEC-M11 — No request body size limits on any Edge Function
- **Location:** `supabase/functions/_shared/guard.ts` (`readJsonBody` → unbounded `req.json()`); `send-notification/index.ts` uses `req.json()` directly.
- **Problem:** Multi-hundred-MB JSON bodies are buffered into memory → per-invocation memory exhaustion (DoS/cost); large payloads flow into unbounded TEXT columns.
- **Fix:** In `readJsonBody`: `Content-Length` pre-check (e.g. 1MB default, higher for export-tenant) + bounded reader → `413`. Headers can lie — enforce during the read too.
- **Surfaces:** api-endpoints, file-uploads, input-validation reports.

### SEC-M12 — `send-notification` has unbounded, untyped body fields
- **Location:** `supabase/functions/send-notification/index.ts:175-177, 251-253, 329-330`.
- **Problem:** `title_urdu`, `body`, `body_urdu` have no length limit and no `typeof` check (`as string` lies if the client sends a number/object); `data` keys/values unbounded (FCM keys must match `[a-zA-Z0-9_-]`, total payload ≤4KB — neither enforced). Reachable by any tenant member.
- **Fix:** `typeof` checks + caps (`title_urdu ≤ 200`, `body`/`body_urdu ≤ 2000`); cap `data` at ~3KB serialized, validate keys, limit key count (≤20).
- **Surfaces:** input-validation report.

### SEC-M13 — No length/format constraints on free-text columns anywhere in the schema
- **Location:** schema-wide (zero `VARCHAR(n)` in the migration set; e.g. `supabase/01_schema.sql:88-114`); only three `char_length` CHECKs exist (017).
- **Problem:** Client validators (`lib/core/utils/validators.dart`) are client-only. Via PostgREST/`sync_apply`, anyone can store a 10MB "name", `phone="abc"`, `email="not-an-email"`. Storage/DoS abuse, broken reports/PDFs (1MB name in an ID card), SMS gateways choking on malformed phones.
- **Fix:** `CHECK (char_length(col) <= N)` on user-facing text (names ≤200, phones ≤32, addresses ≤500, URLs ≤2048, bodies ≤5000); format CHECKs where canonical: phone `~ '^\+?[0-9]{10,15}$'`, email `~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'`. Keep client validators for UX.
- **Surfaces:** input-validation report.

### SEC-M14 — `results.marks_obtained` has no range check and no published state
- **Location:** `supabase/01_schema.sql` (`results`: `marks_obtained NUMERIC(6,2) NOT NULL`, no CHECK; no status column).
- **Problem:** Negative marks or marks > `total_marks` are storable; result cards/percentages/merit lists corrupt. No published/locked state — "final" report cards are mutable forever with no trail beyond the generic audit log.
- **Fix:** `CHECK (marks_obtained >= 0 AND total_marks > 0 AND marks_obtained <= total_marks)`; add `is_published` + immutability trigger once published (corrections via re-issue).
- **Surfaces:** input-validation, database, business-logic reports.

### SEC-M15 — Impossible dates accepted at the DB boundary
- **Location:** `supabase/01_schema.sql:97` (`students.date_of_birth`, `date_of_admit` — no CHECKs; no date CHECKs anywhere in migrations).
- **Problem:** Future DOB, year 0001, admit-before-birth all accepted server-side (client pickers bound the range only). Age calculations, class eligibility, reports silently corrupt.
- **Fix:** `CHECK (date_of_birth IS NULL OR (date_of_birth BETWEEN '1900-01-01' AND CURRENT_DATE))`, `CHECK (date_of_admit >= date_of_birth)`; same for staff joining dates.
- **Surfaces:** input-validation, business-logic reports.

### SEC-M16 — CSV/Excel exports have no formula-injection protection
- **Location:** `lib/core/reports/export/csv_export.dart:27-36` (`_esc` handles only `,"` and newlines); `lib/core/reports/export/excel_export.dart` (no escaping).
- **Problem:** Attacker-controlled strings (names, notes, addresses — no charset validation, SEC-M13) starting with `=`, `+`, `-`, `@` become live spreadsheet formulas. `=cmd|'/c calc'!A0` variants execute on Windows Excel.
- **Fix:** Prefix-escape cells beginning with `=`, `+`, `-`, `@` (prepend `'`); centralize in `tabular_data.dart`.
- **Surfaces:** input-validation report.

### SEC-M17 — `sync_apply` lets clients forge `created_by` / `created_at`
- **Location:** `supabase/migrations/027_user_accounts_app_roles.sql:356-366` (insert), `:440-455` (update) — exclusion lists omit `created_by`; insert also omits `created_at`.
- **Problem:** Any payload key matching a real column is written. `created_by` is the attribution column on finance tables (used by `finance_post_payment` for the ledger) — forging it falsifies the audit trail; backdating `created_at` falsifies record age.
- **Fix:** Add `created_by` to both exclusion lists and stamp server-side (`created_by = auth.uid()` on insert, mirroring the `updated_by` treatment from 027); add `created_at` to the insert exclusion (server default `now()`).
- **Surfaces:** input-validation, frontend-untrusted reports.

### SEC-M18 — Invoice void/cancel needs no reason and no approval
- **Location:** `supabase/migrations/014_finance.sql:1020-1030` (`invoices_update_tenant` WITH CHECK allows `draft/issued → cancelled/void`); void path needs only `fees.collect`.
- **Problem:** A clerk can void an issued invoice (erasing a receivable) with no note and no approver. Audit log records it, but nothing requires justification. (Via `sync_apply` the permission check is absent entirely — SEC-C1.)
- **Fix:** Remove `'cancelled','void'` from the RLS WITH CHECK allow-list; expose voiding only through a dedicated `void_invoice(p_id, p_reason)` RPC requiring a reason string, writing a reversal/audit entry, and enforcing immutability semantics. Consider `finance.approve` for voiding issued invoices.
- **Surfaces:** business-logic, input-validation reports.

### SEC-M19 — Library double-issue race: stock decremented from stale client state
- **Location:** `lib/providers/library_provider.dart:142-207` (`issueBook` computes `book.availableCopies - 1` locally, then syncs); `supabase/05_new_modules.sql` (no server-side decrement on issue, only increment on return).
- **Problem:** Two librarians/devices issuing the last copy both compute 0 from a stale 1; no `CHECK (available_copies >= 0)`; no guard against issuing at 0; no unique guard on unreturned (book_id, borrower).
- **Fix:** `BEFORE INSERT` trigger on `book_issues` that atomically decrements under row lock and raises when it would go negative; keep the client decrement as optimistic UI only; add the CHECK + partial unique index on unreturned issues.
- **Surfaces:** business-logic report.

### SEC-M20 — Discount stacking can drive an invoice negative
- **Location:** `supabase/migrations/014_finance.sql` (`discounts` — percentage capped at 100, but multiple discounts sum unboundedly; `balance_due` generated with no floor).
- **Problem:** 100% + fixed discounts (or two fixed) can make `discount_total > subtotal` → negative `balance_due`; invoice can never be sensibly paid; reports show negative receivables.
- **Fix:** CHECK/trigger `discount_total <= subtotal` (raise inside `finance_recalc_invoice` if violated).
- **Surfaces:** business-logic report.

### SEC-M21 — Attendance: future dates allowed, no locked periods, cascade wipes history
- **Location:** `supabase/01_schema.sql` (`attendance.date` unconstrained; `ON DELETE CASCADE` on student_id/class_id).
- **Problem:** Teachers can mark future attendance; past attendance editable forever (no month-close lock); deleting a student silently deletes their entire attendance history.
- **Fix:** `CHECK (date <= CURRENT_DATE)`; per-tenant `locked_before` period locking; change student FK to RESTRICT or soft-delete students instead.
- **Surfaces:** business-logic report.

### SEC-M22 — Private photo buckets are unrenderable as built (broken-or-dangerous)
- **Location:** `lib/presentation/screens/students/student_widgets.dart:31-32` (plain `NetworkImage`, no auth headers); buckets private per `008_tenant_storage.sql:29-33`.
- **Problem:** `student-photos`/`staff-photos` are private, but the app renders `getPublicUrl` URLs with no `Authorization` header → photos silently never load (functional bug). The "obvious fix" — flipping buckets public — would make minors' photos world-readable at predictable URLs (privacy disaster).
- **Fix:** Do NOT make buckets public. Serve via short-lived signed URLs (e.g. 15-min, minted per view or via a thin Edge Function) or a custom `ImageProvider` attaching the user's JWT (RLS then enforces membership).
- **Surfaces:** file-uploads report.

### SEC-M23 — Storage photo SELECT is membership-only, weaker than the row policy
- **Location:** `supabase/migrations/008_tenant_storage.sql` (`student_photos_select_tenant`: `is_tenant_member(...)` only).
- **Problem:** The `students` table restricts reads to `students.view` holders or the child's own parent, but the photo bucket lets **any** tenant member fetch **any** student photo by path — a parent without `students.view` can download other families' children's photos.
- **Fix:** Mirror the row policy in the storage policy: require `students.view` permission or parent-of-the-student (derive student id from path segment).
- **Surfaces:** tenant-isolation report.

### SEC-M24 — `switchTenant()` accepts any tenant id without membership validation
- **Location:** `lib/core/services/tenant_context.dart` (`switchTenant` sets state unconditionally; only `init()` validates).
- **Problem:** `currentTenantIdProvider` then scopes queries and the sync engine's `_tenantId` to an attacker-chosen tenant. Online reads fail closed via RLS, but the never-purged offline DB is keyed by tenant_id — on a shared device, switching to a previously-cached tenant id exposes that tenant's cached rows offline with no server check.
- **Fix:** Validate `id` against fresh memberships inside `switchTenant` (fail closed, keep previous tenant, log). Defense in depth, cheap.
- **Surfaces:** api-abuse, tenant-isolation, frontend-untrusted reports. (Severity note: frontend-untrusted rated this HIGH in combination with the unwiped offline DB; rated MEDIUM here as a standalone gap — the logout-wipe fix in SEC-H12 is the primary control.)

### SEC-M25 — Offline permission cache is client-writable and UI-trusted
- **Location:** `lib/core/services/permission_service.dart:86-143` (RPC → persisted plaintext cache `authz.perms.v1.*` → static `fallbackFor`); consumed by `authorization_service.dart` / `hasPermissionProvider`.
- **Problem:** Attacker edits the cached set (adds `fees.collect`) → offline UI renders admin screens. The static fallback can grant codes the server revoked. Alone this is UI spoofing — but with SEC-C1 the spoofed actions actually succeed server-side.
- **Fix:** Fix SEC-C1 first (then tampering is UI-only). Additionally: timestamp the cache, expire after N hours (e.g. 24h) → fail closed to read-only/degraded mode with an honest "permissions may be stale" banner; never fall back to `allCodes` for `platform_owner` without a fresh RPC; integrity-protect the cache (HMAC with a secure-storage device key) or don't persist permission sets.
- **Surfaces:** flutter-app, frontend-untrusted reports.

### SEC-M26 — No proactive disabled-account handling on session restore
- **Location:** `lib/providers/auth_provider.dart` (`restoreSession`, `_refreshSessionUser` — no `is_active` check).
- **Problem:** Nothing checks `user_accounts.is_active` or membership `is_active` on cold start/resume/refresh. A deactivated user keeps a valid JWT; RLS denies row access (policies check `tm.is_active` — good), but the app shows generic failures instead of signing out with an "account deactivated" state. The cached session keeps working against any endpoint that doesn't check membership.
- **Fix:** On `restoreSession`/`_refreshSessionUser`, query active membership / `user_accounts.is_active`; if deactivated, `signOut()` + dedicated deactivated screen. (Also the hook for future server-side session revocation.)
- **Surfaces:** flutter-app report.

### SEC-M27 — `log_audit()` lets tenant admins forge or flood audit entries
- **Location:** `supabase/migrations/012_audit_logs.sql` (`log_audit` RPC, `GRANT EXECUTE TO authenticated`).
- **Problem:** Any tenant owner/admin can call `log_audit()` with arbitrary `action`/`entity`/`entity_id`/JSON for their tenant. `user_id` is forced to `auth.uid()` (good — no impersonation), but nothing stops forged actions (`invoice.paid` that never happened) or flooding the log to bury real events (no rate limit; JSONB unbounded).
- **Fix:** Restrict `action` to an allow-listed set (CHECK/validation function); prefer trigger-written rows (like `finance_audit()`) for security-critical entities; cap payload (`octet_length(new_data::text) < 64KB`). Note flooding as residual risk.
- **Surfaces:** error-handling report.

### SEC-M28 — `AppLogger` redacts secrets but not PII; crash logs persist PII in plaintext
- **Location:** `lib/core/observability/app_logger.dart:60-78` (`_sensitiveKey`, `_inlineSecret`); `logCrash` (~:130); logs at `%APPDATA%/Madrassa360/logs` (5×2 MiB rotation, world-readable by local processes/users).
- **Problem:** Redaction covers `password|token|secret|api-key|authorization|bearer|private-key` but not emails/phones/names. `duplicate key … (email)=(…)` or validation text with a phone persists verbatim in log files on shared school computers.
- **Fix:** Extend redaction with email/phone patterns (`[\w.+-]+@[\w-]+\.[\w.]+` → `[EMAIL]`, Pakistani mobile pattern → `[PHONE]`); apply to `logCrash`; document that `context` maps must use IDs, not raw identity fields.
- **Surfaces:** error-handling report.

### SEC-M29 — `ErrorBoundary` adopted in only 6 of 336 catch sites
- **Location:** repo-wide (`grep -rln "ErrorBoundary\." lib` → 6 files vs 336 `catch` sites).
- **Problem:** The taxonomy exists but 330 sites roll their own handling. Most audited samples are benign, but each is an unreviewed disclosure surface — "users never see internals" holds only where the boundary is used. Includes 11 raw-`$e` snackbar sites in `master_admin` screens and `madrasa_provider` storing raw `e.toString()` in displayable state (latent — provider currently unconsumed).
- **Fix:** Migrate tenant-facing screens first (one-line `ErrorBoundary.showErrorSnackBar` per site); add a CI guard (mirroring `tool/no_mock_check.dart`) failing on `showM360SnackBar(context, '...$e')` / `Text('$e')` patterns in `lib/presentation`; document the rule: never interpolate exceptions into widgets.
- **Surfaces:** error-handling, flutter-app reports.

### SEC-M30 — Weak password policy (6 chars, no complexity, no breach check)
- **Location:** `supabase/functions/manage-users/index.ts` (`password.length < 6`); `lib/providers/user_management_provider.dart`; client validators.
- **Problem:** 6-char minimum everywhere; combined with SEC-H8 (no brute-force hardening), short passwords are brute-forceable — especially for tenant-owner/admin accounts.
- **Fix:** Minimum 10–12 chars; enable Supabase Auth leaked-password protection; keep the 6-char floor only where a legacy constraint forces it.
- **Surfaces:** api-abuse, backend, api-endpoints reports.

### SEC-M31 — Peer admins can reset each other's passwords
- **Location:** `supabase/functions/manage-users/index.ts` (`canMutateUser`: `callerRank > 0 && targetRank > callerRank` allows equal-rank mutation).
- **Problem:** `tenant_admin` A can `update_user` `tenant_admin` B (password/email) — lateral takeover between peers with no second pair of eyes.
- **Fix:** Require strictly-greater rank for credential changes (`targetRank >= callerRank` blocks), or require platform-owner approval for admin-credential changes.
- **Surfaces:** api-abuse report.

### SEC-M32 — Unbounded list queries (no pagination caps in the app)
- **Location:** e.g. `lib/data/repositories/finance_repository.dart:594` (`getPayments`: no `.limit()`, plus a `students(name)` embed); only ~14 `.limit(` call sites in `lib/`.
- **Problem:** RLS scopes rows to the tenant, but a large tenant's full table returns in one response — slow, memory-heavy, and a full-dataset scrape in a single request. (PostgREST's 1000-row default cap bounds the worst case but still permits cheap paging scrapes.)
- **Fix:** `.limit()` + keyset pagination (`.lt('created_at', cursor)` / `.range()`) on every list query; never rely on the client to stop paging.
- **Surfaces:** api-endpoints report.

### SEC-M33 — No canonical normalization: phones, emails, names, Urdu text
- **Location:** `lib/core/utils/validators.dart:36` (strips for check only); `staff.dart:61`, `madrasa.dart:65` (store raw); `provision-tenant/index.ts` (trim only); all TEXT writes via PostgREST/`sync_apply`.
- **Problem:** `03001234567` vs `0300-1234567` vs `+923001234567` = 4 identities → duplicate students/staff, failed lookups, SMS to malformed numbers. Email case variants duplicate accounts. Visually identical Urdu names with different codepoints (Arabic vs Farsi Yeh, NFC vs NFD) bypass dedup; zero-width/bidi-control chars storable in names, rendered in reports/ID cards.
- **Fix:** Normalize at write: phones → canonical `+92…` (strip separators, validate); emails → lowercase(trim()); names → trim + collapse whitespace + NFC + strip zero-width/bidi controls + canonicalize Yeh/Kaf variants. Enforce in shared Dart value objects *and* a DB trigger/normalization function so direct API writes are normalized too.
- **Surfaces:** input-validation report.

### SEC-M34 — Cross-tenant FK references are creatable (no composite tenant FKs)
- **Location:** all FKs reference bare `id` (e.g. `invoices.student_id → students(id)`); `sync_apply` INSERT checks payload `tenant_id` membership but never verifies referenced rows belong to that tenant.
- **Problem:** A tenant-A member who learns a tenant-B student UUID can insert an invoice/payment in tenant A pointing at tenant B's student. The row passes FK and RLS. Reports joining without strict tenant filters then leak B's data.
- **Fix:** Defense in depth — in `sync_apply` INSERT, verify every `*_id` FK in the payload resolves to a row with `tenant_id = v_tenant` (whitelisted FK map per entity); longer-term, composite FKs `(tenant_id, id)`.
- **Surfaces:** database report.

### SEC-M35 — `partially_paid`/`overdue` invoices are still mutable
- **Location:** `supabase/migrations/014_finance.sql` — `trg_invoices_guard_immutable` guards only `('paid','cancelled','void')`.
- **Problem:** After a partial payment, `subtotal`/`discount_total` can still be edited directly, changing `total` while `amount_paid` stays fixed → corrupt `balance_due`.
- **Fix:** Extend the guard to `('partially_paid','overdue')` for amount-bearing columns, or make all amount fields immutable once `amount_paid > 0`.
- **Surfaces:** database report.

### SEC-M36 — `approved_by` is client-writable through sync
- **Location:** `supabase/migrations/016_sync.sql` (not in the excluded column list).
- **Problem:** The approver identity — the entire evidence of the approval step — can be set to any UUID by the requester, including self-approving.
- **Fix:** Exclude `approved_by` from sync-writable columns; set it only inside the approve transition (server stamps `auth.uid()`).
- **Surfaces:** business-logic report.

### SEC-M37 — Legacy `fees` table accepts negative amounts, corrupting its generated status
- **Location:** `supabase/01_schema.sql` (`fees.amount_due`, `fees.amount_paid` — no CHECK); still read/written (`lib/data/repositories/fee_repository.dart`, sync entity `'fees'`).
- **Problem:** Negative `amount_due` makes the generated `status` instantly `'paid'`; negative `amount_paid` storable.
- **Fix:** `CHECK (amount_due >= 0 AND amount_paid >= 0)`; decide whether this table is legacy (remove from sync whitelist) or live (harden it).
- **Surfaces:** business-logic report.

### SEC-M38 — Tenant deletion irreversibly wipes all financial history
- **Location:** `supabase/migrations/014_finance.sql` (`ON DELETE CASCADE` on every `tenant_id` FK); inconsistent with 015's RESTRICT (database M-7).
- **Problem:** Deleting a tenant destroys the canonical ledger with no soft-delete, no archive, no DB-level backstop. One privileged misclick (or compromised platform admin) = total, unrecoverable loss for a school. Combined with SEC-M4, the evidence vanishes too.
- **Fix:** Block tenant DELETE at the DB level (trigger) or require two-step archive-then-purge; decide one consistent tenant-delete policy (recommend RESTRICT everywhere + explicit platform-owned archive/wipe procedure).
- **Surfaces:** business-logic, database reports.

### SEC-M39 — RLS permits hard deletes that the sync contract forbids
- **Location:** 014 RLS `…_delete_tenant` policies allow DELETE of draft rows; 016 documents "clients NEVER hard delete through sync_apply" and other devices converge via `'not_found'` → local row dropped.
- **Problem:** A hard delete on one device silently discards other devices' queued edits for that row, and tombstone-based pull never sees it (no `deleted_at` row). Two designs disagree; the stricter one (soft-delete only) should win.
- **Fix:** Remove hard DELETE from RLS policies for synced tables (platform-admin-only if at all); route all deletes through `sync_apply`.
- **Surfaces:** database report.

### SEC-M40 — No documented/tested server backup & restore runbook
- **Location:** repo docs — `docs/BACKUP_RESTORE.md` covers only the local SQLite file; server recovery assumes Supabase PITR without a written procedure.
- **Problem:** No RTO/RPO statement, no restore drill; several migrations are not rollback-safe (no down-migrations; 006's legacy backfill irreversible).
- **Fix:** Write a runbook (PITR steps, who can trigger, verification queries); drill quarterly on a staging project.
- **Surfaces:** database report.

### SEC-M41 — Shared demo password documented in repo
- **Location:** `demo/DEMO_README.md:28` — single shared password for five demo Auth accounts.
- **Problem:** Harmless only if those accounts live on a throwaway demo project; dangerous if any exist on live (public-cloneable repo → anyone can sign in).
- **Fix:** Ensure the five demo accounts exist only on the non-production demo project; if any exist on live, delete them or rotate to per-account random passwords stored outside the repo.
- **Surfaces:** secrets report.

### SEC-M42 — iOS `Info.plist` lacks camera/photo-library usage descriptions
- **Location:** `ios/Runner/Info.plist`; `image_picker` used in 9 Dart files (student/staff photos).
- **Problem:** On iOS, invoking the image picker without `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription` crashes the app; App Store review will reject. Either iOS photo capture is broken in production or silently dead.
- **Fix:** Add both keys with honest Urdu/English strings; test photo capture on a real iPhone.
- **Surfaces:** dependencies report.

### SEC-M43 — CI actions float on mutable tags; Windows installer built by a personal-account action
- **Location:** `.github/workflows/*.yaml` (`actions/checkout@v4`, `subosito/flutter-action@v2`, `denoland/setup-deno@v2`, …, `Minionguyjpro/Inno-Setup-Action@v1.2.2` — a personal account building the distributable `.exe`).
- **Problem:** Mutable tags can be retargeted; a compromised action runs with workflow permissions on the build machine. The Inno Setup action is the highest-value target: it touches the final Windows installer users download.
- **Fix:** Pin all actions to full commit SHAs (keep tags as comments); for Inno Setup, SHA-pin minimum, longer-term vendor the install or use a first-party alternative.
- **Surfaces:** dependencies report.

### SEC-M44 — Refund approve→post is a dead end (broken workflow)
- **Location:** `supabase/migrations/014_finance.sql:815` (`trg_refunds_guard_immutable` treats `'approved'` as final) vs `refunds_post_tenant` RLS (allows approved→posted) and `finance_repository.dart:706` (`transitionRefund`).
- **Problem:** The intended lifecycle draft→approved→posted cannot complete: posting an approved refund raises; `finance_post_refund()` never fires; the refund stays `approved` forever with zero ledger effect while the UI showed local success. Staff will either leave refunds half-done (books wrong) or bypass approval via SEC-C6 (controls erode).
- **Fix:** Change the refunds guard list to `'posted,void'` (matching expenses/income); add a separate transition guard enforcing draft→approved→posted order.
- **Surfaces:** business-logic report.

### SEC-M45 — No audit-log retention, partitioning, or tamper-evidence
- **Location:** (absence) `supabase/migrations/*`; `012_audit_logs.sql`.
- **Problem:** `audit_logs` grows unboundedly (no retention/partitioning); rows have no hash chain, so a service_role compromise (or DB access) can silently rewrite history; `created_at` defaults to `now()` with no backdating protection on service_role writes.
- **Fix:** Monthly range partitioning + documented retention (e.g. 7 years finance, 1 year routine); `prev_hash`/`row_hash` chain (HMAC with a DB-held secret); prefer trigger + `log_audit()` paths over direct service_role writes.
- **Surfaces:** error-handling report.

### SEC-M46 — Deno version floats in CI; `deno.json` check omits `manage-users`
- **Location:** `.github/workflows/ci.yaml` (`denoland/setup-deno@v2`, `deno-version: v2.x`); `supabase/functions/deno.json` (`tasks.check` lists 4 functions, not `manage-users`).
- **Problem:** Edge Function type-checks/lints run against whatever Deno 2.x is newest that day; the most privilege-sensitive function is skipped by the local check task (CI's shell loop does cover it — local-DX only).
- **Fix:** Pin an exact Deno version matching the Supabase Edge Runtime; add `manage-users/index.ts` to the task.
- **Surfaces:** dependencies report.

---

## LOW findings

### SEC-L1 — Globally sequential invoice/receipt numbers leak cross-tenant volume
- **Location:** `supabase/migrations/028_finance_per_table_doc_triggers.sql` (`finance_invoice_seq`, `finance_receipt_seq` global).
- **Problem:** `INV-00000103` then `INV-00000105` tells tenant A another tenant issued an invoice in between — business-volume inference across tenants. Numbers appear in API payloads/exports.
- **Fix:** Per-tenant sequences/counter table (`SELECT … FOR UPDATE`) or a random component. (Also note: payments and income share `finance_receipt_seq` with per-table-only uniqueness — consider per-type prefixes `RCP-`/`INC-`.)
- **Surfaces:** database, tenant-isolation, business-logic reports.

### SEC-L2 — `google_fonts` is an unused dependency
- **Location:** `pubspec.yaml` (`google_fonts: ^6.1.0`); zero imports in `lib/`, `test/`, `tool/`, `android/`, `ios/`.
- **Problem:** Dead weight; worse, if ever imported it would fetch fonts from Google's CDN at runtime — network/privacy liability for an offline-first app handling children's data.
- **Fix:** Remove from `pubspec.yaml`, regenerate lockfile.
- **Surfaces:** dependencies, performance reports.

### SEC-L3 — Two competing SQLite stacks ship in the app
- **Location:** `pubspec.lock` (`sqflite` 2.4.2 via `flutter_cache_manager` 3.4.1 ← `cached_network_image`); app uses drift + sqlite3.
- **Problem:** Two native SQLite implementations, two file formats, larger APK and native attack surface.
- **Fix:** Accept and document, or replace `cached_network_image` with a lighter cache (check whether 4.x drops sqflite during that evaluation).
- **Surfaces:** dependencies report.

### SEC-L4 — Stale comments in `pubspec.yaml` misdescribe pinning
- **Location:** `pubspec.yaml` (drift comment says "Pinned to the 2.31.x line" while `^2.31.0` resolved 2.35.0; same for pdf/printing/firebase).
- **Problem:** Misleading comments cause future maintainers to misjudge upgrade safety.
- **Fix:** Correct comments to describe actual constraints and the real reason for each pin.
- **Surfaces:** dependencies report.

### SEC-L5 — Production builds ship with `ENVIRONMENT=development`
- **Location:** `lib/core/config/app_config.dart:85`; `.github/workflows/build-android.yaml`, `build-windows.yaml` (no `--dart-define=ENVIRONMENT=production`).
- **Problem:** Every shipped build evaluates `isDevelopment == true`. Today it gates nothing — but the first future `if (isDevelopment)` debug bypass (verbose logging, mock data, disabled pinning) would silently ship to production.
- **Fix:** Add `--dart-define=ENVIRONMENT=production` to both build workflows. One line, zero behavior change today.
- **Surfaces:** secrets report.

### SEC-L6 — Wildcard CORS on Edge Functions
- **Location:** `supabase/functions/_shared/guard.ts:11-15` (`Access-Control-Allow-Origin: *`).
- **Problem:** Any website can read responses from privileged functions. Auth is Bearer-JWT (not cookies), so credential leakage/CSRF impact is minimal — broader than necessary, especially with a Flutter web build in the repo.
- **Fix:** Restrict to the app's real origins (`https://madrassa360.com`, localhost dev ports).
- **Surfaces:** api-abuse, api-endpoints, secrets reports. (Severity note: two reports rated MEDIUM; rated LOW here — Bearer auth means `*` cannot leak credentials cross-origin; still worth tightening.)

### SEC-L7 — Postgres `RAISE EXCEPTION` messages reach API callers verbatim
- **Location:** `supabase/migrations/016_sync.sql:238,242,273,310,313`; `014_finance.sql:480-491,602-605`; `007_tenant_rls.sql:774,779`.
- **Problem:** Messages like `sync: not a member of tenant <uuid>` disclose tenant UUIDs and internal state-machine vocabulary; the valid-UUID vs garbage difference is an enumeration oracle.
- **Fix:** Keep detail in the server log (`RAISE LOG`); return short stable codes to clients; at minimum stop echoing UUIDs (`sync: not a member of this tenant`).
- **Surfaces:** error-handling report.

### SEC-L8 — CrashScreen `details` box can show PII
- **Location:** `lib/main.dart:186-190` (`_shortError`); `lib/presentation/screens/crash_screen.dart:78-97`.
- **Problem:** `_shortError` applies secret redaction (not PII redaction) and truncates to 240 chars; the doc comment claims "already-redacted", overstating the guarantee.
- **Fix:** Apply the SEC-M28 PII redaction, or drop the details box in release builds (`kReleaseMode` → null).
- **Surfaces:** error-handling report.

### SEC-L9 — `export-tenant` reports `audit_write_failed` but still hands over data
- **Location:** `supabase/functions/export-tenant/index.ts:206-215`.
- **Problem:** If the audit insert fails, the full-tenant PII export still succeeds — a full exfiltration can occur with no trail if `audit_logs` writes break.
- **Fix:** Keep the behavior (availability), but emit a platform-level alert (log + notify platform admins) on `audit_write_failed`.
- **Surfaces:** error-handling report.

### SEC-L10 — No remote crash reporting; diagnostics die on-device
- **Location:** (absence) `lib/core/observability/*`; `pubspec.yaml`.
- **Problem:** `AppLogger` writes to local files only; support can't see field crashes; users email CrashScreen screenshots instead.
- **Fix:** Add opt-in crash reporting (self-hosted Sentry or Supabase-logged crash pings with SEC-M28 PII redaction). Free-tier, transparent to the user.
- **Surfaces:** error-handling report.

### SEC-L11 — No concurrent-session limit; no session inventory/revocation UI
- **Location:** Supabase Auth defaults; `auth_repository.dart` (`logout()` revokes only the current session).
- **Problem:** Unlimited concurrent sessions; users can't see/revoke other sessions. Combined with SEC-H11, a stolen refresh token lives until natural expiry.
- **Fix:** Accept as documented limitation, or add "sign out all devices" via `manage-users` (admin ban + token invalidation).
- **Surfaces:** api-abuse, flutter-app reports.

### SEC-L12 — `email_confirm: true` bypasses email verification
- **Location:** `supabase/functions/manage-users/index.ts` (`handleCreateUser`: `email_confirm: true`).
- **Problem:** Accounts usable without proving mailbox ownership; a typo'd admin-entered email routes password resets to a stranger.
- **Fix:** Verify-on-first-login or an admin "resend verification" flow.
- **Surfaces:** api-abuse report.

### SEC-L13 — Legacy `01_schema.sql`…`06` SQL files would destroy tenant isolation if re-run
- **Location:** `supabase/01_schema.sql`, `02_rls.sql` (tenant-blind policies e.g. `USING (auth.role()='authenticated')`).
- **Problem:** Nothing stops an operator re-running them and silently dropping tenant isolation.
- **Fix:** Move to `supabase/_archive/` or add a `DO $$ BEGIN RAISE EXCEPTION` guard header.
- **Surfaces:** api-endpoints report.

### SEC-L14 — Internal `finance_*` functions are RPC-callable by any authenticated user
- **Location:** `supabase/migrations/014_finance.sql` (`finance_refresh_invoice_status`, `finance_recalc_invoice` — SECURITY DEFINER, no REVOKE).
- **Problem:** Exposed via `/rpc/` to every authenticated user. They only recompute from existing data (limited direct abuse), but they're internals that shouldn't be public; combined with SEC-C6 they complete the fake-paid workflow without sync.
- **Fix:** `REVOKE EXECUTE … FROM PUBLIC, authenticated, anon` on all `finance_*` internals; keep only documented RPCs granted.
- **Surfaces:** business-logic report.

### SEC-L15 — Certificate serials are client-assigned; duplicates possible
- **Location:** `lib/data/repositories/certificate_repository.dart` (no issuance table by design; serial assigned client-side "until backend exists").
- **Problem:** Two devices can issue the same serial; no server-side uniqueness or verification.
- **Fix:** When the issuance backend is built, assign serials from a per-tenant sequence.
- **Surfaces:** business-logic report.

### SEC-L16 — `schema_migrations` has RLS disabled and no policies
- **Location:** `supabase/migrations/001_*` (only table in the chain without RLS).
- **Problem:** Leaks migration history (feature/fix timeline) to anyone with the anon key. Trivial.
- **Fix:** Enable RLS with a platform-admin-only policy.
- **Surfaces:** backend report.

### SEC-L17 — Search inputs interpolate wildcards / filter syntax
- **Location:** `lib/data/role_ux_repository.dart:705` (`.ilike('name', '%$q%')`); `lib/presentation/screens/master_admin/madrasa_list_screen.dart:106` (`or=` string).
- **Problem:** `%`/`_` act as LIKE wildcards (searching `%` matches everything); `,`/parens in `q` alter the `or=` filter structure after URL-decode. No SQL injection (parameterized), but filter-structure injection is real.
- **Fix:** Escape `%`→`\%`, `_`→`\_` (and `\`) before wrapping; reject/escape `,()` in `or=` strings; centralize in a `SearchSanitizer`.
- **Surfaces:** input-validation report.

### SEC-L18 — `permission_scopes.scope_ref` JSONB has no schema validation
- **Location:** `supabase/migrations/019_role_ux_schema.sql:458`; written from `lib/data/role_ux_repository.dart:605`.
- **Problem:** `scope_type` is CHECK-constrained but `scope_ref` (e.g. `{"class_ids": [...]}`) accepts any JSON; malformed refs fail confusingly at enforcement time.
- **Fix:** CHECK validating `scope_ref` shape per `scope_type` (key allow-list + array length cap), or a trigger.
- **Surfaces:** input-validation report.

### SEC-L19 — Unknown JSON fields silently ignored by Edge Functions (mass-assignment smell)
- **Location:** all 5 Edge Functions (no unknown-key rejection; `sync_apply` ignoring non-column keys is correct).
- **Problem:** A client sending `{"role": "platform_owner"}` to `create_user` gets it silently dropped today — but silent-ignore means a future refactor that starts reading a new key activates an attacker-controlled field with no contract change. Strict schemas fail closed.
- **Fix:** Strict object schemas in the shared guard (allow-list keys per action; 400 on unknown keys).
- **Surfaces:** input-validation report.

### SEC-L20 — `list_users` pre-filter query is unbounded for platform admins
- **Location:** `supabase/functions/manage-users/index.ts:656-664` (output capped at 200, but the membership pre-query `.in("tenant_id", tenantIds)` with up to 1000 tenants has no limit; N+1 `getUserById` per user).
- **Problem:** Large platform deployments exhaust function memory/time; a timing side channel for user enumeration.
- **Fix:** Page the membership query (e.g. 1000-row pages) or push search/limit into the DB query.
- **Surfaces:** input-validation, api-endpoints reports.

### SEC-L21 — `documents` bucket is dead surface
- **Location:** `supabase/migrations/008_tenant_storage.sql` (policies for `documents.manage`); zero references in `lib/`.
- **Problem:** Policies + private bucket for a feature nothing uses — unused attack surface that confuses future auditors.
- **Fix:** Wire the intended document feature through the upload function (SEC-H10) or drop the bucket + policies.
- **Surfaces:** file-uploads report.

### SEC-L22 — Logo/branding download errors are swallowed (`catch (_)`)
- **Location:** `lib/core/reports/report_branding.dart` (bare `catch (_)`).
- **Problem:** Poisoned-cache states are silent; operators get no signal.
- **Fix:** Log branding-fetch failures (host only, never full URL if it could contain secrets) once the SEC-H6 URL allowlist is in place.
- **Surfaces:** file-uploads report.

### SEC-L23 — `check_tenant_access(p_tenant_id)` is a tenant-existence/suspension oracle
- **Location:** `supabase/migrations/023_super_admin.sql` (granted to `authenticated`, boolean for arbitrary UUIDs).
- **Problem:** Anyone can probe whether a tenant UUID exists and whether it's suspended/expired. UUIDs are unguessable so practical risk is low.
- **Fix:** Acceptable to keep; document. Optional: require membership for non-platform callers.
- **Surfaces:** tenant-isolation report.

### SEC-L24 — `send-notification` client-supplied `notification_id` with `ignoreDuplicates`
- **Location:** `supabase/functions/send-notification/index.ts`.
- **Problem:** First-writer-wins idempotency key from the client lets a malicious member squat UUIDs to block legitimate notifications (minor DoS).
- **Fix:** Server-generated ids or per-tenant idempotency scope.
- **Surfaces:** tenant-isolation report.

### SEC-L25 — Realtime posture unverified
- **Location:** (absence) — app uses no Supabase Realtime (no `.channel(` in `lib/`; offline-first, event-driven re-reads).
- **Problem:** If Realtime is enabled on tables project-wide, direct subscribers are still subject to RLS (tenant-scoped) — but this was not verified live.
- **Fix:** Verify live that the `supabase_realtime` publication doesn't expose tables beyond RLS; disable where unused.
- **Surfaces:** tenant-isolation report.

### SEC-L26 — `dead_letter` rows never auto-retry; surfaced only as a badge count
- **Location:** `lib/core/sync/sync_engine.dart` (`_recordFailure` → `dead_letter` after 5 tries); `sync_providers.dart` (badge count).
- **Problem:** Permanently failed rows sit invisible unless the user taps through; no retry/discard affordance wired to the dead-letter list.
- **Fix:** Dead-letter review UI (can share the SEC-M2 screen) with retry and discard actions.
- **Surfaces:** database report.

### SEC-L27 — `book_issues.borrower_id` is free text; FK points at legacy `madrasas`
- **Location:** `supabase/05_new_modules.sql` (`borrower_id TEXT`, no FK); `madrasa_id REFERENCES public.madrasas(id)` (legacy table).
- **Problem:** No referential integrity on borrowers (typos create phantom loans); if `madrasas` is ever dropped, the FK breaks.
- **Fix:** `borrower_student_id UUID REFERENCES students(id)` + `borrower_staff_id UUID` nullable with a CHECK that exactly one is set; repoint `madrasa_id`→`tenants` or drop the column.
- **Surfaces:** database report.

### SEC-L28 — `transactions.reference_id` has no foreign key
- **Location:** `supabase/migrations/014_finance.sql` (`reference_id UUID` + `reference_type` text tag; no FK).
- **Problem:** Referenced payments/refunds/expenses can be deleted (drafts hard-deletable via RLS) leaving ledger rows pointing at nothing; reconciliation breaks silently.
- **Fix:** Polymorphic — add a trigger validating `(reference_type, reference_id)` on insert, or per-type nullable FK columns.
- **Surfaces:** database report.

### SEC-L29 — Migrations 025–028 don't stamp `schema_migrations`
- **Location:** `supabase/migrations/025_*` … `028_*` (zero `schema_migrations` inserts; live ledger reconciled by hand).
- **Problem:** File state and ledger state disagree; a fresh DB built from files alone has an incomplete ledger, breaking audit tooling and idempotency checks.
- **Fix:** Append the standard stamp block to each file.
- **Surfaces:** database report.

### SEC-L30 — Inconsistent `ON DELETE` semantics on tenant FKs
- **Location:** `015_parent_links.sql` (RESTRICT) vs 014/017 (CASCADE).
- **Problem:** Tenant deletion is half-blocked, half-cascading — unpredictable and untestable.
- **Fix:** Decide one policy (recommend RESTRICT everywhere + explicit platform-owned archive/wipe procedure).
- **Surfaces:** database report.

### SEC-L31 — `payments.invoice_id ON DELETE SET NULL` orphans payments while allocations cascade
- **Location:** `supabase/migrations/014_finance.sql`.
- **Problem:** Deleting a draft invoice orphans its payments (`invoice_id → NULL`, money with no bill) while deleting its allocations — payment history loses its invoice link.
- **Fix:** `ON DELETE RESTRICT` on `payments.invoice_id` while allocations exist (force void-then-reversal instead of delete), consistent with the immutability design.
- **Surfaces:** database report.

### SEC-L32 — Failed inserts burn invoice/receipt sequence numbers (audit gap)
- **Location:** `supabase/migrations/014_finance.sql`, `028_*` (`nextval` in `BEFORE INSERT`; later failures burn the number).
- **Problem:** Missing receipt/invoice numbers look like suppressed records — gaps are indistinguishable from fraud.
- **Fix:** Log burned numbers to a `doc_number_gaps` table via exception handler, or document gaps as expected in the auditor's report. Do not reuse numbers.
- **Surfaces:** database report.

### SEC-L33 — Invoice status can move backwards (`issued → draft`)
- **Location:** `supabase/migrations/014_finance.sql` (`invoices_update_tenant` WITH CHECK includes `'draft'`).
- **Problem:** Minor, but a backwards transition shouldn't be legal; lets a user re-open a cancelled-leaning workflow.
- **Fix:** WITH CHECK should require forward transitions from the old status.
- **Surfaces:** business-logic report.

### SEC-L34 — `isPlatformAdmin` never re-checked after sign-in (stale until full re-login)
- **Location:** `lib/providers/auth_provider.dart` (`_checkPlatformAdmin` only in `_handleSignedIn`).
- **Problem:** A demoted platform admin keeps `AuthState.isPlatformAdmin == true` across token refreshes.
- **Why bounded:** `MasterAdminGuard` re-verifies against the server on navigation and fails closed — exposure is the console chrome, not the data.
- **Fix:** Re-run `_checkPlatformAdmin` in `_refreshSessionUser` (two indexed `maybeSingle` reads) or on every `MasterAdminShell` entry.
- **Surfaces:** flutter-app report.

### SEC-L35 — `forgot_password_screen` shows raw `e.message`
- **Location:** `lib/presentation/screens/auth/forgot_password_screen.dart:55`.
- **Problem:** Supabase auth error text displayed directly — generally safe, but implicit contract; bypasses Urdu localization.
- **Fix:** Route through `ErrorBoundary.showErrorSnackBar` like the login screen.
- **Surfaces:** error-handling report.

### SEC-L36 — `platform_config` public read (`USING (true)`) — intentional, keep secret-free
- **Location:** `supabase/migrations/018_platform_config.sql:149` — the only `USING (true)` in the chain.
- **Problem:** None currently — pre-login config by design. Recorded so future reviewers don't "fix" it into a break, and so no secrets are ever stored there.
- **Fix:** None; add a comment guard. Ensure the session-revocation list (SEC-M9) isn't sensitive.
- **Surfaces:** backend report.

### SEC-L37 — Backup manifest is integrity-only, not authenticity
- **Location:** `lib/core/backup/backup_service.dart:350-378` (SHA-256 `data_sha256`).
- **Problem:** SHA-256 detects corruption, not a maliciously crafted backup. Threat model is the device owner attacking themselves — acceptable. Cross-tenant restore correctly blocked; rollback implemented.
- **Fix:** None required; recorded for completeness.
- **Surfaces:** file-uploads report.

### SEC-L38 — `UserManagementNotifier` seeds all system roles when the `app_roles` query fails
- **Location:** `lib/providers/user_management_provider.dart:51-56, 99-118`.
- **Problem:** On `PostgrestException` (including RLS denial) the UI falls back to `AppRole.allSystemRoles` and shows an empty user list as if no users exist — misleading, and masks authorization failures as "not yet set up".
- **Fix:** Distinguish "table missing" from "permission denied": surface RLS denials honestly instead of seeding defaults.
- **Surfaces:** flutter-app report.

---

## Performance findings (availability/UX risk — not counted in security severities)

### PERF-H1 — Sync push is strictly sequential: one HTTPS round-trip per row
- **Location:** `lib/core/sync/sync_engine.dart:710-724` (`pushOnce`), `:802-870` (`_pushRow`, `_callSyncApply`); plus a `Connectivity().checkConnectivity()` platform-channel call per row.
- **Problem:** Marking attendance for a 60-student class = 60 sequential HTTPS round-trips. At 300–600 ms RTT that's 20–60 s of radio time; on flaky networks the batch rarely completes; battery/data drain is severe.
- **Fix:** Batch RPC (`sync_apply_batch(jsonb[])`) applying N rows in one server transaction, or bounded concurrency (4–6 in flight) preserving per-entity FIFO; check connectivity once per batch.

### PERF-H2 — Full sync cycle fires on every connectivity flap and app resume
- **Location:** `lib/core/sync/sync_engine.dart:625-648`, `:685-708`, `:1307-1330` — `syncNow()` = push + pull of 9 entities × 2 passes (live + tombstones) = 18+ sequential HTTPS requests minimum, each selecting all columns, even when nothing changed.
- **Problem:** ~18 round-trips of pure overhead per flap on a quiet DB; mobile networks flap constantly.
- **Fix:** Debounce re-triggers within 60–120 s of a completed cycle; add a cheap "max server_version per tenant" probe to skip unchanged pull passes; back off after consecutive empty cycles.

### PERF-H3 — Student list re-aggregates ALL fees inside `build()` on every keystroke
- **Location:** `lib/presentation/screens/admin/student_list_screen.dart:183-184`, `:461-471`; search `onChanged: (_) => setState(() {})` at `:98`.
- **Problem:** O(fees + students) UI-thread work per keystroke; input lag grows linearly with tenant history.
- **Fix:** Memoize into a derived provider (e.g. `feeStatusByStudentProvider` watching `allFeesProvider`).

### PERF-H4 — APK is 107 MB: 3 ABIs shipped + 37 MB of un-subset fonts (measured)
- **Location:** `build/app/outputs/flutter-apk/app-release.apk` (107,029,599 bytes); `assets/fonts/`; `build-android.yaml:119` (no `--split-per-abi`).
- **Problem:** `libflutter.so` + `libapp.so` + `libsqlite3.so` × 3 ABIs (~80 MB uncompressed; x86_64 is emulator-only). Fonts: JameelNooriNastaleeq 24.8 MB + "Kasheeda-subset" 12.8 MB (25,061 glyphs — not a real subset). A proper Urdu/Arabic/Latin subset (~2k glyphs) would be ~1–2 MB per font.
- **Fix:** `flutter build apk --split-per-abi` (keep AAB for Play); subset both Nastaleeq fonts with `pyftsubset` to the app's character inventory (verify Nastaleeq redistribution license first — already an open item). Estimated achievable: ~35 MB per-ABI APK (~65% reduction).

### PERF-H5 — Dashboard loads ALL fees to compute one number
- **Location:** `lib/providers/dashboard_data_provider.dart:43-50` (`todayCollectionProvider` awaits `allFeesProvider` then filters in Dart); same shape in `finance_overview_provider.dart:183-196`.
- **Problem:** O(all fees) deserialization for a single dashboard number; cost grows with history.
- **Fix:** SQL-side aggregation (`SELECT SUM(amount_paid) FROM fees WHERE paid_date = ?`, GROUP BY student_id for outstanding balances) — local Drift for the offline path.

### PERF-H6 — N+1 provider fan-out on dashboards
- **Location:** `lib/providers/dashboard_data_provider.dart:56-66` (one `examResultsProvider(exam.id)` per exam), `:72-88` (one full attendance query per class).
- **Problem:** 20 exams → 20 sequential result queries; 6 classes → 6 full attendance scans.
- **Fix:** Single aggregate queries: exams-with-zero-results via one LEFT JOIN / NOT EXISTS; attendance flags via one `GROUP BY class_id`.

### PERF-M1 — `saveAttendance` issues ~5 sequential SQLite statements per student
- **Location:** `lib/data/repositories/attendance_repository.dart:150-191`; `sync_engine.dart:475-522`, `:1463-1530`.
- **Problem:** ~300 statements for a 60-student class (inside one transaction — correctness fine, pure waste); 100–300 ms UI-adjacent work on low-end devices.
- **Fix:** Single multi-row upsert for envelopes + single multi-row queue INSERT; one `SELECT id, revision … WHERE id IN (…)` for revisions.

### PERF-M2 — No composite `(tenant_id, server_version)` index for sync pull queries
- **Location:** pull query `lib/core/sync/sync_engine.dart:1334-1342` (`.eq('tenant_id').gt('server_version').order('server_version').limit(500)`); `009_tenant_indexes.sql`, `014_finance.sql` (no such composite).
- **Problem:** Every pull page sorts by `server_version` without a supporting index; at tens of thousands of rows per tenant, every sync cycle pays a sort.
- **Fix:** `CREATE INDEX … ON <table> (tenant_id, server_version)` for each pulled table (migration).

### PERF-M3 — Raw `NetworkImage` in lists: no cache, full-res decode at 52 px
- **Location:** `lib/presentation/screens/students/student_widgets.dart:31-32`, `staff_list_screen.dart:661`, `student_dialogs.dart:697`, `tenant_picker_screen.dart:121` (`cached_network_image` is a dependency but used once).
- **Problem:** Every scroll re-downloads and re-decodes full-resolution photos for 52 px avatars; scroll jank, data use, GC pressure on 2 GB devices.
- **Fix:** `CachedNetworkImage` with `memCacheWidth`/`memCacheHeight` sized to display (e.g. 128 px) everywhere avatars render.

### PERF-M4 — Bootstrap is fully sequential before first frame
- **Location:** `lib/main.dart:104-131` (`_bootstrap` awaits storage → Supabase init → DB open → orientations in series).
- **Problem:** Independent initializations serialized; first frame waits on all disk I/O; hundreds of ms (seconds on slow storage) of extra cold start.
- **Fix:** `Future.wait` the independent inits; show first frame earlier; finish non-critical init behind the auth gate. Measure with `flutter run --trace-startup`.

### PERF-L1 — Dead `OfflineSyncService` still in the tree
- **Location:** `lib/core/services/offline_sync_service.dart` (`init()` never called).
- **Problem:** Dead code ships; a future reader may wire it up and double-sync.
- **Fix:** Delete the file.

### PERF-L2 — RLS per-row function overhead negligible at current scale; pull selects all columns by design
- **Location:** `is_tenant_member()` / `tenant_has_permission()` (STABLE, index-backed EXISTS); `sync_engine.dart:1336`.
- **Problem (non-problem):** Single indexed lookups planned once per query — not a bottleneck until very large tenants. Full-row pull is an accepted offline-first trade-off (tombstone pass correctly selects only `id, server_version`).
- **Fix:** None needed.

---

## Consolidated ROLE × RESOURCE matrix (what the BACKEND enforces)

Roles: `super_admin` (023; seed: platform owner account) · `platform_owner`, `platform_support` (`platform_admins.role`) · `tenant_owner`, `tenant_admin` (004/019) · template roles (`mohtamim`, `naib_mohtamim`, `nazim_*`, `daftar_dar`, `ustad`, `warden`, `mumtahin`, `store_incharge`, `hr_incharge`, … — 021) · legacy codes (`principal`, `accountant`, `teacher`, `librarian`, `hostel_manager`, `parent`, `student`, `staff` — 005). Permission codes: 66 canonical dotted (`students.view` … `tenants.suspend`, `users.create/update/deactivate`, `roles.assign`, `settings.update`, `reports.export`, `finance.approve`, …) + ~56 legacy underscore codes.

**Two enforcement layers — read them together:**

### Layer 1 — Direct PostgREST (RLS policies)

| Resource | super_admin / platform_owner | tenant_owner / tenant_admin | teacher/accountant (perm codes) | student / parent |
|---|---|---|---|---|
| students, classes, darjas, staff, exams | full | full (tenant) | per code (`students.view/create/update`, `academics.manage`) | read own-scoped; no write |
| attendance | full | full | `attendance.mark/edit/delete` + class scope (`scope_allows`) | read own |
| results | full | full | `results.enter/edit` + class scope | read own |
| finance (invoices, payments, income, expenses, accounts…) | full | full | `finance.view/create/update/delete`, `fees.create/collect/refund`; final rows immutable for all | read own invoices (`fees.view`) |
| library | full | full | `library.view/manage` | read |
| notifications | full | full | `notifications.view` | view own + broadcasts; read-receipts |
| documents / photos (storage) | full | full | `documents.manage`, `students.update`, `staff.update` | read (tenant members) |
| tenant settings / logo | full | `settings.update` | — | — |
| users / memberships | full | via 020 RPCs (`roles.assign` or owner/admin) | — | — |
| roles / permissions | full | `roles.assign` (**no grant ceiling** — SEC-H1) | — | — |
| tenants table | full | read own; update with `settings.update` (**no column guard** — SEC-H6) | — | — |
| audit logs | full | read own tenant | — | — |
| licenses / subscriptions | full | read own | — | — |
| platform_admins | **any platform admin (SEC-C5)** | — | — | — |
| Edge: provision/manage/export tenant | platform admin only | — | — | — |
| Edge: manage-users | platform admin; tenant owner/admin; `users.view`/`roles.assign`/`users.deactivate` holders | scoped (rank gates; **bypass for permission-based callers** — SEC-H2; **update_user on view right** — SEC-C4) | — | — |
| Edge: send-notification | yes | **any member (SEC-H4)** | **any member (SEC-H4)** | **any member (SEC-H4)** |
| user_accounts | platform admin | **any member of any tenant can SELECT (SEC-H5)** | — | — |

### Layer 2 — The app's actual write path: `sync_apply` RPC (SEC-C1) ⚠️

**Overrides Layer 1 for every write the app performs.** Effective rule today: *any active member of the tenant (student, parent, teacher, …) can create/update/delete any of the 26 synced entities in their own tenant.* Cross-tenant writes are blocked; per-role/per-permission distinctions are **not enforced**. Until SEC-C1 is fixed, the Layer-1 matrix describes reads and direct-API writes only.

---

## Auth lifecycle table (consolidated)

| Area | Verdict | Evidence / notes |
|---|---|---|
| Login | PASS w/ GAP | Supabase `signInWithPassword`; generic GoTrue credential errors. GAP: brute force = platform defaults only; no CAPTCHA; no client backoff (SEC-H8) |
| Logout | PASS | `auth.signOut()` revokes refresh token server-side; full local cache purge — **but local DB file is NOT deleted (SEC-H12)** |
| Session expiry | PASS | Failed refresh → SIGNED_OUT → login route; gotrue stream errors handled via `onError` |
| Refresh tokens | GAP | SDK rotation works; tokens in **unencrypted** SharedPreferences; `allowBackup` defaults true (SEC-H11) |
| Password reset | **FAIL** | Email sent, but no `redirectTo`, no recovery handler, no new-password screen — flow cannot be completed (SEC-H13) |
| Email/phone verification | GAP | `email_confirm:true` bypasses verification (SEC-L12); no phone verification |
| Account creation | PASS | Via `manage-users:create_user` only; no self-registration |
| Account deletion | PASS | Via `manage-users:delete_user`; last-owner and last-platform-admin guards hold |
| Role changes | **FAIL** | Three bypasses: direct `tenant_memberships` write allows self-promotion (SEC-H3); `update_user` right confusion (SEC-C4); `app_metadata` mass assignment (SEC-H15). `protect_last_owner` covers only the last-owner case |
| Admin creation | PASS w/ HOLE | `set_platform_role` requires `platform_owner` — but direct `platform_admins` writes have no such gate (SEC-C5) |
| Impersonation | PASS | No such feature; nothing to exploit |
| Session revocation | PASS w/ GAP | Server-side on sign-out; GAP: password change doesn't revoke other sessions; no session inventory UI (SEC-L11); admin "revocation" list is advisory-only (SEC-M9) |
| Concurrent sessions | GAP | Not limited; no UI to view/revoke |
| Disabled users | PASS | `ban_duration: 876000h` via `set_active`; banned users fail refresh → signed out. GAP: no proactive client check on session restore (SEC-M26) |
| Deleted users | PASS | `auth.admin.deleteUser`; memberships cascade; client routes to login |

---

## Tenant trust summary (consolidated)

| # | Data path | Tenant derived from auth? | Verdict |
|---|---|---|---|
| 1 | PostgREST on 25+ tenant tables (007/014/020) | ✅ `auth.uid()` → memberships → `tenant_id` | PASS |
| 2 | `sync_apply` insert/update/delete (016) | ⚠️ membership only, no permission check | **FAIL (SEC-C1)** |
| 3 | `sync_apply` `already_exists` row return (016) | ❌ none before return | **FAIL (SEC-C2)** |
| 4 | `tenants` UPDATE (027) | ✅ membership+permission, **no column guard** | **PARTIAL (SEC-H6)** |
| 5 | `madrasas` SELECT (027) | ❌ broken scoping (`id` binds to `tenants.id`) | **FAIL (SEC-H7)** |
| 6 | `user_accounts` SELECT (027) | ❌ any-membership = all rows | **FAIL (SEC-H5)** |
| 7 | Permission-oracle RPCs (`user_effective_permission` etc.) | ❌ arbitrary args, granted to `authenticated` | **FAIL (SEC-M6)** |
| 8 | `check_tenant_access`, `get_my_permissions*` | ✅ `auth.uid()` | PASS (existence-oracle note SEC-L23) |
| 9 | `log_audit()` (012) | ✅ `auth.uid()` + admin checks | PASS |
| 10 | `send-notification` | ⚠️ membership only, no permission | **PARTIAL (SEC-H4)** |
| 11 | `export-tenant` / `manage-tenant` / `provision-tenant` / `manage-users` | ✅ platform-admin or scoped rank/permission | PASS (with SEC-C4/SEC-H2 holes noted) |
| 12 | Storage writes (`tenant-logos`, photos) | ✅ path segment → membership + permission | PASS (content validation missing — SEC-H10) |
| 13 | Storage `student-photos`/`staff-photos` reads | ⚠️ membership only (no `students.view`) | **PARTIAL (SEC-M23)** |
| 14 | Sync pull / app queries | ✅ RLS backstop (fail-closed) | PASS |
| 15 | Global search, PDF/CSV exports | ✅ client-side over active-tenant data | PASS |
| 16 | Realtime subscriptions | n/a (unused by app) | VERIFY LIVE (SEC-L25) |
| 17 | Local Drift cache across logout | ❌ no wipe | **FAIL (SEC-H12)** |
| 18 | Invoice/receipt numbers | ❌ global sequences | PARTIAL (SEC-L1) |
| 19 | `switchTenant()` client context | ⚠️ not validated (server fail-closed) | PARTIAL (SEC-M24) |
| 20 | Background jobs / cron | none found | PASS |

---

## Verified clean / sound (do not regress)

- **No live server-only secret** in the working tree or any of the 83 commits: no service_role key, DB password, private key, or cloud credential. Edge Functions read all secrets from env. CI uses `${{ secrets.* }}`. `AppLogger` has real secret redaction. No `http://` URLs; no cleartext traffic. (The legacy JWT incident was scrubbed 2026-09-25; revocation unverified — SEC-H18.)
- **All `SECURITY DEFINER` functions set `search_path = public`** — no search_path injection surface. `sync_apply` whitelists entities via `CASE` + `%I` quoting — no SQL injection through `p_entity`. All Edge Function DB access is via the parameterized supabase-js builder.
- **Tenant-bound storage paths**: `storage_path_tenant()` UUID-regexes the first segment, fail-closed on malformed paths; no cross-tenant read/write path in storage policies.
- **Sound backstops (keep):** `prevent_tenant_id_change` (006), `protect_last_owner` (019), `profiles_lock_role` (007:769), delegation ceiling (019), finance final-row immutability (RLS + backstop trigger, 014:786), atomic per-table doc-number sequences (028), `is_tenant_member()` requiring `is_active`, `scope_allows()` fail-closed class scoping (020), append-only `audit_logs` via SECURITY DEFINER trigger, `log_audit()` forcing `user_id = auth.uid()`, backup/restore cross-tenant block + pre-restore snapshot + rollback.
- **`sync_apply` correctly:** blocks cross-tenant writes (insert: payload-tenant membership; update/delete: existing row's tenant, client value ignored), strips server-managed columns (`id`, `tenant_id`, `revision`, `server_version`, `deleted_at`, `created_at`, `updated_at`, plus `updated_by` since 027).
- **No WebView/HTML/Markdown rendering** of untrusted content in the app (all user content via `Text`); no deep-link handlers; no client-held FCM server keys; clipboard copies only non-sensitive support text.
- **`MasterAdminGuard`** re-verifies platform-admin status server-side and fails closed; `profiles.role` locked by trigger with `handle_new_user()` forcing `'student'`; `fees.delete`/`users.manage` correctly absent → fail closed; `user_effective_permission` consults only server-side tables (never `app_metadata`/`profiles.role`/`user_accounts.role_name`) — the privilege *model* is sound; the holes are in the *write paths*.
- **Logout revokes server-side** (`auth.signOut()`); gotrue stream errors handled with `onError` (no CrashScreen on dead network); record IDs are UUIDv4 (no predictable-ID enumeration); no SSRF in Edge Functions (no caller-supplied URLs fetched); no impersonation feature; `tenant_memberships` SELECT is self-only + admins.
- **Dependencies:** 0 OSV hits across 19 key packages; all 179 packages from pub.dev (no git/path deps); Edge Function remote imports exact-pinned (`@supabase/supabase-js@2.44.4` + `deno.lock` hash); Android permissions minimal (`INTERNET` + `ACCESS_NETWORK_STATE`); Gradle/AGP/Kotlin current; installer downloads nothing remote.
- **Error handling:** `ErrorBoundary` + `AppException` taxonomy (safe localized user messages, technical detail to logs only) — correct where adopted; Edge Function top-level catch-alls and `guard.ts` use safe generic codes; zero `print()`/`debugPrint()` in `lib/`; sync engine never surfaces RPC error text to users.

---

## Disagreements between raw reports (resolved)

1. **Tenant-row column guard** (`tenants_member_update`): tenant-isolation rated CRITICAL, file-uploads rated HIGH. Resolved as **SEC-H6 HIGH** — exploitation requires an already-privileged `settings.update` holder; the material impact is platform-enforcement defeat, not a low-priv breach.
2. **Logo upload arbitrary bytes**: file-uploads rated CRITICAL, consolidated as **SEC-H10 HIGH** — same reasoning (requires `settings.update`); it remains the highest-impact upload issue.
3. **`switchTenant()` validation**: frontend-untrusted rated HIGH (in combination with the unwiped offline DB), consolidated as **SEC-M24 MEDIUM** standalone — the logout-wipe fix (SEC-H12) is the primary control.
4. **Wildcard CORS**: two reports MEDIUM, secrets LOW. Consolidated as **SEC-L6 LOW** — Bearer-JWT auth (not cookies) means `*` cannot leak credentials cross-origin.
5. **Refund approve→post dead end**: business-logic rated CRITICAL, consolidated as **SEC-M44 MEDIUM** — it is a broken workflow (functionality bug), not an exploitable vulnerability; it matters because it erodes controls (staff bypass approval when the sanctioned path fails).

---

## Method and limitations

- **Static analysis only.** All 14 workstreams were read-only: migrations, Edge Function source, Flutter source, manifests, workflows, git history. No live exploit testing was performed against the production Supabase project.
- **Before remediation is declared complete**, the CRITICAL/HIGH findings should be re-verified adversarially against a staging clone (or live, read-only where possible): the cross-tenant isolation test plan in `docs/audit/security/raw/tenant-isolation.md` §(c) maps 1:1 to findings SEC-C1…SEC-M23 and is designed for exactly this.
- **The central architectural finding:** the app has two authorization regimes — strict RLS transition policies for direct PostgREST writes, and membership-only `sync_apply` for all real writes. Every RLS rule stricter than CHECKs+triggers is currently decorative. Remediation must converge on ONE enforced path: harden `sync_apply` per-entity (status/permission/column rules) or move financial writes to dedicated RPCs and shrink the sync whitelist to non-financial entities.
- **Out of scope for this audit:** penetration testing of the Supabase platform itself, social-engineering/phishing resistance, and the physical security of user devices (beyond the on-device findings above).
