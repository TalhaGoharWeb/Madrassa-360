# Error Handling & Logging — Security Audit

**Repo:** `~/workspace/madrassa-redesign-fix` · **Branch:** `redesign/ux-v2`
**Date:** 2026-10-03 · **Mode:** read-only audit, no code modified

## Executive summary

The codebase has a **well-designed centralized error taxonomy** (`AppException` +
`ErrorBoundary` + `AppLogger` with secret redaction) — but **adoption is
incomplete and the server side was left behind**:

- **Flutter:** `ErrorBoundary` is used in **6 of 336 catch sites**. The auth flow
  uses it correctly; 11 raw `$e` interpolations in snackbars across 5
  `master_admin` screens leak driver/DB detail; `madrasa_provider` stores raw
  `e.toString()` in displayable state.
- **Edge Functions:** 4 of 5 functions return raw `error.message` /
  `detail: <driver message>` to callers — leaking Postgres table, column and
  constraint names. Only the shared `guard.ts` and the top-level
  `manage-users` catch follow the safe pattern.
- **Logging:** `AppLogger` redacts *secrets* but not *PII* — emails/phone
  numbers in error text persist in plaintext crash logs on disk.
- **Audit trail:** strong append-only design for finance + role tables, but
  **no audit for login failures, password changes, notification broadcasts,
  student/record deletions, or bulk PII reads**; `audit_logs` has no retention
  policy and is `ON DELETE CASCADE` with tenants (deleting a tenant destroys
  its evidence).

**Counts:** 2 HIGH · 7 MEDIUM · 5 LOW · 4 verified-clean/positive.

---

## (a) Information-disclosure inventory

| # | Error path | What the user sees | Leaks internals? |
|---|-----------|--------------------|------------------|
| 1 | Login failure (`auth_provider` → `ErrorBoundary`) | Safe Urdu message (`AppException.userMessage`) | **NO** — correct |
| 2 | `manage-users` Edge Function failures (update/set_active/delete/assign/remove/set_platform_role) | `{error:"*_failed", message: error.message}` — raw supabase-js/PostgREST message | **YES** — table/column/constraint names |
| 3 | `export-tenant` read failure | `Could not read ${table}: ${error.message}` | **YES** — table name + driver detail |
| 4 | `provision-tenant` failure | `{error:"provision_failed", step, message}` where message = raw PG error via `step(name, error.message)` | **YES** — PG detail (callers are platform admins only) |
| 5 | `send-notification` failures | `{error:"db_error", detail: insErr.message}` / `detail: e.message` | **YES** — driver detail to any tenant caller |
| 6 | `manage-users` top-level catch | `{error:"internal", message:"Unexpected server error."}` | **NO** — correct |
| 7 | `guard.ts` auth failures | `{error:"unauthorized"/"forbidden", message:"Invalid or expired token."}` | **NO** — correct |
| 8 | `madrasa_detail_screen` (×4), `platform_users_screen` (×2), `master_dashboard_screen`, `create_madrasa_wizard`, `plans_screen` | `showM360SnackBar(context, 'Save failed: $e')` etc. | **YES** — raw exception text in snackbar |
| 9 | `madrasa_provider.update/delete` | `state.error = e.toString()` (designed for display) | **YES (latent)** — provider currently unconsumed by any screen |
| 10 | `forgot_password_screen` | `showM360SnackBar(context, e.message)` | **MARGINAL** — Supabase auth messages are usually safe, not guaranteed |
| 11 | `sync_apply` RPC `RAISE EXCEPTION` (e.g. `sync: not a member of tenant <uuid>`) | Returned in RPC error payload; sync engine swallows it (`catch (_) → null`) | **NO today** — latent for any future direct RPC caller |
| 12 | CrashScreen `details` box | `_shortError(e)` — secret-redacted, 240-char truncated | **MARGINAL** — PII (emails) not redacted |
| 13 | Uncaught async → root zone → CrashScreen | Generic bilingual "something went wrong" | **NO** — correct |
| 14 | RLS denial via PostgREST (direct table queries) | PostgREST `42501` JSON (`"message":"new row violates row-level security policy for table \"x\""`) | **YES (by design of PostgREST)** — table names visible to any authenticated caller; mitigated only where `ErrorBoundary` classifies before display |

---

## (b) Logging inventory

