# Frontend-as-Untrusted Audit — Madrassa-360

**Date:** 2026-10-03 · **Branch:** `redesign/ux-v2` · **Scope:** trust-boundary violations (places where the app or backend incorrectly trusts the client)
**Threat model:** attacker can decompile/patch the app, read/write all local storage (SharedPreferences, local DB files), proxy and modify every request, bypass all UI restrictions, and manipulate in-memory state. Read-only audit — no code modified.

## Verdict up front

The app's client-side architecture is unusually disciplined: permissions come from a server RPC, UI guards are explicitly documented as UI-only, the master-admin gate re-verifies server-side, and there are no WebViews, no HTML/Markdown rendering, and no deep links. **But there is one CRITICAL hole that collapses the entire authorization model:** the offline-sync RPC `sync_apply` — which carries *every* write the app makes — checks only tenant membership and ignores permission codes and data scopes entirely. Every other finding below is secondary to that.

---

## Trust-boundary map

| # | Client-held value | What it gates | Backend enforcement? |
|---|---|---|---|
| T1 | `AuthState.permissions` (from `get_my_permissions_detailed` RPC) | Nav items, buttons, screens | **Reads: YES** (RLS + `tenant_has_permission` + `scope_allows`). **Writes: NO** — `sync_apply` ignores them (→ C1) |
| T2 | `AuthState.isPlatformAdmin` | Routing to platform console | **YES** — `MasterAdminGuard` re-queries `platform_admins`/`super_admins` server-side, fails closed |
| T3 | `active_tenant_id` (SharedPreferences `active_tenant_id`) | Tenant scoping of all queries | **Reads: YES** (RLS). **Writes via sync_apply: membership-only** (→ C1). Value itself never validated against memberships (→ H1) |
| T4 | Offline permission cache (`authz.perms.v1.<uid>.<tenant>` in plaintext prefs) | Offline UI gating | **NO** — UI-only, freely editable on device (→ M2) |
| T5 | `tenant_memberships.role` role key | Offline static permission fallback | **NO** — UI-only |
| T6 | Supabase access + refresh tokens (plaintext SharedPreferences) | All API authentication | Server-validated JWTs; **theft = full impersonation** (→ H3) |
| T7 | Local Drift DB rows (per-tenant cached business data) | Offline reads | **NO server check possible offline**; never purged on logout (→ H2) |
| T8 | `platform_config.download_url` | "Update available" prompt target | Write-gated to platform admins; **no URL allowlist** (→ M1) |

---

## CRITICAL

### C1 — `sync_apply` RPC lets ANY tenant member write to ANY of 26 tables, ignoring permission codes, scopes, and status workflows

- **File/location:** `supabase/migrations/016_sync.sql` — `public.sync_apply(...)` (`SECURITY DEFINER`, bypasses RLS by design); called for every write by `lib/core/sync/sync_engine.dart` → `_callSyncApply`.
- **Problem:** The app is local-first: *all* writes (payments, refunds, discounts, scholarships, invoices, results/marks, students, staff, attendance…) are queued in the local Drift DB and applied through `sync_apply`. The RPC's authorization is exactly:
  ```sql
  IF NOT (public.is_platform_admin() OR public.is_tenant_member(v_tenant)) THEN
    RAISE EXCEPTION 'sync: not a member of tenant %', v_tenant;
  END IF;
  ```
  It never calls `tenant_has_permission()` and never calls `scope_allows()`. The migration header even documents the gap: *"Fine-grained permission codes (fees.collect etc.) remain enforced by RLS on direct table access, not by this RPC."* Direct PostgREST writes are properly gated (e.g. `payments_insert_tenant` requires `fees.collect` **and** `status='draft'`; results/attendance writes require `scope_allows()`), but the sync path — the path the app actually uses — is strictly weaker.
