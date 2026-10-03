# Secrets & Sensitive Configuration Audit — Madrassa-360

- **Date:** 2026-10-03
- **Branch:** `redesign/ux-v2` (83 commits)
- **Scope:** entire repo — code, configs, docs, scripts, CI workflows, Edge Functions, tests, assets, and full git history
- **Rule:** no secret values are printed anywhere in this report. All values redacted.

## Verdict

No live server-only secret (service_role key, DB password, private key, cloud credential) exists in the
working tree or in any commit of this branch's history. The one historical incident (legacy Supabase JWT
keys committed) was redacted in-repo on 2026-09-25, but **dashboard-side revocation is unverified** —
that is the single most important open item. Everything else is hygiene-grade.

## Findings

### 1. [HIGH] Legacy Supabase JWT keys were committed — revocation unverified

- **Location:** incident documented in `docs/DEPLOYMENT.md` (§ "Revoke the OLD keys") and `docs/SECURITY_AUDIT.md`
  (8 `REDACTED` markers; keys introduced already-redacted as `***REDACTED-KEY-ROTATED-2026-09-25***`).
- **Problem:** At some point the legacy Supabase **anon + service_role** JWT keys were committed to the repo.
  In-repo values were scrubbed on 2026-09-25. A full-history scan of all 83 commits on `redesign/ux-v2`
  confirms no full-length legacy JWT (`eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9…`) exists in any commit —
  so there is nothing left to purge from *this* branch's history.
- **Why it matters:** Anyone who cloned the repo while the keys were present still has the **service_role**
  key: full bypass of RLS, read/write any tenant's data, manage Auth users. Scrubbing the repo does not
  revoke the key.
- **Attack scenario:** Attacker with an old clone uses the leaked service_role key against
  `https://<project-ref>.supabase.co` to dump all tenants' student/fee records and create a platform admin.
- **Fix:** Complete the `docs/DEPLOYMENT.md` checklist and confirm each step:
  1. Supabase Dashboard → Project Settings → API Keys → **Revoke** the old legacy JWT keys.
  2. Verify the old keys return 401.
  3. Confirm the app + Edge Functions run on the new publishable/secret keys.
  4. Only then is this finding closed. (History purge is likely unnecessary for this branch — verified clean —
     but check any other remotes/branches if they ever existed.)

### 2. [MEDIUM] Shared demo password documented in repo

- **Location:** `demo/DEMO_README.md:28` (and the accounts table below it) — a single shared password for
  five demo Auth accounts, value `[REDACTED — see file]`.
- **Problem:** Test-only credential committed to the repo. Harmless if those accounts exist only on a
  throwaway demo project; dangerous if any of them exist on the **live** project, where anyone with
  repo access (it's a public-cloneable GitHub repo) can sign in.
- **Attack scenario:** Attacker signs into the live project with a documented demo account that was never
  removed, then explores whatever tenant/data it can reach.
- **Fix:** Ensure the five demo accounts exist **only** on a non-production demo project. If any exist on
  live, delete them or rotate to per-account random passwords stored outside the repo. Consider replacing
  the documented password with "ask the team" and seeding demo users via the `manage-users` Edge Function.

### 3. [LOW] Production builds ship with `ENVIRONMENT=development`

- **Location:** `lib/core/config/app_config.dart:85` —
  `String.fromEnvironment('ENVIRONMENT', defaultValue: 'development')`.
- **Problem:** Neither `.github/workflows/build-android.yaml` nor `build-windows.yaml` passes
  `--dart-define=ENVIRONMENT=production`, so every shipped build evaluates `isDevelopment == true`.
  Today `isDevelopment`/`isProduction` gate nothing in `lib/`, so there is no live misbehavior — but it is
  a trap: the first future `if (isDevelopment)` debug bypass (verbose logging, mock data, disabled
  certificate pinning) would silently ship to production.
- **Fix:** Add `--dart-define=ENVIRONMENT=production` to both build workflows (and `staging` where
  applicable). One-line change, zero behavior change today.

### 4. [LOW] Edge Functions send `Access-Control-Allow-Origin: *`

- **Location:** `supabase/functions/_shared/guard.ts:11-15` (`CORS_HEADERS`).
- **Problem:** Wildcard CORS on all five Edge Functions. Authentication is via `Authorization: Bearer <JWT>`
  (not cookies), so `*` cannot leak credentials cross-origin and CSRF impact is minimal — but it is still
  broader than necessary, especially with a Flutter **web** build in the repo (`web/` exists).
- **Fix:** Restrict `Access-Control-Allow-Origin` to the app's real origins (`https://madrassa360.com`,
  localhost dev ports). Keep `POST, OPTIONS` method allow-list as-is.

## Verified clean (no finding)

