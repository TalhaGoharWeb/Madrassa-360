# Implementation Plan — Production Readiness — 2026-10-01

**Source:** `docs/audit/PRODUCTION_AUDIT_2026-10-01.md` (7 blockers · 8 majors · 46 minors)
**Branch:** `redesign/ux-v2` · **Base:** `90b41e59` (CI-green)
**Rule:** one CI-green commit → then Windows + Android builds → user visual confirmation.

## Phase 1 — Code fixes on the branch (no live-DB writes)

### 1A. Migrations worker — new files in `supabase/migrations/`
- **`027_user_accounts_app_roles.sql`** (blockers L-1, L-2; major B-F6):
  - `CREATE TABLE IF NOT EXISTS public.user_accounts` matching
    `lib/data/models/user_account.dart`: `id uuid PK default gen_random_uuid()`,
    `name text NOT NULL`, `email text NOT NULL UNIQUE`, `role_name text NOT NULL DEFAULT 'teacher'`,
    `role_name_urdu text NOT NULL DEFAULT 'استاد'`, `linked_staff_id uuid NULL`,
    `linked_parent_id uuid NULL`, `is_active boolean NOT NULL DEFAULT true`,
    `created_at timestamptz NOT NULL DEFAULT now()`, `updated_at timestamptz NOT NULL DEFAULT now()`.
  - `CREATE TABLE IF NOT EXISTS public.app_roles` (live has 3 rows out-of-band —
    do NOT drop/recreate; `IF NOT EXISTS` only adds the definition for fresh DBs):
    `id uuid PK`, `name text UNIQUE NOT NULL`, `name_urdu text`,
    `description text`, `permissions text[]`, `is_system boolean DEFAULT false`,
    `created_at timestamptz DEFAULT now()`.
  - Enable RLS on both. Policies:
    - `user_accounts`: SELECT for authenticated users who are active members of
      the same tenant OR platform/super admins (use existing helpers
      `is_platform_admin()`, `is_tenant_member()`); INSERT/UPDATE/DELETE gated on
      `tenant_has_permission(..., 'users.manage')` or platform admin. Keep it
      simple and fail-closed: platform admins full access; tenant members with
      `users.manage` permission full access within their tenant.
    - `app_roles`: SELECT for any authenticated user (role catalog is needed for
      assignment UI); INSERT/UPDATE/DELETE for platform/super admins only.
  - **Tenants UPDATE policy (major B-F2, ships with 024):**
    `tenants_member_update` — `FOR UPDATE USING (is_tenant_member(id) AND tenant_has_permission(id,'settings.update'))`.
    Safe to apply now; the logo feature itself still waits on 024 approval.
- **`028_finance_per_table_doc_triggers.sql`** (blockers L-3, B-F1):
  - Drop the shared trigger + function:
    `DROP TRIGGER IF EXISTS trg_invoices_fill_doc_numbers ON public.invoices;`
    (same for payments, income) then
    `DROP FUNCTION IF EXISTS public.finance_fill_doc_numbers();`
  - Create three per-table functions, each referencing ONLY columns that exist on
    its table:
    - `finance_fill_invoice_number()` → `NEW.invoice_number`
    - `finance_fill_receipt_number()` → `NEW.receipt_number` (payments)
    - `finance_fill_income_doc_number()` → `NEW.receipt_number` (income)
  - Re-create the three BEFORE INSERT triggers pointing at the per-table functions.
  - Verify sequences `public.finance_invoice_seq`, `public.finance_receipt_seq` exist
    (create if missing).
- **Policy fixes (majors B-F3, B-F4)** — include in `027`:
  - Replace `madrasas_member_select` USING with own-tenant scoping:
    `USING (is_tenant_member(tenant_id) OR is_platform_admin())` — check the actual
    column name on `madrasas` first (legacy table; confirm tenant FK column).
  - Replace `fees_delete_tenant` permission code `'fees.collect'` → `'fees.delete'`.
- **Minor:** `sync_apply` (016): add `updated_by` to writable-column exclusion list.
  (Full per-table permission hardening of `sync_apply` (major B-F5) is deferred to a
  follow-up migration after review — SECURITY DEFINER changes need a dedicated
  test pass; record as known limitation.)
