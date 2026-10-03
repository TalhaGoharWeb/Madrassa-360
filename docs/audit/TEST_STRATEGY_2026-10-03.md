# Madrassa-360 — Automated Test Strategy (2026-10-03)

Branch: `redesign/ux-v2`. Flutter 3.47.4, Riverpod, Drift/SQLite (offline-first),
Supabase backend. Companion to the security audit
(`docs/audit/security/SECURITY_AUDIT_2026-10-03.md`) and its remediation.

**Prime directive: no meaningless mock-only tests.** Every test must verify real
behavior or a real security boundary — pure functions, real in-memory
databases, real parsing, real SQL against staging. A test that only asserts a
mock returned what the mock was told to return is banned (CI enforces this for
data: `tool/no_mock_check.dart`).

## 1. Execution tiers — where each test runs

| Tier | What runs | When | Gate |
|---|---|---|---|
| **CI (per push/PR)** | `flutter test` (all unit + widget), `flutter analyze`, `dart format`, `dart tool/no_mock_check.dart`, `dart tool/no_raw_error_check.dart`, pglast parse of every migration + `test/db/*.sql`, `deno check` + `deno lint` (Edge Functions) | every push | must be green before merge |
| **Nightly** | full CI + `flutter test` with `--concurrency=1` stress pass on sync tests, dependency audit (`flutter pub outdated`, license scan) | scheduled | informational, file issues |
| **Staging-only** | `test/db/*.sql` against a staging Supabase project (service_role; each script wraps in `BEGIN…ROLLBACK`), manual adversarial walkthroughs (account enumeration, token replay), real-device offline drills | before any 🔴 LIVE migration batch | must be green before live apply |

Widget tests (`test/widget/`) run in CI with fakes at the repository
boundary — they verify real widget trees and real providers, never mocked
UI logic. True end-to-end (real backend, real devices) is **staging-only**:
no test in CI may depend on network or a live project.

## 2. UNIT tests

### 2.1 What exists (test/unit/, 40 files)

| Area | Files | Real behavior verified |
|---|---|---|
| Fee/finance models | `fee_calculations_test.dart`, `finance_views_test.dart` | ledger aggregation, `ReportInvoice.balanceDue`, enum↔DB mappings, JSON round-trips |
| Grading | `result_grading_test.dart` | grade bands (Urdu labels), dense-rank positions |
| Attendance | `attendance_percentage_test.dart` | `(present+late)/marked` weighting, status enum |
| Validators | `security/validators_adversarial_test.dart`, `validation/validators_extended_test.dart` | email/phone/CNIC/username/rollNumber/numeric/range/password hostile inputs; `required` presence |
| Auth/session | `secure_auth_storage_test.dart`, `logout_wipe_test.dart`, `login_backoff_test.dart`, `tenant_switch_validation_test.dart`, `app_user_role_source_test.dart`, `auth_routing_test.dart`, `auth_state_stream_error_test.dart`, `tenant_memberships_session_test.dart` | secure storage, logout DB wipe, backoff math (2/4/8/16→30s), tenant-switch allow-list, `app_metadata` role-spoof rejection (SEC-H15), gotrue stream `onError` |
| Authorization | `authorization_service_test.dart`, `permission_service_test.dart`, `role_service_test.dart`, `scope_*_test.dart`, `audit_urdu_*_test.dart`, `security/role_boundary_mirrors_test.dart`, `security/tenant_context_isolation_test.dart`, `delegation_test.dart` | permission maps, scope policies, sync permission-map mirror (SEC-C1 deny-by-default) |
| Sync rules | `sync_conflict_rules_test.dart`, `sync/offline_transitions_test.dart` | conflict resolution branches, tombstones, queue atomicity, CHECK constraints |
| Security utils | `app_logger_redact_test.dart`, `safe_download_test.dart` | PII redaction (emails/phones), SSRF URL rejection |
| Business logic | `business_logic/delegation_policy_test.dart`, `business_logic/money_format_test.dart` | delegation grant-ceiling pre-check, Pakistani digit grouping |
| Misc | asset bundling, backup manifest, license, network timeout, error mapping, reports, logo branding, tenant context | asset ships in APK, license states, 20s network timeouts |

