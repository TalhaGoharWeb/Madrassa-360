# RLS Policy Inventory — post migrations 001–018

Static inventory of every **effective** RLS policy after migrations `001`–`018`
(derived 2026-09-25 from the migration files; **not** executed against a live
database). Legacy policies dropped by 007/008/013 are listed only in the
"Retired" section at the end — they are *not* effective.

Conventions:
- `(P)` = platform-admin branch `is_platform_admin()`; `(M)` = tenant-member
  branch `is_tenant_member(<table>.tenant_id)`; `(C:code)` = `tenant_has_permission(tid, 'code')`.
- "Missing" = command with no policy → default-deny for that command.

---

## 001_tenant_core

| Table | Policy | Command | USING / WITH CHECK (one line) | Purpose | Deliberately missing |
|---|---|---|---|---|---|
| `tenants` | `platform admins manage tenants` | ALL | USING+CHECK: (P) | Only platform staff provision tenants; members never create tenants | INSERT/UPDATE/DELETE for members — intended |
| `tenants` | `members read own tenants` *(added by 004)* | SELECT | USING: (M) | Members can read the tenant rows they belong to | — |
| `platform_admins` | `platform admins only` | ALL | USING+CHECK: (P) | Self-protecting admin roster | Everything for non-platform — intended; bootstrap needs superuser/service_role (documented in 004) |

## 002_tenant_settings — `tenant_settings`

| Policy | Command | USING / WITH CHECK | Purpose |
|---|---|---|---|
| `platform admins manage tenant settings` | ALL | (P) | Platform override |
| `members read tenant settings` *(004)* | SELECT | (M) | Members read own tenant's settings |
| `tenant admins manage tenant settings` *(004)* | ALL | USING+CHECK: `is_tenant_admin(tenant_id)` | Tenant-local config management |

## 003_tenant_modules — `tenant_modules` / `modules_catalog`

| Table | Policy | Command | USING / WITH CHECK | Purpose |
|---|---|---|---|---|
| `tenant_modules` | `platform admins manage tenant modules` | ALL | (P) | Platform override |
| `tenant_modules` | `members read tenant modules` *(004)* | SELECT | (M) | Members see enabled modules |
| `tenant_modules` | `tenant admins manage tenant modules` *(004)* | ALL | `is_tenant_admin(tenant_id)` | Tenant-local module toggles |
| `modules_catalog` | `authenticated read modules catalog` | SELECT | `auth.role()='authenticated'` | **Intentionally broad**: low-sensitivity module registry |
| `modules_catalog` | `platform admins manage modules catalog` | ALL | (P) | Platform-only writes |

## 004_memberships — `tenant_memberships`

| Policy | Command | USING / WITH CHECK | Purpose |
|---|---|---|---|
| `users read own memberships` | SELECT | `user_id = auth.uid()` | Users see their own memberships (no cross-user enumeration) |
| `tenant admins manage memberships` | ALL | USING+CHECK: `is_tenant_admin(tenant_id)` | Tenant-local user/role administration |
| `platform admins manage memberships` | ALL | (P) | Platform override |

Notes: no self-insert policy — a non-admin cannot INSERT their own row (regression-tested by S9-A16 → 42501). ⚠️ The tenant-admin branch allows broad role management inside the tenant (incl. granting tenant_admin to others); hierarchy / self-role-change guardrails are application-level, not in RLS — noted for review.

## 005_rbac — `permissions` / `roles` / `role_permissions`

Each table: `authenticated read <t> catalog` (SELECT, `auth.role()='authenticated'` — **intentionally broad**: permission catalogs are needed client-side) + `platform admins manage <t>` (ALL, (P)). `user_roles` left untouched by 005, **dropped by 013** (see Retired).

## 007_tenant_rls — the 13 business tables

Uniform pattern per table `T` (`{T}_{select,insert,update,delete}_tenant`):

- **SELECT**: USING (P) OR ((M) AND (C:`<perm>.view`))
- **INSERT**: WITH CHECK (P) OR ((M) AND (C:`<perm>.create`))
- **UPDATE**: USING (P) OR ((M) AND (C:`<perm>.view`)) — row must first be visible; WITH CHECK (P) OR ((M) AND (C:`<perm>.update`))
- **DELETE**: USING (P) OR ((M) AND (C:`<perm>.delete`))

Permission roots per table: `students`/`staff`/`fees`/`exams`/`results`/`announcements`/`finance_transactions` use their own roots (`students.*`, …); `darjas`/`darja_sections`/`classes` use `academics.manage`; `library_books`/`book_issues` use `library.*`; announcements use `notifications.*`.

