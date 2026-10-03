# Remediation Plan — Madrassa-360 Security Audit 2026-10-03

**Source:** `docs/audit/security/SECURITY_AUDIT_2026-10-03.md` (110 findings: 6 CRITICAL / 20 HIGH / 46 MEDIUM / 38 LOW) + 12 performance findings.
**Rule for every phase:** implement in the branch → run the phase's verification → commit → push → CI green. **Live Supabase changes (migrations, Edge Function deploys, dashboard settings) require explicit user approval before each apply** — they are marked 🔴 LIVE below; everything else is 🟢 branch-only.

**Conventions:**
- Migration files: `supabase/migrations/029_*.sql`, `030_*`, … in order. Each migration must append the standard `schema_migrations` stamp block (fixes SEC-L29 going forward).
- After any migration change, re-run the CI migration-validation job locally (`dart` validator / pglast equivalent) before committing.
- The single architectural decision to make in Phase 1: **harden `sync_apply` per-entity** (recommended — smallest blast radius) vs **move financial writes to dedicated RPCs** (cleaner long-term). The plan below assumes hardening `sync_apply`; if the RPC route is chosen, Phase 1 items marked [RPC-ALT] replace the `sync_apply` edits.

---

## Phase 0 — Immediate containment (live-DB-safe, no code deploy needed where marked)

Goal: close the holes an attacker can use *today* with the smallest possible change surface. All migration items here are additive and rollback-safe.

### 0.1 Revoke the legacy JWT keys 🔴 LIVE (human, Supabase dashboard)
- **Fixes:** SEC-H18.
- **Steps:** Dashboard → Project Settings → API Keys → **Revoke** the old legacy JWT keys → verify they return 401 → confirm app + Edge Functions run on the new publishable/secret keys → check any other remotes/branches that may have carried them.
- **Also rotate:** DB password pasted in chat 2026-09-26 (still owed); audit the five documented demo accounts on the **live** project — delete them from live or move them to the demo project (SEC-M41).
- **Verify:** old keys 401; new keys work for app + functions; demo emails absent from live Auth users.

### 0.2 Restrict `user_accounts` SELECT to the user-management audience 🔴 LIVE
- **Fixes:** SEC-H5 (read half).
- **File:** new migration `supabase/migrations/029_user_accounts_select_scope.sql`: `DROP POLICY user_accounts_select_member …; CREATE POLICY … USING (is_platform_admin() OR EXISTS (active membership AND tenant_has_permission(any tenant, 'users.view')))`. (Full `tenant_id` scoping is Phase 2.)
- **Verify:** as a plain teacher JWT, `GET /rest/v1/user_accounts` → 0 rows / 403; as `users.view` holder → rows visible.

### 0.3 Fix `madrasas_member_select` scoping bug 🔴 LIVE
- **Fixes:** SEC-H7.
- **File:** migration `030_madrasas_select_scope_fix.sql`: qualify `madrasas.id` in the EXISTS predicate (`replace(madrasas.id::text, '-', '')`).
- **Verify:** tenant-A member `GET /rest/v1/madrasas` → only own rows; cross-tenant negative test passes.

### 0.4 Revoke `authenticated` EXECUTE on parameterized permission-oracle RPCs 🔴 LIVE
- **Fixes:** SEC-M6.
- **File:** migration `031_revoke_permission_oracles.sql`: `REVOKE EXECUTE ON FUNCTION user_effective_permission(UUID,UUID,TEXT), user_code_denied(UUID,UUID,TEXT), tenant_has_permission(UUID,TEXT) FROM authenticated, anon;` keep `auth.uid()`-bound wrappers (`get_my_permissions*`) granted. RLS keeps working (SECURITY DEFINER).
- **Verify:** direct `rpc('user_effective_permission', {p_tenant_id:<other>, …})` as low-priv user → 403/permission denied; app permission load still works.

### 0.5 Verify the live `tenant-exports` bucket 🔴 LIVE (human, dashboard)
- **Fixes:** SEC-H9 (triage).
- **Steps:** Storage dashboard → check `tenant-exports` exists, its `public` flag, and its policies. If public or authenticated-read: set private immediately. Then apply the Phase 2 migration that version-controls it.
- **Verify:** unauthenticated GET on an export object → denied.

**Phase 0 exit criteria:** 0.1–0.5 applied and verified; CI green on the branch containing migrations 029–031.

---

