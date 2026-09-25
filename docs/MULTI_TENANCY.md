# Multi-Tenancy — Madrassa 360

**Status:** Phase 2 (2026-09-25) — database architecture + RLS written and parse-validated; **never applied to a live database yet.** Nothing here is production-true until migrations 001–010 run on staging and `supabase/tests/cross_tenant_isolation.sql` passes.

## The model in one paragraph

One codebase, one application, N isolated institutions. A **tenant** is a row in `public.tenants`. Every business row carries `tenant_id`; the **database** (not the app) enforces that you only ever see rows whose `tenant_id` belongs to a tenant you are an active member of. Membership is per-tenant and per-role: the same human can be `tenant_admin` of Madrasa A and `teacher` of Madrasa B. Platform operators (`platform_owner`, `platform_support`) live outside tenants in `platform_admins`.

## Tables

| Table | Purpose | Key columns |
|---|---|---|
| `tenants` | The institution | `id`, `tenant_code` (unique, `T-XXXXXXXX`), `name`, `name_urdu`, `slug` (unique), `logo_url`, `favicon_url`, address/city/district/province/country, `phone`, `email`, `website`, `principal_name`, `registration_number`, `status` ∈ `trial/active/suspended/expired/cancelled/archived` |
| `tenant_settings` | Per-tenant configuration (mission §6) | `tenant_id` PK/FK, `language`, `timezone`, `currency`, `date_format`, `academic_year`, `theme`, `primary_color`, `secondary_color`, `accent_color`, `font`, `dark_mode_enabled`, `receipt_header`, `receipt_footer`. Auto-created by trigger on tenant insert |
| `modules_catalog` / `tenant_modules` | Per-tenant module enablement (mission §7) | Catalog: students, staff, teachers, attendance, academics, exams, results, fees, finance, library, hostel, transport, parents, notifications, reports, documents, certificates. Defaults auto-enabled on tenant insert |
| `tenant_memberships` | **The** user↔tenant↔role source (mission §8) | `id`, `tenant_id` FK, `user_id` FK → `auth.users`, `role` (tenant roles only), `is_active`, `joined_at`, `UNIQUE(user_id, tenant_id)` |
| `platform_admins` | Platform operators (mission §10) | `user_id` PK → `auth.users`, `role` ∈ `platform_owner/platform_support` |
| `profiles` | Global identity (mission §8) | `id` PK → `auth.users`, `name`, `phone`, `photo_url`. **No tenant, no client-writable role** (see lockdown below) |
| `permissions` / `roles` / `role_permissions` | Permission catalog (mission §9) | 66 dotted codes (`students.view`, `fees.collect`, …); 12 roles; join table. Reconciled with (not replacing) the legacy 06 tables |

Legacy `madrasas` rows are migrated into `tenants` by 004 (`tenant_code` derived deterministically as `'M-'` + first 8 hex chars of the madrasa id, so re-runs re-resolve the same row). Legacy `user_roles` rows are backfilled into `tenant_memberships`; `madrasas.admin_user_id` becomes `tenant_owner`.

## RLS enforcement design (the critical decision)

**The database is the single enforcement point. The app is never trusted.**

- **No JWT custom claims for tenant.** Policies do not read tenant from the token and never accept a client-supplied tenant id. Every tenant-scoped policy joins `tenant_memberships` through three `SECURITY DEFINER` helpers (`SET search_path = public`):
  - `is_platform_admin()` — caller is in `platform_admins`
  - `is_tenant_member(p_tenant_id)` — caller has an active membership in that tenant
  - `tenant_has_permission(p_tenant_id, p_code)` — platform admin, or the caller's membership role grants `p_code` via `role_permissions`
  - (`is_tenant_admin(p_tenant_id)` exists for membership-table write policies, where self-referencing RLS would recurse.)
- **Policy template** (every one of the 13 business tables — students, staff, darjas, classes, attendance, fees, exams, results, announcements, darja_sections, library_books, book_issues, finance_transactions):
  - `SELECT`: `is_platform_admin() OR (is_tenant_member(tenant_id) AND (tenant_has_permission(tenant_id,'<mod>.view') OR <ownership fallback>))`
  - `INSERT`: `WITH CHECK (is_platform_admin() OR (is_tenant_member(tenant_id) AND tenant_has_permission(tenant_id,'<mod>.create')))`
  - `UPDATE`: same USING as SELECT; `WITH CHECK` requiring the matching update permission
  - `DELETE`: `USING (is_platform_admin() OR (is_tenant_member(tenant_id) AND tenant_has_permission(tenant_id,'<mod>.delete')))`