### 2.2 Gaps and priority (unit)

1. **P1 — Login error uniformity (account-enumeration guard).** `_mapAuthError`
   is private and `AuthRepository` reads the static `SupabaseService.client`,
   so the "wrong email" vs "user not found" → one generic Urdu message
   contract has **no test**. Needs a seam: make the mapper a public static or
   inject the client. (SEC-M10.)
2. **P1 — Password policy.** `Validators.password` minimum is 6; the audit
   recommends 10–12 with UX. Whichever the user picks, the validator test must
   pin the exact floor (currently pins 6).
3. **P2 — URL validator (missing).** No `Validators.url` exists; `javascript:`
   photo URLs pass client validation (input-validation F-07). Add validator +
   tests.
4. **P2 — Filename sanitizer (missing).** No sanitizer in `lib/`; uploads rely
   on the server-generated filename (file-uploads M5). Add helper + tests.
5. **P3 — Hijri date / date_utils edge cases.** Untested; low risk.
6. **P3 — Report document builders.** PDF/CSV generation is integration-level;
   keep widget-golden out of CI (font-dependent), cover tabular data only.

### 2.3 Rules for new unit tests

- Pure functions in, asserted behavior out. If the "unit" needs a mock to be
  constructed, it is an integration test — move it.
- Security-relevant pure logic gets a named test per rule branch (see the
  conflict-rule and delegation tests as the template).
- Every test file header names the implementation file(s) under test and
  states what is deliberately NOT covered and why (honesty note).

## 3. INTEGRATION tests

### 3.1 What exists

- `test/integration/local_tenant_isolation_test.dart` — **real in-memory
  Drift** (`AppDatabase(NativeDatabase.memory())`): tenant-scoped DAO reads,
  soft-delete invisibility, `markClean` tenant guard, upsert idempotency.
- `test/unit/sync/offline_transitions_test.dart` — in-memory Drift for the
  sync queue + envelope tables (lives under `unit/` by convention; it is an
  integration test in spirit).
- `test/widget/*` (18 files) — real widget trees against fake repositories;
  the seam is the repository interface, and the fakes implement it faithfully.

### 3.2 Gaps and priority (integration)

1. **P1 — Sync engine push/pull cycle.** Skipped tests exist in
   `offline_transitions_test.dart`: queue drain on reconnect, no duplicate
   push after restart, 401-vs-transport retry accounting. Blocked on a
   transport seam: `SyncEngine` must accept an injected Supabase/RPC client
   instead of the static `SupabaseService`. (Offline-first audit §13.)
2. **P1 — Auth flows against a staging project.** Login → refresh → logout →
   session-expiry → password-reset round-trip. Staging-only (needs real
   backend); write as `integration_test/` with a staging flavor.
3. **P2 — Repository write paths.** Repositories currently write through the
   sync queue; test enqueue→(fake transport)→serverRevision stamping with an
   injected transport (same seam as P1).
4. **P2 — Report generation end-to-end.** `ReportData` against in-memory DB →
   tabular data → CSV bytes. No network, runs in CI.
5. **P3 — Migration smoke.** Apply migrations 001→044 to a scratch Postgres
   (docker) in nightly; catches DDL drift before staging.

### 3.3 Rules

- In-memory Drift is the default DB double — it runs the real SQL.
- Skipped tests are allowed ONLY with the exact harness gap named (file +
  line), so they become runnable the moment the seam lands. A skip without
  a named gap is a lie.

## 4. END-TO-END tests

