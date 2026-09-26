# Testing & CI Guards — Madrasa-360

**Last reviewed:** 2026-09-25 (Phase 8, branch `feature/testing-security`).
Honest status first: **no test suite has been observed green in this environment** — there is no
Flutter/Dart toolchain here and no live Supabase project. What follows describes what exists,
how to run it where it can run, and what still requires staging.

---

## 1. Unit + widget tests (`flutter test`)

**Honest status: never observed green here** — no Flutter/Dart toolchain in this environment.
Suites (all written Phase 8 against the real implementation; test seams are `@visibleForTesting`
extractions with unchanged algorithms):

| Location | Files | Covers |
|---|---|---|
| `test/widget_test.dart` | 1 | Phase-4 branding/module-gating: `TenantBranding` fallback carries no institution identity, `buildNavTabs` module gating, dashboard helpers, `TenantNameText`/`TenantLogo` widgets |
| `test/app_logger_test.dart` | 1 | `AppLogger.redact()` secret-masking (pure Dart) |
| `test/unit/` | 8 files, 110 tests | fee calc helpers, attendance %, result grading + dense positions, `TenantContext` resolution, permission matrix, sync conflict decision rules, backup manifest checksum, license status vocabulary |
| `test/widget/` | 6 files | login validation/loading/error, tenant picker, `MasterAdminGuard` deny path (fail-closed), attendance bulk actions, reports hub empty states |

```bash
flutter pub get
flutter test
```

Known doc correction (2026-09-25): `test/widget_test.dart` is NOT a stale smoke test —
it was rewritten in Phase 4 and asserts the identity purge (e.g. `findsNothing` for the old
institution name). An earlier draft of this doc described it wrongly; the file is current.

## 2. No-mock-data guard

User requirement: **no mock/demo/fake data may ship in a release build.** `tool/no_mock_check.dart`
(pure Dart, no Flutter imports) scans `lib/` and exits non-zero if any banned identifier appears
(`Mock`, `mockData`, `fakeData`, `demoData`, `sampleData`, `dummyData`, `loremIpsum`), ignoring
`test/` and lines carrying an explicit `// mock-guard:allow` comment.

```bash
dart tool/no_mock_check.dart
```

Phase-8 check (manual replication — `dart` unavailable in this env, replicated the tool's
`\b(token)` regex logic over `lib/` by grep): **0 violations / 147 files.**

### Purge policy (what the guard enforces)

1. **Dead code** (mock helpers with zero references) → deleted.
2. **Live screens showing fake data** → rewired to real data (local Drift
   DB via the existing repositories/providers) with proper loading/empty/
   error states. Where a real source genuinely doesn't exist yet, the
   screen shows an explicit empty state + `// TODO(phase-8)` — never
   invented numbers or names.
3. **Legitimate dev-only helpers** (SQL seeds) stay, but must be
   unreachable from production code:
   - `supabase/migrations/010_tenant_seed.sql` carries a
     `DEV / STAGING ONLY — NEVER RUN IN PRODUCTION` banner; nothing in
     `lib/` references or executes it (verified by grep).
   - `supabase/04_seed.sql` is a manual SQL-Editor script and is
     intentionally skipped by the migration runbook (`docs/DATABASE.md`).

### Known gaps (honest list)

- The migration runbook (`docs/DATABASE.md` §"Applying") already excludes `010_tenant_seed.sql`
  from the production glob (`grep -v '010_tenant_seed'`); production exclusion additionally rests on
  the file's dev-only banner and its demo-user guard. (An earlier draft of this doc claimed the glob
  included it — corrected 2026-09-25.)
- `flutter analyze` / `flutter test` were not run for the Phase-6 purge
  (no Flutter toolchain in the sandbox) — run them in CI before merging.

## 3. SQL migration checks (pglast)

Every file in `supabase/migrations/` must parse with `pglast` (libpg_query):

```bash
pip install pglast
for f in supabase/migrations/*.sql; do
  python3 -c "import sys, pglast; pglast.parse_sql(open(sys.argv[1]).read())" "$f" || echo "FAIL: $f"
done
```

