# Phase 1 Audit — Role-Aware, Permission-Driven, Urdu-First Madrassa-360

**Date:** 2026-09-26 · **Branch:** `feat/role-aware-ux` (= `origin/main`, commit `cdc289f2`)
**Scope:** READ-ONLY audit. No code modified. Method: full read of `supabase/migrations/{004,005,007,012,013,014,015,016,017}.sql`,
`lib/core/services/permission_service.dart`, `lib/providers/auth_provider.dart`,
`lib/data/repositories/auth_repository.dart`, `lib/core/constants/{app_permissions,app_strings}.dart`,
`lib/core/services/tenant_context.dart`, `lib/main.dart`, screen inventory of all 41 screens in
`lib/presentation/screens/`.

---

## A. DATABASE (`supabase/migrations/`)

### A1. `005_rbac.sql` (369 lines) — full inventory

**Tables created** (all `CREATE TABLE IF NOT EXISTS`; originally defined by legacy `supabase/06_rbac.sql`):

| Table | Columns | Notes |
|---|---|---|
| `public.permissions` | `id UUID PK DEFAULT gen_random_uuid()`, `code TEXT NOT NULL UNIQUE`, `name TEXT NOT NULL`, `module TEXT NOT NULL`, `description TEXT`, `created_at TIMESTAMPTZ DEFAULT NOW()` | Catalog of dotted codes. **No Urdu label column.** Indexes: `idx_permissions_code`, `idx_permissions_module` |
| `public.roles` | `id UUID PK`, `name TEXT NOT NULL UNIQUE`, `display_name TEXT NOT NULL`, `display_urdu TEXT NOT NULL DEFAULT ''`, `scope TEXT NOT NULL DEFAULT 'madrasa'` CHECK `IN ('platform','madrasa','external')`, `is_system BOOLEAN DEFAULT TRUE`, `description TEXT`, `created_at` | Catalog of roles |
| `public.role_permissions` | `role_id UUID FK→roles ON DELETE CASCADE`, `permission_id UUID FK→permissions ON DELETE CASCADE`, `PRIMARY KEY (role_id, permission_id)` | Join table. Indexes: `idx_rp_role`, `idx_rp_permission` |

**Permission codes seeded:** 66 canonical dotted codes (INSERT … `ON CONFLICT (code) DO NOTHING`, 005:96-168):
students (4: view/create/update/delete) · teachers (4) · staff (4) · attendance (4: view/mark/edit/delete) ·
academics (2: view/manage) · exams (5: +publish) · results (4: view/enter/edit/publish) · fees (4: view/create/collect/refund) ·
finance (5: view/create/update/delete/approve) · library (2: view/manage) · hostel (2: view/manage) · transport (2: view/manage) ·
parents (1: view) · notifications (2: view/send) · reports (2: view/export) · documents (2: view/manage) ·
certificates (2: view/issue) · users (4: view/create/update/deactivate) · roles (2: view/assign) ·
settings (2: view/update) · modules (2: view/manage) · audit (1: view) · tenants (4: view/create/update/suspend)

**Roles seeded:** 12 rows (005:177-190), each with a `display_urdu` label —
`tenant_owner` (مالک), `tenant_admin` (ایڈمن), `principal` (پرنسپل), `accountant` (محاسب),
`teacher` (استاذ), `librarian` (لائبریرین), `hostel_manager` (ہاسٹل مینیجر),
`parent` (والدین, scope=`external`), `student` (طالب علم, scope=`external`),
`staff` (عملہ), `platform_owner` (پلیٹ فارم مالک, scope=`platform`),
`platform_support` (پلیٹ فارم سپورٹ, scope=`platform`).
Legacy 06 roles (`teacher`, `accountant`, `parent`, `student`) are left untouched; the new rows upsert by name.

