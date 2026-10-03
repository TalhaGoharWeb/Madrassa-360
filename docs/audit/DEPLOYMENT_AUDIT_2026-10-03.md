# Production Deployment Audit — Madrassa-360

- **Date:** 2026-10-03
- **Branch:** `redesign/ux-v2` (commit `945dce7`)
- **Method:** read-only review of workflows, configs, code, and docs. Dashboard-side facts (Supabase console settings, PITR status, key revocation) cannot be verified from the repo and are flagged as operator-checklist items.
- **Companion reports:** `docs/audit/security/SECURITY_AUDIT_2026-10-03.md`, `docs/audit/security/raw/secrets.md` (secrets detail — not duplicated here).

## Verdicts by area

| # | Area | Verdict | Evidence |
|---|------|---------|----------|
| 1 | HTTPS/TLS | ✅ READY | No `http://` endpoints in app code paths; no `usesCleartextTraffic` in `android/app/src/main/AndroidManifest.xml`; no `NSAppTransportSecurity` exception in `ios/Runner/Info.plist` (platform default = HTTPS-only). Supabase URLs are `https://*.supabase.co`. |
| 2 | Environment config | ⚠️ RISK | Required keys (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) documented in `assets/.env.example`, loaded via `flutter_dotenv` in `SupabaseService.init()`. **BUT:** `AppConfig.environment` defaults to `'development'` via `String.fromEnvironment('ENVIRONMENT', defaultValue: 'development')` and **no build workflow passes `--dart-define=ENVIRONMENT=...`** — release builds self-report as `development`. Currently nothing reads `isDevelopment`/`isProduction` outside `app_config.dart` itself, so no live insecure fallback today; any future env-gated behavior will silently misbehave. |
| 3 | Missing-config fail-safe | ✅ READY | Build workflows **fail loudly**: `build-android.yaml` and `build-windows.yaml` both `exit 1` with an explicit error when `SUPABASE_URL`/`SUPABASE_ANON_KEY` GitHub secrets are unset ("The APK would otherwise ship without backend config and show the crash screen on launch"). At runtime, `SupabaseService.init()` uses `dotenv.env['SUPABASE_URL']!` — a missing key throws inside `_bootstrap()`, which `main()` catches and routes to `CrashScreen` with a restart action (fail-loud, no silent dev fallback). |
| 4 | Build modes / debug flags | ✅ READY | Release builds use `flutter build apk --release` / `flutter build appbundle --release` / `flutter build windows --release`. `debugShowCheckedModeBanner: false` set in both `main.dart:240` and `crash_screen.dart:49`. Debug/test APK is an explicit `workflow_dispatch` `build_type=debug` path, documented "for on-device testing only, never for distribution", and skips AAB + signing. |
| 5 | Obfuscation / source maps | ⚠️ RISK | **No `--obfuscate --split-debug-info` on any release build** (`build-android.yaml`, `build-windows.yaml`). Release binaries ship with readable Dart symbol names; reverse-engineering and stack-trace harvesting are easier than they need to be. No source maps generated or shipped (nothing to secure — but also no de-obfuscation story). |
| 6 | CORS | ⚠️ RISK | `supabase/functions/_shared/guard.ts:12` sets `Access-Control-Allow-Origin: *` with `Access-Control-Allow-Headers: authorization, x-client-info, apikey, content-type` on **every** Edge Function response, including privileged ones (`manage-users`, `manage-tenant`, `provision-tenant`). All six functions require a valid JWT, so a random site cannot call them without a stolen token — but a wildcard on admin functions is unnecessary exposure and any future non-authenticated endpoint inherits it. |
| 7 | Security headers | ⚠️ GAP | Edge Functions return JSON only; no `Strict-Transport-Security`, `X-Content-Type-Options`, or other hardening headers set in `guard.ts`. (CSP is N/A for the mobile/desktop clients, which is the shipped surface.) |
| 8 | DB migrations | ✅ READY (process) / ⚠️ RISK (rollback) | 44 migration files, numeric ordering, `supabase db push` applies pending in order (`docs/DEPLOYMENT.md:125`). Staging-first discipline documented: dry-run on staging project before prod (`docs/DEPLOYMENT.md:119–133`, §8 staging runbook). Migrations 029–044 add pre-flight checks in `MIGRATION_NOTES_029_044.md`. **Rollback = restore from backup; there are no down-migrations** (`docs/DATABASE.md:79`: "No down-migrations; rollback = restore from backup (document your backup before applying)"). A bad migration on prod means PITR/restore, not a clean `db push` reversal. |
| 9 | Backups | ⚠️ RISK | Client-side story is strong: `docs/BACKUP_RESTORE.md` — per-tenant SQLite backup with WAL checkpoint, deterministic SHA-256 manifest, verify/restore UI in `backup_screen.dart`, plus server-side `export-tenant` for master-admin offboarding. **Server-side (Supabase Postgres + Storage) recovery has no written, tested procedure**: PITR is assumed but undocumented; no restore runbook, no RPO/RTO, no drill record. `tenant-exports` bucket privacy is an unverified dashboard item (live-apply list). |
| 10 | Monitoring / health checks | 🔴 GAP | No `/health` endpoint on any Edge Function; no liveness probe for the backend. Client-side `lib/core/observability/health_metrics.dart` records crash-free sessions and sync failures **on-device only** (visible on the Master Admin dashboard card of that device). No alerting, no webhooks, no centralized dashboard — a dead Edge Function or a sync-breaking migration is discovered by user complaints. |
| 11 | Rate limiting | ⚠️ RISK | `guard.ts` gained a `rateLimit()` helper + 429 responses (security fix wave), but **only `send-notification` calls it** (30 broadcasts/hr, 120 targeted/hr). `manage-users`, `manage-tenant`, `provision-tenant`, `export-tenant`, `upload-image` have no rate limiting — password-reset/account-provisioning endpoints are the most abuse-sensitive. |
| 12 | Crash reporting | 🔴 GAP | No Sentry/Crashlytics/remote reporter in release. `AppLogger().logCrash()` writes to on-device logs only (`health_metrics.dart` notes a real reporter as "out of scope"). Release crashes are invisible to the team. |
| 13 | CI/CD integrity | ⚠️ RISK | Strong: `release.yaml` runs full `ci.yaml` before builds, verifies `version.json` matches the `v*` tag, minimal `permissions` (contents:read / write-only-where-needed), `flutter pub get --enforce-lockfile`, `pubspec.lock` + `deno.lock` committed, pglast migration syntax check, Deno check+lint, no-mock guard. **Weak spots:** (a) all GitHub Actions use floating major tags (`actions/checkout@v4`, `flutter-action@v2`, `setup-deno@v2`, `softprops/action-gh-release@v2`) — not SHA-pinned, so a compromised upstream tag is a supply-chain risk; (b) **Windows installer is unsigned** — `installer/madrassa360.iss` contains no `SignTool` directive, so every release exe triggers Windows SmartScreen warnings and has no tamper-evidence; (c) no environment protection rules visible in-repo (manual `workflow_dispatch` can ship a build to anyone with repo access). |
| 14 | APK/AAB signing | ✅ READY | Release signing is proper: keystore decoded from `ANDROID_KEYSTORE_BASE64` secret, `key.properties` generated in-workflow, both gitignored; a pre-build step `exit 1`s if any of the four signing secrets is missing. Keystore itself stays out of the repo (also confirmed `git ls-files` clean by the tests worker). |
| 15 | Dependency installation | ✅ READY | Reproducible: `--enforce-lockfile` on every `flutter pub get`, committed `pubspec.lock` and `deno.lock`, `dart run build_runner build` runs in CI so generated code never drifts. |
| 16 | Deployment secrets | ✅ READY (repo) / 🔴 GAP (dashboard) | No live server-only secret in the working tree or branch history (verified by `raw/secrets.md` full-history scan). Build-time `.env` (only `SUPABASE_URL` + anon key — the anon key is public-by-design) is written from GitHub secrets into gitignored `assets/.env` and never committed. **Open dashboard items from the secrets audit:** legacy JWT keys were once committed and scrubbed in-repo on 2026-09-25, but **dashboard-side revocation is unverified** — anyone with an old clone still holds a service_role key (full RLS bypass). DB password rotation owed since 2026-09-26. |
| 17 | Rollback strategy — mobile | ⚠️ RISK | No staged rollout, no in-app force-update/min-version gate (`grep` for force-update/minAppVersion: none). A bad release can only be fixed by cutting a new release and asking users to install it. Play Console staged rollout is available for the AAB path but is not part of the documented process. |
| 18 | Rollback strategy — Edge Functions | ⚠️ RISK | `supabase functions deploy` overwrites; there is no versioned deploy or one-command rollback documented. Recovery = redeploy the previous commit's code (requires the commit to be identified and redeployed manually). |
| 19 | Rollback strategy — migrations | ⚠️ RISK | See #8: no down-migrations; rollback = Supabase PITR or backup restore. PITR restore wipes writes made after the restore point — on a live multi-tenant system this needs a maintenance window and tenant communication, neither of which is scripted. |

