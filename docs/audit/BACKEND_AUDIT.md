# BACKEND AUDIT — Madrassa-360 (branch `redesign/ux-v2`)

- **Date:** 2026-10-01
- **Auditor:** backend-audit subagent (static review, no live calls)
- **Repo:** `~/workspace/madrassa-redesign-fix`, branch `redesign/ux-v2`, HEAD `90b41e59` (CI-green)
- **Scope:** all 26 migrations (`001`–`026`), `demo/` seed pack, `supabase/functions/`, lib↔backend cross-check (`lib/` read-only)

> Method: read every migration file in order; grepped `lib/` for `.from('…')`, `.rpc('…')`, `functions.invoke(…)`; diffed against migrations; checked demo seed safety; verified storage policies. All SQL quotes are verbatim from the migration files.

---

## 1. Migration inventory

| # | File | Creates / changes | RLS | Notes |
|---|------|-------------------|-----|-------|
| 001 | `001_tenant_core.sql` | `tenants` (+`logo_url` from brand work), `schema_migrations`, `slugify`, `set_updated_at` | ON (`tenants`); **NOT on `schema_migrations`** | — |
| 002 | `002_tenant_settings.sql` | `tenant_settings` | ON | — |
| 003 | `003_tenant_modules.sql` | `modules_catalog`, `tenant_modules` | ON | — |
| 004 | `004_memberships.sql` | `platform_admins`, `tenant_memberships`; helpers `is_platform_admin/is_tenant_member/is_tenant_admin/tenant_has_permission` | ON | Member read policies added |
| 005 | `005_rbac.sql` | `permissions`, `roles`, `role_permissions` + 66 permission codes + 12 roles; `get_my_permissions()` tenant-aware | ON | Legacy `user_roles` left (dropped in 013) |
| 006 | `006_tenant_retrofit.sql` | Adds `tenant_id` (NOT NULL, FK, immutability trigger) to 13 legacy business tables | — | Backfill from `madrasa_id`; legacy 'legacy' tenant |
| 007 | `007_tenant_rls.sql` | RLS ON for the 13 legacy tables + `profiles` + `madrasas`; tenant-bound CRUD policies | ON | **2 major findings** (see F-3, F-4) |
| 008 | `008_tenant_storage.sql` | 3 private storage buckets + tenant-bound policies | ON (`storage.objects`) | — |
| 009 | `009_tenant_indexes.sql` | Indexes incl. `idx_students_tenant_active` | — | — |
| 010 | `010_tenant_seed.sql` | Demo tenant seed | — | **DEV/STAGING ONLY — NEVER RUN IN PRODUCTION** (minor F-16) |
| 011 | `011_licensing.sql` | `license_plans`, `licenses`, `tenant_subscriptions` | ON | No `updated_at` columns (minor F-13) |
| 012 | `012_audit_logs.sql` | `audit_logs` (SELECT-only for clients), SECURITY DEFINER `log_audit()` | ON | — |
| 013 | `013_user_roles_removal.sql` | Drops `user_roles`; rewrites `get_my_permissions()`; `profiles.role` kept for Dart | — | — |
| 014 | `014_finance.sql` | 13 finance tables, `finance_audit()`, `finance_immutable_guard()`, doc-number triggers | ON (fail-loud check) | **Blocker F-1** (shared doc-number trigger function) |
| 015 | `015_guardians_assignments.sql` | `student_guardians`, `teacher_class_assignments` | ON | — |
| 016 | `016_sync.sql` | Sync columns + SECURITY DEFINER `sync_apply()` | — | **Major F-5** (permission bypass) |
| 017 | `017_notifications.sql` | `notifications`, `notification_preferences`, `notification_device_tokens` | ON | — |
| 018 | `018_devices.sql` | `platform_config` (public SELECT `USING (true)` — intentional), `devices`, `device_sessions` | ON | Revocation enforcement advisory only (minor F-11) |
| 019 | `019_role_ux.sql` | `tenant_roles`, `tenant_role_permissions`, `user_permissions`, `permission_scopes`, `permission_delegations`; tenant-editable role catalog | ON (in 020) | Literal role-key gating (minor F-12) |
| 020 | `020_role_ux_rls.sql` | RLS on the 5 RBAC tables; rewrites `tenant_has_permission()` (roles + deny + delegations); RPCs (`assign_tenant_role`, `set_user_permission`, `delegate_permission`…) | ON | `scope_allows()` fail-open→ fail-closed in 022 |
| 021 | `021_role_template_seeds.sql` | `provision_role_templates()` (granted to `service_role` only) | — | Called by the demo seed |
| 022 | `022_scope_failclosed.sql` | `scope_allows()` flips fail-CLOSED; backfills 'all' scopes | — | Attendance/results writes now require a scope row (minor F-14) |
| 023 | `023_super_admin.sql` | `super_admins`; `is_super_admin()`; `is_platform_admin()` redefined (super admins inherit platform-admin policies); `check_tenant_access()` RPC | ON | Semantics change, documented |
| 024 | `024_tenant_logos.sql` | `tenants.use_logo_on_reports`; `tenant-logos` PUBLIC bucket + policies | partial | **NOT applied to live Supabase (needs explicit approval)**; **major F-2** (false header claim, missing UPDATE policy) |
| 025 | `025_repair_finance_doc_columns.sql` | Adds `invoices.invoice_number`, `payments.receipt_number`, `income.receipt_number` if missing; unique constraint | — | Repairs pre-014 tables that skipped 014's `CREATE TABLE IF NOT EXISTS` |
| 026 | `026_repair_profiles_columns.sql` | Adds `profiles.phone`, `photo_url`, `madrasa_id` if missing | — | Columns the app reads but migrations never created |