**`role_permissions` seeding (005:197-268):** `tenant_owner` + `tenant_admin` get every code
**except** `tenants.*` and `audit.view`; `platform_owner` gets all 66; curated mappings for the rest
(accountant: fees+finance+reports; teacher: students.view, attendance view/mark/edit, exams.view,
results view/enter/edit, notifications.view; librarian; hostel_manager; principal: academics+exams+results
full, reports, attendance.view, staff.view, fees.view; parent/student: notifications.view only;
staff: attendance view/mark; platform_support: tenants.view, users.view, audit.view, reports.view).

**RLS on catalog tables** (005:318-360, `ALTER TABLE … ENABLE ROW LEVEL SECURITY` + 6 policies):
- `permissions` / `roles` / `role_permissions`: `"authenticated read <t> catalog"` — `SELECT USING (auth.role()='authenticated')`; `"platform admins manage <t>"` — `FOR ALL USING (is_platform_admin()) WITH CHECK (is_platform_admin())`. **Note:** `user_roles` (legacy) intentionally untouched by 005; its two policies were dropped by 013 (migration `013_auth_cleanup.sql:62-63`) after the table was declared deprecated.

**Helper functions:**

```sql
-- 005:288 (rewritten again by 013 to remove the user_roles branch)
public.get_my_permissions(p_madrasa_id UUID DEFAULT NULL)
  RETURNS TABLE(code TEXT)   -- LANGUAGE sql, STABLE, SECURITY DEFINER, search_path=public
```

Exact logic: `SELECT DISTINCT p.code FROM tenant_memberships tm
JOIN roles r ON r.name = tm.role
JOIN role_permissions rp ON rp.role_id = r.id
JOIN permissions p ON p.id = rp.permission_id
WHERE tm.user_id = auth.uid() AND tm.is_active`
**UNION** (deprecated, kept for the old 02/06 business-table policies) the `profiles.role` branch
(`profiles pr JOIN roles … WHERE pr.id = auth.uid()`).
**Key semantics:** (1) `p_madrasa_id` is **ignored** in the primary branch — the function unions
permissions across **ALL** of the caller's active tenant memberships; (2) there is no per-tenant
scoping in the returned set — the client cannot tell which permission came from which tenant.

```sql
-- 06_rbac.sql:521 (still live per 005:312 contract)
public.has_permission(p_code TEXT, p_madrasa_id UUID DEFAULT NULL) RETURNS BOOLEAN
-- = SELECT EXISTS (SELECT 1 FROM get_my_permissions(p_madrasa_id) WHERE code = p_code)
```

### A2. Tenant-isolation model (`004_memberships.sql`, `007_tenant_rls.sql`, `013_auth_cleanup.sql`)

**Tenant membership representation.** The single source of truth is
`public.tenant_memberships` (004:79-93): `id PK`, `tenant_id FK→tenants ON DELETE CASCADE`,
`user_id FK→auth.users ON DELETE CASCADE`, `role TEXT` CHECK one of the 10 tenant roles
(`tenant_owner, tenant_admin, principal, accountant, teacher, librarian, hostel_manager, parent, student, staff`),
`is_active BOOLEAN DEFAULT true`, `joined_at/created_at/updated_at`, `UNIQUE(user_id, tenant_id)`.
One row per user per tenant — **a user holds at most ONE role per tenant** (no multi-role).
Platform roles live ONLY in `public.platform_admins` (`user_id PK`, `role` CHECK `platform_owner|platform_support`) — never in memberships.

**Resolution chain "user → tenant → role → permissions"** (all helpers `SECURITY DEFINER, SET search_path=public`, 004:224-289):
1. `is_platform_admin()` — row in `platform_admins` for `auth.uid()` → short-circuits everything.
2. `is_tenant_member(p_tenant_id)` — active membership row for this user+tenant.
3. `is_tenant_admin(p_tenant_id)` — platform admin OR membership role ∈ {tenant_owner, tenant_admin}.
4. `tenant_has_permission(p_tenant_id, p_code)` — platform admin OR
   `tenant_memberships(role) → roles(name) → role_permissions → permissions(code = p_code)` for this tenant.