| # | Log call | What is logged | Sensitive? |
|---|----------|----------------|------------|
| 1 | `AppLogger().error/warning/info/debug` (~30 call sites) | Message + optional context map + error + stack | **Secrets: NO** (redacted) · **PII: POSSIBLE** — emails/phones in free text are not redacted |
| 2 | `AppLogger.logCrash` → `logs/crashes/crash_<ts>.log` | Full redacted error + stack, tenant id, version | **PII: YES if present in error text** (e.g. duplicate-email violations) |
| 3 | `console.error` in `manage-users` top-level catch | `(e as Error)?.message` — server-side only | NO (never leaves server) |
| 4 | `console.error` in `provision-tenant` | Step errors incl. `tplErr.message` — server-side only | NO |
| 5 | `print(` / `debugPrint(` in `lib/` | **0 occurrences** | Clean — good |
| 6 | `HealthMetrics` → SharedPreferences | Counters only (sync/auth/api failures) | NO |
| 7 | Log files on disk (`%APPDATA%/Madrassa360/logs`, 5×2 MiB rotation) | All of the above, plaintext | **PII risk per #1–2**; any local user/process can read |
| 8 | Release-mode gating | None found — `AppLogger` writes in all build modes | Acceptable (local file), but no remote crash reporting exists |

---

## (c) Audit-trail coverage table

`public.audit_logs` design (migration `012_audit_logs.sql`): append-only for
clients (no INSERT/UPDATE/DELETE policies → default-deny), writes via
`SECURITY DEFINER log_audit()` RPC or service_role (Edge Functions). SELECT:
platform admins see all; tenant admins/owners see own tenant.

| Security event | Logged? | Actor + timestamp + before/after? | Who can delete the trail? |
|---|---|---|---|
| Finance writes (invoices/payments/expenses) | **YES** — `finance_audit()` trigger (014) | actor=`auth.uid()`, ts, old+new JSONB | nobody client-side (no DELETE policy) |
| Role/permission/membership changes | **YES** — `audit_role_ux_changes()` triggers on 6 tables (019) | actor, ts, old+new | nobody client-side |
| Tenant provisioning | **YES** — `provision-tenant` writes `tenant.provisioned` | callerId, ts, new_data | nobody client-side |
| Tenant export | **YES** — `export-tenant` writes `tenant.export` (warns honestly if audit write fails) | callerId, ts, sha256 + row counts | nobody client-side |
| User create/update/deactivate/delete, membership assign/remove, platform role grant/revoke | **YES** — `manage-users` `audit()` helper, passwords never logged | callerId, ts, new_data (no secrets) | nobody client-side |
| License revoke/extend | **YES** — `log_audit()` RPC from `license_repository` | actor, ts | nobody client-side |
| **Login failures** | **NO** — nowhere in app code | — | — |
| **Password changes** | **NO distinct event** — buried in `manage-users` `update_user` audit as generic update; no `password.changed` marker | — | — |
| **Notification broadcasts** | **NO** — `send-notification` has zero audit writes | — | — |
| **Student/staff/attendance/result deletions** | **NO** — no audit triggers outside finance + role tables | — | — |
| **Bulk PII reads** (list endpoints, search) | **NO** — reads are never audited | — | — |
| **RLS / policy / schema changes** | **PARTIAL** — `schema_migrations` ledger records *what*, not *who/when* | — | — |
| Retention | **NONE** — no retention/partitioning policy; table grows unboundedly | — | — |
| Tenant deletion | Destroys evidence — `audit_logs.tenant_id REFERENCES tenants(id) ON DELETE CASCADE` | — | platform admin deleting a tenant wipes its trail |

---

## Findings

### HIGH-1 — Edge Functions return raw database/driver error messages to API callers
- **Location:** `supabase/functions/manage-users/index.ts:462,507,564,603,644,827,832`;
  `supabase/functions/export-tenant/index.ts:135`;
  `supabase/functions/send-notification/index.ts:261,367,425`;
  `supabase/functions/provision-tenant/index.ts:405-412` (via `step(name, error.message)`)
- **Problem:** Failure branches interpolate `error.message` from supabase-js /
  PostgREST directly into the JSON response (`{error:"update_failed",
  message: error.message}`, `{error:"db_error", detail: insErr.message}`).
  PostgREST messages embed table names, column names and constraint names,
  e.g. `duplicate key value violates unique constraint
  "tenant_memberships_user_id_tenant_id_key"`.