Parent extensions (legacy `students.parent_user_id` link, predates 015): on
`students`, `attendance`, `fees`, `exams`, `results` the SELECT/UPDATE USING
also accepts `s.parent_user_id = auth.uid()` — a parent sees their linked
child's rows. (015 adds the richer `student_guardians` table; both mechanisms
coexist — see Consistency notes.)

| Table | Extra policies | Notes |
|---|---|---|
| `profiles` | `profiles_select_tenant` (SELECT: own row OR (P) OR co-member with `users.view`); `profiles_update_tenant` (UPDATE: own row OR (P), WITH CHECK same) | **No INSERT policy** → clients cannot INSERT profiles (rows are created by the auth trigger) — default-deny intended. `role` is additionally locked by `profiles_lock_role` trigger (regression-tested S8-A13). |
| `madrasas` (legacy) | `madrasas_platform_admin_all` (ALL, (P)); `madrasas_member_select` (SELECT: any active `tenant_memberships` row for the caller) | ⚠️ **Flag**: `madrasas_member_select` is *not* correlated to the target row — any user with *any* active membership can SELECT *every* `madrasas` row. Cross-tenant readable by design-or-oversight; review whether this legacy table should be tenant-correlated. |

## 008_tenant_storage — `storage.objects` (buckets: student-photos, staff-photos, documents)

Per bucket B (`{B}_select_tenant` / `{B}_insert_tenant` / `{B}_update_tenant` / `{B}_delete_tenant`),
with the tenant taken from the object's `{tenant_id}/` name prefix via
`storage_path_tenant(name)`:

- **SELECT** (`{B}_select_tenant`): `bucket_id = B AND is_tenant_member(storage_path_tenant(name))` — any active member of the prefix's tenant can read. Cross-tenant reads return 0 rows (regression-tested S10-A18, S13-A24, S14-A27).
- **INSERT / UPDATE / DELETE** (`{B}_{insert,update,delete}_tenant`): `bucket_id = B AND (is_platform_admin() OR (is_tenant_member(prefix-tenant) AND tenant_has_permission(prefix-tenant, <code>)))` where `<code>` is `students.update` for student-photos, `staff.update` for staff-photos, and `documents.manage` for documents. A teacher without the code cannot write even in her own tenant (regression-tested S14-A29 → 42501 on documents); a tenant admin holding the code can (S14-A30). Cross-prefix writes fail because `is_tenant_member(prefix-tenant)` is false (S10-A17, S13-A25, S14-A28 → 42501).

Note: the write rule is permission-code based, not role-name based — a
`tenant_admin` gets `documents.manage` via the 005 seed mapping (admins hold
all codes); any future role granted `documents.manage` could write too.

## 011_licensing — `license_plans` / `licenses` / `subscriptions`

| Table | Policy | Command | USING / WITH CHECK | Purpose |
|---|---|---|---|---|
| `license_plans` | `authenticated read license plans` | SELECT | `auth.role()='authenticated'` | **Intentionally broad**: public pricing catalog |
| `license_plans` | `platform admins manage license plans` | ALL | (P) | Platform-only writes |
| `licenses` | `tenant admins read own licenses` | SELECT | (M) | Tenant sees own license |
| `licenses` | `platform admins manage licenses` | ALL | (P) | Platform-only writes — tenants cannot self-license (default-deny for tenant INSERT/UPDATE/DELETE) |
| `subscriptions` | `tenant admins read own subscriptions` | SELECT | (M) | Tenant sees own subscription |
| `subscriptions` | `platform admins manage subscriptions` | ALL | (P) | Platform-only writes (default-deny for tenant writes) |
| `platform_admins` | `platform_admins_self_read` | SELECT | `id = auth.uid()` | Lets a platform admin read their own roster row |

## 012_audit_logs — `audit_logs`

| Policy | Command | USING | Purpose |
|---|---|---|---|
| `platform admins read all audit logs` | SELECT | (P) | Full-platform audit visibility |
| `tenant admins read own audit logs` | SELECT | (M) | Tenant-scoped audit visibility |

**No INSERT/UPDATE/DELETE policy** → clients can never write or mutate audit
rows (default-deny); all writes come from SECURITY DEFINER triggers / server
code. Intended.

## 014_finance — ledger tables

Pattern mirrors 007 (`{T}_{select,insert,update,delete}_tenant`) with finance
permission codes (`finance.view/create/update/delete`, `fees.view/create/collect`).