**Policy pattern** (007, four policies per table, e.g. `students_select_tenant` 007:281):
`is_platform_admin() OR (is_tenant_member(tid) AND (tenant_has_permission(tid,'<mod>.view') OR <ownership fallback>))`
INSERT maps to `*.create` / `attendance.mark` / `results.enter` / `academics.manage` / `library.manage`;
UPDATE `USING` = SELECT-expression, `WITH CHECK` = the `*.update`/`*.edit` code; DELETE = `*.delete`.
Ownership fallbacks preserve legacy behavior, now tenant-bound:
students: `parent_user_id = auth.uid()`; attendance/fees/results: via `students.parent_user_id`;
darjas/classes/academic structure & active announcements: readable by all tenant members;
staff: **no** fallback (salary/CNIC stay gated).
`profiles`: self-read + platform-admin + `users.view` holders in shared tenants; UPDATE self-only;
`profiles_lock_role()` trigger (007:769) rejects any non-platform-admin role-column write and forces
new profiles to `role='student'`; `handle_new_user()` (007:797) inserts `role='student'`.
`attendance_summary` / `fee_summary` views are `security_invoker=true` (007:§f).
007 §g is a fail-loud block that raises if any of ~70 legacy policy names survived the sweep.

### A3. Tenant-owned tables × RLS matrix

| Table | Tenant column | RLS + tenant policies | Permission codes used |
|---|---|---|---|
| darjas, classes, darja_sections | `tenant_id NOT NULL` (006) | ✅ 007: 4 each (select = member-readable) | `academics.view` / `academics.manage` |
| students | ✅ | ✅ 007 (parent fallback via `parent_user_id`) | `students.*` |
| staff | ✅ | ✅ 007 (no ownership fallback) | `staff.*` |
| attendance | ✅ | ✅ 007 (parent fallback via students) | `attendance.view/mark/edit/delete` |
| fees | ✅ | ✅ 007 (parent fallback via students) | `fees.view/create/collect` (collect doubles as update+delete; 005 has no `fees.update/delete`) |
| exams | ✅ | ✅ 007 | `exams.view/create/update/delete/publish` |
| results | ✅ | ✅ 007 | `results.view/enter/edit` (edit doubles as delete; 005 has no `results.delete`) |
| announcements | ✅ | ✅ 007 (all members read active) | `notifications.view/send` |
| library_books, book_issues | ✅ | ✅ 007 | `library.view/manage` |
| finance_transactions | ✅ | ✅ 007 | `finance.*` |
| accounts, fee_structures, fee_items, invoices, invoice_items, payments, payment_allocations, refunds, discounts, scholarships, expenses, income, transactions (014) | ✅ | ✅ 014: 56 policies, all tenant-aware | `fees.*` for fee-side tables, `finance.*` for ledger-side; invoices INSERT additionally requires `status='draft'` |
| student_guardians, teacher_class_assignments (015) | ✅ | ✅ 015: 8 policies — but they use `is_tenant_member`/`is_tenant_admin`, **not** fine-grained permission codes | n/a (coarse) |
| notifications, notification_preferences, notification_device_tokens (017) | ✅ | ✅ 017: 8 policies via `is_platform_admin`/`is_tenant_member` + `notifications_read_only_guard()` | n/a (coarse) |
| tenants, tenant_settings, tenant_modules, tenant_memberships, platform_admins (001-004) | n/a (system) | ✅ 004 | n/a |
| audit_logs (012) | ✅ | ✅ SELECT-only for platform admins + tenant admins; writes via `log_audit()` SECURITY DEFINER RPC or service_role | n/a |
| licenses, license_plans, tenant_subscriptions, modules_catalog, platform_config, devices, device_sessions | platform-level | ✅ (own policies) | n/a |

**Tables with permissions seeded but NO table at all:** `hostel.*`, `transport.*`, `certificates.*`,
`documents.*` — permissions `hostel.view/manage`, `transport.view/manage`, `certificates.view/issue`,
`documents.view/manage` exist in the catalog (005) and the Dart translation map references them,
but no corresponding tables exist in any migration.

