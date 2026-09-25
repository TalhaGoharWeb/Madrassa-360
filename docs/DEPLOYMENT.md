# Madrassa-360 Deployment Guide

How we build, sign, and ship Madrassa-360: environments, secrets, migrations,
Edge Functions, and the release process. Pipeline definitions live in
`.github/workflows/`.

## 1. Environments

| Environment | Supabase project | App backend | Purpose |
|---|---|---|---|
| **dev** | personal / local `supabase start` | `.env` / `assets/.env` with dev keys | Daily development |
| **staging** | `madrassa360-staging` project | staging `SUPABASE_URL` + anon key | Pre-release QA, migration dry-runs |
| **prod** | `madrassa360-prod` project | prod `SUPABASE_URL` + anon key | Real schools |

What differs per environment:

- **Supabase project** — separate project refs, separate `SUPABASE_URL` and keys.
  The Flutter client only ever needs `SUPABASE_URL` + `SUPABASE_ANON_KEY`
  (see `.env.example`); these are injected per environment at build time.
- **Edge Function secrets** — set per project with `supabase secrets set`
  (see §4). Each project gets its own `SUPABASE_SERVICE_KEY`, and the service
  key is rotated independently per project.
- **`platform_config`** — the platform-level configuration row (download URLs,
  feature flags, maintenance mode) is maintained per environment. The prod row
  is updated on every release with the new artifact URLs (see §6).

Never point a dev or staging build at the prod Supabase project.

## 2. Secrets management

### GitHub Secrets (CI release signing)

| Secret | Content |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The release keystore file, base64-encoded (`base64 -w0 android/keystore.jks`) |
| `KEYSTORE_PASSWORD` | Keystore (store) password |
| `KEY_ALIAS` | Key alias (e.g. `madrassa360`) |
| `KEY_PASSWORD` | Key password |

The `build-android` workflow decodes the keystore to `android/keystore.jks`
and writes `android/key.properties` from these secrets **inside the runner**;
both files are gitignored and never committed. The workflow fails fast if any
of the four secrets is missing, so a release can never silently ship with the
debug signing key.

Local release signing (developer machine, when you actually need a signed
build): `cp android/key.properties.example android/key.properties`, fill in
real values, and build. Create the keystore once on a secure machine:

```bash
keytool -genkeypair -v -keystore android/keystore.jks \
    -alias madrassa360 -keyalg RSA -keysize 2048 -validity 10000
```

Back the keystore up **off the machine, encrypted** (losing it means you can
never update the Play Store listing). Then base64 it into
`ANDROID_KEYSTORE_BASE64`.

### Supabase secrets

- The **anon key is public-by-design** — it ships in the client and is protected
  by Row Level Security, never by secrecy.
- The **service_role key must ONLY live in Edge Function secrets**
  (`supabase secrets set SUPABASE_SERVICE_KEY=...`). It must never appear in
  the Flutter client, in `.env` files, or in the repo.
- ⚠️ A `SUPABASE_SERVICE_KEY` was committed to this repo's history at one point
  (see `supabase/functions/README.md`). Rotate it in the Supabase dashboard
  (Project Settings → API → regenerate service_role key) **before** deploying
  Edge Functions to any environment.

### Key rotation runbook (do this first, before any staging deploy)

