# Flutter App Security Audit — Madrassa-360

**Scope:** `~/workspace/madrassa-redesign-fix`, branch `redesign/ux-v2` (Flutter 3.47.4, Supabase backend).
**Method:** read-only static analysis of `lib/`, `supabase/migrations/`, `supabase/functions/`, `android/` manifest.
**Threat model:** the attacker can modify/rebuild the app OR call Supabase directly with the anon key. Frontend restrictions are never treated as security boundaries.

---

## 1. How auth works here (verified)

- Supabase Auth (GoTrue) email/password. Session persisted by the SDK (default storage = plain `SharedPreferences`).
- `SupabaseService.init()` (`lib/core/services/supabase_service.dart`) reads `SUPABASE_URL` / `SUPABASE_ANON_KEY` from `assets/.env` (gitignored — verified). No `service_role` key anywhere in `lib/`. No hardcoded passwords.
- Post-login wiring (`lib/providers/auth_provider.dart`): session → tenant memberships (`tenant_memberships`) → active tenant → permissions via `get_my_permissions_detailed` RPC → `AuthorizationService` in-memory set.
- `AuthorizationService` (`lib/core/services/authorization_service.dart`) is **explicitly documented as UI-only**; RLS is the real enforcement. Fail-closed when nothing loaded.
- Platform-admin check: client queries `platform_admins` / `super_admins` via RLS; `MasterAdminGuard` (`lib/core/widgets/master_admin_guard.dart`) re-verifies server-side and fails closed.
- `profiles.role` is locked server-side (`profiles_lock_role()` trigger, `007_tenant_rls.sql`); the legacy `AppUser.role`/`isStaff`/`isPlatformRole` has **zero** decision usages outside auth files — no client role trust there.
- Writes go through the `sync_apply` SECURITY DEFINER RPC (entity whitelist, tenant membership check, server-managed columns stripped). Reads are direct `.from()` queries scoped with `.eq('tenant_id', …)` + RLS.

## 2. Role / permission model as the client understands it

**Roles** (`tenant_memberships.role` keys, `lib/core/constants/app_permissions.dart` → `roleDefaults`):
`tenant_owner`, `tenant_admin`, `mohtamim`, `naib_mohtamim` (= all tenant codes), `principal`, `accountant`, `teacher`/`ustad`/`ustad_hifz`, `librarian`, `hostel_manager`, `staff`, `parent`, `student`, `nazim_aala`, `nazim_taleem`, `nazim_intizamia`, `nazim_maliyat`, `daftar_dar`, `nazim_hifz`, `nazim_darul_iqama`, `warden`, `mumtahin`, `store_incharge`, `hr_incharge`, `platform_owner` (= `allCodes`, incl. `tenants.*` and `system_full_access`), `platform_support`.

**Permission codes:** 66 canonical dotted codes (`students.view` … `tenants.suspend`, `users.create/update/deactivate`, `roles.assign`, `settings.update`, `reports.export`, `finance.approve`, …) + ~56 legacy underscore codes kept for the deprecated `profiles.role` branch.

**Client enforcement points (all UI-only by design):**
| Enforcement point | File | What it gates |
|---|---|---|
| `hasPermissionProvider(code)` | `lib/providers/auth_provider.dart` | Buttons, screens, nav destinations (e.g. logo screen requires `settings.update`) |
| `AuthorizationService.has/hasAll/hasAny` | `lib/core/services/authorization_service.dart` | Same, imperative |
| `ScopeService` | `lib/core/services/scope_service.dart` | List filtering by data scope (`all/department/classes/students`) |
| `MasterAdminGuard` | `lib/core/widgets/master_admin_guard.dart` | `/master` console; re-verifies via RLS, fails closed |
| `AuthGate` / `postAuthDestination` | `lib/presentation/screens/auth/` | Cold-start routing by `isPlatformAdmin` + route |
| Offline fallback `fallbackFor(roleKey)` | `lib/core/constants/app_permissions.dart` | Grants UI capabilities when RPC unreachable, keyed by server-issued membership role |

**Places where the client enforces something the backend demonstrably does NOT (verified gaps):**
1. **Granular write permissions** — `sync_apply` checks tenant *membership* only, not permission codes (see C1). Every `hasPermissionProvider('fees.collect')` gate on a write button is cosmetic against a modified app.
2. **Offline capability** — the persisted permission cache + static fallback + the full local Drift DB let a user keep *acting* offline after revocation (see H1, M1).
3. **`reports.export`** — PDF/report generation is client-side from local data; nothing server-side meters or gates export volume (API-abuse angle for the backend track).