| Flow | CI-capable? | Notes |
|---|---|---|
| Registration (new tenant provisioning) | ❌ staging-only | touches `provision-tenant` Edge Function, real Auth |
| Login (happy + wrong password + locked account) | ❌ staging-only | real session lifecycle |
| Admit student → invoice → collect fee → receipt | ⚠️ widget-level in CI | full chain needs staging; CI covers each screen's happy path with fakes |
| Mark attendance → sync → supervisor view | ⚠️ partial | offline half in CI (queue tests), online half staging |
| Create user → assign role → permission takes effect | ❌ staging-only | exercises 036 ceilings + `manage-users` |
| Deactivate user → session killed | ❌ staging-only | exercises `_checkAccountActive` + revocation |
| Error flows: airplane mode mid-flow, expired token on action, server 500 | ⚠️ partial | client error-mapping in CI (ErrorBoundary tests); server errors staging |

E2E lives in `integration_test/` (device) or scripted staging checklists, never
in `flutter test`. The rule: **if it needs network, it is not a CI test.**

## 5. SECURITY tests — finding → test map

"Client-runnable" = runs in `flutter test`. "Staging" = `test/db/*.sql` or
manual.

| Finding | Fix | Test | Tier |
|---|---|---|---|
| SEC-C1 sync writes bypass permissions | 032 permission map in `sync_apply` | `role_boundary_mirrors_test.dart` (Dart mirror) + `test/db/01` (behavioral) | CI + staging |
| SEC-C2 cross-tenant row oracle | membership check before `already_exists` | `test/db/01` §(c) | staging |
| SEC-C3 TOCTOU revision race | atomic revision check | `test/db/01` + sync engine unit | staging |
| SEC-C4 `update_user` privilege | `users.update` right + authority ceiling | Edge Function unit tests (Deno) + staging manual | CI + staging |
| SEC-C5 support self-promotion | 035 `platform_admins` trigger | `test/db/02` | staging |
| SEC-C6 finance bypass | 034 guards | `test/db/05` (a–c) | staging |
| SEC-H1 no grant ceiling | 036 ceilings | `delegation_policy_test.dart` (client pre-check) + `test/db/06` | CI + staging |
| SEC-H2 rank ceiling bypass | `manage-users` authority ceiling | Deno unit test | CI |
| SEC-H3 membership self-promotion | 041 write restrictions | staging manual | staging |
| SEC-H4 broadcast by any member | `notifications.send` + rate limits | Deno unit test + staging manual | CI + staging |
| SEC-H5 `user_accounts` PII | 029 scoping + 039 tenant_id | `test/db/04` | staging |
| SEC-H6 self-unsuspension | 037 column guard + 038 enforcement | `test/db/03` | staging |
| SEC-H7 `madrasas_member_select` | 030 qualified scoping | `test/db/04` | staging |
| SEC-H8 no rate limiting | `edge_rate_limits` + `rateLimit()` | Deno unit test (limiter math) | CI |
| SEC-H10 upload validation | `upload-image` magic-byte sniff | Deno unit test (sniffer) | CI |
| SEC-H11 plaintext tokens | `SecureAuthStorage` + `allowBackup=false` | `secure_auth_storage_test.dart` | CI |
| SEC-H12 DB survives logout | `wipeOnSignOut` | `logout_wipe_test.dart` | CI |
| SEC-H13 broken password reset | reset flow + `SetNewPasswordScreen` | widget test (screen) + staging manual | CI + staging |
| SEC-H14 raw DB errors | error hygiene in Edge Functions | Deno unit test (error mapper) | CI |
| SEC-H15 `app_metadata` smuggling | strip client `app_metadata.role` | Deno unit test + `app_user_role_source_test.dart` (spoof ignored, `profiles.role` honored) | CI |
| SEC-H16 over-allocation | 034 transition guard | `test/db/05` (b) | staging |
| SEC-H17 no idempotency | 042 `ux_*_idem` indexes | `test/db/05` (e) | staging |
| SEC-H19 no audit trail | 043 audit triggers | staging: perform delete → check `audit_logs` | staging |
| 042 CHECKs | domain constraints | `test/db/05` (d) | staging |
| Local tenant isolation | DAO `tenant_id` scoping | `local_tenant_isolation_test.dart` | CI |

Deliberately NOT covered (documented in the audit): 409 account-existence
oracle (needs rate-limit + product decision), broadcast email `to:`-list PII
(opens only in the mail provider's logs), image re-encode (no native bindings
in the Edge runtime), partitioning.