If API keys were ever committed to git (as happened in this repo's history),
treat them as public and rotate:

1. **Create the new keys** — Supabase Dashboard → Project Settings → API Keys
   → "Create new API key". Create one **publishable** key and one **secret** key.
   Copy both somewhere safe (password manager, not chat, not email).
2. **Revoke the OLD keys** — in the same API Keys page, find the old keys
   (the legacy JWT ones starting with `eyJhbGciOi...`, matching what was
   committed) → **Revoke**. Verify the old keys stop working; nothing in
   production should be using them.
3. **Point the app at the new publishable key** — on your dev machine, create
   `assets/.env` (gitignored, never committed) from `assets/.env.example`:
   ```
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=<new publishable key>
   ```
   The Flutter client reads only this file. The service/secret key must NEVER
   go here.
4. **Point Edge Functions at the new secret key** — Dashboard → Edge Functions
   → Secrets → set `SUPABASE_SERVICE_ROLE_KEY` to the new **secret** key
   (or `supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<new secret key>`).
   Redeploy the functions afterwards.
5. **Purge git history** — after revocation, rewrite history to remove every
   trace of the old keys (e.g. `git filter-repo --invert-paths` on the file,
   or BFG Repo-Cleaner on the key strings), then force-push. Everyone
   re-clones; old clones must be discarded.
6. **Confirm** — `git log -p --all | grep eyJhbGci` returns nothing, the old
   keys are revoked in the dashboard, and the app + functions work with the
   new keys.

## 3. Database migrations

Migrations live in `supabase/migrations/` and run **in numeric order**:

```
001_tenant_core.sql        007_tenant_rls.sql        013_auth_cleanup.sql
002_tenant_settings.sql    008_tenant_storage.sql    014_finance.sql
003_tenant_modules.sql     009_tenant_indexes.sql    015_parent_links.sql
004_memberships.sql        010_tenant_seed.sql       016_sync.sql
005_rbac.sql               011_licensing.sql         017_notifications.sql
006_tenant_retrofit.sql    012_audit_logs.sql        018_platform_config.sql
```

Every migration is syntax-checked in CI (`sql` job: `pglast`), but that only
proves the SQL parses — always dry-run on staging first.

### Applying to staging

```bash
# link once: supabase link --project-ref <staging-ref>
supabase db push          # applies pending migrations in order
```

or paste each file, in order, into the Supabase SQL editor. `010_tenant_seed.sql`
contains seed data — review it before running against anything shared.

### Applying to prod

Only after staging is green: same `supabase db push` against the prod project
ref, during a maintenance window if the migration rewrites tables.

## 4. Edge Functions

Functions live in `supabase/functions/` (`provision-tenant`, `manage-tenant`,
`export-tenant`, `send-notification`; `_shared/` is library code). CI runs
`deno check` + `deno lint` on every `*/index.ts`.

### Deploy

```bash
supabase functions deploy provision-tenant --project-ref <ref>
supabase functions deploy manage-tenant    --project-ref <ref>
supabase functions deploy export-tenant    --project-ref <ref>
supabase functions deploy send-notification --project-ref <ref>
```

### Secrets per environment

```bash
supabase secrets set SUPABASE_URL="https://<project-ref>.supabase.co" \
                    SUPABASE_SERVICE_KEY="<service-role-key>" \
                    --project-ref <ref>
```

Functions read secrets only from `Deno.env` — nothing is hardcoded.

### First platform-owner bootstrap

There is no self-service sign-up for platform admins. After the platform
owner's user has signed up in the app (so `auth.users.id` exists), bootstrap
them directly in SQL as the DB owner / service role:

```sql
insert into public.platform_admins (user_id, role)
values ('<auth.users.id of the platform owner>', 'platform_owner');
```

Full details: `supabase/functions/README.md`.

## 5. CI/CD pipelines

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yaml` | push to any branch, PRs | `flutter analyze`, `dart format` check, `flutter test`, `dart tool/no_mock_check.dart`, pglast parse of all migrations, `deno check` + `deno lint` on Edge Functions. Jobs are independent (fail-fast off) so all results report. |
| `build-windows.yaml` | manual dispatch, `v*` tags, or called by release | `flutter build windows --release`, compiles `installer/madrassa360.iss` with Inno Setup, uploads `Madrassa360-Setup-<version>.exe` (version from the root `version.json`,
the release source of truth). |
| `build-android.yaml` | manual dispatch, `v*` tags, or called by release | Proper release signing from GitHub Secrets, then `flutter build apk --release` + `flutter build appbundle --release`; uploads APK + AAB. |
| `release.yaml` | push of a `v*` tag | Verifies tag == `version.json`, runs the full CI suite, builds both platforms, auto-generates notes from commits since the previous tag, creates the GitHub Release attaching `Madrassa360-Setup-<version>.exe`, `app-release.apk`, `app-release.aab`, and `version.json` as version metadata. |

Flutter is pinned to **3.47.4** (stable) in every workflow via
`subosito/flutter-action@v2`; bump the `FLUTTER_VERSION` env in all four files
together when upgrading. The Windows installer name comes from the root
`version.json` (the release source of truth; `assets/version.json` is the
runtime copy read by `UpdateService`).

## 6. Release process

1. **Bump versions** — update the root `version.json` (`version` + `build`;
   the single release source of truth, also bundled as a runtime asset and
   read by `UpdateService`) and `pubspec.yaml` (`version: X.Y.Z+N`)
   in the same commit.
2. **Merge to the release branch** and confirm `ci.yaml` is green.
3. **Tag:** `git tag vX.Y.Z && git push origin vX.Y.Z` (tag must equal
   `v` + the root `version.json`'s version — `release.yaml` enforces this and
   fails otherwise).
4. **The release workflow** runs CI, builds the Windows installer and the
   signed Android APK/AAB, and publishes the GitHub Release with artifacts.
5. **Update the prod `platform_config` row** (`key = 'default'`, created by
   migration `018_platform_config.sql`) with the new release's download URL and
   version — this is what the Windows auto-update check reads pre-login:

   ```sql
   update public.platform_config
   set latest_version = 'X.Y.Z',
       download_url   = 'https://github.com/<org>/<repo>/releases/download/vX.Y.Z/Madrassa360-Setup-X.Y.Z.exe',
       release_notes  = '<short changelog>',
       updated_at     = now()
   where key = 'default';
   ```
6. **Smoke-test** the installer and the APK on staging before announcing.

## 7. Checklist for a new environment

- [ ] Supabase project created (dev / staging / prod)
- [ ] Migrations applied in order 001 → 018 (staging dry-run before prod)
- [ ] Service-role key rotated if the environment was ever bootstrapped from the old committed key
- [ ] Edge Function secrets set per project; functions deployed
- [ ] First platform owner bootstrapped via SQL (§4)
- [ ] `platform_config` row created for the environment
- [ ] GitHub Secrets for Android signing present (prod releases)

## 8. Staging acceptance runbook (Phase 7)

Run these **in order** against the staging project. Nothing here is optional;
each step gates the next. Record the result of every step (pass/fail + notes)
in the staging run log before proceeding to prod.

1. **Apply migrations 001–018.** `supabase db push` against the staging
   project ref (or paste each file in numeric order into the SQL editor).
   Review `010_tenant_seed.sql` before running — it contains seed data.
   `018_platform_config.sql` creates the `platform_config` row the
   auto-update check reads.
2. **Deploy the Edge Functions** (4: `provision-tenant`, `manage-tenant`,
   `export-tenant`, `send-notification` — see §4) and set the per-project
   secrets (`SUPABASE_URL`, `SUPABASE_SERVICE_KEY`) with `supabase secrets set`.
3. **Bootstrap the first platform owner** via the SQL in §4
   (`insert into public.platform_admins … 'platform_owner'`). There is no
   self-service sign-up for platform admins.
4. **Run the cross-tenant isolation suite:**
   `supabase/tests/cross_tenant_isolation.sql` — all 30 assertions must be
   green (Tenant A/B × Admin/Teacher matrix + escalation + storage +
   stale-policy guard). Any red assertion is a release blocker.
5. **Execute the offline test checklist** in `docs/OFFLINE_SYNC.md`
   ("How to test offline mode — checklist", 10 items): seed → airplane mode
   → crash mid-queue → reconnect → normal conflict → financial conflict →
   retry/dead-letter → tenant switch → logout → future-date guard.
6. **Record results.** Keep the staging run log (date, app version, who ran
   it, per-step pass/fail, log-file excerpts for any failure) — it is the
   evidence the §60 checklist in `docs/PRODUCTION_READINESS.md` cites.

## 9. Observability & log collection (Phase 7)

### Log file locations

All client logs are written by `AppLogger`
(`lib/core/observability/app_logger.dart`) under the per-OS
application-support directory, inside a `Madrassa360/logs` folder — next to
the Drift database, never under Program Files:

| OS | Location |
|---|---|
| Windows | `%APPDATA%\Madrassa360\logs\madrassa360.log` |
| Android | the app's internal application-support dir (`path_provider`), `Madrassa360/logs/madrassa360.log` |
| iOS / macOS | `~/Library/Application Support/<bundle>/Madrassa360/logs/madrassa360.log` |
| Linux | `~/.local/share/<app>/Madrassa360/logs/madrassa360.log` |

Rotation: at most 5 files × 2 MiB (`madrassa360.log`, `madrassa360.1.log` …
`madrassa360.4.log`); the oldest is dropped. Crash reports go to
`logs/crashes/crash_<timestamp>.log` (written by `AppLogger.logCrash`).

To collect logs from a device: pull the whole `Madrassa360/logs` folder
(Windows: copy the folder; Android: `adb` / in-app export — no exporter
exists yet, that is future work).

### What never gets logged

`AppLogger.redact` masks values for keys matching
`password|passwd|pwd|token|secret|api[_-]?key|authorization|bearer|private[_-]?key`,
including inline `key=value` / `key: value` fragments inside free-form
strings (error messages, stack traces, URLs). By convention, callers must
additionally never put into logs:

- service-role or anon keys, session tokens, password-reset links;
- CNIC numbers, salaries, or other staff/student PII in message strings;
- full database row payloads (log ids and counts, not contents).

The `AppException.technicalDetails` field is log-only by design — the error
boundary (`lib/core/errors/error_boundary.dart`) returns only the
user-safe Urdu/English message to the UI, never the technical details.
`avoid_print` is enforced in `analysis_options.yaml`: all diagnostics go
through `AppLogger`, never `print`/`debugPrint`.

### Health metrics

`HealthMetrics` (`lib/core/observability/health_metrics.dart`) keeps
per-device counters in SharedPreferences (`health.*` keys):
`crash_free_sessions`, `sync_failures_24h`, `auth_failures_24h`,
`api_errors_24h`. They are surfaced on the Master Admin dashboard
("Client health (this device)" card). **Fleet-wide aggregation does not
exist yet** — it is a future Edge Function that devices would POST
`toMap()` summaries to.