## Phase 1 — Server-side authorization core

Goal: make the write path enforce what the UI claims. This is the highest-leverage phase.

### 1.1 Per-entity permission map inside `sync_apply` 🔴 LIVE
- **Fixes:** SEC-C1 (the #1 finding), unblocks the permission model everywhere.
- **File:** migration `032_sync_apply_permissions.sql` (edit the `sync_apply` body; keep the 016/027 structure).
- **Change:** add an entity→operation→permission-code map (fail closed on unknown entity/op), e.g.:
  - `students` insert/update/delete → `students.create` / `students.update` / `students.delete`
  - `invoices`/`invoice_items` → `fees.create`, `fees.collect`
  - `payments`/`payment_allocations`/`refunds`/`discounts`/`scholarships` → `fees.collect` (insert/update), `fees.refund` (refunds)
  - `expenses`/`income`/`accounts`/`transactions` → `finance.record` (or the closest existing codes in 005/019 — use only codes that exist; fail closed otherwise)
  - `results` → `results.enter` / `results.edit`; `attendance` → `attendance.mark` / `attendance.edit`
  - `staff` → `staff.create/update/deactivate`; `announcements` → `announcements.send`; `library_books`/`book_issues` → `library.manage`
  - …covering all 26 whitelisted entities.
  Enforce `tenant_has_permission(v_tenant, code)` alongside the membership check in insert/update/delete branches; for scoped entities (`results`, `attendance`) also enforce `scope_allows()`. Return `{ok:false, reason:'forbidden:…', …}` (not an exception) so the client marks the op failed.
- **[RPC-ALT]:** if dedicated financial RPCs are chosen instead, remove the 13 financial entities from the whitelist here and implement `post_payment`/`approve_expense`/etc. RPCs with permission checks.
- **Verify:** pgTAP/Dart adversarial tests — parent-role JWT `sync_apply` insert into `payments`/`results` → denied; teacher with `fees.collect` → allowed; unknown entity → denied. (Test list maps to `raw/tenant-isolation.md` §(c) items 8–9.)

### 1.2 `sync_apply` correctness: membership-before-probe + atomic revision 🔴 LIVE
- **Fixes:** SEC-C2 (cross-tenant read oracle), SEC-C3 (TOCTOU), SEC-C6 (status/column abuse on the sync path), SEC-M17 (`created_by`/`created_at` forgery), SEC-M36 (`approved_by` forgery), SEC-M34 (cross-tenant FK references).
- **File:** migration `033_sync_apply_correctness.sql` (same function body).
- **Changes:**
  1. INSERT: require `p_payload.tenant_id`, verify `is_platform_admin() OR is_tenant_member(v_tenant)` **before** the EXISTS probe; on `already_exists`, include `server_row` only if the row's tenant matches the caller (else bare reason).
  2. UPDATE/DELETE: `… WHERE t.id = $2 AND t.revision = $5` + `GET DIAGNOSTICS v_rows = ROW_COUNT` → return `conflict` payload on 0 rows (or `SELECT … FOR UPDATE` before the check).
  3. Add `created_by`, `created_at`, `approved_by` to the insert exclusion list; `created_by` also to update exclusion; stamp `created_by = auth.uid()` server-side on insert (mirror the `updated_by` treatment from 027).
  4. INSERT: verify every `*_id` FK in the payload resolves to a row with `tenant_id = v_tenant` (whitelisted FK map per entity).
  5. Force `NEW.status = 'draft'` on INSERT for payments/refunds/expenses/income/transactions (or raise unless draft); remove `transactions` from the sync whitelist entirely.
- **Verify:** UUID-probe across tenants returns no row data; concurrent same-`base_revision` writes → one `conflict`; forged `created_by` ignored; cross-tenant FK insert rejected.

### 1.3 Financial transition guards 🔴 LIVE
- **Fixes:** SEC-C6 (remaining), business-logic H1 (approval skipping), SEC-M35, SEC-M18, SEC-M44.
- **File:** migration `034_finance_transition_guards.sql`.
- **Changes:**
  - `BEFORE UPDATE OF status` trigger on invoices rejecting direct writes to derived statuses (`paid`, `partially_paid`, `overdue`) — only `finance_refresh_invoice_status()` may set them; extend the amount-immutability guard to `partially_paid`/`overdue` once `amount_paid > 0`.
  - `finance_transition_guard()` per document table encoding draft→approved→posted (approved requires `finance.approve` + `approved_by = auth.uid()` server-stamped); remove `'cancelled','void'` from the RLS WITH CHECK allow-list; add `void_invoice(p_id, p_reason)` RPC (reason required, reversal/audit entry).
  - Refunds guard list `'approved,posted,void'` → `'posted,void'` so the sanctioned approve→post flow works.
  - `SELECT … FOR UPDATE` on the invoice row in `finance_post_payment()` / `finance_post_refund()`; backstop `CHECK (balance_due >= 0)`.
  - `CHECK (discount_total <= subtotal)` (raise in `finance_recalc_invoice`); `CHECK (amount_due >= 0 AND amount_paid >= 0)` on legacy `fees`; `REVOKE EXECUTE … FROM PUBLIC, authenticated, anon` on `finance_*` internals.
- **Verify:** insert-as-posted → forced draft; direct `status='paid'` → rejected; draft→posted skip → rejected; concurrent double-post → one wins, no over-allocation; approved refund posts and hits the ledger.

### 1.4 `platform_admins` trigger: owner-only role changes, last-owner backstop 🔴 LIVE
- **Fixes:** SEC-C5.
- **File:** migration `035_platform_admins_guard.sql`: `BEFORE INSERT OR UPDATE OR DELETE` trigger — only a current `platform_owner` may change `role` to/from `platform_owner` or delete an owner row; refuse to delete/demote the last `platform_owner`; audit the change (via `log_audit`-style insert).
- **Client:** route `platform_users_screen.dart` through `manage-users:set_platform_role` instead of direct table writes (single privileged path). 🟢 branch-only.
- **Verify:** as `platform_support` JWT, `PATCH platform_admins {role:'platform_owner'}` → trigger raises; deleting the last owner → raises.

### 1.5 Role-RPC grant ceilings 🔴 LIVE
- **Fixes:** SEC-H1.
- **File:** migration `036_role_grant_ceilings.sql`.
- **Changes:** `assign_tenant_role` may not assign `tenant_owner` unless caller is `tenant_owner`; may not assign a role whose effective permission set exceeds the caller's; `set_user_permission`/`set_role_permissions` may not grant codes the caller does not effectively hold (mirror the 019 delegation ceiling); forbid self-grant of `tenant_owner` unless platform admin. Extract the rank table into SQL so the RPC and the Edge Function share one source of truth.
- **Verify:** `roles.assign` holder → `assign_tenant_role(self,'tenant_owner')` → denied; self-grant of unheld code → denied.

### 1.6 `manage-users` fixes (Edge Function deploy) 🔴 LIVE (deploy)
- **Fixes:** SEC-C4, SEC-H2, SEC-H15, SEC-M31, SEC-M10 (409 half), SEC-L12.
- **File:** `supabase/functions/manage-users/index.ts` (+ redeploy).
- **Changes:**
  1. Gate `update_user` on `users.update` (fallback: legacy owner/admin rank) — never on the `"users"`/view set.
  2. Enforce the rank/authority ceiling for permission-based callers: derive effective max rank from granted codes; require strictly-greater rank for mutation/assignment; credential changes require `targetRank < callerRank` (blocks peer resets).
  3. Strip `app_metadata` for non-platform callers (allow-list safe keys only, e.g. `name`); server-derives any role claims.
  4. Uniform responses on create paths (no 409 oracle: generic 202).
  5. Raise password minimum to 10–12 for admin-created accounts.
- **Client:** `lib/providers/user_management_provider.dart` — send only the requested role key as data, never as `app_metadata`; collapse login error strings to one generic message (delete the `'user not found'` branch). 🟢 branch-only.
- **Verify:** `users.view`-only staffer → `update_user` → 403; permission-based caller → deactivating a `tenant_admin` → 403; `app_metadata.role` ignored for non-platform callers.

**Phase 1 exit criteria:** all adversarial tests in `raw/tenant-isolation.md` §(c) items 8–14 pass against staging; `flutter test` green; CI green.

---

## Phase 2 — Tenant isolation + storage/uploads

### 2.1 `tenants` column guard + unified suspension 🔴 LIVE
- **Fixes:** SEC-H6.
- **File:** migration `037_tenants_column_guard.sql`: `BEFORE UPDATE` trigger — `status`/`suspended`/`expires_at`/`tenant_code`/`slug`/`registration_number`/`admin_message*` changeable only by `is_platform_admin()`; allow-list for `settings.update` holders (`name`, `name_urdu`, contact fields, `use_logo_on_reports`); `logo_url` only writable when the new value matches the tenant's own storage logo prefix (until the upload Edge Function owns the write — then revoke client write entirely).
- **File:** migration `038_suspension_enforcement.sql`: single source of truth — `manage-tenant` sets the same flag `check_tenant_access()` reads; add suspension/expiry check to `is_tenant_member()` (or base RLS policies) so RLS enforces it, not just the client gate.
- **Verify:** suspended tenant's admin → `PATCH tenants {status:'active'}` → trigger raises; suspended member → any table read → 0 rows; `check_tenant_access()` false.

### 2.2 `user_accounts` gets `tenant_id` 🔴 LIVE
- **Fixes:** SEC-H5 (full).
- **File:** migration `039_user_accounts_tenant.sql`: `ADD COLUMN tenant_id UUID REFERENCES tenants(id)` (nullable) → backfill from `linked_staff_id`→staff.tenant_id / memberships → `SET NOT NULL` → re-scope all four policies per-row (`tenant_id` = caller's tenant or platform admin); remove `role_name` from client-writable path (platform-admin-only).
- **Verify:** tenant-A teacher → `user_accounts` → only A's rows; `users.update` holder in A cannot touch B's rows.

### 2.3 `upload-image` Edge Function + storage policy tightening 🔴 LIVE (deploy + migration)
- **Fixes:** SEC-H10, SEC-M22, SEC-M23.
- **New:** `supabase/functions/upload-image/index.ts` (service role): JWT → permission check per target (`settings.update` logo / `students.update` / `staff.update` photos) → magic-byte sniff (PNG/JPEG/WebP only; reject SVG/BMP/TIFF) → server-side size cap (5MB logo, 2MB photo) + pixel-dimension cap → **re-encode** → server-generated filename → fixed `contentType` → writes `logo_url`/`photo_url` itself.
- **Client:** route `TenantLogoService.uploadLogo` + photo upload paths through the function (keep picker UX checks only); cap branding/logo downloads (https only, ≤5MB, no private/loopback hosts); versioned logo objects instead of fixed-path upsert. 🟢 branch-only.
- **Migration** `040_storage_policies.sql`: `tenant-exports` bucket created **private** + platform-admin-only policies (SEC-H9); align `student-photos`/`staff-photos` SELECT with the row policy (`students.view` or parent-of-student); decide the `documents` bucket (wire or drop — SEC-L21).
- **Serving:** private photos via short-lived signed URLs (15-min) or authed `ImageProvider`; never public buckets.
- **Verify:** the 9-item adversarial checklist in `raw/file-uploads.md` §4 (malicious SVG/polyglot, 50MB photo, status-flip, `logo_url` poisoning, cross-tenant fetch, unbounded JSON → 413, …).

### 2.4 `tenant_memberships` writes restricted to the privileged path 🔴 LIVE
- **Fixes:** SEC-H3.
- **File:** migration `041_membership_writes.sql`: RLS policy → SELECT for tenant callers (platform-admin-only writes); all mutations forced through `manage-users` / hardened RPC (keeps rank gates + audit).
- **Verify:** `tenant_admin` JWT → `PATCH tenant_memberships {role:'tenant_owner'}` → 0 rows / denied; `manage-users` path still works with audit rows.

### 2.5 Legacy schema baseline 🔴 LIVE
- **Fixes:** SEC-M8, SEC-L13, SEC-L29.
- **File:** migration `000_legacy_base_schema.sql` (pg_dump --schema-only of the 14 pre-existing tables, reviewed, `IF NOT EXISTS`); move `supabase/01_schema.sql`… legacy files to `supabase/_archive/` (or guard header); append `schema_migrations` stamps to 025–028.
- **Verify:** fresh project builds from migrations alone (staging).

**Phase 2 exit criteria:** tenant-isolation test plan §(c) items 1–7, 12, 15–16 pass; file-upload checklist passes.

---

## Phase 3 — Client hardening

All 🟢 branch-only (no live apply needed), verified by `flutter test` + CI.

### 3.1 Token storage + backup lockdown
- **Fixes:** SEC-H11.
- **Files:** `lib/core/services/supabase_service.dart` (pass `flutter_secure_storage`-backed `LocalStorage` to `Supabase.initialize(authOptions:…)`); `android/app/src/main/AndroidManifest.xml` (`android:allowBackup="false"` or tight backup-rules XML). Add `flutter_secure_storage` dependency (safe, maintained).
- **Verify:** tokens absent from SharedPreferences XML; `adb backup` yields no prefs.

### 3.2 Logout wipes the tenant database
- **Fixes:** SEC-H12.
- **Files:** `lib/providers/auth_provider.dart` (`_handleSignedOut` → close + delete `madrassa360.db` + `Madrassa360/` caches); on account switch, same treatment.
- **Verify:** new test — seed local DB, logout, assert zero rows on disk (tenant-isolation §(c) item 17).

### 3.3 Complete the password-reset flow
- **Fixes:** SEC-H13.
- **Files:** `lib/data/repositories/auth_repository.dart` (`redirectTo` app callback scheme); deep-link handler for `PASSWORD_RECOVERY`; new `SetNewPasswordScreen` → `auth.updateUser`; same policy/error mapping as login.
- **Verify:** end-to-end reset on a test account; Supabase dashboard redirect allow-list contains only the app's real URLs (human check — secrets report item 5).

### 3.4 Error hygiene
- **Fixes:** SEC-H14 (Edge Function half), SEC-M29.
- **Files:** `supabase/functions/manage-users|export-tenant|send-notification|provision-tenant/index.ts` — stable error codes + generic messages; server-side `console.error` with correlation id. 🔴 LIVE (deploy, small).
- **Files:** route the 11 `master_admin` snackbar sites + `madrasa_provider` + `forgot_password_screen` through `ErrorBoundary` (one line per site). 🟢 branch-only.
- **CI:** add a `tool/` guard failing on `$e` interpolation into user-facing widgets (mirrors `no_mock_check.dart`).
- **Verify:** trigger an RLS denial as low-priv user → snackbar shows safe Urdu message, no table/constraint names; Edge Function failure → `{error:"<stable_code>"}` only.

### 3.5 Session/deactivation hygiene
- **Fixes:** SEC-M26, SEC-L34, SEC-L11 (partial).
- **Files:** `lib/providers/auth_provider.dart` — on `restoreSession`/`_refreshSessionUser`, check `user_accounts.is_active` / active membership; if deactivated → `signOut()` + dedicated screen; re-run `_checkPlatformAdmin` on refresh.
- **Verify:** deactivate a user mid-session → next resume signs out with the deactivated screen.

**Phase 3 exit criteria:** `flutter test` green (incl. new logout-wipe + deactivation tests); CI green; manual device check of reset flow.

---

## Phase 4 — Validation constraints + audit logging + rate limiting

### 4.1 DB CHECK/domain hardening 🔴 LIVE
- **Fixes:** SEC-M13, SEC-M14, SEC-M15, SEC-M20, SEC-M21, SEC-M37, SEC-M35 (partial), SEC-M33 (DB half), SEC-M18 (RLS half).
- **File:** migration `042_validation_constraints.sql`:
  - Text: `CHECK (char_length(name) <= 200)` on person/tenant names; phones `<= 32`; addresses `<= 500`; URLs `<= 2048` + `CHECK (value ~ '^https://')` on `photo_url`/`logo_url`; announcement/notification bodies `<= 5000`.
  - Format: phone `~ '^\+?[0-9]{10,15}$'` (after a data-cleanup pass — run a SELECT first to find violating rows and clean them before applying), email `~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'`.
  - `results`: `CHECK (marks_obtained >= 0 AND total_marks > 0 AND marks_obtained <= total_marks)`; add `is_published` + immutability trigger once published.
  - `students`: `CHECK (date_of_birth IS NULL OR (date_of_birth BETWEEN '1900-01-01' AND CURRENT_DATE))`, `CHECK (date_of_admit >= date_of_birth)`; `attendance`: `CHECK (date <= CURRENT_DATE)`; legacy `fees`: `CHECK (amount_due >= 0 AND amount_paid >= 0)`.
  - Library: `CHECK (available_copies >= 0)` + `BEFORE INSERT` trigger on `book_issues` doing the atomic decrement under row lock (fixes SEC-M19); partial unique index on unreturned (book_id, borrower).
  - Partial unique indexes `WHERE deleted_at IS NULL` for attendance/fees (fixes SEC-M1).
  - Composite `(tenant_id, server_version)` indexes on pulled tables (also PERF-M2).
  - `audit_logs.tenant_id` → `ON DELETE SET NULL` (fixes SEC-M4).
- **Verify:** each CHECK with a violating INSERT (expect failure) and a valid INSERT (expect success); data-cleanup report for pre-existing violations.

### 4.2 Centralized validation schemas 🟢 branch-only (+ small deploy)
- **Fixes:** SEC-M33 (client half), SEC-M16, SEC-L17, SEC-L19, SEC-M12.
- **Files:**
  - `lib/core/validation/` — value objects: `PhoneNumber` (parse → canonical `+92…`), `EmailAddress` (lowercase+trim), `PersonName` (trim, collapse spaces, NFC, strip zero-width/bidi controls, Yeh/Kaf canonicalization); `SearchSanitizer.escapeLike(q)` used by every `.ilike`/`or=` construction; formula-escape in `CsvExport`/`ExcelExport` (centralize in `tabular_data.dart` — prefix `=,+,-,@` cells with `'`).
  - `supabase/functions/_shared/guard.ts` — `validateBody(body, schema)` with per-action key allow-lists → 400 on unknown keys; `readJsonBody` byte cap → 413 (1MB default); `send-notification` length caps (`title_urdu ≤ 200`, `body`/`body_urdu ≤ 2000`, `data` ≤3KB, key rules); page the `list_users` pre-query. 🔴 LIVE (deploy).
- **Verify:** adversarial validation suite — oversized strings, negative/overflow marks, future DOB, forged `created_by`, `%`-wildcard search, `=cmd` export cells, 5MB notification body → all rejected/neutralized at the boundary (not through the UI).

### 4.3 Audit logging extended 🟢 branch-only + 🔴 LIVE (deploy)
- **Fixes:** SEC-H19, SEC-M27, SEC-M45.
- **Changes:**
  - `send-notification`: write `notification.broadcast` rows (service role). 🔴 LIVE deploy.
  - `lib/data/repositories/auth_repository.dart`: `auth.login_failed` / `auth.password_changed` via `log_audit()` (never the password). 🟢
  - Generic `audit_all_writes()` trigger (modeled on `finance_audit()`) on `students`, `staff`, `attendance`, `results`, `classes`. 🔴 LIVE migration `043_audit_triggers.sql`.
  - `log_audit()`: allow-listed `action` set + `octet_length(new_data::text) < 64KB` cap. 🔴 LIVE (same migration).
  - Retention: monthly range partitioning + documented policy (7y finance, 1y routine); `prev_hash`/`row_hash` HMAC chain (DB-held secret). 🔴 LIVE migration `044_audit_retention.sql`.
- **Verify:** failed logins appear in `audit_logs`; broadcast writes a row; forged `action` rejected; oversized payload rejected.

### 4.4 Rate limiting 🔴 LIVE (deploy + migration)
- **Fixes:** SEC-H8, SEC-M11 (429 path).
- **Files:** `supabase/migrations/045_rate_limit.sql` — `rate_limit_buckets(key TEXT, window_start TIMESTAMPTZ, count INT, PK(key, window_start))` + `SECURITY DEFINER rate_limit_check(p_key, p_max, p_window_sec)`; `supabase/functions/_shared/guard.ts` — `pipeline()` middleware (authenticate → authorize → rateLimit → sizeLimit → handler) adopted by all 5 functions; budgets: auth-adjacent 60/min, manage-users 120/min, send-notification broadcast 30/min, export-tenant 5/hour, provision-tenant 10/hour; `429` + `Retry-After`; CORS restricted to real origins (SEC-L6).
- **Client:** progressive backoff after repeated login failures. 🟢 branch-only.
- **Dashboard (human):** enable Supabase Auth CAPTCHA (Turnstile) on sign-in.
- **Verify:** looped calls → 429 with `Retry-After`; 429s in structured logs; login CAPTCHA appears.

### 4.5 Password policy
- **Fixes:** SEC-M30. In 1.6 (done) + enable Supabase Auth leaked-password protection (dashboard, human).

**Phase 4 exit criteria:** migration 042–045 applied to staging and verified; adversarial validation suite green; CI green.

---

## Phase 5 — Tests: role-boundary, cross-tenant, adversarial

Goal: lock every fix with regression tests so a future migration can't silently reopen a hole. 🟢 branch-only (tests run against staging in CI).

### 5.1 Test inventory (map 1:1 to findings)
- **Role-boundary tests** (per the user's requirement — every role boundary):
  - `sync_apply` as `parent`/`student`/`teacher` (minimal perms) → insert/update/delete on each of the 26 entities → denied unless the role holds the mapped code (SEC-C1).
  - `assign_tenant_role` / `set_user_permission` / `set_role_permissions` ceiling tests (SEC-H1).
  - `manage-users` right tests: `users.view`-only → `update_user` → 403; peer-admin credential change → 403 (SEC-C4, SEC-M31).
  - `platform_admins` trigger tests: support self-promotion → raises; last-owner delete → raises (SEC-C5).
- **Cross-tenant isolation tests:** the full plan in `raw/tenant-isolation.md` §(c) items 1–19 (RLS read/write, `tenant_id` move, `user_accounts`, `madrasas`, RPC oracles, `sync_apply` canaries, tenant-row guard, Edge Functions, storage, logout wipe, tenant switch, sequence inference).
- **Adversarial input tests:** §4.2's validation suite (boundary-level, crafted HTTP — not through the UI).
- **Upload tests:** `raw/file-uploads.md` §4 checklist (9 items).
- **Financial workflow tests:** status-transition graph per entity (draft→approved→posted legal; insert-as-posted rejected; paid-without-payment rejected; concurrent double-post → single allocation).
- **Unit:** PII redaction (SEC-M28), formula escaping (SEC-M16), value objects (SEC-M33), `SearchSanitizer` (SEC-L17), logout wipe (SEC-H12).

### 5.2 Where they run
- DB/RLS/RPC/storage: pgTAP on a staging project **or** Dart integration tests using the service role for fixtures + per-user JWTs for assertions (service role never in the app — test harness only).
- App/device: `flutter test` (logout wipe with in-memory Drift; deactivation flow).
- CI: run the isolation suite on **every migration change** — it is the tenant-boundary contract. Add the `$e`-interpolation guard and a "every new TEXT column must carry a length CHECK" lint (input-validation §(c) item 10).

**Phase 5 exit criteria:** all new tests green; at least one test per CRITICAL/HIGH finding, each failing on the pre-fix code (verify by running against the pre-fix migration set once).

---

## Phase 6 — Performance quick wins + dependency hygiene

Goal: materially improve real-user experience without changing business behavior. 🟢 branch-only unless noted. (Full analysis: `raw/performance.md`.)

### 6.1 Quick wins (hours)
1. `flutter build apk --split-per-abi` in `build-android.yaml` — ~50% smaller direct-install APK immediately (PERF-H4b).
2. Memoize fee-status aggregation into a derived provider (PERF-H3).
3. `NetworkImage` → `CachedNetworkImage(memCacheWidth: 128)` in all avatar lists (PERF-M3).
4. Remove `google_fonts` (SEC-L2) + delete dead `OfflineSyncService` (PERF-L1); regenerate lockfile (below).
5. Check connectivity once per push batch, not per row (PERF-H1 partial).

### 6.2 Structural (days, needs design + testing)
1. Batch `sync_apply` RPC (`sync_apply_batch(jsonb[])`, one server transaction) or bounded-concurrency push (4–6 in flight, per-entity FIFO) (PERF-H1). **Do after Phase 1** — the batch RPC must inherit the permission map.
2. Sync debounce + server-side change probe (skip pull passes with no changes) (PERF-H2).
3. Font subsetting pipeline with `pyftsubset` to the app's character inventory — biggest single size win (~65% total with per-ABI split); **verify the Nastaleeq redistribution license first** (already an open item). (PERF-H4a)
4. SQL-side aggregations for dashboard/finance-hub numbers; batched local writes for attendance (PERF-H5, PERF-H6, PERF-M1).
5. Parallelized bootstrap behind the auth gate; measure with `flutter run --trace-startup` (PERF-M4).

### 6.3 Dependency hygiene
- **Fixes:** SEC-H20, SEC-L2, SEC-L3, SEC-L4, SEC-M43, SEC-M46.
- Regenerate + freeze the lockfile (`--enforce-lockfile` in all workflows + CI sync check); safe upgrades: `shared_preferences` 2.5.5, `image_picker` 1.2.3, `uuid` 4.6.0, `url_launcher` 6.3.3, `path_provider` 2.1.6, `drift` 2.35.1, `supabase_flutter` 2.18.0 (exercise auth paths in tests); evaluate `flutter_dotenv` 6.x / `cached_network_image` 4.x separately; **keep pinned with documented reasons:** `flutter_riverpod` 2.x, `pdf` 3.12.0 / `printing` 5.14.3 (Dart ≥3.12), `firebase_messaging` 15.x + `firebase_core` 3.x, `supabase_flutter` 2.x.
- SHA-pin all GitHub Actions (minimum: the Inno Setup action); pin exact Deno version; add `manage-users` to `deno.json` check task; correct stale pin comments.
- Add iOS `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` (SEC-M42); verify Android camera behavior on older API levels.
- Add `--dart-define=ENVIRONMENT=production` to both build workflows (SEC-L5).

**Phase 6 exit criteria:** measurement plan in `raw/performance.md` re-run — report before/after for: cold start, 60-student attendance sync time on throttled 3G, sync request count per flap, APK size, dashboard paint, list scroll jank.

---

## Cross-phase verification & release discipline

1. **Staging-first:** every 🔴 LIVE migration is applied to a staging project first; the Phase 5 suite runs against staging before production apply.
2. **One approval per live apply batch:** group migrations per phase; the user approves each batch explicitly (as with migration 024 on 2026-10-01). Edge Function deploys are approved the same way.
3. **Do not regress the verified-clean list** (audit §"Verified clean / sound"): the Phase 5 suite includes positive controls (e.g. `protect_last_owner` still fires, `scope_allows` still fail-closed, doc-number sequences still atomic).
4. **Release rule (unchanged):** builds are cut only from exact CI-green commits; every build handoff names the commit, contents, artifact filenames, sizes, SHA-256 hashes, and Actions URLs. CI-green is necessary but not sufficient — the user's visual verification on real Windows + Android remains the final gate.
5. **Standing operational items (not code):** Supabase DB password rotation (owed since 2026-09-26); dashboard checks from the secrets audit (Auth redirect allow-list, email confirmation, password policy, JWT expiry); quarterly backup/restore drill once the runbook (SEC-M40) exists.

## Effort ordering (risk reduction per unit of work)

1. Phase 0 (hours; closes the live-exploitable holes that need no design).
2. Phase 1.1 + 1.2 (the two `sync_apply` migrations — single highest leverage in the program).
3. Phase 1.6 (one-line `update_user` right fix + deploy).
4. Phase 1.3–1.5, 2.1–2.4 (tenant + role hardening).
5. Phase 3 (client hardening; parallelizable with 1–2).
6. Phase 4 (validation + audit + rate limiting; mechanical).
7. Phase 5 (tests lock it in; start writing them alongside Phase 1).
8. Phase 6 (performance + deps; independent track).

---

## Addendum — red-team follow-up (2026-10-03)

Independent red-team re-audit (`docs/audit/security/RED_TEAM_2026-10-03.md`) found and fixed five additional issues beyond the original plan:

- **RT-01 (MEDIUM)** — client-controlled `created_at`/`updated_at` on sync INSERT. **Migration 046** adds a DB trigger forcing server `now()` on insert for all sync-whitelisted tables (covers `sync_apply` and direct PostgREST), with a transaction-scoped `SET LOCAL app.preserve_timestamps='on'` hatch for backfills.
- **RT-02 (HIGH)** — broadcast email put all recipients in `To:` (PII leak). Fixed in `send-notification`: recipients moved to `bcc:`.
- **RT-03 (MEDIUM)** — rate limiting failed open everywhere (backing table never created; only one function called it). **Migration 045** creates `edge_rate_limits` (RLS on, zero policies = service-role only); `rateLimit()` wired into all six functions with per-action windows.
- **RT-04 (MEDIUM)** — `upload-image` path convention broke storage RLS. Fixed: deterministic policy-matching paths + `upsert:true` + orphan deletion on extension change.
- **RT-06 (MEDIUM)** — CSV formula injection. Fixed: text-marker apostrophe prefix on trigger-leading cells.
- **Client wiring (done):** `TenantLogoService.uploadLogo` now routes through the hardened `upload-image` function instead of direct Storage upload. Requires the function to be deployed; fails loudly otherwise (no silent fallback). The sync engine's generic `pending_uploads` path still uploads directly — future hardening.

**Not fixed (documented):** RT-07 password-recovery custom URL scheme intercept risk → needs App Links/Universal Links via `assetlinks.json` on madrassa360.com; RT-10 local SQLite unencrypted at rest → SQLCipher decision pending.