- **Why it matters:** The entire role/permission/scope system is UI theater for anyone who can issue an RPC call. Financial and academic record integrity depends on attackers not knowing the RPC name.
- **Exploit scenario (exact steps):**
  1. Attacker is a low-privilege teacher (permissions: only `attendance.mark`). They log into the unmodified app once to get a valid session, then point the app (or a script) at the Supabase project with their own JWT.
  2. They call `supabase.rpc('sync_apply', params: {'p_entity': 'payments', 'p_entity_id': '<new uuid>', 'p_base_revision': 1, 'p_payload': {'tenant_id': '<their tenant>', 'student_id': '<any>', 'amount': '100000', 'status': 'posted', 'method': 'cash'}, 'p_op': 'insert'})`. The RPC checks membership only → **returns `{"ok": true}`**. A posted payment now exists; no `fees.collect` permission was ever checked, and the `draft`-only insert rule was bypassed.
  3. Same technique: `p_entity='results', p_op='update'` to change any student's marks (scope check bypassed — a class-scoped teacher can edit any class); `p_entity='discounts', p_op='insert'` to grant a 100% discount; `p_entity='students', p_op='delete'` to soft-delete any student; `p_entity='refunds', p_op='insert'` to fabricate refunds. All 26 whitelisted tables are writable.
  4. Note the attacker does not need to patch the app at all — a proxy or a 20-line script suffices, because the trust violation is server-side.
- **Recommended fix:** Enforce authorization *inside* `sync_apply`: map `(p_entity, p_op)` → required permission code (e.g. `payments/insert → fees.collect`, `results/update → results.enter`, `students/delete → students.delete`) and call `tenant_has_permission(v_tenant, code)`; for scoped entities also call `scope_allows()`. Reject with a clear `reason` (not an exception, so the client marks the op failed instead of retrying forever). Until then, treat every financial/academic record as untrusted input from any tenant member. (This was a known deferred item — it is the single highest-risk item in the system.)

---

## HIGH

### H1 — `TenantContext.switchTenant()` accepts any tenant id without validating membership

