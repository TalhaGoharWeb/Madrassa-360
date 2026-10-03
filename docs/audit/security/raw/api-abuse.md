# Security Audit — API Abuse, Auth Lifecycle, Privilege Boundaries

**Target:** Madrassa-360, branch `redesign/ux-v2`, commit `945dce7` (remote `02c06927`)
**Scope:** login brute force, enumeration, password reset, session/token lifecycle,
privilege escalation, admin endpoints, impersonation, rate limiting / API abuse,
CORS/webhooks, predictable IDs, replay/idempotency.
**Method:** read-only static audit of `lib/`, `supabase/migrations/`,
`supabase/functions/`, `android/`, plus SDK source in `~/.pub-cache`.
No code was modified.

---

## CRITICAL

### C1 — `sync_apply` is SECURITY DEFINER with NO per-table permission checks
- **Location:** `supabase/migrations/027_user_accounts_app_roles.sql`
  (`public.sync_apply`, replicated from `016_sync.sql`)
- **Problem:** The function checks only
  `is_platform_admin() OR is_tenant_member(v_tenant)` — membership, not
  permission. Once that passes, ANY of the 26 whitelisted entities
  (`students`, `staff`, `results`, `fees`, `invoices`, `payments`,
  `expenses`, `income`, `finance_transactions`, …) can be
  inserted/updated/soft-deleted. Because it is SECURITY DEFINER, all RLS
  on those tables is bypassed.
- **Why it matters:** The entire client-side permission UI
  (`hasPermissionProvider('results.edit')` etc.) is advisory. The server
  does not enforce it on the offline-sync write path — the exact
  "never rely on frontend restrictions" violation.
- **Attack scenario:** A user whose only membership is `parent` or
  `student` (rank 10) calls `rpc('sync_apply', {p_entity:'results', …})`
  and rewrites exam grades, or `{p_entity:'payments'}` to fabricate fee
  receipts, or soft-deletes every `students` row. One authenticated
  low-privilege account can corrupt a tenant's academic and financial
  records. (UPDATE does exclude `tenant_id`, so cross-tenant writes are
  not possible this way — the damage is intra-tenant but total.)
- **Recommended fix:** Add a per-entity permission map inside
  `sync_apply` (e.g. `results→results.edit`, `fees/payments/invoices→
  fees.collect`, `students→students.edit`, …) enforced via
  `user_effective_permission(v_tenant, v_uid, code)` for insert/update/
  delete, failing closed on unknown entities. This is the hardening that
  migration 027 explicitly deferred.

### C2 — `manage-users:update_user` lets read-only staff take over any account
- **Location:** `supabase/functions/manage-users/index.ts`
  (`handleUpdateUser` → `canMutateUser(..., "users")` → `callerCan(...,
  "users")` → `resolveCaller`)
- **Problem:** The header comment documents the intended mapping as
  "`users.view` → list_users, safety_check, create_user (bare auth
  user)". But `handleUpdateUser` gates on the `"users"` right, and
  `callerCan(tenantId, "users")` returns true for `userTenants` — a set
  that `resolveCaller` populates for anyone holding **`users.view`**.
  `update_user` accepts `email`, `password`, `user_metadata`,
  `app_metadata`.
- **Why it matters:** Read permission silently grants write permission
  on the most sensitive object in the system (credentials).
- **Attack scenario:** `hr_incharge` is seeded with `users.view` but NOT
  `users.update` (`019_role_ux_schema.sql`). An HR staffer calls
  `manage-users {action:"update_user", user_id:<tenant_admin>,
  email:"attacker@evil.com", password:"P@ssw0rd123"}`. `canMutateUser`
  passes (target is not a platform admin, not a tenant_owner, callerRank
  is 0 so the rank check is skipped). The attacker now owns the tenant
  admin's account — full privilege escalation from a read-only HR role.
  Changing `email` needs no verification, so the attacker can also
  route future password resets to themselves.
- **Recommended fix:** Gate `update_user` on a write right
  (`users.update`, falling back to legacy owner/admin rank), never on
  the `"users"`/view set. Separately, require email re-verification
  (or platform-admin approval) for email changes.

---

## HIGH

### H1 — `app_metadata` mass assignment in `manage-users` (client-side role spoofing)
- **Location:** `supabase/functions/manage-users/index.ts`
  (`handleCreateUser`, `handleUpdateUser`); consumer
  `lib/data/repositories/auth_repository.dart` (`AppUser.fromSupabase`)