| Table | Notable policy details |
|---|---|
| `transactions` | `transactions_update_tenant` / `transactions_delete_tenant` require `status='draft'` in USING — **posted/void rows are RLS-invisible to writers** (0 rows, no trigger reached). `finance_immutable_guard()` trigger raises for any UPDATE/DELETE of a non-draft row as the defense-in-depth backstop (regression-tested S18-A40–A44). ⚠️ Note: the platform-admin branches of the 014 UPDATE/DELETE policies do **not** include the `status='draft'` guard — a platform admin passes RLS on a posted row and is stopped only by the trigger. RLS and trigger disagree on the enforcement layer for that role; harmless today (trigger still blocks) but worth aligning. |
| `payments` | `payments_insert_tenant` WITH CHECK: (M) AND (C:`fees.collect`) AND `status='draft'` (regression-tested S15-A31 → 42501 for a teacher without `fees.collect`). |
| `invoices` | `invoices_insert_tenant` WITH CHECK: (M) AND (C:`fees.create`) AND `status='draft'` (regression-tested S15-A32 → 42501 for a teacher without `fees.create`). |
| `refunds` | `refunds_approve_tenant` / `refunds_post_tenant` gate the approve/post transitions in addition to the standard four. |
| `income` | `income_approve_tenant` / `income_post_tenant` gate approve/post. |
| `expenses` | `expenses_approve_tenant` / `expenses_post_tenant` gate approve/post. |
| `accounts`, `discounts`, `fee_items`, `fee_structures`, `invoice_items`, `scholarships` | Standard `{T}_{select,insert,update,delete}_tenant` pattern with `fees.*` / `finance.*` codes (`fee_structures` uses `fees.*`; `invoice_items` tenant-scoped via parent invoice). |
| `account_types` | `authenticated read account types` (SELECT, broad — reference catalog) + platform-admin manage. |

**`payment_allocations`** has only `payment_allocations_insert_tenant` +
`payment_allocations_select_tenant` — **no UPDATE/DELETE policy** → allocations
are append-only (default-deny for mutation). Intended.

## 015_parent_links — `student_guardians` / `teacher_class_assignments`

| Table | Policy | Command | USING / WITH CHECK | Purpose |
|---|---|---|---|---|
| `student_guardians` | `student_guardians_select_tenant` | SELECT | (P) OR `is_tenant_admin(tid)` OR (`guardian_user_id = auth.uid()` AND (M)) | **Parents see only their own family's links** — same-tenant other-family rows and cross-tenant rows are invisible (regression-tested S16-A33–A35). Tenant admins see all links in their tenant (intended). |
| `student_guardians` | `student_guardians_insert_tenant` | INSERT | WITH CHECK: `is_tenant_admin(tid)` OR (P) | Only tenant admins (or platform) create links — parents cannot self-link (default-deny for parent INSERT). |
| `student_guardians` | `student_guardians_update_tenant` / `student_guardians_delete_tenant` | UPDATE/DELETE | `is_tenant_admin(tid)` OR (P) | Link lifecycle is admin-only. |
| `teacher_class_assignments` | `teacher_class_assignments_select_tenant` | SELECT | (P) OR ((M) AND (`teacher_id = auth.uid()` OR (C:`academics.view`))) | Teachers see own assignments; academic viewers see tenant's. |
| `teacher_class_assignments` | `teacher_class_assignments_insert_tenant` / `_update_tenant` / `_delete_tenant` | INSERT/UPDATE/DELETE | `is_tenant_admin(tid)` OR (P) | Admin-only lifecycle. |

## 017_notifications — `notifications` / `notification_preferences` / `notification_device_tokens`

| Table | Policy | Command | USING / WITH CHECK | Purpose |
|---|---|---|---|---|
| `notifications` | `notifications_select_tenant` | SELECT | (P) OR ((M) AND (`user_id IS NULL` OR `user_id = auth.uid()`)) | Users see their own + tenant broadcast (`user_id IS NULL`) notifications; a parent cannot see another user's notifications. |
| `notifications` | `notifications_insert_admin` | INSERT | WITH CHECK: (P) | **Platform admins only** create notifications — tenants cannot inject notifications into other users' feeds (default-deny for tenant INSERT). |
| `notifications` | `notifications_update_read_own` | UPDATE | Same visibility as SELECT (WITH CHECK same) | Read receipts: users mark own/broadcast notifications read; a trigger restricts the write to `read_at`. |
| `notifications` | `notifications_delete_admin` | DELETE | (P) | Platform-only delete. |
| `notification_preferences` | `notification_preferences_select_own` | SELECT | (P) OR ((M) AND `user_id = auth.uid()`) | Users read own prefs. |
| `notification_preferences` | `notification_preferences_write_own` | ALL | (P) OR ((M) AND `user_id = auth.uid()`) | Users manage only their own prefs. |
| `notification_device_tokens` | `notification_device_tokens_select_own` | SELECT | (P) OR ((M) AND `user_id = auth.uid()`) | Push tokens are strictly user-scoped. |
| `notification_device_tokens` | `notification_device_tokens_write_own` | ALL | (P) OR ((M) AND `user_id = auth.uid()`) | Users manage only their own tokens. |

