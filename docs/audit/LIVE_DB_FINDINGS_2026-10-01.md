# Live Supabase Audit — 2026-10-01

Project: `ffhsrnkvjjedvclfwgmr` (via Management API, read-only queries)
Branch audited: `redesign/ux-v2` @ `90b41e59`

## Blockers (live DB)

### B1. `public.user_accounts` table does not exist
- The app's user management (`lib/providers/user_management_provider.dart:87,188,220`)
  reads/writes `public.user_accounts`, but the table exists in NO migration file
  and does NOT exist live. The entire Users screen is non-functional.
- Fix: new migration `027_user_accounts.sql` creating the table per
  `lib/data/models/user_account.dart` schema + RLS.

### B2. `public.app_roles` has RLS enabled with ZERO policies
- Table exists live (3 rows: admin, teacher, parent) but was created out-of-band
  (in no migration). RLS on + no policies = all reads return empty for the app's
  authenticated client (`user_management_provider.dart:99,293,327,344`).
- Note the duality: migrations seed a `roles` table (39 rows live) which the app
  NEVER queries; the app uses `app_roles` instead.
- Fix: migration `027` — create `app_roles` idempotently with proper RLS
  (read for authenticated, write for platform/super admins).

### B3. Finance doc-number triggers missing live
- `trg_invoices_fill_doc_numbers`, `trg_payments_fill_doc_numbers`,
  `trg_income_fill_doc_numbers` are ABSENT (function `finance_fill_doc_numbers`
  exists but nothing fires it). The demo-seed workaround dropped them and the
  re-create never landed.
- Impact: new invoices/payments/income get NULL doc numbers.
- Fix: re-create the three triggers live (idempotent migration 027 or direct apply).

### B4. Migration tracking out of sync
- `public.schema_migrations` records only up to `023_super_admin`, but 025's
  `invoices.invoice_number` column and 026's `profiles` columns exist live.
  024 (`tenant_logos`) is genuinely not applied.
- Fix: record 025/026 in tracking; keep 024 pending explicit user approval.

### B5. Migration 024 not applied (needs user approval)
- No `tenants.use_logo_on_reports`, no `tenant-logos` bucket → tenant logo
  upload fails live. Do NOT apply without explicit approval.

## Non-blockers / notes
- All 5 Edge Functions deployed and ACTIVE: provision-tenant, manage-tenant,
  manage-users, export-tenant, send-notification (memory note "undeployed" is stale).
- 50 tables queried by the app; only `user_accounts` missing live.
- `platform_config` has a public-read policy (`USING true`) — verify intentional.
- Tables without `tenant_id` that the app queries: app_roles, license_plans,
  madrasas/tenants (root), modules_catalog, permissions, platform_admins,
  platform_config, profiles, super_admins, tenant_role_permissions — mostly
  platform-level; `tenant_role_permissions` deserves a look.
