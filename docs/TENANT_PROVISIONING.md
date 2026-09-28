# Tenant Provisioning — Madrasa-360 (mission §12)

**Goal:** "Create Madrasa" wizard → tenant + settings + modules + subscription + admin user + membership + license + audit event, **with no manual SQL**. Privileged steps run in a service-role Edge Function; the service key never touches the client.

## End-to-end flow (Phase 3 contract)

The Master Admin "Create Madrasa" wizard collects: institution name (+ Urdu name), contact details, city/district, chosen `license_plans` row, and the first admin's email/name. It then calls the `provision-tenant` Edge Function (service_role) exactly once. The function executes these steps **in one database transaction** so partial tenants are impossible:

1. **Create the tenant** — `INSERT INTO tenants (name, …)` (status starts `trial`; the 001 slug trigger + 003 default-module trigger fire automatically).
2. **Write tenant settings** — defaults into `tenant_settings` (002).
3. **Apply the module set** — enable the plan's `enabled_modules` in `tenant_modules` (codes must exist in the 003 `modules_catalog`).
4. **Create the subscription** — `INSERT INTO tenant_subscriptions (tenant_id, plan_id, status, expires_at)` (011).
5. **Issue the license** — `INSERT INTO licenses (tenant_id, plan_id, status, max_users, max_students, enabled_modules)` copying the limits snapshot from the chosen `license_plans` row (011).
6. **Create the admin auth user** — `auth.admin.createUser` (email invite; no password set by the platform).
7. **Create the profile row** — `INSERT INTO profiles (id, …)` for the new user.
8. **Grant membership** — `INSERT INTO tenant_memberships (tenant_id, user_id, role='tenant_owner', is_active=true)`.
9. **Seed any plan-specific defaults** (reserved for future use — must stay idempotent).
10. **Write the audit event** — `INSERT INTO audit_logs (tenant_id, user_id, action='tenant.provision', …)` (012) with the plan, limits, and wizard inputs in `metadata`.

## Compensation on failure

- Because steps 1–10 run in **one transaction**, any failure (e.g. duplicate slug, invalid module code, auth-admin error) rolls back the tenant, settings, subscription, license, membership, and audit rows together. The only non-transactional step is the auth user creation (Supabase Auth lives outside the DB transaction): on rollback after step 6 the function must call `auth.admin.deleteUser` to avoid an orphaned login with no tenant.
- The wizard surfaces the failure as a user-safe message (never raw SQL errors — §46) and keeps the wizard inputs so the operator can retry.
- License/subscription expiry and grace transitions (`active` → `grace_period` → `expired`) are a separate scheduled Edge Function (mission §§42–43), not part of provisioning.

## Audit trail

Every provisioning writes one `tenant.provision` audit row (step 10) plus, in practice, `license.issue` and `platform_admin` actor attribution (`user_id` = the provisioning platform admin). Platform-level provisioning events use `tenant_id = NULL` only when no tenant exists yet; here the tenant exists, so the event is tenant-scoped.

## Bootstrapping the FIRST platform owner (chicken-and-egg)

No UI can create the first platform owner: the Master Admin guard (MASTER_ADMIN.md) requires a row in `public.platform_admins`, and RLS on that table only lets platform admins (or service_role) write. The supported bootstrap, per `004_memberships.sql`, is a superuser/service-role INSERT (RLS is bypassed for both):

```sql
-- 1. Create the user in Supabase Auth (Dashboard → Authentication → Add user),
--    or accept an invite. Note the user's UUID.
-- 2. As service_role (SQL Editor with the service key, or psql as superuser):
INSERT INTO public.platform_admins (user_id, role)
VALUES ('<the-auth-user-uuid>', 'platform_owner')
ON CONFLICT (user_id) DO NOTHING;
```

Notes:

- `role` is `platform_owner` or `platform_support` (CHECK constraint).
- Migration 004 already seeds `platform_admins` from legacy `profiles.role` values (`superAdmin` → `platform_owner`, `franchiseManager` → `platform_support`) — use the manual INSERT only when no legacy super-admin exists.
- After this one row exists, all further platform admins are granted through the Master Admin UI (audited `platform_admin.grant`), never through ad-hoc SQL.
- Never commit the UUID or any key alongside these instructions; the SQL above contains placeholders only.