- **Ownership fallbacks preserved** (tenant-bound): parents still reach only their own children (`parent_user_id = auth.uid()` AND same-tenant correlation) — the sound parts of the old 02 policies, minus the leaks (`fees_teacher_read`, `staff_teacher_view` salary exposure, all-authenticated photo reads are all dropped).
- **`profiles` lockdown** (kills the live P0 escalation): all five legacy 02 policies dropped by exact name; users can UPDATE only their own row and a `profiles_lock_role()` trigger raises on any non-platform-admin attempt to change `role`; there is **no** INSERT policy for clients (only the rewritten `handle_new_user()` trigger inserts, least-privilege default `role='student'` — real power comes from `tenant_memberships` via provisioning).
- **`tenant_id` is immutable**: `prevent_tenant_id_change()` trigger on all 13 tables — rows can never be moved between tenants by UPDATE.
- **Storage**: objects live under `{tenant_id}/…` in `student-photos`, `staff-photos`, `documents`; policies check `is_tenant_member(((storage.foldername(name))[1])::uuid)`; malformed paths deny.
- **Views** `attendance_summary` / `fee_summary`: `security_invoker = true` so caller RLS applies (Postgres 15+).
- **Stale-policy stacking is impossible by construction**: 007 drops all 81 legacy policies by *verified* names (scripted cross-check: 100% of DROPs match a real `CREATE POLICY` in 02/05/06/03) and ends with a fail-loud `pg_policies` assertion — the migration **aborts** if any legacy policy survives.

## Active-tenant resolution (a UI concept, not a DB concept)

The database deliberately has no "current tenant": a member of three madrasas can query all three, and RLS filters each row. The *app* picks one active tenant for display:

- `lib/core/services/tenant_context.dart` — `TenantMembership` model; `tenantMembershipsProvider` (reads `tenant_memberships` + embedded `tenants` for the signed-in user); `TenantContext` (`StateNotifier<String?>`) with `init()` (restores `SharedPreferences` `active_tenant_id`, validates, falls back to first membership), `switchTenant()`, `refresh()`; `currentTenantIdProvider` (`String?`, null when logged out).
- Providers scope every query with unconditional `.eq('tenant_id', tenantId)` (the old optional `if (madrasaId != null)` pattern is gone from providers); models carry required `tenantId`; inserts stamp the context's tenant.
- Realtime inherits table RLS, so subscriptions are tenant-scoped automatically once 007 is applied.

## Roles & permissions (mission §9)

12 roles: `platform_owner`, `platform_support` (platform table) and `tenant_owner`, `tenant_admin`, `principal`, `accountant`, `teacher`, `librarian`, `hostel_manager`, `parent`, `student`, `staff` (membership roles). 66 dotted codes; `tenant_owner`/`tenant_admin` hold all 61 tenant-scoped codes; `platform_owner` holds all 66. `get_my_permissions()` returns the **union** across the caller's active memberships (kept signature-compatible for the app; the legacy `user_roles`/`profiles.role` UNION branches inside it are deprecated). Write policies in 007 use the real 005 codes (`attendance.mark/edit`, `results.enter/edit`, `fees.collect`, `academics.manage`, …) — the mapping is documented in 007's header because the generic `<mod>.update/delete` template does not exist for every module.

## What Phase 2 deliberately did NOT change

- **No screen rewrites.** 5 screens got one-line `tenantId:` constructor fixes only (compile-safety); full rewiring is Phase 8.
- **Repositories** (`student_repository`, etc.) still query unscoped — providers are scoped, repositories follow in Phase 8.
- **Auth flow untouched**: fake logout, session restore, secure storage, and invitation-based provisioning are Phase 5/7. `TenantContext.init()` is not yet wired into login/logout.
- **Legacy RBAC remnants**: `user_roles` table + policies, `profiles.role` column + CHECK, `get_user_role()`/`get_my_role()`/single-arg `has_permission()` are deprecated-in-place, not removed (decommission in Phase 5).
- **Missing entirely (later phases)**: provisioning wizard + Edge Functions (§12), licensing/subscriptions (§§42–43), offline SQLite + sync (§§20–23), `audit_logs` (§30), finance rebuild (§28), reporting (§31), CI/installer (§§39, 65–66).
- **Secrets**: the committed keys are still in git history and the client still reads `SUPABASE_SERVICE_KEY` — key rotation + purge remain the user's P0 action; Phase 2 added `.env.example` (placeholders only) and verified `.env` is gitignored.

