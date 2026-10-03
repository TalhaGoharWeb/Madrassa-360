# DB security test scripts

SQL assertions for the role-boundary and tenant-isolation contract, runnable
against a **staging** Supabase project (never production). They complement the
Dart unit tests in `test/unit/security/` — the Dart tests pin the *intended*
policy tables as pure-Dart mirrors; these scripts assert the *deployed*
database actually enforces them.

## Scripts

| File | Finding(s) | What it asserts |
|---|---|---|
| `01_sync_apply_role_boundaries.sql` | SEC-C1 | `sync_required_permission()` (032) deny-by-default contract incl. drift spot-checks; behavioral: unpermitted `sync_apply` insert denied; unknown op fails closed with reason; cross-tenant sync write rejected |
| `02_platform_admins_trigger.sql` | SEC-C5 | `trg_platform_admins_guard`: support self-promotion blocked, last-owner delete/demote blocked, owner management still works (SKIPs if trigger not deployed) |
| `03_tenants_column_guard.sql` | SEC-H6 | `trg_tenants_column_guard`: `settings.update` holders cannot write `status`/`suspended`/`expires_at`/`tenant_code`/`slug`/`registration_number`/`logo_url`; allow-listed columns still writable; platform bypass works (SKIPs if trigger not deployed) |
| `04_cross_tenant_isolation.sql` | tenant-isolation §(c), SEC-H5, SEC-H7, SEC-M6 | RLS read/write isolation, `tenant_id` immutability trigger, `user_accounts` scoping (029: plain members read nothing, `users.view` holders can), `madrasas_member_select` qualified-`id` check (030), permission-oracle EXECUTE revocation (031) |
| `05_finance_guards.sql` | SEC-C6, SEC-H16, SEC-H17, 042 | 034: force-draft on payment insert (ghost receipts), draft→posted legal / posted terminal, invoice derived-status rejection, 042 CHECKs (marks sanity, fee amounts), idempotency-key uniqueness |
| `06_role_rpc_ceilings.sql` | SEC-H1 | 036: `assign_tenant_role` cannot mint `tenant_owner` without being one, cannot assign roles granting unheld codes, `set_role_permissions` cannot add unheld codes; owner-can-assign positive control |
| `07_redteam_guards.sql` | RT-01, RT-03, RT-04 | 046: `trg_<table>_server_timestamps` present on all dual-timestamp sync tables + behavioral (hostile 2001 timestamps overwritten; `app.preserve_timestamps` hatch honored); 045: `edge_rate_limits` present/indexed/RLS-on with zero policies + window-count query; 040 helpers parse the upload-image deterministic path convention |

## How to run

```bash
# service_role / postgres superuser connection string (fixtures write to
# auth.users and bypass RLS for setup — the anon key cannot do this).
psql "postgresql://postgres:<password>@<staging-host>:5432/postgres" \
  -v ON_ERROR_STOP=1 \
  -f test/db/01_sync_apply_role_boundaries.sql
```

Repeat for `02_`, `03_`, `04_`. Each script:

- wraps everything in `BEGIN; … ROLLBACK;` — staging data is untouched;
- prints `PASS` / `SKIP` / `CANARY` notices;
- raises `FAIL …` exceptions (non-zero exit with `ON_ERROR_STOP=1`) on real
  violations.

`SKIP` means the corresponding fix migration/trigger is not deployed on the
target database yet — expected when running against a pre-fix snapshot.

## Simulating authenticated callers

RLS and `auth.uid()` read `request.jwt.claims`. The scripts set it per block:

```sql
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  jsonb_build_object('sub', '<user-uuid>', 'role', 'authenticated')::text,
  true);
-- … statements under test …
RESET ROLE;
```

This is exactly what PostgREST does per request; no real JWTs needed.

## CI

These scripts are **not** run in CI (no staging project is wired up). The
`sql` CI job (`validate Supabase migrations (pglast)`) parses every file under
`supabase/migrations/`; these test scripts are syntax-checked the same way
before committing:

```bash
python3 -c "
import pglast, glob
for f in sorted(glob.glob('test/db/*.sql')):
    pglast.parse_sql(open(f).read()); print('OK', f)"
```