### A4. Database gaps

1. **No delegation model.** There is no `permission_delegations` table, no "granted-by/granted-until"
   concept, no delegation ceilings. `tenant_memberships` is one-role-per-user; temporary or partial
   delegation (e.g. principal delegates fee-collection to a teacher for a week) is impossible.
2. **No scope model.** There is no `permission_scopes` table. `teacher_class_assignments` exists (015)
   but **no RLS policy consults it** — a teacher's `attendance.mark`/`results.enter` is tenant-wide,
   not limited to assigned classes. The DB cannot express "own class only".
3. **No per-user overrides.** There is no `user_permissions` table; `get_my_permissions()` reads only
   role grants (+ deprecated legacy branches). Exceptions to a role require a new role or a membership change.
4. **No automatic audit of authorization changes.** `audit_logs` (012) exists with a client-safe
   `log_audit()` RPC, but **no trigger writes to it** on `tenant_memberships` / `role_permissions` /
   `roles` changes — role grants/revocations are not auto-recorded.
5. **No Urdu labels for permissions.** `permissions` has only English `name`/`module`/`description`;
   only `roles.display_urdu` is localized (and `tenant_admin`'s label is literally 'ایڈمن' — a
   transliteration, not Urdu). Any Urdu permission UI must be built client-side.
6. **Permission granularity quirks baked into RLS:** no `fees.update`/`fees.delete` (collect covers both),
   no `results.delete` (edit covers), `users.deactivate`, `roles.assign`, `modules.*`, `documents.*`,
   `certificates.*`, `parents.view`, `transport.*`, `audit.view` (for tenants) have no table-level enforcement.
7. **`get_my_permissions()` unions across all tenants** — a user who is `teacher` in madrasa A and
   `tenant_admin` in madrasa B receives the union; per-tenant least privilege is enforced only by RLS,
   never visible to the client permission set.

---

## B. FLUTTER (`lib/`)

### B1. `lib/core/services/permission_service.dart` (214 lines)

- **Loading:** `loadForUser({userId, roleName, madrasaId})` (L134) calls the Supabase RPC
  `get_my_permissions` (passing `p_madrasa_id` only when non-null; the server ignores it anyway).
  Response rows' `code` values are collected into a `Set<String>`, then translated through
  `_dottedToLegacy` (L38-104) into the **legacy underscore vocabulary** (`AppPermissions.*`,
  e.g. `students.view` → `view_students`). Unmapped dotted codes are **dropped with a warning**
  (fail-closed). On null response or any exception → `AppPermissions.fallbackFor(roleName)`
  (offline static defaults).
- **Caching:** results stored in `AuthState.permissions` (a `Set<String>`); reloaded on
  `signedIn`, `tokenRefreshed`, `userUpdated` — **not** on tenant switch (`selectTenant` never
  reloads permissions).
- **Check API:** static `has(Set,String)`, `hasAll(Set,Iterable)`, `hasAny(Set,Iterable)` (L182-192)
  — pure set-membership tests; Riverpod wrappers `hasPermissionProvider` /
  `hasAllPermissionsProvider` in `auth_provider.dart` (L458-470).
- **Role-family helpers** (L196-213) use **legacy role-name strings**, disconnected from the DB:
  `isPlatformRole` = {superAdmin, franchiseManager}; `isMadrasaAdmin` = {madrasaAdmin, admin,
  editor, itManager}; `isStaffRole` = 13 legacy names; `isExternalRole` = {parent, student}.
  None of the 10 `tenant_memberships` role names (`tenant_owner`, …) appear here.
- **Notably unmapped server codes** (dropped client-side; server/RLS still enforces):
  `notifications.*`, `parents.view`, `certificates.*`, `documents.*`, `modules.*`, `transport.*`,
  `audit.view`, `fees.collect`, `fees.refund`, `results.publish`, `exams.publish`,
  `users.deactivate`, `roles.assign`. Practical effect: the client cannot gate UI on
  "can collect fees" vs "can view fees", "can publish results", or "can send announcements".

