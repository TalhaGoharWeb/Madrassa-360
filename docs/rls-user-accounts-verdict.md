# RLS verdict — `user_accounts` / `app_roles` (user_management_provider.dart)

Date: 2026-09-29 · Branch: `redesign/ux-v2` · Scope: read-only investigation, no RLS changed.

## What the provider does

`lib/providers/user_management_provider.dart` issues these Supabase queries with **zero
`tenant_id` filter**:

| Line | Query |
|---|---|
| 83 | `_client.from('user_accounts').select().order('name')` — full table read |
| 95–97 | `_client.from('app_roles').select().order('is_system', ...)` — full table read |
| 184 | `_client.from('user_accounts').insert(row).select().single()` |
| 216 | `_client.from('user_accounts').update(...).eq('id', ...)` |
| 269 | `_client.from('user_accounts').delete().eq('id', ...)` |
| 289–340 | `app_roles` insert / update / delete by id |

## What the branch migrations say

- `grep` over `supabase/migrations/001_*.sql` … `023_super_admin.sql`:
  - **No `CREATE TABLE` for `user_accounts` or `app_roles` exists in any branch migration.**
  - **No RLS policy mentions either table.** (`007_tenant_rls.sql`, `020_role_ux_rls.sql` and all others are silent on them.)
- The provider itself anticipates the tables may not exist: `_loadAccounts` catches
  `PostgrestException` with the comment `// table may not exist yet — keep empty list`.
- The canonical RBAC tables that **do** exist with tenant-scoped RLS are different tables:
  `tenant_users`, `tenant_roles`, `tenant_role_permissions`, `user_permissions`
  (`019_role_ux_schema.sql` / `020_role_ux_rls.sql`). `user_management_provider.dart`
  does **not** use them — it uses the legacy `user_accounts` / `app_roles` pair.

## Verdict: ISOLATION NOT VERIFIABLE FROM THE BRANCH — TREAT AS UNSAFE

Server-side tenant isolation for `user_accounts` / `app_roles` **cannot be confirmed**
from branch artifacts because the tables (and any policies on them) are not defined
in the migration ledger. Three possibilities, in decreasing order of safety:

1. **Tables don't exist live** (likely, given the provider's "may not exist yet" guard):
   reads fail closed into empty lists; writes fail. No leak, but user/role management
   is non-functional against live Supabase.
2. **Tables exist live with proper tenant RLS** (created out-of-band): isolation holds
   *only* if every policy filters on the caller's tenant. Unverifiable from here.
3. **Tables exist live with missing/permissive RLS**: the unfiltered `.select()` calls
   above return **every tenant's user accounts and roles** to any authenticated caller —
   a cross-tenant data leak (names, emails, role assignments).

Because (3) cannot be ruled out from the branch, this must be treated as a
**production blocker for the user/role management screens** until resolved.

## Recommended remediation (not applied — needs owner decision)

1. Check the live Supabase schema for `public.user_accounts` / `public.app_roles`
   (table existence, columns, `relrowsecurity`, `pg_policies`).
2. If they exist live without tenant RLS: either add proper tenant-scoped policies via
   a new migration, or — preferred — migrate `user_management_provider.dart` to the
   canonical `tenant_users` / `tenant_roles` tables that already carry RLS (020).
3. If they don't exist live: decide whether `user_management_provider.dart` is dead
   code against the new RBAC model and remove or rewire it; do not ship screens that
   silently no-op on missing tables.
4. Add the chosen tables + policies to the migration ledger so branch and live stop
   drifting (cf. the 023 drift fixed 2026-09-29).