- **Why it matters:** Any tenant admin (manage-users, send-notification) or
  tenant member can map the internal schema — table/column/constraint names —
  which directly aids SQL-injection-adjacent probing and RLS-policy inference.
- **Scenario:** A malicious `tenant_admin` repeatedly calls `assign_membership`
  with crafted role values; the constraint-violation messages enumerate valid
  role keys and the exact unique constraints on `tenant_memberships`.
- **Fix:** Return stable error codes + generic messages to the client
  (`{error:"update_failed"}`); log the full driver message server-side with
  `console.error`. Apply the pattern already used in `guard.ts` and the
  `manage-users` top-level catch (`{error:"internal"}`).

### HIGH-2 — No audit trail for authentication events, notification broadcasts, or core-entity deletions
- **Location:** (absence) `lib/data/repositories/auth_repository.dart`;
  `supabase/functions/send-notification/index.ts` (no `audit_logs` write);
  `supabase/migrations/*` (no audit triggers on `students`, `staff`,
  `attendance`, `results`, `classes`)
- **Problem:** Login failures are logged nowhere in the application; password
  changes have no distinct event; `send-notification` broadcasts (usable by any
  tenant member per the API-abuse audit) leave no trace; deleting a student or
  their fee history writes no audit row.
- **Why it matters:** Brute-force attacks are undetectable from the app's own
  trail; a malicious insider can broadcast phishing to all tenant members or
  delete records with zero forensic footprint. The existing finance/role
  triggers prove the pattern works — it just wasn't extended.
- **Scenario:** An attacker brute-forces a teacher's password (no CAPTCHA per
  API-abuse audit); `audit_logs` shows nothing — the compromise is discovered
  only via Supabase dashboard logs the tenant admin cannot see.
- **Fix:** (1) Write `auth.login_failed` / `auth.password_changed` rows via
  `log_audit()` from the client auth repository (actor = attempted identity
  where known, never the password). (2) Add `notification.broadcast` audit in
  `send-notification` (service_role). (3) Extend the `finance_audit()`-style
  trigger to `students`, `staff`, `fee_payments`-adjacent core tables — or one
  generic `audit_all_writes()` trigger. (4) Never log passwords/tokens in these
  rows (already the convention — keep it).

### MEDIUM-1 — Raw exceptions shown in snackbars across master_admin screens
- **Location:** `lib/presentation/screens/master_admin/madrasa_detail_screen.dart:186,211,247,253`;
  `platform_users_screen.dart:154,221`; plus `master_dashboard_screen.dart`,
  `create_madrasa_wizard.dart`, `plans_screen.dart` (11 sites total, pattern
  `'... failed: $e'`)
- **Problem:** `showM360SnackBar(context, 'Save failed: $e')` renders
  `PostgrestException.toString()` verbatim — full driver message with table /
  column / constraint detail.
- **Why it matters:** Exposure is limited to platform admins today, but it
  normalizes the anti-pattern and the same copy-paste will reach tenant-facing
  screens. It also bypasses the Urdu-first UX contract.
- **Scenario:** A platform_support admin triggers a unique-violation; the
  snackbar reveals the exact constraint name and conflicting column, which they
  relay (or screenshot) externally.
- **Fix:** Route all 11 sites through
  `ErrorBoundary.showErrorSnackBar(context, e, stackTrace: st)` — one-line
  change per site, keeps logging + health counters.

### MEDIUM-2 — `madrasa_provider` stores raw `e.toString()` in displayable error state
- **Location:** `lib/providers/madrasa_provider.dart:104,126`
  (`state = state.copyWith(error: e.toString())`, returned to callers)
- **Problem:** `error` is a display-intended field; raw `toString()` of a
  PostgrestException contains DB structure. The provider is currently not
  consumed by any screen (latent), but the next screen wired to it inherits the
  leak.
- **Why it matters:** Latent information disclosure + a trap for future
  developers who will reasonably assume `state.error` is display-safe.
- **Scenario:** A future madrasa-management screen shows `state.error` in an
  `ErrorDisplayWidget`; an RLS denial renders `new row violates row-level
  security policy for table "madrasas"` to a tenant user.
- **Fix:** Replace with
  `ErrorBoundary.handleErrorSimple(e, st, tag: 'madrasa/update')` (already the
  documented pattern in the sibling `auth_provider`).