- **Problem:** Both handlers copy caller-supplied `app_metadata` verbatim
  into `auth.admin.createUser` / `updateUserById`. Any tenant caller
  (e.g. a tenant_admin, or via C2, an hr_incharge) can set
  `app_metadata: {"role": "superAdmin"}`. The Flutter client reads
  `user.appMetadata['role']` **first**, before the `profiles` table, to
  decide `UserRole`.
- **Why it matters:** Server-side data access is still gated by
  `tenant_memberships` + `user_effective_permission` (verified — neither
  consults `app_metadata` or `user_accounts.role_name`), so this is
  client-side role spoofing, not a data breach. But `UserRole.superAdmin`
  drives UI routing and could expose admin-only screens/flows that then
  fail confusingly — or worse, any future code that trusts
  `currentUserRoleProvider` for a decision inherits a spoofable root.
  The app's own `createAccount` sends `'app_metadata': {'role':
  account.roleName}`, normalizing the dangerous pattern.
- **Attack scenario:** A tenant_admin creates a sleeper account with
  `app_metadata.role = "superAdmin"`. The victim client renders the
  platform-console shell; combined with any future role-trusting code
  path, this becomes real escalation.
- **Recommended fix:** Strip `app_metadata` for non-platform callers
  (or allowlist safe keys like `name` only). Platform admins keep the
  current behavior. Never read role from `appMetadata` client-side —
  resolve it from the server permission RPC.

### H2 — Direct PostgREST write to `tenant_memberships` bypasses all manage-users guards
- **Location:** `supabase/migrations/004_memberships.sql` (policy
  `"tenant admins manage memberships" FOR ALL USING/WITH CHECK
  (is_tenant_admin(tenant_id))`)
- **Problem:** A legacy `tenant_admin` can INSERT/UPDATE/DELETE
  `tenant_memberships` rows directly through PostgREST. The
  `protect_last_owner` trigger (019) stops deleting/demoting the *last*
  owner, but nothing stops a `tenant_admin` from **self-promoting to
  `tenant_owner`** via a direct UPDATE (`WITH CHECK` still passes —
  they remain an admin-or-owner of the tenant), or from granting
  attacker accounts arbitrary template roles, all without audit logging
  and without the rank gates in `assignRoleGate`.
- **Why it matters:** The carefully built authorization logic in
  `manage-users` (rank ceilings, last-owner protection, audit trail) is
  optional — the database offers a parallel, weaker path.
- **Attack scenario:** Compromised/low-trust `tenant_admin` account runs
  `PATCH /rest/v1/tenant_memberships?user_id=eq.<self>` setting
  `role='tenant_owner'`. No Edge Function is involved, no audit row is
  written, and the caller is now owner — able to demote the real owner
  (as long as one other owner remains, the trigger stays silent).
- **Recommended fix:** Restrict the RLS policy to SELECT for
  non-platform callers (or `FOR ALL` → platform-admin-only) and force
  all membership mutations through `manage-users` / a hardened RPC that
  keeps the rank gates and audit writes.

### H3 — `send-notification`: any tenant member can spam/phish the whole tenant
- **Location:** `supabase/functions/send-notification/index.ts`
  (authorization block ~line 205)
- **Problem:** Authorization is only "authenticated AND (platform admin
  OR active member of the tenant)". There is **no permission check**
  (e.g. `notifications.send` / `announcements.send`), yet the function
  sends push (FCM) **and email (Resend)** with fully caller-controlled
  `title`/`body` to either a targeted user or **all active members**
  (up to 2000).
- **Why it matters:** Any compromised student/parent account becomes a
  tenant-wide phishing cannon ("Urgent: pay fees here <evil link>") sent
  from the institution's own sender identity, plus direct Resend cost.
- **Attack scenario:** Attacker with a stolen parent login posts
  `{tenant_id, notification_id, type:"fee", title:"فیس کی آخری تاریخ",
  body:"…pay at evil.example…", channels:["push","email"]}` — every
  parent gets a push notification and an email that looks official.
- **Recommended fix:** Require an explicit send permission
  (`notifications.send`) for tenant callers; keep member-broadcast for
  privileged roles only. Add per-caller rate limiting (e.g. N
  broadcasts/hour) and log every broadcast to `audit_logs`.

### H4 — `user_accounts` RLS: cross-tenant PII read; write gated on the wrong scope
- **Location:** `supabase/migrations/027_user_accounts_app_roles.sql`
- **Problem:** (a) `user_accounts_select_member` allows **any active
  member of any tenant** to SELECT **all** rows — names, emails, phone
  numbers of users in *other* tenants (the migration admits per-row
  scoping is impossible without `tenant_id`). (b) INSERT/UPDATE/DELETE
  require holding `users.create/update/deactivate` in **≥1** tenant —
  a user with `users.update` in tenant A can UPDATE rows belonging to
  tenant B, including `role_name` and `is_active` (deactivate anyone's
  metadata row). (c) `role_name` is client-writable via the provider's
  direct `.update()`.
- **Why it matters:** Cross-tenant personal-data exposure violates the
  core multi-tenant isolation promise; the write scope mismatch is a
  latent escalation primitive even though `role_name` is currently
  cosmetic (verified: `user_effective_permission` and RLS consult only
  `tenant_memberships`/`tenant_roles`).
- **Attack scenario:** A teacher in tenant A enumerates every user
  account (names + emails) across all tenants for spear-phishing; or a
  user with `users.update` in one tenant flips `is_active=false` on
  another tenant's admin metadata rows to cause confusion/DoS of the
  user-management UI.
- **Recommended fix:** Add `tenant_id` to `user_accounts` and scope all
  four policies per-row (this was deferred in 027 — do it now); until
  then, restrict SELECT to callers with a user-management permission and
  document the residual exposure. Remove `role_name` from the
  client-writable update path or lock it behind platform admin.

### H5 — No rate limiting anywhere; login brute force rests on platform defaults alone
- **Location:** `supabase/functions/_shared/guard.ts` (no throttling);
  `lib/presentation/screens/auth/login_screen.dart` (no attempt counter,
  no CAPTCHA); all five Edge Functions
- **Problem:** No Edge Function implements rate limiting. The login
  screen has no client-side backoff, and `signInWithPassword` is called
  without a CAPTCHA token (Supabase CAPTCHA not configured — no
  `captcha` references anywhere). Brute force protection is whatever
  Supabase Auth's default rate limits happen to be.
- **Why it matters:** Credential-stuffing against known tenant emails is
  unimpeded at the app layer; expensive endpoints (`list_users` with its
  N+1 `auth.admin.getUserById` fan-out, `export-tenant`,
  `provision-tenant`) can be hammered to burn CPU, Resend/FCM quota, and
  admin-API rate budget (DoS / cost).
- **Attack scenario:** Attacker scripts login attempts with a password
  list against harvested staff emails; in parallel, a low-privilege
  compromised account loops `list_users` (each call = up to 200 admin
  API reads) to degrade the function for everyone.
- **Recommended fix:** Add a shared token-bucket limiter in `_shared`
  (per-caller-ID + per-IP, in-memory is fine on Deno Deploy per
  isolate; stricter for auth-adjacent actions), enable Supabase Auth
  CAPTCHA (Turnstile) on sign-in, and add client-side progressive
  backoff after repeated failures.

---

## MEDIUM

### M1 — Refresh tokens stored unencrypted; Android backup enabled by default
- **Location:** `supabase_flutter` 2.12.0 default
  (`SharedPreferencesLocalStorage` — verified in
  `~/.pub-cache/.../supabase_flutter-2.12.0/lib/src/supabase.dart:113`);
  `android/app/src/main/AndroidManifest.xml` (no `android:allowBackup`,
  defaults to `true`)
- **Problem:** The long-lived refresh token sits in plaintext
  SharedPreferences. With `allowBackup` unset, `adb backup` (or a
  rooted device / malicious backup restore) exfiltrates it; the token
  is a bearer credential with the full power of the account until
  expiry/revocation.
- **Attack scenario:** Attacker with brief physical access (or a
  malicious "phone cleaner" app on a rooted device) copies the prefs
  XML, extracts the refresh token, and maintains a persistent session
  as the victim — including after the victim changes their password
  (password change does not revoke existing refresh tokens by
  default in GoTrue).
- **Recommended fix:** Pass a `flutter_secure_storage`-backed
  `localStorage` to `Supabase.initialize`; set
  `android:allowBackup="false"` (or a tight backup-rules XML); on
  password change/reset, revoke all sessions via
  `auth.admin.signOut(userId)` server-side.

### M2 — Login error mapper contains an account-enumeration landmine
- **Location:** `lib/data/repositories/auth_repository.dart`
  (`_mapAuthError`)
- **Problem:** Maps `'user not found'` → `'یہ اکاؤنٹ موجود نہیں'`
  ("this account does not exist"). Current GoTrue returns generic
  "Invalid login credentials" for both bad-password and unknown-user,
  so the branch is **dead code today** — but if Supabase ever changes
  the message (or a self-hosted GoTrue fork is used), login starts
  distinguishing existing vs non-existing accounts. Separately,
  `'email not confirmed'` → a distinct message reveals that an account
  exists *and* the guessed password was correct.
- **Recommended fix:** Collapse all credential failures to one generic
  message; delete the `'user not found'` branch.

### M3 — Weak password policy (6 chars, no complexity, no breach check)
- **Location:** `supabase/functions/manage-users/index.ts`
  (`password.length < 6`); `lib/providers/user_management_provider.dart`
  (`createAccount`); client validators
- **Problem:** 6-character minimum everywhere; no complexity, no
  haveibeenpwned-style screening. Combined with H5, short passwords are
  brute-forceable.
- **Recommended fix:** Minimum 10–12 chars, enable Supabase Auth's
  leaked-password protection, keep the 6-char floor only where a legacy
  constraint forces it.

### M4 — Peer admins can reset each other's passwords
- **Location:** `supabase/functions/manage-users/index.ts`
  (`canMutateUser`: `if (callerRank > 0 && targetRank > callerRank)`)
- **Problem:** Equal-rank mutation is allowed, so `tenant_admin` A can
  `update_user` `tenant_admin` B (password/email). Lateral takeover
  between peers with no second pair of eyes.
- **Recommended fix:** Require strictly-greater rank for credential
  changes (`targetRank >= callerRank` blocks), or require platform-owner
  approval for admin-credential changes.

### M5 — `switchTenant` accepts any ID without membership validation
- **Location:** `lib/core/services/tenant_context.dart`
  (`switchTenant`)
- **Problem:** Sets the active tenant to an arbitrary ID and persists
  it. Mitigations hold today: `currentTenantIdProvider` nulls out
  non-member IDs, permissions reload via the server RPC
  (`get_my_permissions_detailed`), and RLS is the real backstop — so
  impact is UI confusion, not data access.
- **Recommended fix:** Validate `id` against memberships inside
  `switchTenant` (fail closed) instead of relying on downstream guards.

### M6 — CORS `Access-Control-Allow-Origin: *` on all Edge Functions
- **Location:** `supabase/functions/_shared/guard.ts`
  (`CORS_HEADERS`)
- **Problem:** Wildcard origin with `Authorization` allowed. Since auth
  is Bearer-JWT (not cookies), the practical risk is low — but any
  malicious site can make *authenticated* calls if it ever obtains a
  JWT (e.g. via M1 token theft), and the wildcard normalizes that.
- **Recommended fix:** Restrict to the app's origins; keep `*` only if
  a documented reason exists.

---

## LOW

### L1 — No concurrent-session limit; no session inventory/revocation UI
- Users cannot see or revoke other sessions. Combined with M1, a stolen
  refresh token lives until natural expiry. (Server-side revocation on
  `signOut` works — verified in `auth_repository.dart`.)

### L2 — Fee double-record across devices (offline-first inherent)
- Same-device double-tap is guarded (`_saving ? null : _record` in
  `finance_payments_tab.dart`); sync retries are idempotent per op ID
  (`sync_apply` returns `already_exists`). Two devices recording the
  same cash payment concurrently will still create two rows — inherent
  to offline-first, acceptable; consider a human-reviewable
  "possible duplicate" heuristic in the finance UI.

### L3 — `email_confirm: true` bypasses email verification
- `manage-users:create_user` sets `email_confirm: true`, so accounts are
  usable without ever proving mailbox ownership. A typo'd admin-entered
  email means password-reset links go to a stranger. Consider
  verifying-on-first-login or an admin "resend verification" flow.

---

## VERIFIED — claims checked, no issue found

- **V1.** `fees.delete` is NOT in the 019 permission seed (grep of
  `019_role_ux_schema.sql` returns nothing) → fee DELETE fails closed
  for tenant users; platform-admin-only. **PASS** (as documented).
- **V2.** `users.manage` is NOT seeded (migration 027 header notes it as
  verified-absent) → `user_accounts` policies correctly fall back to
  `users.create/update/deactivate`. **PASS** (as documented).
- **V3.** gotrue background-refresh stream errors are handled with
  `onError` in `auth_provider.dart` (`_init`) — no CrashScreen on dead
  network; a truly dead session still arrives as SIGNED_OUT. **PASS**.
- **V4.** `provision-tenant`, `manage-tenant`, `export-tenant` all gate
  on `requirePlatformAdmin` (JWT → `auth.getUser` → `platform_admins`
  row). `set_platform_role` requires `platform_owner`; last-admin
  deletion is refused. **PASS**.
- **V5.** `profiles.role` is locked by the `trg_profiles_lock_role`
  trigger — non-platform clients cannot change role on INSERT/UPDATE;
  real roles live in `tenant_memberships`. **PASS**.
- **V6.** `signOut` calls `auth.signOut()` which revokes the refresh
  token server-side; local cleanup is best-effort but complete
  (permission caches, delegation caches, tenant context).
  **PASS** — logout revokes.
- **V7.** No `service_role` key anywhere in `lib/`; `assets/.env` is
  gitignored and CI injects it from GitHub secrets at build time.
  **PASS** — no hardcoded secrets found.
- **V8.** Record IDs are UUIDv4 (`gen_random_uuid()`), not sequential —
  no predictable-ID enumeration. **PASS**.
- **V9.** No SSRF: the only server-side `fetch` to a non-fixed host is
  none — FCM/Resend URLs are hardcoded. **PASS**.
- **V10.** No impersonation / "login as" feature exists; tenant
  switching is membership-checked downstream. **PASS** (nothing to
  exploit).
- **V11.** `protect_last_owner` trigger (019) fires on
  `tenant_memberships` DELETE/UPDATE — last-owner removal is blocked at
  the DB layer even when manage-users is bypassed. **PASS** (partial
  backstop; does not stop self-promotion, see H2).
- **V12.** `user_effective_permission` (020) is the server-side
  permission source and consults only `tenant_memberships` /
  `tenant_roles` / `user_permissions` — never `app_metadata`,
  `profiles.role`, or `user_accounts.role_name`. **PASS** — privilege
  data model is sound; the holes are in the *write paths* (C1, C2, H2).

---

## AUTH LIFECYCLE CHECKLIST

| Area | Verdict | Evidence / notes |
|---|---|---|
| Login | PASS w/ GAP | Supabase `signInWithPassword`; generic credential errors (GoTrue). GAP: brute-force hardening = platform defaults only, no CAPTCHA, no client backoff (H5) |
| Logout | PASS | `auth.signOut()` revokes refresh token server-side; full local cache purge (`auth_provider.dart`) |
| Session expiry | PASS | Failed refresh → SIGNED_OUT → login route; stream errors handled via `onError` (V3) |
| Refresh tokens | GAP | SDK rotation works, but tokens live in **unencrypted** SharedPreferences; `allowBackup` defaults true (M1) |
| Password reset | PASS w/ GAP | Supabase email flow; UI success message is enumeration-safe. GAP: dead `'user not found'`→distinct-message branch is an enumeration landmine (M2) |
| Email/phone verification | GAP | `email_confirm:true` bypasses verification entirely (L3); no phone verification exists |
| Account creation | PASS | Via `manage-users:create_user` only; no self-registration (login screen states provisioning-only) |
| Account deletion | PASS | Via `manage-users:delete_user`; last-owner and last-platform-admin guards hold |
| Role changes | **FAIL** | Three bypasses: direct `tenant_memberships` RLS write allows self-promotion tenant_admin→tenant_owner (H2); `update_user` right confusion (C2); `app_metadata` mass assignment (H1). `protect_last_owner` trigger only covers the last-owner case (V11) |
| Admin creation | PASS | `set_platform_role` requires `platform_owner`; last-admin deletion refused |
| Impersonation | PASS | No such feature; nothing to exploit (V10) |
| Session revocation | PASS | Server-side on sign-out; GAP: password change does not revoke other sessions; no session inventory UI (L1) |
| Concurrent sessions | GAP | Not limited; no UI to view/revoke (L1) |
| Disabled users | PASS | `ban_duration: 876000h` via `set_active`; banned users fail `getUser`/refresh → signed out |
| Deleted users | PASS | `auth.admin.deleteUser`; memberships cascade; client routes to login on missing user |

---

## Recommended fix order (this scope)

1. **C2** — re-gate `update_user` on `users.update` (one-line right change; closes account takeover by read-only staff).
2. **C1** — per-entity permission map in `sync_apply` (closes tenant-wide write bypass; the deferred hardening).
3. **H2** — restrict `tenant_memberships` RLS to read for tenant callers; force mutations through `manage-users`.
4. **H1** — strip/allowlist `app_metadata` for non-platform callers.
5. **H3** — permission-gate `send-notification` + rate limit broadcasts.
6. **H4** — add `tenant_id` to `user_accounts`, per-row RLS.
7. **H5** — shared Edge Function rate limiter; Supabase CAPTCHA on login; client backoff.
8. **M1** — secure-storage session persistence; `allowBackup="false"`.
9. **M2/M3/M4/M5/M6, L1–L3** — hygiene fixes in the same pass.