## 2. RLS matrix (per-table)

Legend: ✅ enabled + tenant-scoped policies · ⚠️ enabled with issues · ❌ not enabled

| Table | RLS | Notes |
|---|---|---|
| `schema_migrations` | ❌ | Migration ledger, no RLS (minor F-9) |
| `tenants` | ⚠️ | SELECT: platform-admins + members read own; **NO UPDATE/DELETE policy for tenant members** (major F-2) |
| `tenant_settings`, `tenant_modules` | ✅ | — |
| `modules_catalog` | ✅ | — |
| `platform_admins` | ✅ | — |
| `tenant_memberships` | ✅ | — |
| `permissions`, `roles`, `role_permissions` | ✅ | — |
| Legacy 13 (darjas, classes, students, staff, attendance, fees, exams, results, announcements, darja_sections, library_books, book_issues, finance_transactions) | ⚠️ | `fees` DELETE checks wrong permission (major F-4) |
| `profiles` | ✅ | — |
| `madrasas` (legacy) | ⚠️ | `madrasas_member_select`: ANY active member of ANY tenant can SELECT all rows (major F-3) |
| `license_plans`, `licenses`, `tenant_subscriptions` | ✅ | — |
| `audit_logs` | ✅ | SELECT-only for clients |
| 014 finance ×13 | ✅ | Lifecycle gates via permission codes |
| `student_guardians`, `teacher_class_assignments` | ✅ | — |
| `notifications`, `notification_preferences`, `notification_device_tokens` | ✅ | Direct INSERT = platform-admin only (by design) |
| `platform_config` | ⚠️ | Public `SELECT … USING (true)` — intentional pre-login read (minor F-10) |
| `devices`, `device_sessions` | ✅ | — |
| `tenant_roles`, `tenant_role_permissions`, `user_permissions`, `permission_scopes`, `permission_delegations` | ✅ | Write = tenant-admin or `roles.assign` |
| `super_admins` | ✅ | — |
| `storage.objects` (3 private buckets) | ✅ | Tenant-path UUID check via `storage_path_tenant()` |
| `storage.objects` (`tenant-logos` public bucket) | ⚠️ | Bucket not yet created live (024 unapplied); writes member+`settings.update`, public read by design |

## 3. Trigger review

