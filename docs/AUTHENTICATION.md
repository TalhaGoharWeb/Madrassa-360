# Authentication — Madrasa-360 (Phase 3)

**Provider:** Supabase Auth. **Principle:** the database is the authority; the client only holds a session and asks questions RLS answers.

## Sign-in

- Email + password sign-in via `supabase.auth.signInWithPassword`. (OAuth providers are not configured in Phase 3.)
- On success the client receives a session (access + refresh tokens). The client then resolves identity in order:
  1. `public.platform_admins` row for the user id (via the `platform_admins_self_read` policy, `011_licensing.sql`) → if present, route to the Master Admin area (MASTER_ADMIN.md).
  2. `public.tenant_memberships` rows (via the "users read own memberships" policy) → tenant picker if more than one active membership, direct entry if exactly one.
  3. Neither → "no access" screen. There is no fallback admin role.
- Role/permission data inside the tenant comes from `tenant_memberships.role` + `get_my_permissions()` RPC (`013_auth_cleanup.sql` rewrite: tenant-aware, no `user_roles` branch). Legacy `profiles.role` is still read by `auth_repository.dart` for display-role fallback, but it is **client-locked** — 007's `profiles_lock_role()` trigger rejects client writes, and `user_roles`/`get_user_role()`/`get_my_role()` are dropped in 013.

## No public sign-up

Public self-registration is **disabled** (Supabase Auth → disable "Enable sign ups"). Users enter the system only through:

- the tenant-provisioning flow (§12 Edge Function creates the tenant's first admin user — TENANT_PROVISIONING.md), or
- an admin-created user (tenant admin / platform admin via a service-role Edge Function — never the anon key).

`handle_new_user()` (`007_tenant_rls.sql`) still exists as a safety net and defaults new profiles to `role = 'student'` with no memberships — a leaked sign-up cannot grant access.

## Session persistence and expiry

- Phase 3 contract: sessions persist via the Supabase client's storage adapter; expired sessions are refreshed with the refresh token; a failed refresh (revoked/expired) must route to the sign-in screen — never to a cached "logged in" state.
- Logout must call `supabase.auth.signOut()` and clear all local caches (the Phase-2 audit found a fake logout that only cleared local state — `profile_screen.dart:532-539`; §60 item 9 stays red until the real flow ships and is tested).
- Plaintext demo credentials (`auth_service.dart:61-81`: `admin123/teacher123/parent123`) and plaintext SharedPreferences session storage are audit findings, not features — they must be removed before any production claim (§60 items 2, 7, 9).

## Password reset

- Standard Supabase reset flow: `resetPasswordForEmail` → emailed link → in-app reset screen → `updateUser(password:)`.
- The reset link must deep-link into the app; on success the user is signed in fresh (new session), not left on a stale token.
- §60 item 8 is red until the flow is verified end-to-end on a staging project.

## Tenant picker

- A user may hold several active `tenant_memberships` (e.g. an accountant serving two madrasas). After sign-in with >1 active membership, the tenant picker lists the user's tenants (name, logo, role); the choice sets the active `tenant_id` for all subsequent queries (the `TenantContext` service, Phase 2).
- Switching tenants re-resolves permissions via `get_my_permissions()` and must clear tenant-scoped caches.

## Platform-admin routing

- Determined solely by the `platform_admins` row (never by `profiles.role`, `app_metadata`, or a client flag). Platform admins bypass tenant picker and land in the Master Admin shell; they may still open a tenant in read/manage mode, which is audited as a support action.

## What Phase 3 implements (Worker 2's auth work builds on these contracts)

- Sign-in → session → identity resolution order above; real `signOut()`; session-restore redirect; secure token storage replacing plaintext SharedPreferences; removal of demo credentials and the mock `auth_service.dart`.
- DB-side, Phase 3 closed: platform-admin guard (`platform_admins` + self-read policy), privilege-escalation closure (profiles lock trigger, 013's decommission of `user_roles`/`get_user_role()`/`get_my_role()`), and the append-only audit trail (`audit_logs` + `log_audit()`).

## What is still open

- §50 MFA for platform accounts (table carries no MFA state today).
- End-to-end verification of reset, expiry, and logout on staging (§60 items 7–9).