---

## 3. Findings

### CRITICAL

#### C1 — `sync_apply` enforces membership, not permissions: any tenant member can write any entity
- **Location:** `supabase/migrations/016_sync.sql` (lines ~89–91, 308–368); client write path `lib/core/sync/sync_engine.dart:857`
- **Problem:** The SECURITY DEFINER `sync_apply` RPC whitelists the entity table and verifies `is_platform_admin() OR is_tenant_member(tenant)` — but never checks the caller's granular permission codes (`students.create`, `fees.collect`, `finance.delete`, …). The migration itself documents this: *"Fine-grained permission codes (fees.collect etc.)"* enforcement is deferred.
- **Why it matters:** The entire in-app permission model (66 codes, role templates, per-user overrides, delegations, data scopes) is enforced **only in the UI**. A tenant member with a read-only role (e.g. `parent` with only `notifications.view`) can call `supabase.rpc('sync_apply', …)` directly with `p_entity='finance_transactions'` and insert/update/delete rows in their tenant.
- **Attack scenario:** A teacher's credentials are phished. The attacker doesn't even need the app — with the anon key + the victim's JWT they push `sync_apply` calls: backdate fee receipts, alter exam results, delete attendance. RLS is bypassed by design (SECURITY DEFINER); no permission check exists anywhere in the path.
- **Fix:** Add per-entity/per-op permission checks inside `sync_apply` (map `p_entity`+`p_op` → required code, verify via the same grant-resolution logic as `get_my_permissions_detailed`). Until then, treat every client write-gate as cosmetic in risk assessments.

### HIGH

#### H1 — Full tenant database persists on disk after logout; readable by the next device user
- **Location:** `lib/providers/auth_provider.dart` (`_handleSignedOut`, lines 456–478); `lib/data/local/database_provider.dart` (`closeDatabase` only closes, never deletes)
- **Problem:** Sign-out clears in-memory auth state, the persisted permission cache, and the active-tenant id — but **never deletes the Drift SQLite file** (`madrassa360.db`), which contains the tenant's entire synced dataset (students, fees, finance, staff PII, attendance). `closeDatabase()` is only called from backup-restore and app restart, not from logout.
- **Why it matters:** On shared/family devices (common in the target environment) the next person to use the device — or anyone who can read app-private files (root, backup extraction, Windows `%APPDATA%`) — gets the previous tenant's full offline dataset with no authentication at all.
- **Attack/failure scenario:** A clerk signs out on a shared school computer. The next user copies `%APPDATA%/…/madrassa360.db` and opens it in any SQLite browser: complete student records, fee/finance history, staff data.
- **Fix:** On sign-out, close and **delete** the tenant database file (and the logo/report caches under `Madrassa360/`), or encrypt it with a key kept in `flutter_secure_storage` that is wiped on logout (SQLCipher). At minimum, delete on explicit logout; keep on token-expiry (offline continuity) only with a documented risk acceptance.

#### H2 — Password-reset flow cannot be completed: no `redirectTo`, no recovery handler, no new-password screen
- **Location:** `lib/data/repositories/auth_repository.dart:215` (`resetPasswordForEmail` without `redirectTo`); no `app_links` usage; no `PASSWORD_RECOVERY` handling; no screen calls `auth.updateUser`
- **Problem:** The forgot-password screen sends the reset email, but the recovery link points at the Supabase site URL (no `redirectTo` to `io.supabase.madrasa360://login-callback`), and the app has no code path to receive a recovery session and no UI to set a new password.
- **Why it matters:** Users who forget passwords have **no self-service recovery**. This is both broken functionality and a security driver: it pushes admins toward insecure workarounds (sharing passwords, admin-set weak passwords via `manage-users`).
- **Failure scenario:** A mohtamim forgets their password before fee-collection day. The email link opens a browser page (or dead-ends); they cannot regain access without platform-admin intervention.
- **Fix:** Pass `redirectTo` to the app's callback scheme in `resetPasswordForEmail`, handle the recovery deep link (verify `PASSWORD_RECOVERY` event → route to a new SetNewPasswordScreen → `supabase.auth.updateUser(password: …)`), with the same 6-char-minimum policy and error mapping as login.