- **File/location:** `lib/core/services/tenant_context.dart` — `TenantContext.switchTenant(String id)`; called by `AuthNotifier.selectTenant` ← `lib/presentation/screens/auth/tenant_picker_screen.dart`.
- **Problem:** `init()` validates the persisted id against the user's memberships, but `switchTenant()` does not — it sets state and persists unconditionally. Today the only caller passes a picker-selected id, but the provider method is the trust boundary and it is unguarded.
- **Why it matters:** `currentTenantIdProvider` then scopes every query (and the sync engine's `_tenantId`) to an attacker-chosen tenant. Online reads fail closed via RLS, but the **offline local DB is keyed by tenant_id and is never purged** (→ H2): on a shared device, switching to a previously-cached tenant id exposes that tenant's cached rows offline with no server check.
- **Exploit scenario:** Attacker (tenant B member) learns tenant A's UUID (visible in URLs/exports shared with them, or from a previous session on the shared tablet). On a patched app they invoke `switchTenant(<tenant-A-uuid>)` while offline → the app reads tenant A's cached students/fees from the local SQLite file. Queued writes would target tenant A but fail at `sync_apply` membership check — reads are the leak.
- **Recommended fix:** In `switchTenant`, verify `id` is in the current user's memberships (or caller is platform admin); otherwise throw and keep the previous tenant. Defense in depth, cheap.

### H2 — Local Drift database is never wiped on logout; previous user's PII persists on device

- **File/location:** `lib/data/local/database_provider.dart` (`closeDatabase()` documented "Call on logout" but only invoked from `lib/main.dart` restart path and `lib/core/backup/backup_service.dart`); `AuthNotifier._handleSignedOut` (`lib/providers/auth_provider.dart`) clears permission cache, delegation cache, and tenant context but **not** business tables.
- **Problem:** After logout, the SQLite file still contains all cached business data for the previous user's tenants: students (names, family details), staff (salaries, CNICs), invoices, payments, results, and the `sync_queue` with not-yet-synceived payloads. The next device user is in the same tenant, so queries "work" — but a deactivated staff member's full dataset remains on a device they no longer control, and any patched app (or `adb` file pull on a debuggable/rooted device) reads it directly.
- **Why it matters:** PII retention beyond the session; violates the principle that logout ends data access. Combined with H1, cached rows for *other* tenants are reachable.
- **Exploit scenario:** Principal uses a shared school tablet, logs out. A teacher logs in (same tenant). Teacher roots/patches the app or pulls `/data/data/.../app.db` → reads staff salary rows and student family PII that the UI never shows them and that their role's scopes would deny.
- **Recommended fix:** On logout, close and **delete** the database file (or delete all rows in all business + queue tables) after clearing prefs. If multi-account offline data is required, use per-user database files.

### H3 — Supabase session tokens persisted in plaintext SharedPreferences

- **File/location:** `supabase_flutter` 2.x `LocalStorage` (`~/.pub-cache/.../supabase_flutter-2.12.0/lib/src/local_storage.dart` → `shared_preferences`); the app does not override with secure storage. No `flutter_secure_storage` usage in `lib/`.
- **Problem:** Access and refresh JWTs sit unencrypted in the app's SharedPreferences XML. On a rooted device, via Android auto-backup extraction, or on a shared workstation (Windows), token theft = full session impersonation with the victim's permissions until the refresh token is revoked. "Remember me = false" only signs out on the *next* launch — the token persists until then.
- **Why it matters:** Standard stack weakness, but this app holds children's PII and financial records; token theft is the cheapest full-compromise path.
- **Exploit scenario:** Attacker with brief physical access to an unlocked staff phone (or a backup image) copies the prefs XML, extracts the refresh token, and maintains a persistent session as the victim from another device. Server-side, nothing distinguishes the thief.
- **Recommended fix:** Provide a custom `LocalStorage` backed by `flutter_secure_storage` (Keystore/Keychain); set `android:allowBackup="false"` (verify `android/app/src/main/AndroidManifest.xml`); ensure `signOut()` clears stored tokens immediately regardless of "remember me".

---

## MEDIUM

### M2 — Offline permission cache and static role fallback are client-writable and UI-trusted

- **File/location:** `lib/core/services/permission_service.dart` (`_cacheKey` → `authz.perms.v1.<uid>.<tenant>` in SharedPreferences; `AppPermissions.fallbackFor(roleKey)`); consumed by `lib/core/services/authorization_service.dart` and `hasPermissionProvider`.
- **Problem:** The persisted permission set is plaintext on device and editable. An attacker adds e.g. `students.delete`, `fees.collect` to the cached list → the offline UI renders admin screens and destructive buttons. The static fallback (`roleDefaults[roleKey]`) can also grant codes the server revoked, since `roleKey` comes from the last-known membership row.
- **Why it matters (with C1):** On its own this is UI spoofing — but because `sync_apply` doesn't check permissions (C1), the spoofed UI's actions actually succeed. The fallback *amplifies* C1: the app itself will happily queue a "collect fee" op for a user the server never authorized, and the server will apply it.
- **Exploit scenario:** Teacher edits `authz.perms.v1.<uid>.<tenant>` to include `fees.collect`, restarts the app offline → fee-collection UI appears → collects a fee → sync queue → `sync_apply` applies it (no permission check). Even without editing, the static fallback may show capabilities the admin revoked.
- **Recommended fix:** Fix C1 first (then cache tampering is UI-only). Additionally: integrity-protect the cache (HMAC with a device key from secure storage, or don't persist permission sets at all — reload from RPC on launch); make `fallbackFor` return the *minimum* safe set and log a warning whenever the fallback is used for a write-gated action.

### M5 — "Hidden button" pattern is used pervasively — safe only where the backend enforces

- **File/location:** `lib/presentation/shell/nav_destinations.dart` (`isVisible` permission checks), `hasPermissionProvider` usages across screens.
- **Problem:** Every privileged screen/button is hidden by client-side permission checks. The codebase is honest about this ("UI-ONLY: Supabase RLS remains the real enforcement"). The pattern is correct for reads (RLS + scopes enforce) and for the master console (`MasterAdminGuard` re-verifies server-side, fails closed — good). It is **incorrect for every write**, because writes flow through `sync_apply` (C1).
- **Recommended fix:** No UI change needed — fix C1. Add a lint/test rule: every `hasPermissionProvider` gating a *write* action must have a corresponding server-side check; the `sync_apply` permission map is that check.

---

## LOW / HARDENING

### M1 — Update download URL launched with scheme-presence check only

- **File/location:** `lib/core/update/update_service.dart` → `openDownload` (`Uri.tryParse` + `uri.hasScheme` → `launchUrl(externalApplication)`); URL sourced from `platform_config.download_url`.
- **Problem:** No allowlist — any scheme (`intent:`, `market:`, `javascript:`) passes. Currently safe because `platform_config` writes require platform admin (RLS `platform_config_admin_write`, migration 018). A compromised platform-admin account could point every user's "update" prompt at a malicious APK.
- **Recommended fix:** Allowlist to `https` only, and ideally to the known release host. Verify the downloaded file's hash against a server-provided SHA-256 before prompting install (the build pipeline already produces hashes).

### M3 — `tel:` URIs built from user-supplied phone numbers

- **File/location:** `lib/presentation/screens/admin/staff_list_screen.dart` → `_callStaff` (`Uri(scheme: 'tel', path: number)`).
- **Problem:** Phone numbers are user-entered (staff records). A crafted number with `,`/`;` DTMF separators or `**21*` call-forwarding codes could trigger unwanted dialer behavior on some devices. Writes to staff records are admin-gated, so exploitation requires an admin-level attacker or a compromised admin.
- **Recommended fix:** Sanitize to `[0-9+\- ]` before building the URI.

### M4 — `sync_apply` INSERT allows client-forged `created_at`

- **File/location:** `supabase/migrations/016_sync.sql` — insert column exclusion list is `('id','revision','server_version','updated_by','deleted_at')`; `created_at` is not excluded, so a client can backdate records. (UPDATE correctly excludes `created_at`.)
- **Recommended fix:** Add `created_at` to the insert exclusion list (server default `now()`).

---

## Verified GOOD (trust boundaries done right)

- **No WebView / HTML / Markdown rendering anywhere in `lib/`** — user-generated content (announcements, names, notes) renders via `Text`. No `javascriptMode`, no HTML injection surface, no file-preview script execution.
- **No deep-link handlers** (`app_links`/`uni_links` absent) — no crafted-link-to-privileged-action surface.
- **Master admin gate re-verifies server-side** (`lib/core/widgets/master_admin_guard.dart` → `fetchPlatformAdminRole()` queries `platform_admins`/`super_admins`; fails closed). Client `isPlatformAdmin` flag alone grants nothing.
- **Permissions originate from the server RPC** (`get_my_permissions_detailed`, SECURITY DEFINER, `auth.uid()`-scoped); unknown codes are dropped client-side (fail-closed); tenant_id in RPC rows is cross-checked against the requested tenant.
- **Scopes enforced server-side** (`scope_allows()`, migrations 020/022, fail-closed) for direct reads/writes — a class-scoped teacher cannot read/mark outside their classes via the API.
- **Deactivation enforced at the RPC layer**: `is_tenant_member()` requires `is_active` — deactivated users are rejected by `sync_apply` and (via RLS helpers) by direct access.
- **No self-membership assignment**: no client-side insert into `tenant_memberships` found; role changes go through the `manage-users` Edge Function with server-side rank/permission checks.
- **Push notifications don't use client-held FCM server keys**: `push_channel.dart` delegates fan-out to the `send-notification` Edge Function.
- **`.env.example` files contain placeholders only**; Supabase config loads from `.env` (`SUPABASE_URL`/`SUPABASE_ANON_KEY` — public by design). No service_role key found in client code paths reviewed.
- **Clipboard**: only non-sensitive support text is copied (`about_screen.dart`). No passwords/tokens/PII copied.
- **No URL route parameters**: navigation is imperative with constructor args from server-loaded lists — no IDOR-via-URL-manipulation surface.

---

## Recommended fix order

1. **C1** — per-entity permission + scope checks inside `sync_apply` (migration). This is the one fix that matters most; everything else is hardening.
2. **H2** — wipe local DB on logout (client change).
3. **H3** — secure token storage (custom `LocalStorage` → `flutter_secure_storage`; `allowBackup=false`).
4. **H1** — validate `switchTenant` id against memberships.
5. **M2** — integrity-protect or drop the persisted permission cache; minimize `fallbackFor`.
6. **M4** — exclude `created_at` from `sync_apply` inserts.
7. **M1** — https-only allowlist for the update download URL (+ hash verification).
8. **M3** — sanitize phone numbers for `tel:` URIs.