## Silent-fallback check (the hard rule)

The app must **fail safely and loudly** when required configuration is missing — never silently fall back to insecure development behavior. Result of the sweep:

- ✅ **Build time:** missing `SUPABASE_URL`/`SUPABASE_ANON_KEY` secrets → workflow `exit 1` with an explicit error (`build-android.yaml`, `build-windows.yaml`). Missing signing secrets → `exit 1`. No defaults, no fallbacks.
- ✅ **Runtime startup:** `SupabaseService.init()` dereferences `dotenv.env[...]` with `!`; a missing key throws into `_bootstrap()` → `main()` shows `CrashScreen` with restart. Loud, no dev-backend fallback.
- ⚠️ **Environment flag:** `AppConfig.environment` silently defaults to `'development'` in every release build because no workflow sets `--dart-define=ENVIRONMENT=production`. Today nothing branches on it, so no live insecure path — but it is a latent trap: the first feature that checks `isDevelopment` to enable a debug behavior will silently enable it in production. **Fix: pass `--dart-define=ENVIRONMENT=production` in release builds (or remove the default and require the define).**
- ✅ No `kDebugMode`-gated security bypasses found in `lib/` (only `debugShowCheckedModeBanner: false`, which is cosmetic).
- ✅ No hardcoded dev API URLs or fallback keys in `lib/` (grep for `localhost`, `127.0.0.1` in non-test code: none found in the config path).

