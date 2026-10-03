# Backend Security Audit — Madrassa-360

- **Date:** 2026-10-03
- **Auditor role:** senior security engineer (read-only audit; no code modified)
- **Repo:** `~/workspace/madrassa-redesign-fix`, branch `redesign/ux-v2`
- **Scope:** `supabase/migrations/` (001–028), all `SECURITY DEFINER` functions/RPCs,
  all triggers, all Edge Functions in `supabase/functions/`, storage buckets +
  storage policies, secrets hygiene.
- **Threat model:** attacker holds a **valid low-privilege account** (e.g. a
  `student` or `parent` membership in a tenant) **plus the anon key**. The
  attacker can call PostgREST, any RPC, and any Edge Function directly —
  frontend restrictions are assumed bypassed.

## Method

Every migration was read in order (001→028). Policy inventory was built by
extracting every `CREATE POLICY`, every `SECURITY DEFINER` function, every
trigger, and every `ALTER TABLE … ENABLE ROW LEVEL SECURITY` from the chain.
Edge Functions were read in full. Claims (a)–(d) were re-verified against the
SQL text, not taken on trust.

## Independently verified claims

| # | Claim | Verdict |
|---|-------|---------|
| (a) | `sync_apply` RPC lacks per-table permission hardening | **CONFIRMED** — `016_sync.sql:312,367` checks only `is_platform_admin() OR is_tenant_member(v_tenant)`. No permission-code check per entity/op. Header documents this as known. |
| (b) | `user_accounts` has no `tenant_id` | **CONFIRMED** — `027_user_accounts_app_roles.sql:48-59`: columns are `id,name,email,role_name,role_name_urdu,linked_staff_id,linked_parent_id,is_active,created_at,updated_at`. No tenant scoping possible; header flags it. |
| (c) | `fees.delete` permission is not seeded | **CONFIRMED** — `005_rbac.sql` seeds `fees.view/create/collect/refund` only; `grep -c "fees.delete"` = 0 in 005 and 019. |
| (d) | `users.manage` permission is not seeded | **CONFIRMED** — `005_rbac.sql` seeds `users.view/create/update/deactivate` only; `grep -c "users.manage"` = 0 in 005 and 019. `027` works around it with the three existing codes. |

---

# FINDINGS

## CRITICAL

### C1 — `sync_apply` lets ANY active tenant member write ANY synced entity (no per-table permission check)

