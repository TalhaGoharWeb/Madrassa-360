# Madrassa-360 Platform (Master-Admin) Edge Functions

Three Deno Edge Functions for privileged platform operations. `provision-tenant`
and `manage-tenant` are platform-admin only; `manage-users` additionally serves
tenant owners/admins scoped to the tenants they administer.

| Function | Route | Purpose |
|---|---|---|
| `provision-tenant` | `POST /functions/v1/provision-tenant` | Create a complete tenant: `tenants` row → `tenant_settings` update → `tenant_modules` → `tenant_subscriptions` + `licenses` → auth user (`tenant_owner`) → `tenant_membership` → `audit_logs`. Compensating cleanup on failure. |
| `manage-tenant` | `POST /functions/v1/manage-tenant` | `suspend` / `reactivate` / `archive` a tenant (flips `tenants.status`, writes `audit_logs`). Archive never deletes data. |
| `manage-users` | `POST /functions/v1/manage-users` | Privileged user management: `create_user` / `update_user` / `set_active` / `delete_user` (Auth Admin API) + `assign_membership` / `remove_membership` / `list_users` + `set_platform_role`. Platform admins unrestricted (only a platform_owner may grant platform roles); tenant owners/admins scoped to their own tenants, role assignment capped at their own rank, last-owner protected. Every mutation writes `audit_logs`. |

Shared code (CORS, JWT → platform-admin guard, input validators) lives in
`_shared/guard.ts`. Nothing in `supabase/functions/` may hardcode keys — secrets
come only from `Deno.env`.

## Prerequisites

### 1. Platform admins table (caller prerequisite)

The caller of these functions must already have a row in `public.platform_admins`
(role `platform_owner` or `platform_support`). There is no self-service sign-up
for this — the platform owner bootstraps the **first** platform owner directly
in SQL (service role bypasses RLS, so run this as the DB owner / service role):

```sql
-- After the user has signed up in the app (so auth.users.id exists):
insert into public.platform_admins (user_id, role)
values ('<auth.users.id of the platform owner>', 'platform_owner');
```

Once one platform owner exists, they call `provision-tenant` / `manage-tenant`
with their own JWT; the functions verify the `platform_admins` row on every call.

### 2. Secrets — ROTATE THE COMMITTED KEY FIRST

> ⚠️ **P0:** the repository history contains a committed `SUPABASE_SERVICE_KEY`.
> Rotate it in the Supabase dashboard **before** deploying these functions
> (Dashboard → Project Settings → API → regenerate service_role key), then set:

```bash
supabase secrets set SUPABASE_URL="https://<project-ref>.supabase.co"
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="<rotated-service-role-key>"
```

Both are required at runtime. The functions throw a 500 `server_misconfigured`
if either is missing.

## Deploy

```bash
cd ~/workspace/madrassa-360            # repo root
supabase functions deploy provision-tenant
supabase functions deploy manage-tenant
supabase functions deploy manage-users
supabase functions deploy export-tenant
```

Or both at once:

```bash
supabase functions deploy provision-tenant manage-tenant manage-users export-tenant
```

## Type-check

```bash
cd supabase/functions
deno task check
```

(runs `deno check` on all three functions plus the shared module).

## API reference

### POST /functions/v1/provision-tenant

Headers: `Authorization: Bearer <platform-admin JWT>`, `Content-Type: application/json`.

Body:

```json
{
  "name": "Jamia Anwar-ul-Uloom",
  "name_urdu": "جامعہ انوار العلوم",
  "slug": "anwar-ul-uloom",
  "address": "Main Road", "city": "Karachi", "district": "Malir",
  "province": "Sindh", "country": "Pakistan",
  "phone": "0300-1234567", "email": "info@example.com",
  "website": "https://example.com",
  "principal_name": "Mufti Ahmed", "registration_number": "REG-123",
  "language": "ur", "timezone": "Asia/Karachi", "currency": "PKR",
  "plan_id": "<license_plans.id>",
  "modules": ["students", "teachers", "attendance", "academics", "exams",
              "results", "fees", "parents", "notifications", "reports"],
  "admin": { "name": "Owner Name", "email": "owner@example.com", "password": "secret123" }
}
```

- `name`, `plan_id` (active `license_plans` row), and `admin` are required.
- `slug` is optional — omitted slugs are generated from the name by the
  database trigger (uniqueness guaranteed with `-2`, `-3`, … suffixes).
  An explicitly provided taken slug returns **409 `slug_taken`**.
- `modules` is optional. Each name is validated against the live
  `modules_catalog`; unknown names return **400 `unknown_modules`**. When a plan
  lists `enabled_modules`, requested modules outside the plan are rejected
  (**400 `module_not_in_plan`**). Omitted → the plan's modules (or the 10
  trigger defaults when the plan lists none).
- The license row is created with `status = "trial"`, `issued_at = now`,
  `expires_at = now + 30 days`, plus the plan's `max_users`/`max_students` and
  the final enabled-module set.
- The admin user is created with `email_confirm: true` and a
  `tenant_owner` membership.