### MEDIUM-3 — `ErrorBoundary` adopted in only 6 of 336 catch sites
- **Location:** repo-wide (`grep -rln "ErrorBoundary\." lib` → 6 files vs
  `grep -rn "catch" lib` → 336 sites)
- **Problem:** The taxonomy exists but 330 catch sites roll their own handling.
  Audited samples show most are benign (log-and-continue, generic Urdu
  snackbars), but each is an unreviewed disclosure surface — the guarantee
  "users never see internals" holds only where the boundary is actually used.
- **Why it matters:** Security properties must be systematic, not coincidental.
  One missed site in a future tenant-facing screen is a leak.
- **Scenario:** A new fee screen copies an old catch block that interpolates
  `$e`; no test fails because nothing enforces boundary usage.
- **Fix:** (1) Migrate catch sites incrementally, tenant-facing screens first.
  (2) Add the existing `no_mock_check`-style CI guard: a `tool/` script that
  fails CI on `showM360SnackBar(context, '...$e')` / `Text('$e')` patterns in
  `lib/presentation`. (3) Document the rule: never interpolate exceptions into
  widgets.

### MEDIUM-4 — `AppLogger` redacts secrets but not PII; crash logs persist PII in plaintext
- **Location:** `lib/core/observability/app_logger.dart:60-78` (`_sensitiveKey`,
  `_inlineSecret`); `logCrash` (~line 130)
- **Problem:** Redaction covers `password|token|secret|api-key|authorization|
  bearer|private-key` but not emails, phone numbers, or names. An error like
  `duplicate key ... (email)=(foo@bar.com)` or a validation message containing
  a phone number is written verbatim to `madrassa360.log` and
  `logs/crashes/crash_*.log` on disk (5×2 MiB rotation, world-readable by any
  local process/user on the machine).
- **Why it matters:** Student/parent PII at rest in plaintext logs on shared
  school computers; crash reports shared with support leak PII.
- **Scenario:** A clerk hits a duplicate-student error; the email + phone in
  the constraint message persist in the log file, later copied off the machine
  during "support diagnostics".
- **Fix:** Extend redaction with email/phone patterns (e.g.
  `[\w.+-]+@[\w-]+\.[\w.]+` → `[EMAIL]`, Pakistani mobile
  `(\+92|0)?3\d{2}[-\s]?\d{7}` → `[PHONE]`); apply to `logCrash` (already via
  `redact()`) and document that `context` maps must use IDs, not raw identity
  fields.

### MEDIUM-5 — `log_audit()` lets tenant admins forge/flood audit entries
- **Location:** `supabase/migrations/012_audit_logs.sql` (`log_audit` RPC,
  `GRANT EXECUTE TO authenticated`)
- **Problem:** Any tenant owner/admin can call `log_audit()` with arbitrary
  `action`/`entity`/`entity_id`/JSON payloads for their own tenant.
  `user_id` is forced to `auth.uid()` (good — no impersonation), but nothing
  stops forged actions (`invoice.paid` that never happened) or flooding the
  log to bury real events (no rate limit; JSONB payload unbounded).
- **Why it matters:** The audit trail's evidentiary value depends on entries
  being trustworthy; a malicious tenant admin can manufacture exonerating
  entries or drown an investigation in noise.
- **Scenario:** After fabricating receipts, a rogue accountant writes
  `payment.verified` entries via raw RPC to make the trail look clean.
- **Fix:** (1) Restrict free-text `action` to an allow-listed set via a CHECK
  or validation function. (2) Prefer trigger-written rows (like
  `finance_audit()`) for security-critical entities over client-callable RPC.
  (3) Cap payload size (`octet_length(new_data::text) < 64KB`). Flooding is
  inherently hard to prevent — rely on the append-only + admin-read design and
  note the residual risk.

### MEDIUM-6 — Tenant deletion cascades destroy the audit trail
- **Location:** `supabase/migrations/012_audit_logs.sql:34`
  (`tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE`)
- **Problem:** Deleting a tenant deletes all its `audit_logs` rows. A
  platform admin (or a compromised `manage-tenant` flow) can erase the entire
  forensic history of a tenant.
- **Why it matters:** Audit logs exist precisely for post-incident forensics;
  a single privileged action should not be able to vaporize them.
- **Scenario:** After a billing dispute, a tenant is deleted; with it goes all
  evidence of who changed fees, who exported data, who granted roles.