- `finance_fill_doc_numbers()` — **BLOCKER F-1.** One shared function attached BEFORE INSERT on three tables with *different* columns (`invoices`→`invoice_number`; `payments`,`income`→`receipt_number`):
  ```sql
  IF TG_TABLE_NAME = 'invoices'
     AND (NEW.invoice_number IS NULL OR btrim(NEW.invoice_number) = '') THEN ...
  ELSIF TG_TABLE_NAME IN ('payments', 'income')
     AND (NEW.receipt_number IS NULL OR btrim(NEW.receipt_number) = '') THEN ...
  ```
  014 attaches `trg_invoices_fill_doc_numbers`, `trg_payments_fill_doc_numbers`, `trg_income_fill_doc_numbers` (lines 829–843). Root cause of the intermittent live 42703 `record "new" has no field "invoice_number"` on Supavisor (PG 17.6): plan caches record-field resolution per pooled connection; the non-matching branch's field reference resolves against the wrong rowtype. 025 only adds missing columns; the demo seed (lines 245–247, 314–322) works around it by dropping/re-creating the triggers — the hazard itself is NOT fixed. Fix: split into three table-specific functions so each `NEW` type is stable.
- `finance_immutable_guard()` (014 lines 474–495) — blocks UPDATE/DELETE only when `OLD.status` is in the protected list (e.g. `invoices`: `'paid,cancelled,void'`, `payments`: `'posted,void'`). It does NOT validate the transition: a `draft` row may be moved to `posted`/`void` by anyone whose policy permits the UPDATE — and `sync_apply()` bypasses those policies entirely (F-5).
- `sync_apply` update branch (016) — the writable-column exclusion list `('id','tenant_id','revision','server_version','deleted_at','created_at','updated_at')` does **not** exclude `status` or `updated_by`. Consequence: (a) `status` is client-writable via sync (feeds F-5); (b) if the payload contains `updated_by`, the audit stamp's extra `, updated_by = $3` produces a duplicate-SET error (minor F-8).
- `set_updated_at` — attached on `tenants`, `tenant_settings`, `tenant_memberships`, `tenant_roles`, and all 014 tables except `payment_allocations` (documented exclusion: it has no `updated_at`). Missing where the column exists: `notification_preferences`, `notification_device_tokens`, `platform_config` (minor F-13).
- `protect_last_owner()` / `is_tenant_admin()` / `user_is_tenant_admin()` — still keyed on literal role keys `'tenant_owner'`/`'tenant_admin'` while 019 made the role catalog tenant-editable; deleting/renaming those keys silently disables admin gating (minor F-12).
- Device-revocation enforcement is advisory only — documented NOT implemented (018: no auth hook / check-session wiring) (minor F-11).

## 4. Edge Functions — called vs existing

Functions in `supabase/functions/`: `export-tenant`, `manage-tenant`, `manage-users`, `provision-tenant`, `send-notification` (+ `_shared/`, `deno.json`, `README.md`).

| Called by lib | Exists | Used from |
|---|---|---|
| ✅ `send-notification` | yes | `lib/core/notifications/email_channel.dart:42`, `push_channel.dart:127` |
| ✅ `manage-users` | yes | `lib/data/role_ux_repository.dart` (×5), `lib/providers/user_management_provider.dart` (×2) |
| ✅ `manage-tenant` | yes | `lib/presentation/screens/master_admin/madrasa_detail_screen.dart:237` |
| ✅ `provision-tenant` | yes | `lib/presentation/screens/master_admin/create_madrasa_wizard.dart:220` |
| — `export-tenant` | yes | **nothing in `lib/` calls it** (referenced only by `docs/BACKUP_RESTORE.md`, `docs/DEPLOYMENT.md`, function README) |

Diff result: no called-but-missing function; one existing-but-uncalled function (`export-tenant`, informational). Deployment status cannot be verified statically (known: `manage-users` and others undeployed per standing context).

## 5. Seed safety (`demo/`)