- **File/location:** `supabase/migrations/016_sync.sql:312` (insert), `:367` (update/delete); entity whitelist `:246-271`.
- **Problem:** The sole authorization check in `sync_apply` is
  `is_platform_admin() OR is_tenant_member(v_tenant)`. There is **no mapping
  of entity → required permission code** (e.g. `invoices` should need
  `finance.create`, `results` should need `results.enter`). Cross-tenant
  writes are blocked (insert uses the payload's `tenant_id` after a
  membership check; update/delete re-read the existing row's `tenant_id` and
  never trust the client's), but **within a tenant every active member —
  including `student` and `parent` — can INSERT/UPDATE/DELETE all 26
  whitelisted entities**: `students, staff, attendance, exams, results,
  announcements, library_books, book_issues, accounts, fee_structures,
  fee_items, invoices, invoice_items, payments, payment_allocations, refunds,
  discounts, scholarships, expenses, income, transactions`, etc.
- **Why it matters:** The app's own sync engine is documented as *"the only
  writer to the server (via the `sync_apply` RPC)"*
  (`lib/data/repositories/fee_repository.dart:10`,
  `lib/data/repositories/attendance_repository.dart:8`,
  `lib/core/sync/sync_engine.dart:796`). That means the carefully-built
  per-permission RLS policies in 007/014/020 are **bypassed on the write
  path the app actually uses**. The RLS layer only constrains direct
  PostgREST calls, which the app does not make for writes.
- **Attack scenario:** Attacker registers as (or compromises) a low-privilege
  `student` account in tenant T. Using the anon key they call
  `rpc('sync_apply', {p_entity:'invoices', p_op:'insert', p_payload:{tenant_id:T,
  student_id:…, total_amount:1, status:'paid'}})` — or worse,
  `p_entity:'payments'` to fabricate payment receipts, `p_entity:'results'`
  to alter grades, `p_entity:'fee_structures'` to zero out fees. All succeed
  because membership is the only gate. Financial immutability triggers (014)
  stop *overwriting finalized* rows, but do not stop *creating* fraudulent
  rows or editing non-final ones.
- **Recommended fix:** Add an entity→operation→permission-code map inside
  `sync_apply` (fail closed: unknown entity/op → deny) and enforce
  `tenant_has_permission(v_tenant, code)` alongside the membership check.
  Until then, treat every write as privileged. Long-term, consider moving
  the permission check into a single `sync_required_permission(p_entity,
  p_op)` helper covered by tests.

---

## HIGH

### H1 — `manage-users` Edge Function: permission-based callers bypass the rank ceiling

- **File/location:** `supabase/functions/manage-users/index.ts` —
  `canMutateUser()` (~line 560), `assignRoleGate()` (~line 585).
- **Problem:** The rank ceiling only applies to legacy rank-based callers
  (`callerRank > 0`). Callers authorized via **permission codes** (template
  roles, `callerRank === 0`) skip it:
  - `canMutateUser`: for `callerRank === 0` the check
    `callerRank > 0 && targetRank > callerRank` is skipped; only `tenant_owner`
    targets and platform admins are protected. A custom-role holder with
    `users.deactivate` can **ban/deactivate a `tenant_admin` (rank 90)**.
  - `assignRoleGate`: for `callerRank === 0` only the literal
    `'tenant_owner'` assignment is blocked — a holder of `roles.assign` can
    **assign `tenant_admin` to anyone (including themselves)**.
- **Why it matters:** `tenant_roles` are per-tenant editable (019/020/021);
  a tenant owner can legitimately create a "junior admin" custom role with
  `users.deactivate`/`roles.assign`. That junior admin can then deactivate
  the real `tenant_admin` (DoS / lockout) and promote an accomplice to
  `tenant_admin`. Privilege escalation *within* the tenant, using only
  granted permissions.
- **Attack scenario:** Owner creates custom role "office assistant" with
  `users.view, users.deactivate, roles.assign`. Attacker with that role calls
  `manage-users` `set_active` on the tenant_admin's user id → admin is banned
  (`ban_duration: 876000h`). Attacker then calls `assign_role` with
  `role: 'tenant_admin'` on their accomplice → full tenant control.
- **Recommended fix:** Enforce a rank/authority ceiling for permission-based
  callers too: derive an effective max rank from the caller's granted codes
  (or require an explicit `users.manage`-style senior code), and require
  caller rank **strictly greater** than the target's rank for both mutation
  and assignment. Never allow assigning `tenant_admin` (or any rank ≥ own)
  without being `tenant_owner`.

### H2 — `assign_tenant_role` / `set_user_permission` / `set_role_permissions` RPCs have no grant ceiling

- **File/location:** `supabase/migrations/020_role_ux_rls.sql` —
  `assign_tenant_role()` (~line 580), `set_role_permissions()` (~line 613),
  `set_user_permission()` (~line 660).
- **Problem:** All three require only `is_tenant_admin() OR
  tenant_has_permission(…, 'roles.assign')`, but then allow granting
  **anything**:
  - `assign_tenant_role` can assign **any** role key, including
    `tenant_owner` — no check that the caller outranks the granted role.
  - `set_user_permission` can grant **any** permission code to **any** user
    (including self) without the caller effectively holding that code. (The
    *delegation* trigger in 019 correctly enforces "delegator must hold the
    code"; this RPC does not.)
  - `set_role_permissions` can add any codes to any role.
- **Why it matters:** `roles.assign` becomes a de-facto "become owner" code.
  The delegation ceiling (019) shows the designers knew this pattern; the
  management RPCs missed it.
- **Attack scenario:** Attacker holds a custom role with `roles.assign` (or
  receives it via a legitimate delegation). They call
  `assign_tenant_role(tenant, self, 'tenant_owner')` → instant tenant owner.
  Even without that: `set_user_permission(tenant, self, 'finance.delete',
  'grant')` for every code → full permissions.
- **Recommended fix:** Add ceilings: (a) `assign_tenant_role` may not assign
  `tenant_owner` unless caller is `tenant_owner`; may not assign a role whose
  effective permission set exceeds the caller's; (b) `set_user_permission`
  may not grant a code the caller does not effectively hold (mirror the
  delegation ceiling); (c) same for `set_role_permissions`.

### H3 — `send-notification`: any tenant member can broadcast to all members

- **File/location:** `supabase/functions/send-notification/index.ts`
  (~line 330: authorization block).
- **Problem:** Authorization is "platform admin OR **any active member of the
  tenant**". No permission check (e.g. `notifications.send`). A caller can
  trigger push + email fan-out to **all active members (up to 2000)** with
  arbitrary `title`/`body`. The 017 migration's own design notes say
  *"Direct INSERT is platform-admin only, so a compromised client token
  cannot spam a tenant's broadcasts"* — but the Edge Function re-opens
  exactly that spam path to every member.
- **Why it matters:** Mass-notification spam and phishing ("Pay fees to this
  account…") from a compromised student/parent account, delivered through the
  madrassa's trusted push/email channel. Additionally the email fan-out puts
  up to 200 addresses in a single Resend `to:` list, so **recipients see each
  other's email addresses** (member PII disclosure).
- **Attack scenario:** Attacker with a student account calls
  `send-notification` with `user_id: null` (broadcast), `title_urdu` mimicking
  the principal, `body` containing a phishing payment link, `channels:
  ['push','email']` → every parent/teacher gets it.
- **Recommended fix:** Require `tenant_has_permission(tenant_id,
  'notifications.send')` (020 helper) for broadcasts; targeted sends require
  membership only for self. Send emails per-recipient (or BCC). Add length
  caps on `body`/`body_urdu` (currently uncapped; FCM data limit is 4KB).

### H4 — Tenant suspension is split-brain: `manage-tenant` writes `status`, `check_tenant_access` reads `suspended`

- **File/location:** `supabase/functions/manage-tenant/index.ts` (sets
  `tenants.status = 'suspended'`); `supabase/migrations/023_super_admin.sql:49`
  (adds `suspended BOOLEAN` column); `:102-121` (`check_tenant_access()`
  reads `t.suspended`).
- **Problem:** Two independent suspension flags exist. `manage-tenant` —
  the only writer — sets the `status` **string**. `check_tenant_access()`
  (the RPC the app's AuthGate consults) reads the `suspended` **boolean**,
  which **nothing ever sets** (no trigger, no function, no edge function
  writes `suspended = true`). Worse, **no RLS policy anywhere checks
  suspension or expiry** — a "suspended" tenant's members pass every RLS
  policy unchanged.
- **Why it matters:** Suspending a tenant (non-payment, abuse) does not
  actually revoke access at the backend layer. It is cosmetic.
- **Attack scenario:** Tenant is suspended for non-payment via the platform
  console. Members keep using the app: `check_tenant_access()` still returns
  true (boolean untouched), all RLS passes (no policy checks it), sync and
  reads continue indefinitely.
- **Recommended fix:** Single source of truth. Either (a) make
  `manage-tenant` set `suspended = true/false` (and `expires_at`) and keep
  `check_tenant_access` as the gate, **and** add a suspension check to
  `is_tenant_member()` or to the base RLS policies; or (b) rewrite
  `check_tenant_access` to read `status`. Option (a) is safer — RLS must
  enforce it, not just the client gate.

### H5 — `tenant-exports` bucket is not version-controlled; full-tenant PII exports land there

- **File/location:** `supabase/functions/export-tenant/index.ts:60`
  (`BUCKET = "tenant-exports"`); no `INSERT INTO storage.buckets` for it in
  any migration (008 creates only `student-photos`, `staff-photos`,
  `documents`; 024 creates `tenant-logos`).
- **Problem:** `export-tenant` (platform-admin only, good) writes a JSONL
  file containing **every row of 21 tenant tables** — students, parents
  (via guardians), staff, invoices, payments, results — to
  `exports/{tenant_id}/{timestamp}.jsonl` in a bucket that **does not exist
  in version control**. Either the function is broken in production (bucket
  missing → upload fails), or the bucket was created manually in the
  dashboard with **unknown, unreviewed storage policies**. A permissive
  manual policy (e.g. authenticated read) would expose one tenant's full
  export to any authenticated user of any other tenant.
- **Recommended fix:** Create the bucket + strict storage policies in a new
  migration (private bucket; read = `is_platform_admin()` only; path prefix
  `exports/{tenant_id}/`); then verify the **live** bucket's actual policies
  in the Supabase dashboard and reconcile.

---

## MEDIUM

### M1 — `get_my_permissions()` still grants permissions from the "deprecated" `profiles.role` branch

- **File/location:** `supabase/migrations/020_role_ux_rls.sql:199-262`
  (`get_my_permissions`, last UNION branch reads `profiles.role →
  roles → role_permissions`).
- **Problem:** 013 (`013_auth_cleanup.sql`) claims `profiles.role` is
  "fully inert" and documents that *"no RLS policy and no SECURITY DEFINER
  function reads profiles.role"* — but 020's `get_my_permissions()` does
  exactly that, and 013 explicitly declined to touch 020. Today the
  `profiles_lock_role` trigger (007:769) blocks non-admin role writes and
  `handle_new_user()` forces `'student'`, so the branch is dormant. But it is
  a **live second authorization path**: if the trigger is ever dropped,
  bypassed (e.g. by a future migration), or a platform admin sets an
  elevated role, the permissions silently activate for anything consuming
  `get_my_permissions()` (the client's `PermissionService`).
- **Recommended fix:** Delete the deprecated branch (fail-closed: unknown →
  no permissions). Keep the trigger as defense-in-depth.

### M2 — `manage-users` accepts arbitrary caller-supplied `app_metadata`; the client trusts `appMetadata['role']`

- **File/location:** `supabase/functions/manage-users/index.ts:357,394,455-456`;
  `lib/data/repositories/auth_repository.dart:78-80`;
  `lib/providers/user_management_provider.dart:160`.
- **Problem:** `create_user`/`update_user` copy caller-supplied
  `app_metadata` verbatim into the Auth user. The Flutter client resolves
  the user's role with *"Prefer app_metadata (set by admin/service key),
  fall back to profiles table"* — and the app's own provider **sends**
  `'app_metadata': {'role': account.roleName}` from client input. A caller
  with `users.create`/`users.update` can therefore stamp
  `app_metadata: {role: 'superAdmin'}` on an account, and the app will treat
  that user as platform super-admin (`isPlatformRole`, SuperAdminDashboard).
- **Why it matters (bounded):** Backend Edge Functions re-check
  `platform_admins`/`super_admins` **tables**, not `app_metadata`, so this
  does not escalate at the database/RPC layer — every privileged action
  still fails server-side. Impact is client-side: admin UI exposure,
  confused-deputy screens, and a trust anchor the client treats as
  server-issued but is actually caller-controlled.
- **Recommended fix:** Strip `app_metadata` from caller input in
  `manage-users`; the server should derive and set it from the resolved
  role/membership. Never accept authorization-relevant claims from the
  client.

### M3 — Core tables have no `CREATE TABLE` in the migration chain (fresh DBs can't be rebuilt)

- **File/location:** `supabase/migrations/006_tenant_retrofit.sql`
  (ALTERs `darjas, classes, students, staff, attendance, fees, exams,
  results, announcements, darja_sections, library_books, book_issues,
  finance_transactions` that are **never created** in 001–028); same for
  `profiles`, `madrasas`, `devices`, `device_sessions`.
- **Problem:** The migration chain is not self-contained: it retrofits a
  legacy schema whose DDL lives nowhere in version control. A fresh project
  (new environment, disaster recovery, local dev) cannot be built from
  migrations alone — `006`'s `ALTER TABLE … ADD COLUMN` would fail on
  missing tables, and the 56 RLS policies in 007 target tables with no
  recorded definition.
- **Recommended fix:** Add a `000_legacy_base_schema.sql` migration capturing
  the current live DDL of those tables (pg_dump --schema-only, reviewed),
  placed before 001. This is also a prerequisite for trustworthy
  backup/restore testing.

### M4 — Session revocation is stored but never enforced ("advisory" only)

- **File/location:** `supabase/migrations/018_platform_config.sql`
  (revocation list in `platform_config`; header documents enforcement as an
  "advisory" contract with no auth hook / Edge Function implementing it).
- **Problem:** An admin "revoking" a session writes a record that nothing
  reads at authentication time. Compromised sessions stay valid until natural
  expiry. Additionally the revocation list itself is world-readable via the
  `platform_config_public_read` `USING (true)` policy (018:149) — low
  sensitivity, but worth noting.
- **Recommended fix:** Implement enforcement (Supabase Auth Hook
  `custom_access_token` or a `send-notification`-style authorizer), or stop
  presenting revocation as a security control in the UI.

### M5 — `user_accounts` is unscoped: any member of any tenant can read all rows; writes are tenant-agnostic

- **File/location:** `supabase/migrations/027_user_accounts_app_roles.sql:93-107`
  (`user_accounts_select_member`: any user with ≥1 active membership in **any**
  tenant can SELECT **all** rows).
- **Problem:** This is the documented consequence of claim (b) — no
  `tenant_id` column. A student in tenant A can list every user account
  (names, emails, role names) across all tenants. Writes require holding
  `users.create/update/deactivate` in ≥1 tenant, but the grant is not tied
  to the row's tenant — a user-manager in tenant A can create/disable
  accounts that belong to tenant B.
- **Recommended fix:** Add `tenant_id` (nullable initially, backfill from
  `linked_staff_id`/email domain heuristics, then NOT NULL) and scope all
  four policies by it.

### M6 — No server-side upload validation (type/size) for storage

- **File/location:** `supabase/migrations/008_tenant_storage.sql`
  (policies check bucket + tenant path + permission code only);
  `024_tenant_logos.sql` (same pattern); client upload path
  `lib/core/sync/sync_engine.dart:901` (`uploadBinary`, no `contentType`
  enforcement found in `storage_service.dart` / `storage_repository.dart`).
- **Problem:** Nothing server-side constrains MIME type or file size. Any
  holder of `students.update` / `documents.manage` / logo rights can upload
  arbitrary content (HTML/JS → stored-XSS if ever served inline; multi-GB
  files → storage quota/cost abuse). Path traversal is handled
  (`storage_path_tenant()` UUID-regexes the first segment, fail-closed on
  malformed paths), and tenant isolation on read/write is correct — this is
  purely a content-validation gap.
- **Recommended fix:** Enforce an allowlist (`image/jpeg`, `image/png`,
  `image/webp`, `application/pdf`) and size cap in the storage policies via
  `storage.objects` metadata checks, or front uploads with a small validation
  Edge Function; serve with `Content-Disposition: attachment` for documents.

### M7 — Account enumeration via 409 responses

- **File/location:** `supabase/functions/manage-users/index.ts`
  (`handleCreateUser` → 409 on already-registered email);
  `supabase/functions/provision-tenant/index.ts` (`admin_email_taken` 409).
- **Problem:** Distinct error codes/messages reveal whether an email address
  has an account. Low value (emails of staff are often semi-public), but it
  is a free oracle for targeted phishing.
- **Recommended fix:** Return a generic 200/202 ("if the email is new, the
  account was created") or a uniform error for create paths.

---

## LOW

### L1 — Password minimum of 6 characters
- `provision-tenant/index.ts` (`admin.password: minimum 6 characters`) and
  `manage-users/index.ts` (`password.length < 6`). Matches the Supabase
  default but is weak for tenant-owner/admin accounts. Raise to ≥10 and align
  with the project's Auth settings (haveibeenpwned / length checks).

### L2 — `schema_migrations` has RLS disabled and no policies
- The only table in the chain without RLS. It leaks migration history
  (feature/fix timeline) to anyone with the anon key. Trivial; enable RLS
  with a platform-admin-only policy for hygiene.

### L3 — Unbounded notification body length
- `send-notification` caps `type` (64) and `title` (200) but not
  `body`/`body_urdu`. Oversized payloads break FCM (4KB data limit) and bloat
  the `notifications` table. Cap at e.g. 2–4KB.

### L4 — `platform_config` public read (`USING (true)`)
- `018_platform_config.sql:149` — the **only** `USING (true)` in the chain,
  and it is intentional (pre-login config). Accepted risk; documented here
  for completeness. Ensure no secrets are ever stored in `platform_config`.

### L5 — `export-tenant` collects all rows in memory
- Documented scaling limit (fine for an offboarding tool). Not a
  vulnerability; noted so it is not mistaken for one.

---

# Per-table RLS inventory (condensed)

Conventions: every tenant table below is `ENABLE ROW LEVEL SECURITY`.
"Perm-code" = the 005/019-seeded dotted permission checked via
`tenant_has_permission()` (020), on top of `is_platform_admin()` /
`is_tenant_member()` (004/023). **Caveat: the app's write path is
`sync_apply` (C1), which ignores all of this — the table below describes the
*direct PostgREST* layer only.**

| Table(s) | Migration(s) | Read | Write | Notes |
|---|---|---|---|---|
| `tenants` | 001, 004, 027 | platform admin (all); members read own | platform admin (all); members with `settings.update` (027) | Suspended flag split-brain (H4) |
| `tenant_settings` | 002 | members of tenant | `settings.update` | |
| `tenant_modules`, `modules_catalog` | 003 | authenticated (catalog), members | platform admin | |
| `tenant_memberships`, `platform_admins` | 004, 019 | member-scoped / self | `roles.assign` via 020 RPCs; direct writes owner/admin | `protect_last_owner` trigger (019) |
| `permissions`, `roles`, `role_permissions` | 005, 019 | authenticated read (catalog) | platform admin | Global catalogs; 122 codes (66 dotted + 56 legacy) |
| `students`, `classes`, `darjas`, `darja_sections`, `staff`, `announcements`, `student_guardians`, `teacher_class_assignments` | 007, 015 | tenant members (+ perm codes per 007 contract) | perm codes: `students.*`, `academics.manage`, etc. | `prevent_tenant_id_change` (006) |
| `attendance` | 007, 020 | members + `attendance.view` (+ scope) | `attendance.mark/edit/delete` + `scope_allows()` class scoping (020) | 020 rewrote write policies with scope checks |
| `exams`, `results` | 007, 020 | members + `results.view` (+ scope) | `results.enter/edit` + `scope_allows()` (020) | |
| `profiles` | 007, 026 | own + `users.view` | own (non-role cols); `profiles_lock_role` trigger blocks role writes (007:769) | `handle_new_user()` forces `role='student'` |
| `license_plans` | 011 | **any authenticated user** | platform admin | Plan names/limits visible to all — by design |
| `licenses`, `tenant_subscriptions` | 011 | platform admin; tenant admins read own | platform admin | |
| `audit_logs` | 012 | platform admin (all); tenant admins own-tenant | `log_audit()` SECURITY DEFINER (012) | No suspension check (H4) |
| `invoices`, `invoice_items`, `payments`, `payment_allocations`, `refunds`, `discounts`, `scholarships`, `accounts`, `transactions`, `income`, `expenses`, `fee_structures`, `fee_items` | 014 | members + `finance.view` / `fees.view` | `finance.create/update/delete`, `fees.create/collect/refund`; **final rows immutable** (RLS + backstop trigger, 014:786) | Doc-number triggers per-table (028), not definer |
| `notifications`, `notification_preferences`, `notification_device_tokens` | 017 | own + tenant broadcasts | platform admin (insert); own read-receipts only (`notifications_read_only_guard` trigger) | Fan-out via Edge Function (H3) |
| `platform_config` | 018 | **public** (`USING (true)`) | platform admin | Pre-login config; keep secret-free (L4) |
| `tenant_roles`, `tenant_role_permissions`, `user_permissions`, `permission_scopes`, `permission_delegations` | 019, 020 | tenant members | tenant owner/admin or `roles.assign` (020 RPCs) | Grant ceiling missing (H2); delegation ceiling OK (019) |
| `super_admins` | 023 | super admins only | super admins only | Seed: `muhaqqiqcreates@gmail.com` |
| `user_accounts`, `app_roles` | 027 | **any active member of any tenant** (user_accounts); authenticated (app_roles) | `users.create/update/deactivate` in ≥1 tenant (not row-scoped) | No `tenant_id` (M5, claim b) |
| `schema_migrations` | 001 | no RLS | — | L2 |
| storage.objects (`student-photos`, `staff-photos`, `documents`) | 008 | tenant members (path-bound) | `students.update` / `staff.update` / `documents.manage` + path-bound | Private buckets; UUID path segment (good) |
| storage.objects (`tenant-logos`) | 024 | **public read** (by design) | `settings.update` + path-bound | Logo bucket intentionally public |
| `tenant-exports` bucket | — | **not in version control** | — | H5 |

**RLS-disabled tables:** none, except `schema_migrations` (L2).
**`USING (true)` / `WITH CHECK (true)`:** exactly one — `platform_config_public_read`
(018:149), intentional (L4). No other permissive policies found.

---

# SECURITY DEFINER inventory

All functions below set `SET search_path = public` (verified: zero
`SECURITY DEFINER` functions without it). Read-only helpers are granted to
`authenticated` where noted.

| Function | Migration | Definer? | search_path | Notes |
|---|---|---|---|---|
| `is_platform_admin()` | 004, redefined 023 | yes | set | Now includes `super_admins` |
| `is_tenant_member(UUID)` | 004 | yes | set | Active membership only |
| `is_super_admin()` | 023 | yes | set | `authenticated` can execute |
| `check_tenant_access(UUID)` | 023 | yes | set | `authenticated` can execute; reads `suspended` boolean — **never set (H4)** |
| `tenant_has_permission(UUID, TEXT)` | 020 | yes | set | Permission oracle; read-only, safe to expose |
| `user_effective_permission`, `user_code_denied`, `user_is_tenant_admin` | 020 | yes | set | Internal; parameterized by user |
| `get_my_permissions`, `get_my_permissions_detailed` | 020 | yes | set | **Legacy `profiles.role` branch (M1)** |
| `scope_allows` | 020 | yes | set | Fail-closed scoping; sound |
| `result_class_id` | 020 | yes | set | Read-only helper |
| `assign_tenant_role`, `set_role_permissions`, `set_user_permission`, `create_tenant_role` | 020 | yes | set | **No grant ceiling (H2)** |
| `sync_apply` | 016 | yes | set | **No per-table permission check (C1)** |
| `log_audit()` | 012 | yes | set | Client-safe audit writer; sound |
| `provision_role_templates(UUID)` | 021 | yes | set | EXECUTE revoked from PUBLIC, granted to `service_role` only — correct |
| `delegation_ceiling_check()` (trigger) | 019 | yes | set | Delegator must hold code; no chaining — correct |
| `audit_role_ux_changes()` (trigger) | 019 | yes | set | Tamper-evident audit; sound |
| `protect_last_owner()` (trigger) | 019 | no | set | Last-owner backstop; sound |
| `tenant_memberships_validate_role()` (trigger) | 019 | no | set | Role key must exist; sound |
| `prevent_tenant_id_change()` (trigger) | 006 | no | set | Tenant immutability; sound |
| `profiles_lock_role()` (trigger) | 007 | no | set | Blocks client role writes; sound |
| `notifications_read_only_guard()` (trigger) | 017 | no | set | Read-receipt-only updates; sound |
| Finance automation fns (014:443-661) | 014 | yes | set | Ledger automation; sound |
| Finance immutability guard (014:786) | 014 | trigger | n/a | Backstop incl. service_role; sound |
| Per-table doc-number fns (028) | 028 | no | n/a | Plain trigger fns; sound |
| `storage_path_tenant()` | 008 | no | n/a | UUID-regex path parsing, fail-closed; sound |

No `search_path` injection surface found. No definer function trusts
caller-supplied table/column names except `sync_apply`, which whitelists via
`CASE` + `%I` quoting (016:246) — safe against SQL injection.

---

# Edge Functions audit

| Function | Auth | AuthZ | Input validation | Verdict |
|---|---|---|---|---|
| `provision-tenant` | JWT via `auth.getUser()` (`requirePlatformAdmin`) | platform admin only (table check) | Thorough (UUID, email, slug regex, module allowlist vs catalog + plan) | **Pass** (L1: 6-char pw; M7: 409 oracle) |
| `manage-tenant` | `requirePlatformAdmin` | platform admin only | UUID + action allowlist + reason ≤1000 | **Pass** — but writes `status`, not `suspended` (**H4**) |
| `manage-users` | `requirePlatformAdmin`-or-tenant path (`resolveScope`: platform admin, or membership + effective permission codes) | Rank gates for legacy roles; **permission-based callers bypass rank ceiling (H1)**; last-owner/self-demotion guards present | Good (email/UUID/role allowlist) | **Fail (H1)** + accepts caller `app_metadata` (**M2**), 409 oracle (M7), 6-char pw (L1) |
| `export-tenant` | `requirePlatformAdmin` | platform admin only | UUID | **Pass** — but target bucket unversioned (**H5**); in-memory collect (L5) |
| `send-notification` | JWT via `auth.getUser()` | **Any active tenant member (H3)** | Good UUID/channel allowlist; body lengths uncapped (L3) | **Fail (H3)** |
| `_shared/guard.ts` | — | `requirePlatformAdmin`, `requireTenantAccess`, `serviceClient` from env only | Reusable validators (`isUuid`, `isEmail`, `isSlug`, `parseWebsite` SSRF-aware) | **Pass** — no SSRF (no caller-supplied URLs fetched; website only stored), no path traversal (no filesystem), no secrets from client |

SSRF: none of the functions fetch caller-supplied URLs. Injection: all DB
access is via the supabase-js query builder (parameterized); `sync_apply`'s
dynamic SQL uses a `CASE` whitelist + `%I` quoting. Path traversal: storage
paths are tenant-UUID-prefixed and regex-validated (008).

---

# Storage audit

- **Buckets (in version control):** `student-photos`, `staff-photos`,
  `documents` (private, 008); `tenant-logos` (public read by design, 024).
- **Tenant isolation:** enforced by `storage_path_tenant()` (first path
  segment must be a UUID; NULL → deny) combined with `is_tenant_member()` on
  reads and permission codes (`students.update`, `staff.update`,
  `documents.manage`, `settings.update` for logos) on writes. No
  cross-tenant read/write path found.
- **Gaps:** no MIME/size validation server-side (M6); `tenant-exports`
  bucket missing from version control (H5).

---

# Secrets audit

- `service_role` key: **not present** in the repo. All references are in
  comments/docs or the correct `GRANT … TO service_role` (021). Edge
  Functions read it from env (`SUPABASE_SERVICE_ROLE_KEY`) only.
- Anon/JWT literals in `lib/`: none found.
- Private keys (`BEGIN PRIVATE KEY` etc.): none.
- Password literals: none (only UI route/string constants).
- API-key patterns (`sk-`, `AKIA`, `ghp_`, `xox`): none.
- `.env` files: only Flutter ephemeral build files, no secrets.
- **Result: clean.** (The standing commitment to rotate the Supabase DB
  password pasted in chat on 2026-09-26 is an operational item, unchanged.)

---

# ROLE × RESOURCE matrix (what the BACKEND enforces)

Roles discovered: `super_admin` (023) · `platform_owner`, `platform_support`
(`platform_admins.role`) · `tenant_owner`, `tenant_admin` (004/019) ·
template roles `mohtamim, naib_mohtamim, nazim_aala, nazim_taleem,
nazim_intizamia, nazim_maliyat, daftar_dar, ustad, ustad_hifz, nazim_hifz,
nazim_darul_iqama, warden, mumtahin, store_incharge, hr_incharge` (021) ·
legacy codes `principal, accountant, teacher, librarian, hostel_manager,
parent, student, staff` (005).

**Two enforcement layers exist. Read them together:**

### Layer 1 — Direct PostgREST (RLS policies)

| Resource | super_admin / platform_owner | tenant_owner / tenant_admin | teacher/accountant (perm codes) | student / parent |
|---|---|---|---|---|
| students, classes, darjas, staff, exams | full | full (tenant) | per code (`students.view/create/update`, `academics.manage`) | read own-scoped (007 parent rules); no write |
| attendance | full | full | `attendance.mark/edit/delete` + class scope | read own |
| results | full | full | `results.enter/edit` + class scope | read own |
| finance (invoices, payments, income, expenses, accounts…) | full | full | `finance.view/create/update/delete`, `fees.create/collect/refund`; final rows immutable for all | read own invoices (fees.view) |
| library | full | full | `library.view/manage` | read |
| notifications | full | full | `notifications.view/send` | view own + broadcasts; read-receipts |
| documents / photos (storage) | full | full | `documents.manage`, `students.update`, `staff.update` | read (tenant members) |
| tenant settings / modules / logo | full | `settings.update` | — | — |
| users / memberships | full | manage via 020 RPCs (`roles.assign` or owner/admin) | — | — |
| roles / permissions / delegations | full | `roles.assign` (no ceiling — H2) | — | — |
| tenants table | full | read own; update with `settings.update` | — | — |
| audit logs | full | read own tenant | — | — |
| licenses / subscriptions | full | read own | — | — |
| platform_config | full | — | — | — |
| platform admin / super-admin roster | super_admin only | — | — | — |
| Edge: provision/manage/export tenant | platform admin only | — | — | — |
| Edge: send-notification | yes | **any member (H3)** | **any member (H3)** | **any member (H3)** |

### Layer 2 — The app's actual write path: `sync_apply` RPC (C1) ⚠️

**Overrides Layer 1 for every write the app performs.** Effective rule:
*any active member of the tenant (student, parent, teacher, …) can
create/update/delete any of the 26 synced entities in their own tenant.*
Cross-tenant writes are blocked; per-role/per-permission distinctions are
**not enforced**. Until C1 is fixed, the Layer-1 matrix above describes
reads and direct-API writes only — the app itself operates at
"member = writer".

---

# Prioritized fix list

1. **[CRITICAL — C1]** Add per-entity/per-operation permission checks to
   `sync_apply` (fail closed). This is the single highest-leverage fix: it
   re-arms every RLS policy the app currently bypasses.
2. **[HIGH — H2]** Add grant ceilings to `assign_tenant_role`,
   `set_user_permission`, `set_role_permissions` (cannot grant above own
   authority; `tenant_owner` only by `tenant_owner`; cannot grant unheld
   codes).
3. **[HIGH — H1]** Enforce the rank/authority ceiling for permission-based
   callers in `manage-users` (assignment + ban/deactivate paths).
4. **[HIGH — H4]** Unify suspension: one flag, written by `manage-tenant`,
   enforced in `is_tenant_member()`/RLS (not just the client gate).
5. **[HIGH — H3]** Gate `send-notification` on `notifications.send`; send
   emails per-recipient (BCC); cap body lengths.
6. **[HIGH — H5]** Version-control the `tenant-exports` bucket + strict
   platform-admin-only policies; audit the live bucket's actual policies.
7. **[MEDIUM — M1]** Remove the deprecated `profiles.role` branch from
   `get_my_permissions()`.
8. **[MEDIUM — M2]** Strip caller-supplied `app_metadata` in `manage-users`;
   server-derive it.
9. **[MEDIUM — M3]** Add `000_legacy_base_schema.sql` capturing the legacy
   DDL so fresh databases build from migrations alone.
10. **[MEDIUM — M5]** Add `tenant_id` to `user_accounts` and scope its
    policies.
11. **[MEDIUM — M4]** Enforce session revocation (auth hook) or remove the
    control from the UI.
12. **[MEDIUM — M6]** Server-side upload MIME/size validation for storage.
13. **[MEDIUM — M7]** De-oracle the 409s on user creation/provisioning.
14. **[LOW]** Password minimum ≥10 (L1); RLS on `schema_migrations` (L2);
    notification body caps (L3); keep `platform_config` secret-free (L4).

## Deliberately NOT findings (verified sound)

- All `SECURITY DEFINER` functions set `search_path = public` (no
  search_path injection).
- `provision_role_templates()` EXECUTE locked to `service_role`.
- Tenant-bound storage paths (`storage_path_tenant()` UUID regex,
  fail-closed).
- `prevent_tenant_id_change`, `protect_last_owner`, `profiles_lock_role`,
  delegation ceiling, finance final-row immutability backstop.
- `sync_apply` blocks cross-tenant writes (insert: payload tenant membership;
  update/delete: existing row's tenant, client value ignored).
- `platform_config` `USING (true)` is the sole permissive policy and is
  intentional (pre-login config).
- No secrets/service_role keys in the repo.