**Parse-validated ≠ applied.** Parsing catches syntax errors only — it says nothing about policy
correctness, which is what the isolation suite is for (§4).

## 4. Cross-tenant isolation suite (SQL, staging-only)

`supabase/tests/cross_tenant_isolation.sql` — 1217 lines, 44 assertions (A1–A44) + 9 contract
guards (G1–G9), self-labeled **NOT YET EXECUTED**. Negative security tests (Tenant A vs Tenant B ×
roles, escalation negatives, storage prefix isolation, permission boundaries, parent isolation via
`student_guardians`, platform_config protection, finance immutability, stale-policy sweep) + a
positive control. Run as `postgres` on a **fresh staging project** with migrations 001–018 applied:

```bash
psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/cross_tenant_isolation.sql
```

Expected: `NOTICE: PASS: …` per assertion, ending `ALL CROSS-TENANT ISOLATION TESTS PASSED`.
The script ends with `ROLLBACK` (staging left untouched); any `FAIL` raises an EXCEPTION.
This is the **only** test that can move §60 items 3–6 toward "pass" — and it has never run.

## 5. Edge Functions (Deno)

`supabase/functions/` — `provision-tenant`, `manage-tenant`, `export-tenant`, `send-notification`
(+ `_shared/guard.ts`). **Missing:** the `manage-users` function the client invokes for
privileged auth-user ops (`lib/providers/user_management_provider.dart:152`) — it must be written and
deployed; until then the call fails closed with an honest error.

```bash
deno check supabase/functions/<name>/index.ts && deno lint supabase/functions/<name>/index.ts
```

Deployment (staging, then prod) per `docs/DEPLOYMENT.md` §§8–9; bootstrap the first
`platform_admins` row via SQL before anything else (see `supabase/functions/README.md`).

## 6. Offline/sync acceptance (staging)

Per `docs/OFFLINE_SYNC.md` checklist: enqueue offline → reconnect → push/pull converges →
conflict rules → retry/dead-letter behavior. **Never observed end-to-end.** The real conflict rule
(correcting earlier docs that said "latest revision wins"): normal entities — server row newer by
`updated_at` → take server, else rebase the local op onto the fresh `base_revision` and retry the RPC
exactly once; financial entities → **never overwrite** → park in `sync_conflicts` → manual review.

## 7. What CI runs (`.github/workflows/ci.yaml`)

Six independent jobs on every push/PR (`workflow_call`-reusable from `release.yaml`):

1. **analyze** — `flutter pub get` + `flutter analyze`
2. **format** — `dart format --set-exit-if-changed lib test tool`
3. **test** — `flutter test`
4. **mock-guard** — `dart tool/no_mock_check.dart`
5. **sql** — pglast parse of every `supabase/migrations/*.sql`
6. **deno** — `deno check` + `deno lint` on every function (skips `_shared`)

Status: **exists in-branch, never observed green** — CI has not run against a pushed branch yet.

## 8. What requires staging (the pre-"pass" list)

Nothing below has happened yet. This is the ordered runbook (`docs/DEPLOYMENT.md` §§8–9
has the full version):

1. Provision a fresh Supabase staging project.
2. Apply migrations 001–018 **in order** (idempotent; 007 must print the "legacy-policy sweep clean" notice).
3. Deploy the 4 Edge Functions; write + deploy `manage-users`.
4. Bootstrap the first `platform_admins` row.
5. Run `supabase/tests/cross_tenant_isolation.sql` green (§4).
6. Run the Flutter client against staging: sign-in, password-reset round-trip, logout + session expiry, offline-sync checklist, upload a photo, trigger an audit row, run the Master Admin tenant-provision flow.
7. Rotate the committed keys (see `docs/SECURITY_AUDIT.md` P0) — the current keys must be considered public.
8. Record all results in `docs/PRODUCTION_READINESS.md` — only then may §60 verdicts change from "code-complete" to "pass".