#### H3 — Auth tokens stored in plaintext `SharedPreferences` (SDK default; no secure-storage adapter)
- **Location:** `lib/core/services/supabase_service.dart` (`Supabase.initialize` with no `authOptions`/`localStorage` override)
- **Problem:** `supabase_flutter` persists the session (access token + long-lived **refresh token**) in unencrypted `SharedPreferences`. A stolen refresh token = full account takeover until it expires or is revoked, with no binding to the device.
- **Why it matters:** On rooted devices, via Android auto-backup extraction, or on Windows (`%APPDATA%` is user-readable), tokens are recoverable with trivial tooling. Combined with H1, a lost/stolen device yields both the data and the credentials to keep syncing.
- **Attack scenario:** Attacker extracts `shared_prefs` from a backup of a principal's phone, replays the refresh token from their own machine, and now has the principal's session — including platform-console access if the victim is a platform admin.
- **Fix:** Provide a `flutter_secure_storage`-backed `LocalStorage` to `Supabase.initialize(authOptions: …)`; disable Android auto-backup for the prefs file (`android:allowBackup="false"` or backup rules); keep the "remember me = false → sign out persisted session" behavior (already correct).

#### H4 — Raw exception details surfaced to users in SnackBars (information disclosure)
- **Location:** `lib/presentation/screens/admin/user_management_screen.dart:322,720` (`'خرابی: $err'`); `lib/presentation/screens/master_admin/madrasa_detail_screen.dart:186,211,253` (`'Save failed: $e'` etc.); `lib/presentation/screens/master_admin/platform_users_screen.dart:154,221`; `lib/presentation/screens/sync/conflict_review_screen.dart:358`; `lib/core/services/network_service_improved.dart:116`; `lib/providers/user_management_provider.dart:80` (`'ڈیٹا لوڈ نہیں ہوا: $e'`), `:269` (`e.message` from PostgrestException)
- **Problem:** `PostgrestException.toString()`/`message` embeds table names, constraint names, column names, and sometimes query fragments. These reach end users verbatim in admin screens.
- **Why it matters:** It hands an attacker the exact schema vocabulary (table/column/constraint names) needed to craft targeted `sync_apply`/PostgREST attacks, and it trains users to ignore error text.
- **Attack scenario:** Attacker with a low-privilege account opens user management, triggers an RLS denial, and reads the constraint/table names from the snackbar to refine direct API probing.
- **Fix:** Route every user-facing error through the existing `AppException.userMessageUr` contract (`lib/core/errors/app_exceptions.dart` already mandates "UI code must ONLY ever show these"); log the technical detail via `AppLogger` only. Add a lint/test asserting no `$e`/`$err` interpolation in `showM360SnackBar`/`showUxSnack` call sites.

#### H5 — Client sends `app_metadata.role` to `manage-users`; server must not trust it
- **Location:** `lib/providers/user_management_provider.dart:153–163` (`'app_metadata': {'role': account.roleName}`)
- **Problem:** The client proposes the new user's role inside `app_metadata` in the Edge Function request body. If `manage-users` copies that value into the Auth user's `app_metadata` (or into `tenant_memberships.role`) without independently authorizing the *caller* to grant that role, any tenant admin (or any caller of the function) can mint `platform_owner`/`tenant_owner` accounts.
- **Why it matters:** `app_metadata` is the exact field `AppUser.fromSupabase` prefers for role display, and role-grant is the highest-value privilege-escalation primitive in the system.
- **Attack scenario:** A compromised `users.create`-holding account calls `manage-users` directly with `app_metadata.role = 'platform_owner'` and takes over the platform console.
- **Fix (client + server):** Client should send only the *requested role key* as data (not as `app_metadata`); the Edge Function must (a) authenticate the caller, (b) verify the caller holds `users.create`/`roles.assign` for the tenant, (c) validate the requested role against an allow-list the caller may grant (never `platform_*`), and only then set metadata. **Backend track must verify the current function behavior.**

### MEDIUM

#### M1 — Offline permission cache + static fallback let revoked users keep acting offline
- **Location:** `lib/core/services/permission_service.dart:86–143` (RPC → persisted cache → `fallbackFor`); cache in `StorageService` (plain SharedPreferences)
- **Problem:** When the RPC is unreachable the app uses the last-known-good permission set, else static per-role defaults — including `platform_owner → allCodes`. A user whose permissions were revoked (or whose membership was deactivated) keeps the old capabilities offline indefinitely, against the full local DB (see H1).
- **Why it matters:** Revocation is a security control; offline mode silently suspends it with no expiry and no user-visible indication.
- **Fix:** Timestamp the persisted cache; treat cache older than N hours (e.g. 24h) as expired → fail closed to a read-only/degraded mode with an honest "offline — permissions may be stale" banner. Never fall back to `allCodes` for `platform_owner` from cache alone without a fresh RPC.