- **Fix:** Change to `ON DELETE SET NULL` (platform-level retention, still
  queryable by platform admins) or `ON DELETE RESTRICT` (block tenant deletion
  while audit rows exist, forcing explicit archival). Add a `deleted_tenant`
  marker column if `SET NULL` is chosen.

### MEDIUM-7 — No audit-log retention, partitioning, or tamper-evidence
- **Location:** (absence) `supabase/migrations/*`; `012_audit_logs.sql`
- **Problem:** `audit_logs` grows unboundedly (no retention policy, no
  partitioning); rows have no hash chain or signature, so a service_role
  compromise (or anyone with DB access) can silently alter history;
  `created_at` defaults to `now()` with no protection against backdating via
  direct service_role writes.
- **Why it matters:** For a financial system (fees, receipts), the audit trail
  is a compliance artifact. Unbounded growth → performance cliff; no
  tamper-evidence → the trail is only as trustworthy as the service key.
- **Scenario:** Two years of fee audits make the tenant dashboard's audit
  screen time out; or a leaked service_role key is used to rewrite a
  `payment.deleted` row's `old_data`.
- **Fix:** (1) Monthly range partitioning + a documented retention policy
  (e.g. 7 years for finance, 1 year for routine events). (2) Add a
  `prev_hash`/`row_hash` chain (HMAC with a DB-held secret) so tampering is
  detectable. (3) Revoke direct service_role writes in favor of the trigger +
  `log_audit()` paths where possible.

### LOW-1 — Postgres `RAISE EXCEPTION` messages reach API callers verbatim
- **Location:** e.g. `supabase/migrations/016_sync.sql:238,242,273,310,313`;
  `014_finance.sql:480-491,602-605`; `007_tenant_rls.sql:774,779`
- **Problem:** Messages like `sync: not a member of tenant <uuid>` or
  `finance: invoice INV-… is paid — line items immutable` are returned in the
  RPC error payload, disclosing tenant UUIDs and internal state-machine
  vocabulary.
- **Why it matters:** Low direct harm (callers are authenticated members), but
  it leaks enumeration primitives (valid tenant UUIDs) and internal naming.
- **Scenario:** Attacker calls `sync_apply` with guessed tenant UUIDs; the
  difference between `not a member of tenant X` (valid UUID) and
  `unknown entity` (garbage) becomes an oracle.
- **Fix:** Keep detailed messages in the server log (`RAISE LOG`), return
  short stable codes to clients (`RAISE EXCEPTION ... USING ERRCODE` with
  generic text, or map in a wrapper). At minimum, stop echoing UUIDs:
  `sync: not a member of this tenant`.

### LOW-2 — CrashScreen `details` box can show PII
- **Location:** `lib/main.dart:186-190` (`_shortError`); 
  `lib/presentation/screens/crash_screen.dart:78-97`
- **Problem:** `_shortError` applies `AppLogger.redact` (secrets only) and
  truncates to 240 chars. An exception containing an email/phone renders in
  the monospace details box.
- **Why it matters:** Minor — but the box's doc comment claims
  "already-redacted", which overstates the guarantee.
- **Scenario:** Bootstrap fails on a duplicate-admin email; the crash screen
  shows the address.
- **Fix:** Apply the same PII redaction as MEDIUM-4, or drop the details box
  in release builds (`kReleaseMode` → null).

### LOW-3 — `forgot_password_screen` shows raw `e.message`
- **Location:** `lib/presentation/screens/auth/forgot_password_screen.dart:55`
- **Problem:** `showM360SnackBar(context, e.message, isError: true)` displays
  the Supabase auth error text directly.
- **Why it matters:** Supabase auth messages are generally safe, but the
  contract is implicit; a backend change could surface new text. Also bypasses
  Urdu localization.
- **Scenario:** Rate-limit error text changes upstream and renders in English
  with internal wording.
- **Fix:** Route through `ErrorBoundary.showErrorSnackBar` like the login
  screen does.

### LOW-4 — `export-tenant` reports `audit_write_failed` but still hands over data
- **Location:** `supabase/functions/export-tenant/index.ts:206-215`
- **Problem:** If the audit insert fails, the export (full tenant PII dump)
  still succeeds; the caller is merely warned.
