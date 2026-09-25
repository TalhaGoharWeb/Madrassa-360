# Database — Madrassa 360

**Baseline:** `supabase/01_schema.sql` … `supabase/06_rbac.sql` are the legacy hand-run scripts (kept for history; see `docs/DATABASE_AUDIT.md` for everything wrong with them). **The canonical forward path is `supabase/migrations/001`–`010`** (Phase 2, 2026-09-25): ordered, idempotent, ledger-tracked. They assume the legacy baseline has been applied (that's the state of any existing deployment) and are also safe on a fresh project where the baseline ran first.

## Schema map

**Platform layer** (no tenant): `tenants`, `tenant_settings`, `modules_catalog`, `tenant_modules`, `tenant_memberships`, `platform_admins`, `profiles` (global identity), `permissions`, `roles`, `role_permissions`, `schema_migrations`.

**Tenant-scoped** (all have `tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT` + immutability trigger): `students`, `staff`, `darjas`, `classes`, `darja_sections`, `attendance`, `fees`, `exams`, `results`, `announcements`, `library_books`, `book_issues`, `finance_transactions`.

**Legacy / deprecated** (kept, do not build on): `madrasas` (migrated into `tenants`; read-only policies), `user_roles` (+ policies), `profiles.role` (client writes blocked by trigger), `get_user_role()`, `get_my_role()`, single-arg `has_permission()`, views `attendance_summary`/`fee_summary` (now `security_invoker`).

## Migration order (each ends with a `schema_migrations` ledger insert)

| # | File | Purpose |
|---|---|---|
| 001 | `001_tenant_core.sql` | `schema_migrations` ledger; `tenants` table (code/slug generation, status CHECK, slug trigger); platform-admin RLS seed |
| 002 | `002_tenant_settings.sql` | `tenant_settings` + auto-provision trigger on tenant insert |
| 003 | `003_tenant_modules.sql` | `modules_catalog` (17 modules) + `tenant_modules` + default-enablement trigger |
| 004 | `004_memberships.sql` | `madrasas`→`tenants` migration; `platform_admins`; `tenant_memberships` (+ backfill from `user_roles` and `madrasas.admin_user_id`); helpers `is_platform_admin()`, `is_tenant_member(uuid)`, `is_tenant_admin(uuid)`, `tenant_has_permission(uuid,text)`; RLS for all of the above |
| 005 | `005_rbac.sql` | Reconcile legacy 06 catalog (drops its 6 policies by verified name); 66 dotted permission codes; 12 roles; `role_permissions` matrix; tenant-aware `get_my_permissions()`; catalog RLS |
| 006 | `006_tenant_retrofit.sql` | `tenant_id` on the 13 business tables; backfill (via `madrasa_id`→deterministic `tenant_code`, else auto-created `Legacy Institution` tenant); `SET NOT NULL`; FK; `prevent_tenant_id_change()` triggers |
| 007 | `007_tenant_rls.sql` | **The RLS rewrite.** Drops 81 legacy policies by verified exact name (100% scripted cross-check); recreates tenant+permission policies on all 13 tables + `profiles` lockdown + role-lock trigger + rewritten `handle_new_user()`; `security_invoker` on the two views; ends with a **fail-loud `pg_policies` assertion** (aborts if any stale policy survived) |
| 008 | `008_tenant_storage.sql` | Ensures the 3 buckets exist; drops 13 legacy storage policies by verified name; `{tenant_id}/` prefix policies on `storage.objects` |
| 009 | `009_tenant_indexes.sql` | `tenant_id` btree on all 13 tables + composites: `attendance(tenant_id,date)`, `attendance(tenant_id,class_id,date)`, `fees(tenant_id,student_id)`, `fees(tenant_id,month)`, `results(tenant_id,student_id)`, `results(tenant_id,exam_id)`, `students(tenant_id,class_id)`, `students(tenant_id,is_active)`, `announcements(tenant_id,is_active)`, `tenant_memberships(user_id,is_active)`, `tenant_memberships(tenant_id,is_active)` |
| 010 | `010_tenant_seed.sql` | **DEV/STAGING ONLY — never in production.** Demo tenant + settings/modules (via triggers); attaches `demo.admin@madrasa360.local` as `tenant_owner` if that auth user exists |

Idempotency: every migration is re-runnable (`IF NOT EXISTS` / `ON CONFLICT DO NOTHING` / `pg_policies`-guarded DO blocks). Re-running 007 after success is a no-op; re-running 006 re-resolves the same tenants via the deterministic `tenant_code`.

## How to run on a fresh staging project

Prerequisites: a Supabase project (Postgres 15+), `pgcrypto` available (Supabase ships it), and the service-role/`postgres` connection string. **Do not run against production.**

```bash
# 1. Apply the legacy baseline once, in order (existing deployments already have this)
for f in supabase/01_schema.sql supabase/02_rls.sql supabase/03_storage.sql \
         supabase/05_new_modules.sql supabase/06_rbac.sql; do
  psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f "$f"
done
# NOTE: 04_seed.sql is intentionally skipped — it ships mock PII.

# 2. Apply the tenant migrations in order
for f in $(ls supabase/migrations/*.sql | sort); do
  psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f "$f"
done

# 3. Verify the ledger
psql "$STAGING_DB_URL" -c "SELECT version FROM public.schema_migrations ORDER BY version;"

# 4. (dev only) create the demo auth user in the Supabase dashboard, then run the seed
psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/010_tenant_seed.sql
```

If 007 aborts with `007 FAILED: stale legacy policies survived the sweep`, do not work around it — inspect `pg_policies` for the named survivors; it means the baseline drifted from the audited files.

## How to run the isolation tests

```bash
psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/cross_tenant_isolation.sql
```

- 30 assertions: contract guards (§0) + the Tenant A/B × Admin/Teacher matrix (SELECT/UPDATE/DELETE/INSERT denial both directions), role-escalation attempt (must fail, legit self-update must pass), membership self-grant (must fail), storage cross-tenant read/write (must fail), a 45-name stale-policy regression guard, and a positive control proving the policies aren't deny-all.
- The whole suite runs inside one transaction and ends with `ROLLBACK` — staging is left untouched.
- **Status: NOT YET EXECUTED** (written 2026-09-25; no staging database is available from this environment). The first green run on staging is the Phase-2 acceptance gate.

## Backfill notes

- `madrasas` → `tenants`: `tenant_code = 'M-' + first 8 hex of the madrasa id`; `is_active=false` → `status='suspended'`; plan basic/standard/premium → `'active'`.
- Business tables with `madrasa_id` resolve through that code; tables without it (and unresolvable rows) land in the auto-created `Legacy Institution` (`slug='legacy'`, `status='trial'`) — rename/split it per real institutions afterwards.
- `profiles.role` is **not** backfilled anywhere privileged: new signups get `role='student'`; real power comes only from `tenant_memberships`.

## Known limitations (honest)

- Parse-validated only (`pglast`); never executed — planner behavior, trigger ordering vs RLS, and the `storage.foldername` cast path are unproven until staging.
- `profiles.role` CHECK still lists legacy role names (trigger enforces least-privilege regardless); full column decommission is Phase 5.
- `get_my_permissions()` keeps deprecated `user_roles`/`profiles.role` UNION branches so the app keeps working until Phase 5 rewires auth.
- No down-migrations; rollback = restore from backup (document your backup before applying).