### B2. `lib/providers/auth_provider.dart` (466 lines) — permission wiring, role resolution, session restore

- `AuthState.permissions: Set<String>` (L83-86) populated once per sign-in via
  `PermissionService.loadForUser(userId: user.id, roleName: user.role.name, …)` (L~300);
  `AuthState.can(p)` convenience (L139).
- **Role resolution does NOT use `tenant_memberships`:** `AppUser.fromSupabase`
  (`lib/data/repositories/auth_repository.dart:74-103`) resolves `UserRole` from
  `auth.users.app_metadata['role']` ?? `profiles.role` ?? `'teacher'` (case-insensitive
  match against the legacy enum; unknown → `teacher`). The `tenant_memberships.role`
  (e.g. `tenant_admin`) is read only into `TenantMembership.role` (a display string in
  `tenant_context.dart`) and never drives `AppUser.role`.
- **Routing** (`_resolveRoute`, L~420 + `AuthRoute` enum L44-57): 0 memberships → `noAccess`
  (unless platform admin → `home`); 1 → `home`; >1 → `tenantPicker`.
  `AuthGate` (auth/auth_gate.dart) maps `home` → `MainScreen` **for every role**; `login_screen.dart`
  (L110-133) does the same post-login.
- **Session restore:** `restoreSession()` honors the "remember me" flag (`auth_remember_me`,
  default true; e-mail prefill only, password never stored), then runs the same
  `_handleSignedIn` wiring. Token expiry → `SIGNED_OUT` → login.
- `isPlatformAdmin` = row in `platform_admins` (`_checkPlatformAdmin`, L~445; fail-closed on error).

### B3. Dashboard / screen inventory by role (41 screens)

| Screen file | Serves | Permission-aware? |
|---|---|---|
| `main_screen.dart` | **Everyone** — bottom nav shell (home/attendance/results/profile) whose tabs are **hard-coded for the Teacher role** ("navigation wrapper for the Teacher role") | ❌ hard-coded; only addition is a platform-admin `'/master'` shortcut |
| `teacher/teacher_dashboard_screen.dart` (277 L) | Teacher: schedule + headcount from `teacher_class_assignments` | ⚠️ scoped by assignments, not permission-gated |
| `teacher/attendance_screen.dart` (786 L), `teacher/results_screen.dart` | Teacher: mark attendance, enter results | ❌ (relies on RLS) |
| `admin/admin_main_screen.dart` | **Unreferenced dead code** — "All 11 staff roles land here", permission-driven nav via `userPermissionsProvider` (L53). Nothing routes to it | ✅ (but unreachable) |
| `admin/admin_dashboard_screen.dart` (907 L) | Admin overview; cards gated by `userPermissionsProvider` (L41) **and** `tenantModulesProvider` | ✅ nav-level only |
| `admin/{student_list,staff_list,fee_management,finance,library,darja}_screen.dart` | Admin CRUD per module | ❌ no in-screen permission checks (nav + RLS only) |
| `admin/user_management_screen.dart` | Admin: user accounts + roles/permissions | ⚠️ see B3-note |
| `admin/backup_screen.dart` | Admin: offline backup/restore | ❌ |
| `parent/parent_main_screen.dart`, `parent/parent_dashboard_screen.dart` | Parent: own children via `student_guardians` | ⚠️ scoped, not permission-gated. **Unreachable**: nothing routes to it |
| `parent/fee_history_screen.dart` | Parent: fee history | ⚠️ unreachable |
| `master_admin/*` (10 screens: shell, dashboard, madrasa list/detail, create wizard, licenses, plans, subscriptions, modules, platform users, audit logs) | Platform operators (`platform_owner`/`platform_support`), behind `/master` + `MasterAdminGuard` | ✅ guard |
| `super_admin/*` (3 screens) | — | @deprecated, superseded by master_admin |
| `reports/reports_hub_screen.dart` | Reports catalog/preview/share/print | ❌ |
| `common/{announcements,notifications,profile,about}_screen.dart`, `auth/*`, `crash_screen.dart` | Shared/auth | ❌ |