## PRODUCTION CHECKLIST — go/no-go for every release

### A. Source integrity (before tagging)
- [ ] Release cut from an exact CI-green commit (`ci.yaml` 6/6 green on that commit) — record the SHA.
- [ ] `version.json` == `pubspec.yaml` version == tag `v<version>` (enforced by `release.yaml`).
- [ ] `git status` clean on the release tree; no `.env` or `key.properties` tracked (`git ls-files | grep -i env`).
- [ ] CHANGELOG / release notes reviewed for migration + breaking-change callouts.

### B. Configuration & secrets
- [ ] GitHub Actions secrets present: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` (build fails loudly without them — still verify before a timed release).
- [ ] **`ENVIRONMENT=production` dart-define added to release builds** (pending fix — until then, confirm no code branches on `isDevelopment`).
- [ ] Supabase dashboard: legacy JWT keys revoked (owed — the committed-keys incident); **DB password rotated** (owed since 2026-09-26).
- [ ] Supabase Auth → URL Configuration: redirect allow-list contains only `io.supabase.madrasa360://login-callback` (+ `madrassa360://auth-callback`) and real site URLs — no `localhost`, no `*`.
- [ ] Storage: `tenant-exports` bucket is private (verify in dashboard).

### C. Database
- [ ] Migrations applied to **staging first** via `supabase db push`; app smoke-tested against staging.
- [ ] Pre-flight checks for the migration batch run on staging (e.g., 039 backfill-null, 042 dedup queries per `MIGRATION_NOTES_029_044.md`).
- [ ] Migration ledger on staging == expected count (`select count(*) from supabase_migrations.schema_migrations`).
- [ ] **Fresh backup / PITR restore point confirmed before touching prod** (document the timestamp).
- [ ] Then apply to prod, re-run ledger count + `test/db/*.sql` verification scripts.

