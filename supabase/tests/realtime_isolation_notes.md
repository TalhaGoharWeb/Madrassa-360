# Realtime isolation notes — cross_tenant_isolation.sql companion

**Status: static analysis only — no live execution.** Verified 2026-09-25
against the migration sources (`supabase/migrations/001`–`018`) and repo docs.
The isolation suite cannot assert realtime behavior without a staging database;
this note documents what the migrations do and do not guarantee.

## Finding: no table is realtime-enabled by migrations 001–018

- `grep -ri "supabase_realtime\|realtime"` over `supabase/` (migrations +
  legacy SQL) on 2026-09-25: **zero hits** in migration sources. No
  `ALTER PUBLICATION supabase_realtime ADD TABLE`, no publication membership,
  no `replica identity` statements anywhere in the version-controlled schema.
- The client has no realtime usage either: `docs/SECURITY_AUDIT.md:199`
  records "No realtime in the client (no `.channel(` / `.stream(` / `realtime`
  in `lib/`) and no publication config in migrations"; sync is REST polling.
- Conclusion: **as migrations define it, there is no realtime feed to
  isolate.** A table only appears on realtime if someone adds it to the
  `supabase_realtime` publication manually (dashboard / SQL) — that is
  out-of-band state this audit cannot see.

## What WOULD gate the feed if realtime were enabled later

Supabase realtime authorizes each event against the table's SELECT RLS
policies using the subscriber's JWT claims (`auth.uid()`, `auth.role()`).
`docs/MULTI_TENANCY.md:50` states the design intent: "Realtime inherits table
RLS, so subscriptions are tenant-scoped automatically once 007 is applied."

Per-table consequences, if the table were added to the publication:

| Table(s) | Gating SELECT policy | Effect on a Tenant-B subscriber |
|---|---|---|
| 13 business tables (007), finance ledger (014), licenses/subscriptions (011), audit_logs (012), student_guardians / teacher_class_assignments (015) | `…_select_tenant`: requires `is_tenant_member(row.tenant_id)` (or platform admin) | Cannot receive Tenant-A row events — the policy filter excludes them. |
| notifications (017) | `notifications_select_tenant`: member AND (own or broadcast) | Receives only own + own-tenant broadcast events. |
| notification_preferences / notification_device_tokens (017) | `…_select_own`: own `user_id` | Receives only own rows' events. |
| devices / device_sessions (018) | own / tenant-admin / platform | Receives only own-device or own-tenant events. |
| platform_config (018) | `platform_config_public_read` (USING true) | ⚠️ **All authenticated subscribers receive all config events** — intended (public config). |
| license_plans, modules_catalog, account_types (011/003/014) | authenticated-read | ⚠️ **All authenticated subscribers receive all catalog events** — intended (low-sensitivity registries). |
| madrasas (legacy, 007) | `madrasas_member_select`: ANY active membership | ⚠️ **Any tenant member receives ALL madrasas-row events** — the policy is not row-correlated (see inventory flag #1). |
| storage.objects (008) | `{bucket}_select_tenant`: member of prefix tenant | Receives only own-tenant objects' events. |

## What static analysis CANNOT assert

1. Whether any table has been manually added to `supabase_realtime` on a
   given project (dashboard / API state, invisible here).
2. Actual websocket delivery behavior per subscriber — RLS is evaluated
   per-event at subscription/delivery time against the subscriber's auth
   context; only a live staging test with two authenticated subscribers can
   prove the feed boundary.
3. `REPLICA IDENTITY` settings (needed for UPDATE/DELETE payloads) — not set
   by any migration.

## Recommendation

Before enabling realtime on any table in production: add the table to the
publication on **staging**, then re-run `cross_tenant_isolation.sql` plus a
subscription-level test (Tenant-A and Tenant-B subscribers, assert each
receives only own-tenant events). Do not enable realtime on `madrasas`
without first resolving inventory flag #1.