**B3-note — user management is disconnected from tenant RBAC:** `user_management_provider.dart`
reads/writes a table **`app_roles` that does not exist in any migration** (falls back to
`AppRole.allSystemRoles` in-memory), and assigns user roles by writing
`auth.users.app_metadata.role` (L156) — never `tenant_memberships`. So in-app role assignment
feeds only the *deprecated* `profiles.role`/`app_metadata` branch of `get_my_permissions()`,
bypassing the tenant-aware model entirely. It also uses a **second permission vocabulary**:
`Permission` enum in `lib/data/models/app_role.dart` (11 values with Urdu labels) vs the
`AppPermissions` string constants used everywhere else.

**No principal (مہتمم) dashboard exists.** `principal` appears only as a free-text
`principal_name` field in `master_admin/madrasa_detail_screen.dart:140-163` and the DB role seed.
There is likewise no dedicated ناظم/دفتر دار/خازن screen — all staff share the teacher-shaped
`MainScreen` or the unreachable `AdminMainScreen`.

### B4. Guards

- `lib/core/widgets/master_admin_guard.dart` — `MasterAdminGuard` widget + `fetchPlatformAdminRole()`;
  gates `/master` on a `platform_admins` row; fail-closed. The only true route guard in the app.
- **No `PermissionGuard` / `RoleGuard` / `PermissionGate` widget exists** (grep: zero hits).
  Feature-level gating is done ad hoc: 2 call sites watch `userPermissionsProvider`
  (`admin_main_screen.dart:53`, `admin_dashboard_screen.dart:41`); `hasPermissionProvider` is
  defined but used only ~2×; the static `PermissionService.has*` helpers have no call sites in
  `lib/` outside their definition file.

### B5. Role identifiers in Dart (three parallel, inconsistent vocabularies)

1. `UserRole` enum — `lib/data/repositories/auth_repository.dart:18-42` — 19 **legacy** values:
   `superAdmin, franchiseManager, madrasaAdmin, admin, editor, academicManager, teacher,
   attendanceOfficer, accountant, financeManager, libraryManager, hostelManager,
   announcementManager, admissionOfficer, itManager, parent, student`. This is what
   `AppUser.role` holds and what the offline `roleDefaults` map is keyed by.
2. `AppPermissions.roleDefaults` — `lib/core/constants/app_permissions.dart:104-407` —
   keyed by the same 19 legacy names ("Must be kept in sync with 06_rbac.sql Part 8" — a
   comment that predates the 005 tenant-role model).
3. DB `tenant_memberships.role` — 10 new names (`tenant_owner … staff`) — surfaced in Dart
   only as `TenantMembership.role` (plain `String`, display use).
4. `Permission` enum — `lib/data/models/app_role.dart:11` — 11 coarse values, used only by
   the disconnected user-management flow.

Consequence: a user whose real authority is `tenant_admin` in the DB is resolved in Dart as
whatever legacy string sits in `app_metadata`/`profiles.role` (default `teacher`), and offline
fallbacks grant permissions for that legacy role — a privilege-model mismatch in both directions.

### B6. Urdu coverage & jargon (`lib/core/constants/app_strings.dart`, 108 lines)

- ~100 Urdu string constants: nav, attendance flow, auth, roles (منتظم/استاد/والدین/طالب علم),
  common actions, days of week, درجات, dashboard cards. `main.dart:238` sets
  `locale: Locale('ur','PK')` and `main.dart:255-256` wraps the app in
  `Directionality(textDirection: TextDirection.rtl)` — **RTL is already the default**.