- `demo/seed_demo_madrassa.sql` — creates one demo tenant (`demo-madrassa`), ON CONFLICT DO NOTHING, warns "Do NOT run on a production database holding real data unless you intend to add a demo tenant there". **Drops and re-creates the three doc-number triggers** as the 42703 workaround (minor F-15: failure between DROP and CREATE would leave production trigger-less). Hardcoded shared demo password `Demo@1234` in the file's STEP 0 comments (minor F-17). Verified working 2026-09-30 (counts matched).
- `demo/remove_demo_data.sql` — wrapped in a transaction; deletes only rows with `tenant_id` of `demo-madrassa`; DISABLEs the 8 finance immutability triggers and re-enables them before COMMIT (minor F-15 note: session abort between DISABLE and COMMIT leaves guards off until the session ends — the ALTERs are transactional, rollback restores). **Deletes `audit_logs` rows for the demo tenant** — a documented exception to the append-only audit design (minor F-15). Does NOT delete the 5 demo Auth users (documented manual step).

## 6. Table cross-check (lib vs backend)

All RPCs called by lib exist: `sync_apply` (016), `assign_tenant_role` / `set_user_permission` / `delegate_permission` (020), `log_audit` (012). `get_my_permissions` (005/013) and `check_tenant_access` (023) present.

**Major F-6:** `lib/providers/user_management_provider.dart` (used by `lib/presentation/screens/admin/user_management_screen.dart`, reachable from admin + super-admin shells) performs reads AND writes on **`user_accounts` and `app_roles` — tables that exist in NO migration**. Loads swallow `PostgrestException` ("table may not exist yet"), but `createAccount`/`updateAccount`/`createRole`/`updateRole`/`deleteRole` fail at runtime, and `deleteAccount` deletes the real Auth user via `manage-users` and *then* fails on the `user_accounts` delete — leaving the account deleted-but-reporting-an-error. Local optimistic state never persists server-side. This is dead legacy code paths duplicating the new RBAC (`role_ux_repository.dart`).

## 7. FINDINGS (complete list)

### Blockers
- F-1 — `014_finance.sql` / invoices, payments, income — **blocker** — shared BEFORE INSERT trigger function `finance_fill_doc_numbers()` references `NEW.invoice_number` and `NEW.receipt_number` across three tables with different columns; intermittent 42703 on pooled connections breaks ALL invoice/payment/income inserts. Not fixed (025 only adds columns; seed works around it by drop/re-create).

### Majors
- F-2 — `024_tenant_logos.sql` / tenants — **major** — migration header claims "the existing tenant-member policies already allow members to read their tenant row and `settings.update` holders to update it", but `public.tenants` has NO UPDATE policy for tenant members (only 001 `"platform admins manage tenants"` FOR ALL + 004 `"members read own tenants"` FOR SELECT). Verified: `lib/services/tenant_logo_service.dart` lines 85/108/142 (`update({'logo_url': …})`, `update({'logo_url': null})`, `update({'use_logo_on_reports': …})`) are RLS-denied for non-platform tenant admins — the whole logo-upload feature is broken for real tenant admins even after 024 is applied.
- F-3 — `007_tenant_rls.sql` / madrasas — **major** — policy `madrasas_member_select` (lines 828–835): `USING (EXISTS (SELECT 1 FROM tenant_memberships m WHERE m.user_id = auth.uid() AND m.is_active = TRUE))` — ANY active member of ANY tenant can SELECT every row of the legacy `madrasas` table. Cross-tenant read on a legacy table (the app still reads it from master-admin screens).
- F-4 — `007_tenant_rls.sql` / fees — **major** — `fees_delete_tenant` DELETE policy (lines 466–470) checks `tenant_has_permission(fees.tenant_id, 'fees.collect')` instead of `fees.delete`. Fee DELETE is gated by the collect permission; nothing checks the `fees.delete` code.
- F-5 — `016_sync.sql` / sync_apply — **major** — SECURITY DEFINER RPC checks only `is_platform_admin() OR is_tenant_member(tenant)`; any active member can insert/update/soft-delete rows in their tenant across all 26 whitelisted tables with no fine-grained permission-code check and no status-transition validation — incl. writing `status` directly on finance tables (insert with `status='posted'`, update `draft→void`/`draft→posted`), bypassing 014's status-lifecycle RLS gates. `finance_immutable_guard()` only protects rows already in final statuses; it does not validate transitions.
- F-6 — `lib/providers/user_management_provider.dart` / user_accounts, app_roles — **major** — reads AND writes tables that NO migration creates; `deleteAccount` deletes the real Auth user via `manage-users` then fails on the missing-table delete; optimistic local state never persists server-side (legacy path duplicating the new RBAC).
- F-7 — `024_tenant_logos.sql` / tenant-logos — **major** — migration NOT applied to live Supabase (known, needs explicit approval); the app reads `logo_url`/`use_logo_on_reports` and uploads to the bucket, so tenant logo settings fail until it is applied. (Combined with F-2: applying 024 alone still leaves UPDATE denied.)

