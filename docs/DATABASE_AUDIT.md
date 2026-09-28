# Database & RLS Security Audit — Madrasa 360

**Scope:** `supabase/01_schema.sql` (273 lines), `02_rls.sql` (268), `03_storage.sql` (143), `04_seed.sql` (216), `05_new_modules.sql` (394), `06_rbac.sql` (826). Total 2,120 lines, read line-by-line 2026-09-25.
**Cross-referenced:** `lib/data/repositories/auth_repository.dart` (AppUser/UserRole), `lib/core/services/permission_service.dart`.
**Type:** audit only — no code changes made.

---

## Executive summary

1. **There is no tenant model.** No `tenants` table, no `tenant_id` column on any table (grep over all six files: zero hits). `madrasas` (05_new_modules.sql:49) is the closest thing, but 13 of 19 tables have no `madrasa_id`, and **zero** RLS policies filter by madrasa — any user holding a permission (e.g. `view_students`) sees rows from **all** madrasas. Multi-tenant SaaS is currently impossible, not just incomplete.
2. **Privilege escalation is live.** `02_rls.sql:48` (`profiles_update_own`, `FOR UPDATE USING (auth.uid() = id)` — no `WITH CHECK`) plus `02_rls.sql:63` (`profiles_insert_own`, no role restriction) let any authenticated user set `profiles.role='superAdmin'`. `06_rbac.sql` tries to close this but its `DROP POLICY` statements target policy names that never existed (see §10), so the vulnerable policies remain active and permissive policies OR-stack.
3. **Two authorization systems run in parallel and disagree.** `02_rls.sql` trusts the JWT claim via `get_user_role()` (`auth.jwt() -> 'app_metadata' ->> 'role'`); `05`/`06` trust `profiles.role` via `get_my_role()` / `has_permission()`. `handle_new_user()` maps new-signup `'admin'` → `'madrasaAdmin'` (06:46-67) while the 02 policies still gate on JWT `'admin'` and the 06 CHECK constraint still lists `'admin'` as legal. Stale 02 policies were never actually dropped (wrong names in 06's DROPs) and OR-stack with the new permission policies.
4. **RBAC madrasa-scoping is decorative.** `get_my_permissions(p_madrasa_id UUID DEFAULT NULL)` (06:499) treats NULL as wildcard (`ur.madrasa_id IS NULL OR p_madrasa_id IS NULL`, 06:506), every 06 policy calls `has_permission(code)` **without** a madrasa argument, and `AppUser.madrasaId` is always null because `profiles` has no `madrasa_id` column (`auth_repository.dart:93` reads a column that doesn't exist). A role scoped to madrasa A grants its permissions globally.
5. **Secrets and identity are hard-coded in seed files; no security tests exist.** `05_new_modules.sql:354` (commented) ships `crypt('***REDACTED-PASSWORD-ROTATED-2026-09-25***', gen_salt('bf'))` for `superadmin@madrasa360.com`; `04_seed.sql:201-214` (commented) hard-codes the institution's real email domain `@almarkazalislamikasur.pk`. `test/` contains only `widget_test.dart` — zero DB/RLS/cross-tenant tests.

---

## 1. Table inventory matrix

All FKs below are **real inline `REFERENCES` constraints** (verified, not conventions) — except `book_issues.borrower_id`, which is a `TEXT` convention with no FK (05:178). All `CREATE TABLE`s use `IF NOT EXISTS`.

| Table | File:line | tenant_id? | `madrasa_id`? | RLS enabled? | Policies (count) | Notes |
|---|---|---|---|---|---|---|
| `profiles` | 01:12 | ❌ | ❌ | ✅ 02:22 | 5 (02) + 3 (06) = 8, stacked | PK = FK to `auth.users(id)` CASCADE. `role` CHECK rewritten twice (05, 06). **No `madrasa_id`** — app reads `profile['madrasa_id']` which doesn't exist |
| `darjas` | 01:61 | ❌ | ✅ 05:84 (nullable, CASCADE) | ✅ 02:23 | 2 (02) | 05 added `name_urdu/name_english/level/order_index/...`; old `name/name_en/order_num` columns left in place (drift) |
| `classes` | 01:74 | ❌ | ❌ | ✅ 02:24 | 2 (02) | FKs: `darja_id`, `teacher_id`→profiles |
| `students` | 01:88 | ❌ | ❌ | ✅ 02:25 | 3 (02, stale) + 4 (06) = 7, stacked | FKs to darjas/classes/profiles; `UNIQUE(roll_no, class_id)` |
| `staff` | 01:115 | ❌ | ❌ | ✅ 02:26 | 2 (02, stale) + 4 (06) = 6, stacked | **salary column readable by teachers/parents** via stale `staff_teacher_view` |
| `attendance` | 01:140 | ❌ | ❌ | ✅ 02:27 | 3 (02, stale) + 4 (06) = 7, stacked | `UNIQUE(student_id, date)`; 3 indexes |
| `fees` | 01:161 | ❌ | ❌ | ✅ 02:28 | 3 (02, stale) + 4 (06) = 7, stacked | Generated `status` column; `UNIQUE(student_id, month)` |
| `exams` | 01:194 | ❌ | ❌ | ✅ 02:29 | 2 (02) | 06 never touched exams |
| `results` | 01:207 | ❌ | ❌ | ✅ 02:30 | 3 (02) | 06 never touched results |
| `announcements` | 01:225 | ❌ | ✅ 05:127 (nullable, CASCADE) | ✅ 02:31 | 2 (02) + 1 (05) + 4 (06) = 7, stacked | Dual columns: `target_role` (01) + `target` (05); `posted_by` (01) + `posted_by_user_id` (05) |
| `madrasas` | 05:49 | n/a (tenant-ish) | n/a | ✅ 05:248 | 2 (05) | "franchise branches"; `admin_user_id` single-admin link; `subscription_plan` basic/standard/premium |
| `darja_sections` | 05:106 | ❌ | ✅ 05:109 | ✅ 05:263 | 2 (05) — **never replaced by 06** | `authenticated users read` = all-auth cross-tenant read still live |
| `library_books` | 05:147 | ❌ | ✅ 05:149 | ✅ 05:276 | 2 (05→dropped) + 2 (06) | 06 DROPs matched 05 names here ✓ |
| `book_issues` | 05:173 | ❌ | ✅ 05:175 | ✅ 05:289 | 2 (05→dropped) + 2 (06) | `borrower_id TEXT` — **not a real FK** (convention only) |
| `finance_transactions` | 05:216 | ❌ | ✅ 05:218 | ✅ 05:302 | 2 (05→dropped) + 3 (06) | Sensitive amounts/donors; 06 policy is permission-only, no tenant filter |
| `permissions` | 06:77 | ❌ (global, correct) | ❌ | ✅ 06:563 | 2 (06) | 57 seeded codes (`view_students`, `manage_exams`, …) |
| `roles` | 06:94 | ❌ (global, correct) | ❌ | ✅ 06:565 | 2 (06) | 16 system roles, `scope` ∈ platform/madrasa/external |
| `role_permissions` | 06:111 | ❌ (global, correct) | ❌ | ✅ 06:566 | 2 (06) | Composite PK join table |
| `user_roles` | 06:125 | ❌ | ✅ 06:129 (nullable) | ✅ 06:566 | 2 (06) | `UNIQUE(user_id, role_id, madrasa_id)`; **nullable madrasa_id = global role** |

**Views (no RLS possible; not tenant-filtered):** `attendance_summary` (01:242), `fee_summary` (01:259), `my_permissions` (06:822).

**Indexes:** present on the hot paths (`attendance(date)`, `(class_id,date)`, `(student_id)`; `fees(student_id)`, `(month)`; `results(student_id)`, `(exam_id)`; `madrasa_id` indexes on all 05 tables; `user_roles(user_id)`, `(madrasa_id)`). Index coverage is adequate; not a finding.

---

## 2. Tenant model — evidence of absence

- `grep -rni "tenant" supabase/` returns only comments: `05_new_modules.sql:8` (`madrasas → new multi-tenant franchise table`) and `05_new_modules.sql:77` (`darjas (rebuild for multi-tenant)`). **No `tenants` table, no `tenant_id` column, no `get_current_tenant_id()` function exist anywhere.**
- The word "multi-tenant" appears only in comments; the actual mechanism is `madrasas` + nullable `madrasa_id` on 6 of 13 business tables, with **no policy ever referencing `madrasa_id` except** `user_roles` row-visibility and the unenforced `get_my_permissions` parameter.
- Core tables with **no** institution scoping at all: `profiles, classes, students, staff, attendance, fees, exams, results`.
- The only user↔madrasa links are `madrasas.admin_user_id` (one admin per madrasa) and `user_roles.madrasa_id` (nullable; NULL = global). There is no "primary madrasa" for ordinary staff — and the app's `AppUser.madrasaId` reads `profile['madrasa_id']`, a column that was never created (`auth_repository.dart:93`), so it is always null and `PermissionService.loadForUser` (permission_service.dart:33) calls `get_my_permissions` **without** `p_madrasa_id`, hitting the NULL-wildcard branch.

**Verdict:** single-institution design with franchise-table aspirations. The MASTER MISSION's "every business table needs tenant_id, RLS keyed on server-trusted get_current_tenant_id()" is 0% implemented.

---

## 3. RLS policy-by-policy verdict

Legend: ✅ sound · ⚠️ weak/stale (active but wrong authority or over-broad) · 🔴 leak/escalation.

### 3a. `02_rls.sql` — role-via-JWT era (all still active; 06's DROPs missed them)

| Policy | Table / cmd | Verdict | Reason |
|---|---|---|---|
| `profiles_view_own` (02:44) | profiles SELECT | ⚠️ stale | Superseded by 06's `profiles select authenticated`; harmless alone |
| `profiles_update_own` (02:48) | profiles UPDATE | 🔴 **escalation** | `USING (auth.uid() = id)` with **no `WITH CHECK`** — any user can `UPDATE profiles SET role='superAdmin'` on their own row. 06's DROP targeted `"users update own profile"` (nonexistent), so this is still live and OR-stacks with 06's fixed version |
| `profiles_admin_view_all` / `profiles_admin_update_all` (02:53,57) | profiles SELECT/UPDATE | ⚠️ stale | Gate on `get_user_role()='admin'` (JWT `app_metadata`); `handle_new_user` no longer assigns `'admin'` to new users |
| `profiles_insert_own` (02:62) | profiles INSERT | 🔴 **escalation** | `WITH CHECK (auth.uid() = id)` — checks id only; a fresh user can INSERT their profile row with `role='superAdmin'` before the trigger's `ON CONFLICT DO NOTHING` path matters |
| `darjas_read` / `classes_read` (02:76,86) | SELECT | ⚠️ over-broad | `auth.role()='authenticated'` — every authenticated user of every madrasa reads all |
| `darjas_admin_write` / `classes_admin_write` (02:80,90) | ALL | ⚠️ stale authority | JWT `'admin'` only |
| `students_admin_all` (02:106) | students ALL | ⚠️ stale | JWT `'admin'`; OR-stacks with 06's permission policies |
| `students_teacher_view` (02:110) | students SELECT | ⚠️ stale-active | Teacher sees students of classes where `teacher_id=auth.uid()` — reasonable scoping, wrong authority layer, no tenant bound |
| `students_parent_view_own` (02:118) | students SELECT | ✅ sound | `parent_user_id = auth.uid()` — correct pattern, survives as defense-in-depth |
| `staff_admin_all` (02:134) | staff ALL | ⚠️ stale | JWT `'admin'` |
| `staff_teacher_view` (02:138) | staff SELECT | 🔴 **leak** | `get_user_role() IN ('teacher','parent') AND is_active` — **any teacher or parent reads all active staff rows including `salary`, `cnic`, `phone`** |
| `attendance_admin_all` (02:152) | attendance ALL | ⚠️ stale | JWT `'admin'` |
| `attendance_teacher_manage` (02:156) | attendance ALL | ⚠️ stale-active | `teacher_id = auth.uid()` — ok scoping, stale authority |
| `attendance_parent_view_own` (02:163) | attendance SELECT | ✅ sound | Own-children subquery |
| `fees_admin_all` (02:180) | fees ALL | ⚠️ stale | JWT `'admin'` |
| `fees_teacher_read` (02:184) | fees SELECT | 🔴 **leak** | **Every teacher reads every fee record** (amounts, paid status) across all madrasas |
| `fees_parent_view_own` (02:188) | fees SELECT | ✅ sound | Own-children subquery |
| `exams_read_all_auth` (02:201) | exams SELECT | ⚠️ over-broad | All-auth, cross-tenant (low sensitivity) |
| `exams_admin_all` (02:205) | exams ALL | ⚠️ stale | JWT `'admin'` |
| `results_admin_all` (02:213) | results ALL | ⚠️ stale | JWT `'admin'` |
| `results_teacher_manage` (02:217) | results ALL | ⚠️ stale-active | Own-classes subquery; ok scoping, stale authority |
| `results_parent_view_own` (02:225) | results SELECT | ✅ sound | Own-children subquery |
| `announcements_read` (02:238) | announcements SELECT | ⚠️ over-broad | `is_active AND authenticated AND (target_role='all' OR = role)` — cross-tenant; OR-stacks with 05's + 06's 4 policies |
| `announcements_admin_all` (02:250) | announcements ALL | ⚠️ stale | JWT `'admin'` |

### 3b. `06_rbac.sql` Part 10 — permission era (active, but stacked on top of 3a)

All `has_permission(code)` calls pass **no** `p_madrasa_id` → madrasa scoping dead. All are additionally **cross-tenant** because no business table carries an enforced tenant column.

| Policy | Verdict | Reason |
|---|---|---|
| `view/create/edit/delete_students permission` (06:628-648) | ⚠️ | Permission-gated but tenant-blind; `OR parent_user_id = auth.uid()` on SELECT is good. 02's three policies still stacked underneath |
| `view/create/edit/delete_staff permission` (06:652-668) | ⚠️ | Tenant-blind; stacked on 02's `staff_teacher_view` salary leak |
| `view/mark/edit/delete_attendance permission` (06:672-690) | ⚠️ | Tenant-blind; stacked on 02's teacher/parent policies |
| `view/create/update/delete_fees permission` (06:694-714) | ⚠️ | Tenant-blind; SELECT keeps parent fallback ✅; stacked on 02's `fees_teacher_read` leak |
| `view/create/delete_finance permission` (06:718-734) | 🔴 **leak** | Any holder of `view_finance` (e.g. franchiseManager, accountant of madrasa A) reads **all madrasas'** donations/zakat/expenses. No UPDATE policy at all (falls back to nothing = denied, inconsistent) |
| `view_library` / `manage_library permission` (06:738-752) | ⚠️ | Tenant-blind; note `manage_library FOR ALL` overlaps `view_library` SELECT (redundant, harmless) |
| `view_library book_issues` / `manage_library book_issues permission` (06:756-766) | ⚠️ | Tenant-blind |
| `view/create/edit/delete_announcements permission` (06:770-786) | ⚠️ | Tenant-blind; 7 stacked policies total on this table |
| `profiles select authenticated` (06:794) | 🔴 **leak** | **Every authenticated user SELECTs every profile** — names, phones, photo URLs of all users across all madrasas |
| `profiles update own` (06:799) | ✅ intent, ❌ ineffective | Correct `WITH CHECK` anti-escalation, but 02's `profiles_update_own` (no WITH CHECK) is still live → permissive-OR defeats it |
| `admin manage profiles` (06:812) | ⚠️ | `FOR ALL` on `has_permission('create_users') OR is_platform_admin()` — fine once escalation is closed; dangerous until then |
| `authenticated read permissions/roles/role_permissions` (06:570,581,592) | ✅ acceptable | Low-sensitivity catalog reads |
| `superAdmin manage permissions/roles/role_permissions` | ✅ sound | |
| `read own user_roles` (06:610) | ⚠️ | `user_id=auth.uid() OR is_platform_admin() OR has_permission('manage_roles', madrasa_id)` — NULL-wildcard in `get_my_permissions` means `manage_roles` anywhere reads all rows |
| `platform admin manage user_roles` (06:616) | ⚠️ | Same wildcard issue on write path |

### 3c. `05_new_modules.sql` §9 policies

| Policy | Verdict | Reason |
|---|---|---|
| `superAdmin full access on madrasas` / `admin sees own madrasa` (05:251,255) | ⚠️ | SELECT-only for admins (`admin_user_id=auth.uid()`); admins cannot UPDATE their own madrasa row (only superAdmin FOR ALL) — inconsistent, not a leak |
| `authenticated users read darja_sections` (05:266) | 🔴 **leak** | All authenticated users read all sections cross-tenant; **06 never replaced this** (no DROP for darja_sections in 06) |
| `admin manage darja_sections` (05:269) | ⚠️ | Gates on `get_my_role() IN ('admin','superAdmin')` — `profiles.role`, client-escalatable (see §3a) |
| library/book_issues/finance 05 policies | ✅ replaced | 06's DROP names matched; superseded (but replacements are tenant-blind) |
| `superAdmin manage announcements` (05:313) | ⚠️ | Stacked 4th policy on announcements |

### 3d. `03_storage.sql` — buckets: `student-photos`, `staff-photos`, `documents` (all Private per header comment, 03:11-13)

| Policy | Verdict | Reason |
|---|---|---|
| `student_photos_auth_select` / `staff_photos_auth_select` (03:38,86) | 🔴 **leak** | `bucket_id=... AND auth.role()='authenticated'` — **any authenticated user (any madrasa, incl. parents) can read every student's and staff member's photo**. Photos of minors, no per-user/per-tenant scoping |
| `*_admin_insert/update/delete` (photos) | ⚠️ | Admin-only write is fine; but no path restriction — admin can write anywhere in bucket |
| `documents_staff_select` (03:118) | 🔴 **leak** | `get_user_role() IN ('admin','teacher')` — any teacher reads **all** documents (fee receipts with PII) cross-tenant |
| `documents_parent_select` (03:128) | ⚠️ fragile | Path-convention check `(storage.foldername(name))[2] IN (own children's ids)` — correct shape, but **nothing enforces the `students/{id}/` path on upload** (only admins upload, so it relies on admin discipline, not the DB) |
| `documents_admin_insert/update/delete` | ✅ sound | Admin-only |

No `USING(true)` and no `anon`-role policies exist anywhere (verified by grep) — the leaks are all *authenticated-but-unscoped*, which is worse for a SaaS: every tenant's users are "authenticated".

---

## 4. Auth model — user ↔ institution ↔ role

**Database truth:**
- `profiles(id PK→auth.users, name, phone, photo_url, role TEXT CHECK, is_active, timestamps)` — one **global** role string per user, no institution link, no `madrasa_id`.
- `user_roles(user_id→profiles, role_id→roles, madrasa_id→madrasas NULLABLE, assigned_by, assigned_at)` — the only user↔institution↔role structure; `madrasa_id IS NULL` means "global".
- `madrasas.admin_user_id` — single admin pointer, the only institution link for the legacy path.

**App truth (`auth_repository.dart`):**
- `AppUser.fromSupabase` (lines 67-95) resolves role preferring `user.appMetadata['role']` (JWT, admin-set) then `profile['role']`, case-insensitively, into a 17-value `UserRole` enum (superAdmin … student, incl. legacy `admin`).
- Reads `profile['madrasa_id']` (line 93) → **always null** (column doesn't exist); comment at line 91-92 admits "madrasaId is loaded here".
- Permissions loaded separately via `PermissionService.loadForUser` → RPC `get_my_permissions` (permission_service.dart:33), passing `p_madrasa_id` only if non-null (never), else `{}` → NULL wildcard; on RPC failure falls back to **client-side** `AppPermissions.fallbackFor(roleName)` — UI gating with no server meaning.

**Net:** the app believes in a per-user madrasa + permission set; the database provides neither reliably. Role authority is split three ways: JWT `app_metadata` (02), `profiles.role` (05/06 + app), `user_roles` rows (06).

---

## 5. RBAC reality check (06_rbac.sql)

It **is** permission-level, not just role names: 57 permission codes (`view_students` … `system_full_access`, 06:143-201), 16 roles (06:239-262), `role_permissions` join seeded per role via `assign_perms()` (06:269-290, ~16 `SELECT assign_perms(...)` blocks), and `has_permission(code)` / `get_my_permissions()` helpers (06:499-528). The tables it creates (`permissions`, `roles`, `role_permissions`, `user_roles`) are new and don't conflict with `01_schema.sql`.

**But:**
1. **Enforcement ≠ assignment.** Policies check `has_permission(code)` with no tenant argument; nothing stops madrasa A's accountant from reading madrasa B's finance.
2. **`get_my_permissions` NULL-wildcard** (06:506): `(ur.madrasa_id = p_madrasa_id OR ur.madrasa_id IS NULL OR p_madrasa_id IS NULL)` — with the default NULL, a role granted for one madrasa is honored everywhere. And the legacy UNION branch (06:512-518) grants the full permission set of `profiles.role` to **every** user regardless of `user_roles`.
3. **`is_madrasa_admin()` (06:545) is defined but never used in any business-table policy** — dead code.
4. **Legacy `profiles.role` is client-writable** (see §3a escalation), so `get_my_role()`, `is_platform_admin()`, and the legacy UNION branch all rest on attacker-controlled input.
5. `has_permission`/`get_my_permissions`/`is_platform_admin` are `SECURITY DEFINER` (06:501,523,540) — intended so they can read the RBAC tables past RLS, but combined with (4) it means an escalated `profiles.role` instantly yields platform admin through definer-rights helpers.
6. `my_permissions` view (06:822) exposes the caller's own codes — fine.

**Verdict:** permission catalog = real; permission *enforcement* = tenant-blind and built on an escalatable role column.

---

## 6. Seed-data findings (04_seed.sql, 05_new_modules.sql §10)

- **Hard-coded credential (commented, still in repo):** 05:353-354 —
  `'superadmin@madrasa360.com',` / `crypt('***REDACTED-PASSWORD-ROTATED-2026-09-25***', gen_salt('bf')), -- ← change to your password`
  Exposure path: anyone with repo read access learns a documented default password; if the block is ever uncommented and run as-is, the instance gets a publicly known weak password. [REDACTED] per rule; value noted by location only.
- **Hard-coded institution identity (commented):** 04:201,205,209,214 — `admin@almarkazalislamikasur.pk`, `teacher@almarkazalislamikasur.pk`, `parent@almarkazalislamikasur.pk`. Real organizational domain baked into the repo.
- **Mock PII in active (uncommented) inserts:** 5 staff rows (04:74-89) with sequential fake phones (`03001234567`, `03123456789`, …), salaries (75000/45000/50000/35000/40000), joining dates; 8 student rows (04:97-141) with Urdu names; fee rows (04:150-159); exam + 10 result rows (04:166-189). All `ON CONFLICT DO NOTHING` — safe to re-run, but ships fake PII-shaped data into every fresh DB.
- 04's §7 role-assignment block is commented out (requires manual dashboard user creation first) — no active auth.user inserts in 04. 05's superadmin INSERT is likewise commented out.

---

## 7. Migration / reproducibility verdict

- Files are numbered `01`–`06` with header comments stating run order ("Run AFTER 01_schema.sql…", "Run this AFTER 01…04"), **but execution is manual** ("Run this entire file in Supabase → SQL Editor"). No migration tracking table, no checksums, no down-migrations, no CI application.
- **Drift-masking everywhere:** `CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION/VIEW`, `DROP POLICY IF EXISTS`, `ALTER TABLE … ADD COLUMN IF NOT EXISTS`, `DROP CONSTRAINT IF EXISTS`. A half-applied or hand-edited DB converges silently; there is no way to prove a given database matches these files.
- **Destructive-adjacent:** 05:77-100 warns "If existing darjas data exists, back it up first!" then backfills and `ALTER COLUMN name_urdu SET NOT NULL` unconditionally — will hard-fail on any pre-existing NULL row on re-run against drifted data. Old columns (`name`, `name_en`, `order_num`) are left alongside new ones.
- **Silent overrides:** `handle_new_user()` is defined 3× (01:27, 05:38, 06:46 — 06 wins, changes semantics: `admin`→`madrasaAdmin` mapping); `get_my_role()` defined 2× (05:235, 06:531); `profiles_role_check` dropped/re-added 2× (05:22, 06:22) with different role sets.
- **Not reproducible from these files alone:** 03 requires manual bucket creation in the Dashboard; 04/05 require manual Auth user creation; 04 §7 and 05 §10 require hand-edited emails/passwords.

**Verdict:** not a migration system — a set of ordered scripts with idempotency theater. Phase 2 needs real versioned migrations (`001`–`010`) with a ledger.

---

## 8. Ranked issue list (with recommended fix)

| # | Severity | Issue | Fix |
|---|---|---|---|
| 1 | 🔴 P0 | **Privilege escalation via `profiles`**: 02's `profiles_update_own` (no `WITH CHECK`, 02:48) and `profiles_insert_own` (no role check, 02:62) let any authenticated user become `superAdmin`; 06's DROPs missed them so the fixed policy is OR-defeated | Migration: `DROP POLICY "profiles_update_own"`, `"profiles_insert_own"`, `"profiles_view_own"`, `"profiles_admin_view_all"`, `"profiles_admin_update_all"` **by exact 02 names**; keep 06's `WITH CHECK` version; remove `role` from client-writable columns (move role into `tenant_memberships`) |
| 2 | 🔴 P0 | **No tenant isolation**: zero policies filter by tenant; permission holders see all madrasas' students/fees/finance/photos | Add `tenant_id` to all business tables; `get_current_tenant_id()` SECURITY DEFINER reading server-side membership; rewrite every policy as `tenant_id = get_current_tenant_id()` AND permission check |
| 3 | 🔴 P0 | **Stale 02 policies OR-stacked under 06** (wrong DROP names: `"admin full access on students"` etc. never existed; actuals are `students_admin_all`, `students_teacher_view`, `students_parent_view_own`, …) | Explicit migration dropping every 02/05 policy by its real name before creating replacements; add a post-migration assertion query on `pg_policies` |
| 4 | 🔴 P0 | **Cross-tenant photo/PII leaks**: `student_photos_auth_select`, `staff_photos_auth_select` (03:38,86), `documents_staff_select` (03:118) grant all-authenticated read | Per-tenant object prefixes (`{tenant_id}/…`) + storage policies keyed on `get_current_tenant_id()`; parents scoped to own children only |
| 5 | 🟠 P1 | **Salary/CNIC leak**: stale `staff_teacher_view` (02:138) exposes `salary, cnic, phone` to all teachers/parents | Drop it (covered by #3); new policy: `view_staff` permission + tenant filter; consider splitting sensitive columns or a restricted view |
| 6 | 🟠 P1 | **Teachers read all fees**: stale `fees_teacher_read` (02:184) | Drop it (covered by #3); teachers get fee visibility only via explicit permission + tenant scope, or not at all |
| 7 | 🟠 P1 | **RBAC scoping dead**: `get_my_permissions` NULL-wildcard (06:506); policies never pass madrasa; legacy UNION grants `profiles.role` perms unconditionally | Replace with `get_current_tenant_id()`-bound check; remove NULL-wildcard; drop the legacy UNION branch once `profiles.role` is decommissioned |
| 8 | 🟠 P1 | **Dual authority**: JWT `app_metadata.role` (02) vs `profiles.role` (05/06/app) vs `user_roles` (06) | Single source: server-side `tenant_memberships`; stop reading role from JWT in policies; app keeps JWT only as a hint, never as authority |
| 9 | 🟠 P1 | **Hardcoded credential in repo**: `***REDACTED-PASSWORD-ROTATED-2026-09-25***` / `superadmin@madrasa360.com` (05:353-354, commented) | Delete the password from the file; document vault/env-based bootstrap; rotate if it was ever used |
| 10 | 🟠 P1 | **`profiles` world-readable**: `profiles select authenticated` (06:794) exposes all users' phones/names cross-tenant | Restrict to own row + tenant members with `view_users` permission |
| 11 | 🟡 P2 | **`is_madrasa_admin()` dead code** (06:545, unused); `manage_library FOR ALL` redundant with `view_library` | Wire tenant-admin checks into policies or delete |
| 12 | 🟡 P2 | **Announcements policy pile-up**: 7 stacked policies across 02/05/06; dual `target_role`/`target` and `posted_by`/`posted_by_user_id` columns | Consolidate to one policy set; migrate data; drop legacy columns |
| 13 | 🟡 P2 | **`book_issues.borrower_id` is TEXT, not an FK** (05:178) | Normalize to `borrower_student_id UUID REFERENCES students` + `borrower_staff_id`, or enforce via trigger |
| 14 | 🟡 P2 | **Views unfiltered**: `attendance_summary`, `fee_summary` cross-tenant; `attendance_summary` INNER JOINs `darjas` (drops students with NULL darja) | Add `security_invoker = true` + tenant predicate, or tenant-filtered variants |
| 15 | 🟡 P2 | **No security tests**; manual SQL-editor deploys; drift-masking idempotency | Versioned migrations + `pgTAP`/SQL cross-tenant test suite run in CI (attempt cross-tenant read/write as tenant-A user, expect denial) |

---

## 9. What Phase 2 must build (precise list)

1. **`001_tenants`**: `tenants(id, name, slug UNIQUE, …, created_at)` — canonical tenant table (replaces `madrasas`-as-tenant; migrate `madrasas` rows in).
2. **`002_tenant_memberships`**: `tenant_memberships(user_id→auth.users, tenant_id→tenants, role, created_at, UNIQUE(user_id, tenant_id))` — the single user↔tenant↔role source; **remove `role` from client-writable `profiles`** (or make it read-only via trigger).
3. **`003_get_current_tenant_id()`**: `SECURITY DEFINER` function returning the caller's tenant from `tenant_memberships` keyed on `auth.uid()` — server-trusted, never from JWT claims or client input. (Also keep `has_permission(code)` but bound to it.)
4. **`004_tenant_columns`**: `tenant_id UUID NOT NULL REFERENCES tenants(id)` on **every** business table: `profiles` (or via membership), `darjas`, `classes`, `students`, `staff`, `attendance`, `fees`, `exams`, `results`, `announcements`, `darja_sections`, `library_books`, `book_issues`, `finance_transactions` — with backfill from existing `madrasa_id`→tenant mapping, then `SET NOT NULL`.
5. **`005_rls_rewrite`**: drop **all** 02/05/06 table policies by exact name; recreate each as `USING (tenant_id = get_current_tenant_id())` combined with the permission check; fix the `profiles` escalation (no client role writes); scope storage policies to `{tenant_id}/` prefixes.
6. **`006_storage_tenant_paths`**: bucket layout `student-photos/{tenant_id}/{…}` etc.; storage policies using `get_current_tenant_id()`; remove all-authenticated photo reads.
7. **`007_seed_hygiene`**: delete the hard-coded password/email blocks; seed via env/vault; separate demo-seed from schema migrations.
8. **`008_backfill_verify`**: data migration `madrasas`→`tenants`, `madrasa_id`→`tenant_id`, `user_roles`→`tenant_memberships`; drop legacy duplicate columns (`darjas.name` vs `name_urdu`, `announcements.target_role` vs `target`, …) after verification.
9. **`009_cross_tenant_tests`**: SQL-level negative tests — tenant-A user `SELECT/INSERT/UPDATE/DELETE` on tenant-B rows across students, fees, finance, attendance, storage objects; role-escalation attempt on `profiles`; permission-without-tenant attempt. Must run in CI.
10. **`010_ledger`**: migration ledger table (`schema_migrations`) + single runner; remove `IF NOT EXISTS`/`OR REPLACE` drift-masking from forward migrations.

---

## 10. Conflicts & DROP/ALTER risks (quick reference)

- 06's `DROP POLICY` names that match **nothing** (no-ops — the real policies survive): `"admin full access on students"`, `"teacher read students"`, `"parent read own child"`, `"admin full access on staff"`, `"teacher read staff"`, `"teacher manage own attendance"`, `"users read own profile"`, `"users update own profile"`. Real 02 names are `students_admin_all`, `students_teacher_view`, `students_parent_view_own`, `staff_admin_all`, `staff_teacher_view`, `attendance_admin_all`, `attendance_teacher_manage`, `attendance_parent_view_own`, `profiles_view_own`, `profiles_update_own`, `profiles_admin_view_all`, `profiles_admin_update_all`, `profiles_insert_own`.
- `handle_new_user()` redefined 3× with changing semantics (01 → 05 → 06); 06 maps `'admin'`→`'madrasaAdmin'` but the 06 CHECK still permits `'admin'`.
- `get_my_role()` redefined in 06 over 05 (same body — harmless but confusing).
- `profiles_role_check` dropped/re-added with different role sets in 05 then 06.
- 02 policies gate on JWT `'admin'`; 06's signup trigger never produces `'admin'` for new users — legacy admins keep working, new ones can't be created the same way.
- 05's `darja_sections` policies were never superseded by 06 (no DROPs, no replacements).
- 06 adds an UPDATE policy on `finance_transactions`? No — it adds view/create/delete only; UPDATE falls through to deny (inconsistent with 05's `FOR ALL` admin policy it dropped).
- `my_permissions` view + `get_my_permissions()` RPC are readable by any authenticated user (by design — own codes only).

---

*End of audit. No implementation performed; no commits made.*