- Role display Urdu also exists in `role_config.dart` (19 legacy roles) and DB `roles.display_urdu`.
- **Jargon in user-facing UI:** none of RBAC/tenant/CRUD/JWT surfaces in `AppStrings`; hits for those
  terms in `lib/` are code comments, docstrings, or provider section headers only
  (e.g. `user_management_screen.dart` docstring "admin CRUD", `plans_screen.dart` docstring).
  The one user-visible-adjacent leak is the master-admin console itself, which legitimately shows
  "Tenant", "License", "Module" labels to platform operators (`audit_logs_screen.dart:254`,
  `modules_screen.dart`) — acceptable for operators, not for madrasa users.

### B7. Navigation & role-based routing today

`main.dart:263` → `home: AuthGate()`; named route `/master` → `MasterAdminGuard(MasterAdminShell())`.
There is **no role-based route table**: `AuthGate` and `login_screen` both send `AuthRoute.home`
→ `const MainScreen()` unconditionally. `MainScreen` is the teacher shell (tabs: home/attendance/
results/profile). The permission-driven `AdminMainScreen`, the `ParentMainScreen`, and the
`SuperAdminMainScreen` exist but **no code navigates to them** — i.e. today admins, parents and
students all land in the teacher-shaped shell after login.

---

## C. GAPS vs the mission (prioritized)

**P0 — correctness / security of the authorization story**
1. **Role assignment UI bypasses tenant RBAC.** `user_management_provider` writes
   `app_metadata.role` and a nonexistent `app_roles` table — never `tenant_memberships`.
   Assigning "accountant" in the app does not create the DB grant that RLS enforces.
2. **Dart resolves roles from the legacy single-role column**, not from `tenant_memberships`
   (`auth_repository.dart:80-88`). Offline fallback permissions and all role-family helpers
   (`isPlatformRole`, `isStaffRole`, …) run on legacy names (`superAdmin`, `madrasaAdmin`, …)
   that no longer exist in the DB model.
3. **Permissions are unioned across all tenants** (`get_my_permissions`), and the client never
   reloads them on tenant switch — a `tenant_admin` in madrasa B sees admin UI affordances
   while operating in madrasa A as `teacher`.
4. **No delegation, no scopes, no per-user overrides** (DB §A4.1-3) — the mission's "delegation
   ceilings" have no data model at all; `teacher_class_assignments` exists but no policy uses it.

**P1 — role-aware UX (the mission's core)**
5. **Everyone lands in the teacher shell.** `MainScreen` hard-codes teacher tabs; the
   permission-driven `AdminMainScreen` is unreachable dead code; there is no principal/مہتمم
   dashboard, no ناظم/دفتر دار/خازن differentiation.
6. **No reusable `PermissionGuard`/`RoleGuard` widget** — gating is ad hoc in 2 screens;
   feature screens (fees, finance, students…) contain zero in-widget permission checks.
7. **Unmapped permission codes** (`fees.collect/refund`, `results/exams.publish`,
   `notifications.send`, `roles.assign`, …) are dropped client-side, so the UI cannot
   distinguish "view fees" from "collect fees" or gate publish/send actions.
8. **Two/three competing permission vocabularies** (`AppPermissions` strings vs `Permission`
   enum vs DB dotted codes) with a hand-maintained translation map that silently drops codes.

**P2 — Urdu-first polish**
9. **Permissions catalog has no Urdu labels** (DB §A4.5); `tenant_admin`'s `display_urdu` is
   'ایڈمن' (transliteration). Any Urdu permission-management UI needs new labels.
10. **No Urdu-first permission concepts for non-technical users** — the mission wants مہتمم/ناظم/
    استاد to see human concepts, but role/permission naming in the app is still the legacy
    English enum (`madrasaAdmin`, `attendanceOfficer`, …).

**P3 — hardening**
11. **Authorization changes are not auto-audited** (no triggers into `audit_logs` on
    membership/grant changes).
12. **Permissions seeded for nonexistent tables** (`hostel`, `transport`, `certificates`,
    `documents`) — either the tables or the codes should go before they confuse a
    permission-management UI.
13. `profiles.role` / `app_metadata.role` legacy branches in `get_my_permissions()` are still
    live — the old privilege path coexists with the new one until the 02/06 policies they
    serve are fully retired.