#### M2 — `isPlatformAdmin` is never re-checked after sign-in (stale until next full login)
- **Location:** `lib/providers/auth_provider.dart` (`_checkPlatformAdmin` only in `_handleSignedIn`; `_refreshSessionUser` → `refreshPermissions` only)
- **Problem:** A demoted platform admin keeps `AuthState.isPlatformAdmin == true` across token refreshes; `postAuthDestination` routes them to the platform console shell.
- **Why it matters:** Privilege revocation doesn't take effect until the user fully re-authenticates.
- **Mitigating factor:** `MasterAdminGuard` re-verifies against the server on navigation and fails closed, so data access is still blocked — the exposure is the console chrome, not the data.
- **Fix:** Re-run `_checkPlatformAdmin` in `_refreshSessionUser` (cheap: two indexed `maybeSingle` reads) or on every `MasterAdminShell` entry.

#### M3 — Logo upload: no content validation; arbitrary bytes into a public bucket at a predictable URL
- **Location:** `lib/services/tenant_logo_service.dart:62–100`
- **Problem:** Only emptiness and a 5MB client-side size check. No magic-byte/MIME validation that the bytes are actually a PNG, despite forcing `contentType: 'image/png'`. Bucket `tenant-logos` is public; path is predictable (`<tenant_id>/logo.png`).
- **Why it matters:** A tenant admin (or anyone who can pass the storage RLS policy) can host arbitrary content on the Supabase CDN domain — phishing kits, HTML/JS polyglots — abusing the platform's domain reputation. The logo URL is also rendered into PDF reports and the offline cache.
- **Fix:** Validate PNG magic bytes client-side (defense in depth) **and** add a server-side check (storage webhook or Edge Function) rejecting non-image uploads; consider randomizing the object name per upload.

#### M4 — Student/staff photo uploads: attacker-influenced extension, no size/type limits
- **Location:** `lib/providers/student_provider.dart:118–125` (`photo.name.split('.').last`), `lib/providers/staff_provider.dart:90`; upload at `lib/core/sync/sync_engine.dart:906` (`uploadBinary` with `upsert: true`, no `contentType`)
- **Problem:** The file extension is taken from the user-controlled picked-file name (`photo.svg` → `.svg`); no size cap, no MIME sniffing, no `contentType` set (server sniffs or defaults).
- **Why it matters:** Limited blast radius (buckets are private, RLS-gated reads), but SVG/HTML uploads could become stored-XSS if any future surface renders them as images inline, and unbounded size enables storage-quota abuse.
- **Fix:** Whitelist extensions (`jpg/jpeg/png/webp`), verify magic bytes, cap size (e.g. 5MB like logos), set explicit `contentType`, normalize the stored extension from the sniffed type rather than the filename.

#### M5 — `tenant-backups` bucket is not provisioned by migrations ("platform ops") — latent cross-tenant leak
- **Location:** `lib/core/backup/backup_service.dart:197–203` (`cloudBucket = 'tenant-backups'`); `docs/BACKUP_RESTORE.md:112`
- **Problem:** The app uploads **complete tenant SQLite files** to `tenant-backups/{tenant_id}/backups/…`, but no migration creates this bucket or its storage policies. If ops ever creates it as a plain bucket without tenant-bound `storage.objects` policies, any authenticated user can list/download every tenant's full database.
- **Fix:** Add a migration creating the bucket (private) + tenant-bound policies (`(storage.foldername(name))[1] = tenant_id` + membership check), same pattern as `008_tenant_storage.sql` / `024_tenant_logos.sql`. Until then, disable `enqueueCloudCopy` or document the bucket as not-yet-safe.

#### M6 — No proactive disabled-account handling: deactivated users fail confusingly instead of being signed out
- **Location:** `lib/providers/auth_provider.dart` (`restoreSession`, `_refreshSessionUser` — no `is_active` check)
- **Problem:** Nothing checks `user_accounts.is_active` or membership `is_active` on cold start / resume / token refresh. A deactivated user keeps a valid JWT; RLS denies row access (policies check `tm.is_active` — good), but the app shows generic failures rather than signing out with an "account deactivated" state. The cached session also keeps working against any endpoint that doesn't check membership.
- **Fix:** On `restoreSession` and `_refreshSessionUser`, query the user's active membership/`user_accounts.is_active`; if deactivated, `signOut()` + show a dedicated deactivated screen. (Also gives a clean hook for future server-side session revocation.)

### LOW

