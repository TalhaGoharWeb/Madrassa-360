# Master Admin — Madrasa-360

**What it is.** The Master Admin area is the private, platform-level console for operating the SaaS itself — not for running any madrasa. It exists to manage tenants, users, plans, licenses, subscriptions, modules, audit logs, system health, and support. Mission §§10–11, §72. Only users in `public.platform_admins` may enter; it is never reachable from the tenant (customer) app.

## Guard mechanism (database contract — the real enforcement)

The UI must never be the security boundary. Entry is guarded in layers:

1. **`public.platform_admins` table** (`004_memberships.sql`) — the single source of platform roles. Roles: `platform_owner` (full control) and `platform_support` (limited visibility: `tenants.view`, `users.view`, `audit.view`, `reports.view` per 005's curated mapping).
2. **`public.is_platform_admin()`** (`004_memberships.sql`) — SECURITY DEFINER helper that checks membership in `platform_admins`. Every platform-scoped RLS policy and the Master Admin routes must funnel through it.
3. **`platform_admins_self_read` policy** (`011_licensing.sql`) — lets any authenticated user read *their own* row in `platform_admins` (so the client can check "am I a platform admin, and which role" without a service-role call). Without it, only platform admins could read the table at all.
4. **RLS deny-by-default.** Client credentials can only ever read what the policies above allow. All privileged writes (tenant provisioning, plan edits, license changes, role grants) go through service-role Edge Functions — never the anon key.

Routing rule (Phase 3 contract): after sign-in, the client reads its `platform_admins` row (via `platform_admins_self_read`). If a row exists → Master Admin shell; otherwise → tenant picker / tenant app. A user with no `platform_admins` row and no `tenant_memberships` row gets the "no access" screen, never a fallback admin view.

## Screens (mission §72 structure)

Dashboard (KPIs + system health) → Madrasas (tenants: list, suspend/unsuspend, archive) → Users (platform + tenant user management) → Plans (license_plans CRUD) → Subscriptions → Licenses → Modules (module catalog enable/disable) → Audit Logs → Health → Support → Settings.

> Status: the shell under `lib/presentation/screens/super_admin/` is a static prototype (SAAS_GAP_ANALYSIS §10–11). The real screens are being rebuilt on this DB contract; every screen must re-check `is_platform_admin()` at the data layer, not just hide navigation items.

## Privileged-action confirmation rules

Destructive or irreversible platform actions **must** require an explicit, typed or double confirmation in the UI, and **must** write an `audit_logs` row via `public.log_audit()` (`012_audit_logs.sql`) with `tenant_id = NULL` (platform-level event). Minimum set:

| Action | Confirmation | Audit event |
|---|---|---|
| Suspend / unsuspend / archive a tenant | Typed tenant name + reason | `tenant.suspend` / `tenant.restore` |
| Delete / purge tenant data | Typed tenant code + second approver note (deferred to §50 MFA flow) | `tenant.purge` |
| Grant / revoke `platform_admins` row | Confirm dialog + reason; only `platform_owner` may grant `platform_owner` | `platform_admin.grant` / `platform_admin.revoke` |
| Change license plan or limits | Confirm dialog | `license.change` |
| Impersonate / act as tenant user (support) | Explicit banner + time-boxed session | `support.impersonate` (start/end) |

Audit entries for Master Admin actions are platform-level (`tenant_id = NULL`); per 012, only platform admins can SELECT them and only platform admins can write them through `log_audit()`.

## §50 security notes (Master Admin hardening)

- **No service-role in the client** (§60 items 1, 11): Master Admin features that need elevated writes (provisioning, user creation, plan edits) call Edge Functions that hold the service key server-side. A decompiled APK must never yield platform power.
- **Session handling:** Master Admin sessions follow the same hardened session contract as the app (AUTHENTICATION.md). MFA for platform accounts is a §50 follow-up — the `platform_admins` table carries no MFA state today; do not claim it exists.
- **Least privilege:** `platform_support` exists precisely so support staff never need `platform_owner`. Grant `platform_owner` only to people who can suspend tenants and grant other platform owners.
- **Escalation is closed at the DB layer:** `profiles.role` is client-locked (`007_tenant_rls.sql` `profiles_lock_role()` trigger); `user_roles` and the legacy `get_user_role()`/`get_my_role()` helpers are dropped in `013_auth_cleanup.sql`. Platform roles live only in `platform_admins`.
- **Audit everything:** every privileged action must be auditable after the fact — if an action has no audit event, it is not done.

## Bootstrapping (chicken-and-egg)

No UI can create the first platform owner (the guard requires an existing row). Bootstrap via SQL as a superuser/service_role — see TENANT_PROVISIONING.md.