### D. Edge Functions
- [ ] `deno check` + `deno lint` green; `deno.lock` unchanged unexpectedly.
- [ ] Deploy to staging project first; run the function smoke tests (auth rejection, permission denial, happy path).
- [ ] Deploy to prod; note the previous deployed commit SHA for manual rollback.

### E. Builds & signing
- [ ] CI green → `release.yaml` builds Windows installer + APK + AAB.
- [ ] **Windows exe code-signed** (pending fix — currently unsigned; document the SmartScreen caveat in release notes until signed).
- [ ] APK/AAB signed with the release keystore (verify `apksigner verify` / Play Console upload success).
- [ ] Record artifact names, byte sizes, SHA-256 hashes, and the Actions run URLs in the release notes.

### F. Rollout & monitoring
- [ ] Publish AAB via **Play staged rollout** (start 10%) where applicable; direct APK/exe via the release page with the SHA-256 beside each download.
- [ ] Smoke-test the signed artifacts on a real device (install → login → fee collection → receipt) before announcing.
- [ ] Post-release watch: no crash-reporting exists yet — actively solicit install feedback in the first 24h; check Supabase Auth/DB error logs in the dashboard.
- [ ] Rollback plan written in the release notes: for a bad client → cut a fix release (no force-update exists); for a bad function → redeploy prior commit; for a bad migration → PITR/restore with maintenance-window script.

## Prioritized fixes

**HIGH**
1. **Verify legacy JWT key revocation + rotate the DB password** (dashboard, manual). A leaked service_role key nullifies every database fix in this audit. — `raw/secrets.md` §1.
2. **Add crash reporting** (Sentry or Crashlytics) to release builds. Right now production crashes are invisible; every other monitoring investment is blind without this.
3. **Sign the Windows installer** (code-signing certificate + `SignTool` in `installer/madrassa360.iss`). Unsigned exes train users to click through SmartScreen — the exact habit malware relies on.
4. **SHA-pin GitHub Actions** (or use Dependabot for action updates). Floating `@v4`/`@v2` tags are a supply-chain single point of failure on the release path.

**MEDIUM**
5. Pass `--dart-define=ENVIRONMENT=production` in release builds; audit/remove the `'development'` default. (Latent silent-fallback trap.)
6. Write and drill the **Supabase PITR restore runbook** (who triggers, verification queries, maintenance-window tenant comms). Untested restores fail when needed.
7. Extend `rateLimit()` to `manage-users`, `provision-tenant`, `manage-tenant`, `export-tenant`, `upload-image` (only `send-notification` is covered today).
8. Replace wildcard CORS with an allow-list for the privileged Edge Functions (keep `*` only where a public, unauthenticated endpoint genuinely needs it).
9. Add a `/health` (or status) endpoint + a lightweight uptime check so a dead function pages someone instead of waiting for user complaints.
10. Add `--obfuscate --split-debug-info` to release builds (store the symbol files as CI artifacts, not in the shipped binaries).

**LOW**
11. Set `Strict-Transport-Security` / `X-Content-Type-Options` on Edge Function JSON responses in `guard.ts`.
12. Add an in-app min-version / force-update gate so a bad release can be retired without relying on users to notice.
13. Document Play staged-rollout as the default AAB publish path in `docs/DEPLOYMENT.md`.

## What is already solid (don't regress)

- Build fails loudly on missing secrets/config; runtime fails loud at startup via `CrashScreen` — no silent insecure fallbacks found in the config path.
- `release.yaml` gates everything on full CI + version/tag match with minimal workflow permissions.
- Release APK/AAB signing via gitignored keystore material; reproducible installs (`--enforce-lockfile`, committed lockfiles).
- Staging-first migration discipline documented; per-tenant client backup with checksums and verify/restore UI.
- No cleartext traffic on Android/iOS; release builds have no debug banner; debug builds are explicitly non-distributable.