- **Why it matters:** Acceptable availability-vs-audit tradeoff, and it's
  honest — but it means a full data exfiltration can occur with no trail if
  `audit_logs` writes are broken.
- **Scenario:** `audit_logs` insert path broken (permissions regression);
  attacker exports the tenant repeatedly, each time "without a trace".
- **Fix:** Keep the behavior (availability), but emit a platform-level alert
  (log + notification to platform admins) on `audit_write_failed` so silent
  trail loss is noticed.

### LOW-5 — No remote crash reporting; diagnostics die on-device
- **Location:** (absence) `lib/core/observability/*`; `pubspec.yaml` (no
  crash-reporting dependency)
- **Problem:** `AppLogger` writes to local files only. Support has no way to
  see crashes from the field; the "developer diagnostics" channel effectively
  doesn't exist beyond the device.
- **Why it matters:** Production issues are undebuggable without user
  cooperation; users email screenshots of the CrashScreen instead.
- **Scenario:** A crash loop on a specific Android device is reported as "app
  nahi khul rahi" with no actionable data.
- **Fix:** Add opt-in crash reporting (self-hosted Sentry or Supabase-logged
  crash pings with PII redaction per MEDIUM-4). Keep it free-tier and
  transparent to the user.

---

## Verified clean / positive patterns (do not regress)

1. `ErrorBoundary` + `AppException` taxonomy: user messages are safe,
   localized (Urdu-first), stable codes; technical details go only to logs.
   The auth login/logout flow uses it correctly.
2. `guard.ts` + `manage-users` top-level catch: generic error codes, no stack
   traces, no secret leakage; CORS helper is centralized.
3. `audit_logs` RLS: no client INSERT/UPDATE/DELETE policies (default-deny);
   `log_audit()` forces `user_id = auth.uid()` and tenant-admin scope checks.
4. `manage-users` `audit()` helper never logs passwords.
5. Zero `print()`/`debugPrint()` in `lib/`; sync engine never surfaces RPC
   error text to users (`catch (_) → null`).
6. `export-tenant` honestly reports `audit_write_failed` instead of silently
   dropping the trail.

---

## Recommended: three separated channels

1. **User-facing errors** — stable machine codes + localized human messages,
   nothing else. All UI error paths go through `ErrorBoundary`
   (`showErrorSnackBar`/`showErrorDialog`/`handleErrorSimple`); Edge Functions
   return `{error: "<stable_code>"}` with a generic message; Postgres
   `RAISE EXCEPTION` uses short codes without UUIDs/table names. CI guard
   rejects `$e` interpolation into widgets.
2. **Developer diagnostics** — structured logs (`AppLogger` file log +
   server-side `console.error`) containing codes, stack traces, request IDs —
   with **secret + PII redaction** (extend to emails/phones), per-tenant
   tagging (already present), rotation (already present), and opt-in remote
   crash reporting.
3. **Security events** — append-only `audit_logs` with restricted delete
   (already), extended coverage (login failures, password changes,
   broadcasts, core-entity deletes, bulk-read exports), allow-listed actions,
   payload caps, `ON DELETE SET NULL` instead of CASCADE, retention policy,
   and tamper-evident hashing.

---

## Prioritized fix order

1. **HIGH-1** — strip `error.message`/`detail` from all Edge Function client
   responses (4 files, mechanical).
2. **HIGH-2** — extend audit coverage: login failures, password-change events,
   `send-notification` broadcasts, core-entity delete triggers.
3. **MEDIUM-1 + MEDIUM-2 + LOW-3** — route the 11 snackbar sites,
   `madrasa_provider`, and forgot-password through `ErrorBoundary`.
4. **MEDIUM-3** — CI guard against raw-exception interpolation in
   `lib/presentation` (mirrors the existing `tool/no_mock_check.dart`).
5. **MEDIUM-4 + LOW-2** — PII redaction (email/phone) in `AppLogger` and the
   CrashScreen details box.
6. **MEDIUM-5** — allow-list `log_audit` actions + payload cap.
7. **MEDIUM-6** — `audit_logs.tenant_id` → `ON DELETE SET NULL`.
8. **MEDIUM-7** — retention/partitioning policy + hash-chained rows.
9. **LOW-1** — stop echoing UUIDs/table names in `RAISE EXCEPTION` client text.
10. **LOW-4** — platform alert on `audit_write_failed`.
11. **LOW-5** — opt-in remote crash reporting (free-tier).