Success: **200**

```json
{ "tenant_id": "<uuid>", "tenant_code": "T-A1B2C3D4", "slug": "anwar-ul-uloom",
  "admin_user_id": "<uuid>", "admin_email": "owner@example.com" }
```

Failure after the tenant row exists triggers best-effort compensating cleanup
in reverse order (auth user → membership → license → subscription → modules →
settings → audit → tenant) and returns **500** with `{ error:
"provision_failed", step, message, cleanup_errors }`. The admin password is
never returned or logged.

### POST /functions/v1/manage-tenant

Headers: `Authorization: Bearer <platform-admin JWT>`, `Content-Type: application/json`.

Body:

```json
{ "tenant_id": "<uuid>", "action": "suspend", "reason": "Unpaid invoice #42" }
```

`action` ∈ `suspend` | `reactivate` | `archive` → `tenants.status` ∈
`suspended` | `active` | `archived`. Each change writes an `audit_logs` entry
`tenant.<action>` with `{ old_data: {status}, new_data: {status, reason} }`.
Archive only flips status — no data is deleted.

Success: **200** `{ "tenant_id": "<uuid>", "status": "suspended", "changed": true }`

Unknown tenant → **404**; non-platform-admin caller → **403**; missing/bad
token → **401**.

### POST /functions/v1/manage-users

Headers: `Authorization: Bearer <JWT>`, `Content-Type: application/json`.
Caller: a `platform_admins` row, or an active `tenant_owner`/`tenant_admin`
membership (tenant callers are scoped to the tenants they administer).

Body: `{ "action": "<action>", ...action fields }`

| action | fields | notes |
|---|---|---|
| `create_user` | `email`, `password` (≥6), `user_metadata?`, `app_metadata?`, `tenant_id?`+`role?` | Creates the Auth user (email confirmed), optionally adds a `tenant_membership`. Rolls back the Auth user if the membership insert fails. Returns `{ id, user_id, email }` — never the password. |
| `update_user` | `user_id`, `email?`, `password?`, `user_metadata?`, `app_metadata?` | |
| `set_active` | `user_id`, `active` | Deactivate = long ban; refuses to strand a tenant without an owner. |
| `delete_user` | `user_id` | Refuses the last platform admin and a tenant's last owner. Memberships cascade. |
| `assign_membership` | `user_id`, `tenant_id`, `role` | `role` must be a valid tenant role; tenant callers cannot assign above their own rank. |
| `remove_membership` | `user_id`, `tenant_id` | Refuses to remove a tenant's last active owner. |
| `list_users` | `tenant_id?`, `search?`, `limit?`, `offset?` | Scoped listing with each user's tenant memberships. |
| `set_platform_role` | `user_id`, `role` (`platform_owner`\|`platform_support`\|`null`) | Platform-owner only; refuses to remove the last platform admin. |

Tenant callers can never touch `platform_admins` rows, never assign platform
roles, and never manage users outside their tenants. Every mutating action
writes an `audit_logs` entry (`manage-users.<action>`); passwords are never
logged or returned. The Flutter `UserManagementNotifier` already invokes
`create_user`/`delete_user` with exactly these shapes.

## How the Flutter app invokes them

Both functions are plain HTTPS endpoints — call them with the signed-in
platform admin's access token:

```dart
final token = Supabase.instance.client.auth.currentSession!.accessToken;

final res = await http.post(
  Uri.parse('${supabaseUrl}/functions/v1/provision-tenant'),
  headers: {
    'Authorization': 'Bearer $token',
    'apikey': supabaseAnonKey,          // required by the gateway
    'Content-Type': 'application/json',
  },
  body: jsonEncode({
    'name': 'Jamia Anwar-ul-Uloom',
    'plan_id': planId,
    'admin': {'name': name, 'email': email, 'password': password},
  }),
);
final body = jsonDecode(res.body);
if (res.statusCode == 200) {
  final tenantId = body['tenant_id'];
  // …navigate to the new tenant's admin console…
} else {
  // show body['message'] / body['details']
}
```

The same pattern works for `manage-tenant`:

```dart
body: jsonEncode({'tenant_id': tenantId, 'action': 'suspend', 'reason': reason}),
```

Keep these calls behind a platform-admin-only screen in the app (the functions
also enforce this server-side, but never expose the UI to tenant users).

## Notes / assumptions

- Licensing tables (`license_plans`, `licenses`, `tenant_subscriptions`) and
  `audit_logs` follow the Phase-3 contract in the coordinator brief (Worker 4's
  migration 011): `licenses.status` CHECK ∈
  `trial/active/grace_period/expired/suspended/cancelled`;
  `audit_logs(tenant_id, user_id, action, entity, entity_id, old_data,
  new_data, metadata, created_at)`. If 011 changes column names, update the
  `insert` payloads here to match.
- These functions use the **service role** and deliberately bypass RLS;
  authorization is the `platform_admins` lookup in code, checked on every call.
- Email/password sign-in must be enabled for `auth.admin.createUser` to work.