## Module gating + dynamic branding design (mission §§32–33, Phase 4)

**Status:** design contract only — the branding implementation is being built
by a separate worker; what follows is the contract it must honor. Module
gating UX follows the same contract. Both are *presentation-layer* concerns:
they never replace RLS, which remains the single enforcement point.

### Module gating contract

- **Source of truth:** `public.tenant_modules(tenant_id, module, is_enabled)`
  (migration 003; auto-seeded on tenant insert — defaults: students,
  teachers, attendance, academics, exams, results, fees, parents enabled).
- **Who can toggle:** `modules.view` to read, `modules.manage` to flip a
  switch (tenant_admin/tenant_owner only, per 005).
- **Client behavior:** after `TenantContext.init()`, the app fetches the
  active tenant's `tenant_modules` and hides nav items / routes for disabled
  modules. A disabled module's screens are unreachable AND its providers
  return [] — belt and suspenders.
- **Honest limitation (2026-09-25):** gating is UX-only. RLS policies do
  *not* consult `tenant_modules` — a disabled module's rows are still fully
  protected by the 007 permission policies, but a direct API call with a
  valid permission code would still return rows. Closing that gap
  (RLS-side module check, e.g. a `tenant_module_enabled(uuid, text)`
  helper in policy USING clauses) is a documented Phase-8 hardening item,
  not a blocker for the portal UX.

### Dynamic branding contract (implemented by the branding worker)

- **Data:** `tenants(name, name_urdu, logo_url, favicon_url)` +
  `tenant_settings(language, theme, primary_color, secondary_color,
  accent_color, font, dark_mode_enabled, receipt_header, receipt_footer)`
  (migrations 001–002; settings auto-created by trigger on tenant insert).
- **Client behavior:** after `TenantContext.init()` (and on every tenant
  switch), the app loads the tenant's branding row and applies it —
  `ThemeData` from the color/font/dark-mode fields, app-bar title from
  `name_urdu` when the locale is Urdu (else `name`), logo widget from
  `logo_url` with a bundled fallback. Values are cached per tenant in
  `SharedPreferences` under a `branding_<tenant_id>` key and re-fetched
  on switch.
- **Contract rules the branding worker must follow:**
  1. Read branding from the DB rows above — never hardcode a tenant's
     name, logo, or colors in Dart.
  2. Apply only *after* `currentTenantIdProvider` is non-null; before
     that (or on logout) render the neutral default brand.
  3. Fall back gracefully: any NULL branding field resolves to the
     neutral default (missing `logo_url` → bundled logo, missing colors
     → default palette). A tenant with no branding configured must look
     identical to today's app.
  4. RTL/Urdu is non-negotiable: `name_urdu` + Urdu labels are the
     primary display when the locale is `ur`; the layout must stay RTL.

### Portal link tables (Phase 4, migration 015)

- `public.student_guardians(tenant_id, student_id, guardian_user_id →
  auth.users, relationship, is_primary)` — the enforced parent↔child
  link. Replaces the legacy single-column `students.parent_user_id`
  (kept for 007 RLS-fallback compatibility only; new code joins through
  the link table). Backfilled once from legacy `parent_user_id` values
  that resolve to real `auth.users` rows.
- `public.teacher_class_assignments(tenant_id, teacher_user_id →
  auth.users, class_id → classes, subject, academic_year, is_active)` —
  the enforced teacher↔class link (no such table existed before).
- RLS mirrors the 007 template: guardians/teachers `SELECT` only their
  own rows within tenants they belong to
  (`guardian_user_id = auth.uid() AND is_tenant_member(tenant_id)`);
  INSERT/UPDATE/DELETE are tenant-admin (+ platform-admin) only.
  `tenant_id` is immutable via the 006 `prevent_tenant_id_change()`
  trigger. Parse-validated with pglast; never applied to a live DB.
- Dart: `lib/providers/parent_portal_provider.dart` (guardian link →
  own children → scoped fees/results/attendance/announcements) and
  `lib/providers/teacher_portal_provider.dart` (assignments → assigned
  classes → assigned students). Every provider bails out (returns [])
  when `currentTenantIdProvider` is null and always filters by
  `tenant_id` — unscoped queries are impossible by construction.