| Check | Result |
|---|---|
| Supabase service_role key in Flutter client | Absent. Client reads only `SUPABASE_URL` + `SUPABASE_ANON_KEY` from gitignored `assets/.env` (`lib/core/services/supabase_service.dart:26-30`). Client-side service-key usage was removed 2026-09-25 (note in `lib/providers/user_management_provider.dart:4`). |
| Edge Function secrets | All via `Deno.env.get(...)`: `SUPABASE_SERVICE_ROLE_KEY` (`_shared/guard.ts:41`), `FCM_SERVICE_ACCOUNT`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL` (`send-notification/index.ts:317,391-392`). Nothing hardcoded. |
| `.env` committed | No. `.gitignore` excludes `*.env`, `assets/.env`; only `.env.example` / `assets/.env.example` / `android/key.properties.example` are tracked, all placeholders. |
| Private keys / cloud credentials | None in tree or history: no `BEGIN PRIVATE KEY`, no `AKIA…`, no `AIza…`, no `ghp_…`/`github_pat_`, no `postgres(ql)://` URLs, no `google-services.json` / `GoogleService-Info.plist` (no Firebase client config — FCM is server-side only). |
| GitHub workflows | All secrets via `${{ secrets.X }}` (`build-android.yaml`, `build-windows.yaml`). Keystore decoded to a CI-only path, `key.properties` generated at build time and never committed. |
| Credentials in logs | `lib/core/observability/app_logger.dart` implements real redaction (`password\|token\|secret\|api[_-]?key\|authorization\|bearer…` → `***REDACTED***`), applied to messages, context, errors and stack traces. No log line observed emitting a credential. |
| Credentials in tests | None in `test/` or `integration_test/`. |
| Insecure HTTP | No `http://` URLs in `lib/`; `AndroidManifest.xml` sets no `usesCleartextTraffic` (defaults to HTTPS-only). |
| Hardcoded production URLs | None in `lib/` — Supabase URL comes from `assets/.env` (local) or CI secrets (builds). |
| Installer | `installer/madrassa360.iss` intentionally contains no keys/passwords/certs (per `installer/README.md:75`). |
| Webhooks | None in use; no webhook secrets to manage. |
| Demo seed SQL | `demo/seed_demo_madrassa.sql:17` keeps passwords out of the script by design. |

## Notes (public-by-design, confirm understanding)

- The **Supabase anon key** ships inside the APK/AAB/EXE (bundled `assets/.env`, written by CI from GitHub
  Secrets). This is correct and expected: the anon key is public; all real protection comes from RLS and
  server-side checks. Never "fix" this by trying to hide the anon key — fix RLS instead.
- The Supabase **project ref** (`ffhsrnkvjjedvclfwgmr`) appears in docs and one test string. It is not a
  secret (it is embedded in the public anon JWT and URL).
- `docs/DEPLOYMENT.md`, `docs/SECURITY_AUDIT.md`, `SUPABASE_INTEGRATION_PLAN.md` reference key *patterns*
  (`eyJhbGciOi...`) only as documentation of the rotation procedure — no values present.

## Remediation checklist (specify — not yet implemented)

1. [ ] **Rotate & revoke (human, Supabase dashboard):** finish the `docs/DEPLOYMENT.md` key-rotation
    checklist; confirm old legacy JWT keys are revoked and return 401. This closes finding #1.
2. [ ] **Demo accounts (human):** audit Auth users on the live project for the five documented demo emails;
    delete them from live or move them to the demo project. Closes finding #2.
3. [ ] **Build config (code):** in `.github/workflows/build-android.yaml` and `build-windows.yaml`, add
    `--dart-define=ENVIRONMENT=production` to the `flutter build` invocations. Closes finding #3.
4. [ ] **CORS (code):** in `supabase/functions/_shared/guard.ts`, replace `"*"` with the explicit origin
    allow-list. Closes finding #4.
5. [ ] **Dashboard settings (human, not in repo — verify):** Supabase Auth → redirect URLs allow-list
    contains only the app's real URLs; email confirmation enabled as intended; password policy set;
    JWT expiry reviewed. None of this is visible in the repo, so it must be checked in the dashboard.
6. [ ] **Ongoing:** keep `assets/.env` and `android/key.properties` out of git (already ignored); never paste
    the DB password or keys in chat (the 2026-09-26 DB-password paste is still owed a rotation — tracked
    separately).

## Rotation list (credentials to rotate / verify rotated)

| Credential | Where it appeared | Status |
|---|---|---|
| Legacy Supabase anon + service_role JWT keys | Committed pre-2026-09-25; scrubbed in-repo, documented in `docs/DEPLOYMENT.md` | **UNVERIFIED — revoke in dashboard, confirm 401** |
| Supabase DB password | Pasted in chat 2026-09-26 (not in repo) | **Owed — rotate in dashboard** |
| Demo accounts shared password | `demo/DEMO_README.md:28` | Rotate/delete if accounts exist on live |
| Android keystore + passwords | GitHub Secrets `ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD` | No exposure found — no action |