## 6. REGRESSION tests — every bug fixed in this audit

Each row is a bug found by the 2026-10-03 audit and the test that must catch
its return. If the fix is reverted, the test goes red.

**Auth/session (Flutter worker):**
- R-1 Plaintext tokens in SharedPreferences → `secure_auth_storage_test.dart`
- R-2 DB + caches survive logout → `logout_wipe_test.dart`
- R-3 No login backoff (credential stuffing) → `login_backoff_test.dart`
- R-4 Tenant switch accepts arbitrary tenant → `tenant_switch_validation_test.dart`
- R-5 Role smuggling via `app_metadata` → `app_user_role_source_test.dart`
  (spoofed `app_metadata.role` ignored; `profiles.role` honored) + Deno unit
  test (Edge Function strips client `app_metadata.role`)
- R-6 SSRF via tenant logo URL → `safe_download_test.dart`
- R-7 Backoff overflow (`1 << (failures-1)` → 0) → `login_backoff_test.dart` (extreme counts)
- R-8 gotrue stream error → CrashScreen → `auth_state_stream_error_test.dart`

**Edge Functions (Deno):**
- R-9 `update_user` gated on `users.view` → Edge unit test: `users.view` caller denied
- R-10 `manage-users` rank ceiling bypass → Edge unit test: permission-caller capped at own rank
- R-11 No body size cap → `guard.ts` test: oversized body → 413
- R-12 Unknown JSON keys silently accepted → `validateBody` test: unknown key → 400
- R-13 No rate limiting → `rateLimit` test: over-limit → 429
- R-14 Broadcast by any member → `send-notification` test: missing `notifications.send` → 403; over-quota → 429
- R-15 Raw DB errors to callers → error-mapper test: no `SQLSTATE`/paths leak

**Database (staging scripts):**
- R-16 Membership-only `sync_apply` → `test/db/01`
- R-17 Support self-promotion → `test/db/02`
- R-18 Self-unsuspension / column tampering → `test/db/03`
- R-19 Cross-tenant reads → `test/db/04`
- R-20 Ghost receipts / paid-without-payment → `test/db/05` (a–c)
- R-21 Double-charge on retry → `test/db/05` (e)
- R-22 Insane marks / negative money → `test/db/05` (d)
- R-23 `roles.assign` → become owner → `test/db/06`

**Client hardening:**
- R-24 Raw `$e` in snackbars → `tool/no_raw_error_check.dart` (CI job `error-guard`)
- R-25 PII in logs → `app_logger_redact_test.dart`
- R-26 Sequential per-row sync / N+1 providers → **gap**: no automated perf
  regression test yet; verified by code review. P2: add batch-counter
  assertions (e.g., sync batch count, provider query count) to the sync
  tests.
- R-27 Dead `offline_sync_service.dart` → (removed; CI compiles — absence is the test)
- R-28 Stale `pubspec.lock` → CI `--enforce-lockfile`
- R-29 107 MB universal APK → CI `--split-per-abi` on release APK
- R-30 `todayCollectionProvider` refactor compile break → full `flutter test` compile (the bundle fails to build on type errors)

## 7. Anti-patterns (banned)

1. Mock-only tests: a test whose assertions merely repeat the mock's setup.
2. `sleep()`-based async tests — use fake async or deterministic seams.
3. Tests that depend on wall-clock time, locale of the dev machine, or
   network. Inject `now`, set the locale, stay offline.
4. Golden image tests in CI (font rendering differs across runners).
5. `skip` without a named harness gap (see §3.3).
6. New tests that duplicate an existing file's coverage — check first
   (the inventory in §2.1 is the index).

## 8. Maintenance

- This document is reviewed whenever a new audit lands; the finding→test map
  (§5) and regression list (§6) are append-only.
- When a P1 gap in §2.2/§3.2 is closed, move its row into §5/§6.
- Test counts are informational; branch coverage of security-critical pure
  functions (conflict rules, permission maps, guards, validators) is the
  metric that matters.