### Minors
- F-8 — `016_sync.sql` / sync_apply — **minor** — update-branch writable-column exclusion does not include `updated_by`; payloads containing it hit the audit stamp's extra `, updated_by = $3` → duplicate-SET SQL error.
- F-9 — `001_tenant_core.sql` / schema_migrations — **minor** — RLS never enabled on the migration ledger (read-only version table; convention gap).
- F-10 — `018_devices.sql` / platform_config — **minor** — `SELECT` policy `USING (true)` exposes all platform_config rows publicly (documented pre-login update-check intent; verify no sensitive values).
- F-11 — `018_devices.sql` / devices, device_sessions — **minor** — revocation enforcement is advisory only (documented: auth hook / check-session edge function not wired).
- F-12 — `019_role_ux.sql` / `020_role_ux_rls.sql` — **minor** — `is_tenant_admin()`, `user_is_tenant_admin()`, `protect_last_owner()` keyed on literal role keys `'tenant_owner'`/`'tenant_admin'` while 019 made the role catalog tenant-editable; deleting/renaming those keys silently disables admin gating.
- F-13 — misc — **minor** — `updated_at` columns without `set_updated_at` triggers: `notification_preferences`, `notification_device_tokens`, `platform_config`; and `licenses`/`tenant_subscriptions` have no `updated_at` at all despite status transitions (Phase 11 revoke/extend).
- F-14 — `022_scope_failclosed.sql` / attendance, results — **minor** — writes now fail-CLOSED on `scope_allows()`; teachers holding 'classes' scope rows are denied writes with NULL `class_id` (by design, but a behavioral edge to keep in the runbook).
- F-15 — `demo/seed_demo_madrassa.sql`, `demo/remove_demo_data.sql` — **minor** — seed drops/re-creates three production triggers (42703 workaround; failure between DROP and CREATE leaves triggers missing); removal script DISABLEs 8 immutability guards in-transaction (re-enabled pre-COMMIT; abort mid-window leaves them off until session end); removal deletes `audit_logs` rows for the demo tenant (exception to append-only design).
- F-16 — `010_tenant_seed.sql` — **minor** — dev/staging-only seed header ("NEVER RUN IN PRODUCTION"); ensure the runbook glob excludes it.
- F-17 — `demo/seed_demo_madrassa.sql` — **minor** — shared demo auth password `Demo@1234` hardcoded in file comments for the five demo accounts.

### Informational (no action)
- `export-tenant` Edge Function exists but nothing in `lib/` calls it (docs-only reference). Deployment status of all functions unverifiable statically.
- `is_platform_admin()` redefinition in 023 (super admins inherit platform-admin policies) changes policy semantics — documented in-file, by design.
- Demo seed verified working 2026-09-30 after 025/026 + trigger workaround (tenants 1, darjas 6, classes 8, students 28, invoices 10, payments 7, memberships 5, +140 attendance rows).

**Totals: 1 blocker · 6 majors · 10 minors.**