## 018_platform_config — `platform_config` / `devices` / `device_sessions`

| Table | Policy | Command | USING / WITH CHECK | Purpose |
|---|---|---|---|---|
| `platform_config` | `platform_config_public_read` | SELECT | `true` | **Intentionally public**: clients check config/force-update before login. |
| `platform_config` | `platform_config_admin_write` | ALL | USING+CHECK: (P) | Tenant admins can read but never write (regression-tested S17-A36–A39: UPDATE/DELETE → 0 rows, INSERT → 42501). |
| `devices` | `devices_select` | SELECT | (P) OR `is_tenant_admin(tid)` OR (`user_id = auth.uid()` AND (M)) | Users see own devices; tenant admins see tenant's. |
| `devices` | `devices_insert_own` | INSERT | (P) OR (`user_id = auth.uid()` AND (M)) | Users register only their own devices. |
| `devices` | `devices_update` | UPDATE | (P) OR `is_tenant_admin(tid)` OR (`user_id = auth.uid()` AND (M)) | Owner or tenant admin updates. |
| `devices` | `devices_delete_admin` | DELETE | (P) OR `is_tenant_admin(tid)` | Users cannot delete their own device row directly (admin-only) — revocation goes through sessions. |
| `device_sessions` | `device_sessions_select` | SELECT | (P) OR `is_tenant_admin(tid)` OR (`user_id = auth.uid()` AND (M)) | Session visibility follows device ownership; tenant admins see tenant's. |
| `device_sessions` | `device_sessions_insert_own` | INSERT | (P) OR (`user_id = auth.uid()` AND (M)) | Session creation is owner-scoped (server login flow runs as the user). |
| `device_sessions` | `device_sessions_revoke` | UPDATE | (P) OR `is_tenant_admin(tid)` OR (`user_id = auth.uid()` AND (M)) | Revocation by owner or tenant admin. |
| `device_sessions` | `device_sessions_delete_admin` | DELETE | (P) OR `is_tenant_admin(tid)` | Admin-only delete. |

## 016_sync — no new tables

Adds `server_version` / `updated_at` columns to existing tables; the
`sync_bump_revision` triggers are row-local and permission-neutral. No policy
changes.

---

## Consistency notes (not holes, worth knowing)

1. **Two parent-link mechanisms coexist**: legacy `students.parent_user_id`
   (used by 007-era policies on students/attendance/fees/exams/results) and
   015's `student_guardians`. Both are enforced in their respective policies;
   the isolation suite covers `student_guardians` (S16).
2. **Permission-code generations coexist**: legacy undotted codes
   (`view_fees`, … from 06) and dotted codes (`fees.view`, … from 005/007/014).
   All 007+ policies check dotted codes only, so legacy grants cannot leak
   through the new policies.
3. **No RLS-without-policy and no policy-without-RLS** was found on any table
   created or altered by 001–018 (checked via migration sources; live
   confirmation needs staging).

## Retired (dropped, NOT effective)

- 007 drops all legacy 02/03/05-era policies on the 13 business tables,
  `profiles`, and `storage.objects` (fail-loud guard aborts the migration if a
  legacy policy name is still present) — this kills the §10 OR-stacking class.
- 008 drops legacy storage policies on the three buckets.
- 013 drops the `user_roles` table and its two policies
  (`read own user_roles`, `platform admin manage user_roles`), plus orphaned
  legacy helper functions.
- The S11 section of `cross_tenant_isolation.sql` asserts none of the 45 known
  legacy policy names exist.

## Flags for review

1. `madrasas_member_select` (007): any active membership → can SELECT **all**
   `madrasas` rows (not row-correlated). Confirm intended for this legacy table.
2. `tenant admins manage memberships` (004): tenant admins can grant
   `tenant_admin` to anyone in their tenant; no hierarchy / self-demotion
   guard in RLS (application-level concern).
3. 014 platform-admin branches on `transactions` UPDATE/DELETE omit the
   `status='draft'` guard present in the member branch — enforcement for that
   role rests solely on the `finance_immutable_guard()` trigger.