- **Minor:** demo SQL hygiene — wrap seed trigger drop/re-create in a single
  transaction; move `Demo@1234` out of `demo/seed_demo_madrassa.sql` comments
  into the runbook note.

### 1B. Reports worker — `lib/core/reports/documents/`
- **Blocker R-1** `admin_reports.dart:270`: remove the `pw.Column` wrapper around the
  income/expense `dataTable` inside the MultiPage `section()` so the table becomes
  a direct spanning child and paginates. Verify no other generator wraps a long
  table in `pw.Column` inside MultiPage.
- Minors: route `subEn` through `auto()` (`admin_reports.dart:198-216`); fix
  `pw.Spacer()` misuse (`student_documents.dart:156`); constrain ID-card name/line
  widths (`:117`, `:320`); route Urdu-digit phones through `auto()` (`:173`);
  add `signatureRow` to attendance report (`student_reports.dart:132-166`), fee
  statement (`:190-261`), and all 8 admin tabular reports; add `emptyNotice` to
  `resultCard` (`result_documents.dart:35-58`).
- Add/extend a unit test that builds the income/expense PDF with >1 page of rows
  (regression for the MultiPage crash) and one that renders an Urdu-heavy ID card.

### 1C. Flutter-app worker — `lib/`
- **Majors:** delete dead screens/widgets (list in audit §Frontend minors dead-code,
  incl. `teacher_dashboard_screen.dart` legacy + `main_screen.dart` to kill the
  `TeacherDashboardScreen` name collision); fix `madrasa_provider.dart`
  `update()`/`delete()` false-success `catch (_) {}` — surface errors, roll back
  optimistic state.
- `user_management_provider.dart`: after 027 exists, remove/retire the legacy
  duplicate-RBAC path if it shadows the new tables; keep behavior identical for
  the live UI.
- Minors: Nastaleeq `height` 1.6 → 2.0 (`master_admin_nav.dart:268`); wrap
  `attendance_screen.dart:328` and `app_widgets.dart:401` titles in
  `Expanded`+ellipsis; replace hardcoded `Color(0x…)` literals with `AppColors`
  tokens (`crash_screen.dart`, `app_nav_rail.dart:30`, `madrassa_logo_screen.dart:312`,
  `tenant_branding_provider.dart`); add `semanticLabel`s to logo/user images
  (list in audit); `AppLogger` on the silent `catch (_) {}` in
  `finance_repository.dart:561,643` and `announcement_provider.dart:129`.
- Regression tests: `madrasa_provider` error-surfacing test; keep suite green.

## Phase 2 — Live Supabase (operator step, via Management API)
Explicitly NOT included: migration **024** (tenant logos) — needs user approval.
1. Record 025/026 in the ledger (L-4):
   `INSERT INTO public.schema_migrations(version, applied_at) VALUES
   ('025_repair_finance_doc_columns', now()), ('026_repair_profiles_columns', now())
   ON CONFLICT DO NOTHING;`
2. Apply `027_user_accounts_app_roles.sql`, then `028_finance_per_table_doc_triggers.sql`.
3. Verify live: `user_accounts`/`app_roles` exist with policies; insert a test
   invoice/payment/income row and confirm doc numbers generate; confirm triggers fire;
   delete test rows. Confirm `madrasas_member_select` + `fees_delete_tenant` policies replaced.

## Phase 3 — Verify
1. `flutter analyze`, full `flutter test`, `dart format` check, no-mock-data guard,
   migration validation, Deno check/lint (local first).
2. Push branch; full GitHub Actions CI to 6/6 green on ONE commit.
3. Cut Windows + Android builds from that exact green commit; deliver SHA-256 +
   artifact names + run URLs.
4. User installs on Windows + Android and visually confirms (final gate).

## Deferred / needs user decision
- **Migration 024 (tenant logos):** apply only on explicit approval.
- **`sync_apply` full hardening (B-F5):** dedicated follow-up with test pass.
- **DB password rotation** (owed since 2026-09-26), **legacy JWT keys**, **Nastaleeq
  redistribution license**, **platform-console profile persistence** — unchanged.