#### L1 — Login error map distinguishes "account not found" (latent enumeration)
- **Location:** `lib/data/repositories/auth_repository.dart` (`_mapAuthError`: `'یہ اکاؤنٹ موجود نہیں'` vs `'غلط ای میل یا پاس ورڈ'`)
- **Problem:** Two distinct user-facing strings exist for unknown-account vs wrong-password. Supabase GoTrue currently returns generic "Invalid login credentials" for both, so the branch is dormant — but any upstream message change silently enables account enumeration.
- **Fix:** Collapse to a single "incorrect email or password" string; keep the branch only for logging.

#### L2 — No client-side brute-force mitigation
- **Location:** `lib/presentation/screens/auth/login_screen.dart` (no attempt counting, backoff, or CAPTCHA)
- **Problem:** Unlimited rapid login attempts from the app; protection relies entirely on Supabase's server-side rate limits.
- **Fix:** Exponential backoff after N failed attempts + optional CAPTCHA on the 5th failure; document reliance on GoTrue rate limiting.

#### L3 — No concurrent-session control or session-revocation UI
- **Problem:** Supabase default allows unlimited concurrent sessions; users cannot see/revoke other sessions. `logout()` revokes only the current session server-side.
- **Fix:** Accept as documented limitation, or add a "sign out all devices" action via `manage-users` (admin `updateUser` ban + token invalidation).

#### L4 — `UserManagementNotifier` seeds all system roles when the `app_roles` query fails
- **Location:** `lib/providers/user_management_provider.dart:51–56, 99–118`
- **Problem:** On `PostgrestException` (including RLS denial) the UI falls back to `AppRole.allSystemRoles` and shows an empty user list as if no users exist — misleading, and it masks authorization failures as "not yet set up".
- **Fix:** Distinguish "table missing" from "permission denied": surface RLS denials honestly instead of seeding defaults.

#### L5 — Dead storage keys `user_token` / `user_data`
- **Location:** `lib/core/services/storage_service.dart:200–201` (defined, never used)
- **Problem:** Unused keys named like credential storage invite future misuse and confuse auditors.
- **Fix:** Delete them.

#### L6 — Stale "implicit flow" comment in `SupabaseService`
- **Location:** `lib/core/services/supabase_service.dart:33–35`
- **Problem:** Comment claims implicit flow is used; no `authFlowType` is actually set, so PKCE (the default) is used. A future maintainer acting on the comment could enable the weaker implicit flow.
- **Fix:** Correct the comment to state PKCE is intentionally the default.

---

## 4. What the app gets right (verified, keep)

- No `service_role` key, no hardcoded secrets/passwords in `lib/`; `assets/.env` gitignored.
- `AuthorizationService`/`ScopeService` explicitly UI-only with fail-closed semantics; RLS + `scope_allows()` do real enforcement.
- `sync_apply`: entity whitelist via CASE (no dynamic table names), server-managed columns (`id`, `tenant_id`, `revision`, …) stripped on write, `tenant_id` re-derived from the existing row on update/delete, `updated_by` excluded from client-writable columns (027).
- `profiles.role` not client-writable (trigger); `AppUser.role` has no authorization usages.
- `MasterAdminGuard` fails closed and re-verifies server-side.
- Password never serialized into `user_accounts` (`toJson` excludes it); only sent over TLS to `manage-users`.
- Role assignment / permission overrides go through server RPCs (`assign_tenant_role`, `set_user_permission`) and Edge Functions, not direct table writes.
- `AppException.userMessageUr` contract + `AppLogger` redaction exist (H4 is about call sites not using them).
- No WebView / HTML widget rendering untrusted content → no XSS surface in-app.
- Tenant switching validates against the membership list; `selectTenant` can't escape to an unlisted tenant.
- Backup/restore enforces tenant match, typed confirmation, pre-restore copy, and path confinement.

## 5. Recommended fix priority (client-side)

1. **H1** — wipe tenant DB + caches on sign-out (or encrypt at rest).
2. **C1** — server: permission checks inside `sync_apply` (blocks the whole write path otherwise).
3. **H2** — complete the password-reset flow (redirectTo + recovery handler + new-password screen).
4. **H3** — secure-storage-backed Supabase local storage.
5. **H4** — purge raw `$e` interpolation from user-facing messages.
6. **H5** — verify `manage-users` doesn't trust client `app_metadata.role` (backend track).
7. **M1/M6** — stale-cache expiry + proactive deactivation check on session restore.
8. **M2–M5, L1–L6** — as ordered above.
