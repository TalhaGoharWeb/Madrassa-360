# Security & Hard-Coded-Identity Audit — Madrasa 360

**Repo:** `~/workspace/madrassa-360` · **Package:** `al_markaz_al_islami`
**Audit date:** 2026-09-25 · **Scope:** audit only, no fixes, nothing committed
**Method:** full-tree grep of `lib/`, `assets/`, `android/`, `ios/`, `macos/`, `windows/`, `linux/`, `web/`, root docs, `supabase/`, gradle/xcode/cmake configs, `.gitignore`, git-tracked files.

> **Secret values are never printed.** They are shown as `[REDACTED]` with `file:line` + exposure path only.

---

## Executive Summary

- **2 CRITICAL findings, both involving the Supabase `service_role` key**: (1) the **real anon key and the real service_role key are committed verbatim** in `SUPABASE_INTEGRATION_PLAN.md:105,107`; (2) the app calls the **Supabase Admin Auth API from client code** using a `SUPABASE_SERVICE_KEY` from the bundled `.env` (`lib/providers/user_management_provider.dart:129,240`).
- **High:** plaintext hard-coded mock credentials (`admin123`/`teacher123`/`parent123`) still live in `lib/core/services/auth_service.dart`; auth session tokens persist in **plaintext SharedPreferences** (supabase_flutter default); photo uploads **ignore** the declared type/size validation.
- **Identity:** the repo is in a *split-identity* state — runtime identity is currently `Khawaja Educational System / Qili Piranwali` (`lib/core/config/madrassa_config.dart`), while package/Bundle identifiers, store manifests, seed SQL, docs, and the widget test still say **Al Markaz al Islami Kasur / al_markaz_al_islami**. The SaaS goal is NOT met; per-client editing still requires a code change (that part is documented as intentional single-file config — acceptable only if bundle identity is also parameterized at build time).
- `.gitignore` is well-configured (`.env`, `key.properties`, `*.jks`/`*.keystore` excluded; only `assets/.env.example` tracked). No keystore/key.properties committed. No key values in Dart/SQL — but the keys **are** in a committed markdown file.

---

## Top-10 Ranked Findings

| # | Sev | Finding | Evidence |
|---|-----|---------|----------|
| 1 | **CRITICAL** | Real Supabase **anon key + service_role key committed** in repo docs | `SUPABASE_INTEGRATION_PLAN.md:105` (`SUPABASE_ANON_KEY=[REDACTED]`), `:107` (`Service role key=[REDACTED]`) — `git ls-files` confirms tracked; URL `https://ffhsrnkvjjedvclfwgmr.supabase.co` in the open |
| 2 | **CRITICAL** | Client app calls **Admin Auth API with service_role key** (god-mode key shipped in mobile app) | `lib/providers/user_management_provider.dart:129` `final serviceKey = dotenv.env['SUPABASE_SERVICE_KEY'] ?? '';`, `:138-146` `http.post(... 'apikey': serviceKey, 'Authorization': 'Bearer $serviceKey', ...)` against `$supabaseUrl/auth/v1/admin/users`; same pattern at `:240-247` (delete user). Any extracted key = full auth-admin power from a decompiled APK |
| 3 | **HIGH** | Hard-coded plaintext demo credentials in live source | `lib/core/services/auth_service.dart:61` `'password': 'admin123'`, `:69` `'teacher123'`, `:77` `'parent123'` — `_mockUsers` map still present despite `kUseSupabase = true` / "mock data has been removed for production" comment in `app_config.dart` |
| 4 | **HIGH** | Auth session tokens stored in plaintext (SharedPreferences, no secure enclave) | supabase_flutter persists session via SharedPreferences on Android (XML in app sandbox, plaintext on rooted devices). No `flutter_secure_storage` dependency. `enableBiometricAuth = false` in `app_config.dart:37`; `rememberMeEnabled = true` (`app_config.dart:66`). Parallel legacy pattern: `StorageKeys.userToken = 'user_token'` in `lib/core/services/storage_service.dart:200` |
| 5 | **HIGH** | File-upload validation defined but **never enforced**; storage path built from user filename | `lib/providers/student_provider.dart:89-98` `uploadPhoto()`: `final ext = photo.name.split('.').last.toLowerCase();` → `final path = 'students/$studentId.$ext';` — no check against `allowedImageExtensions` / `maxImageSizeKB` (defined in `app_config.dart:59-62`), no magic-byte/content-type validation. `studentId` interpolated into the object path unsanitized. `image_picker` used in 3 screens + 2 providers with no validation layer |
| 6 | **HIGH** | Secrets shipped via bundled `assets/.env` — extractable from any built APK; hard crash on missing keys | `lib/core/services/supabase_service.dart:26` `await dotenv.load(fileName: 'assets/.env');`, `:29-32` `url: dotenv.env['SUPABASE_URL']!` / `anonKey: dotenv.env['SUPABASE_ANON_KEY']!` — anything in `assets/` is trivially readable from a decompiled APK/AAB. `.env` itself is **not** currently committed (only `assets/.env.example` tracked) — but the mechanism is fragile; also note the file is marked `assets:` in `pubspec.yaml:53-55` |
| 7 | **MEDIUM** | Hard-coded institution identity in platform manifests (Android label, iOS display name, bundle names, seed SQL) | `android/app/src/main/AndroidManifest.xml:7` `android:label="المرکز الاسلامی قصور"`; `ios/Runner/Info.plist:10` `<string>المرکز الاسلامی قصور</string>`, `:16` `<string>al_markaz_al_islami</string>`; `pubspec.yaml:1` `name: al_markaz_al_islami`, `:2` description "Al Markaz al Islami Kasur…"; seed SQL `supabase/04_seed.sql:201-214` emails `admin@almarkazalislamikasur.pk` etc. (inside a `/* … */` comment block); `test/widget_test.dart:20` expects text `'Al Markaz al Islami Kasur'` |
| 8 | **MEDIUM** | **Split identity**: runtime config says a *different* institution than the bundle identifiers | `lib/core/config/madrassa_config.dart:25` `nameUrdu = 'خواجہ ایجوکیشنل سسٹم'`, `:28` `nameEnglish = 'Khawaja Educational System'`, `:31/34` city `قلعی پیرانوالی` / `Qili Piranwali`, `:39` `email = 'info@khawajaeducational.com'`, `:42` `phone = '+92-300-1234567'` (placeholder), `:45` `website = 'https://khawajaeducational.com'` — while bundle IDs/package stay `al_markaz_al_islami` / `com.madrasa360.*`. Phone `+92-300-1234567` is a placeholder, not a real number (Low privacy impact) |
| 9 | **MEDIUM** | Developer PII hard-coded in About screen (real email + real phone, shipped to end users) | `lib/presentation/screens/common/about_screen.dart:15` `const _devName = 'Muhammad Talha Farid';`, `:16` `const _devEmail = 'goharenaqshband@gmail.com';`, `:17` `const _devPhone = '03287819000';`, `:18` `const _production = 'HijaziApps Production';` — shown/copyable in-app (Clipboard). `url_launcher` present (`pubspec.yaml:36`) so these likely become `mailto:`/`tel:` links |
| 10 | **LOW** | Hard-coded placeholder image URLs; stale mock residue | `lib/data/repositories/storage_repository.dart:36,40,50` `https://via.placeholder.com/150` (external dependency + tracking surface); `lib/providers/madrasa_provider.dart:69` `// Optimistic add for demo`; `lib/core/constants/app_strings.dart:2`, `app_colors.dart:4` header comments still say "Al Markaz al Islami Kasur" |

---

## 1. Secrets & Credentials

### 1.1 Keys committed in docs (CRITICAL — Finding #1)
- `SUPABASE_INTEGRATION_PLAN.md:105` — full **anon key** (`[REDACTED]`), tied to `https://ffhsrnkvjjedvclfwgmr.supabase.co`.
- `SUPABASE_INTEGRATION_PLAN.md:107` — full **service_role key** (`[REDACTED]`), printed as a bare line: `Service role key=[REDACTED]`.
- **Exposure path:** committed in git (`git log` shows it since the initial commit), so every clone/fork/archive of this repo contains a full-admin key. File is a root-level doc — indexable if the repo is public.
- **Required action:** rotate BOTH keys in Supabase Dashboard → API immediately; then purge from git history (`git filter-repo`) — deleting the file in a new commit is NOT enough.

### 1.2 Service-role key used from the client (CRITICAL — Finding #2)
- `lib/providers/user_management_provider.dart:129` — `final serviceKey = dotenv.env['SUPABASE_SERVICE_KEY'] ?? '';`
- `lib/providers/user_management_provider.dart:138-146`:
  ```dart
  final uri = Uri.parse('$supabaseUrl/auth/v1/admin/users');
  final response = await http.post(
    uri,
    headers: {
      'Content-Type':  'application/json',
      'apikey':        serviceKey,
      'Authorization': 'Bearer $serviceKey',
    },
    body: jsonEncode({
      'email':         account.email,
      'password':      account.password,
      'email_confirm': true,          // skip confirmation email
      'user_metadata': {'name': account.name},
      'app_metadata':  {'role': account.roleName},
    }),
  );
  ```
- Same credential reused for auth-user deletion at `:240-247`.
- `SUPABASE_SERVICE_KEY` is **not** in `assets/.env.example` — the template only documents `SUPABASE_URL`/`SUPABASE_ANON_KEY` — so it is either missing at runtime (dead feature with Urdu error at `:132-136`) or present undocumented. Either way the design places a god-mode key on the device.
- **Required action:** move user create/delete to a Supabase Edge Function (or backend) that holds the service_role key server-side; client calls it with the user's own JWT; enforce admin-role checks in the function.

### 1.3 How credentials are loaded (mechanism — HIGH, Finding #6)
- `lib/core/services/supabase_service.dart:24-33` — `init()` loads `assets/.env` via `flutter_dotenv`, then `Supabase.initialize(url: dotenv.env['SUPABASE_URL']!, anonKey: dotenv.env['SUPABASE_ANON_KEY']!)`.
- `assets/.env` is **not** committed (only `assets/.env.example` is tracked — `git ls-files` verified), and `.gitignore` excludes `*.env`, `assets/.env`, `assets/*.env`.
- Problems: (a) non-null assertion `!` → hard crash on missing keys instead of a graceful error; (b) `assets/` content is bundled into the APK and trivially extractable (apktool/unzip), so **any** secret in `assets/.env` is public the moment the app ships — acceptable only for the anon key, never for `SUPABASE_SERVICE_KEY`.
- Comment at `:30-31` claims "Use implicit flow" but the code doesn't set `authFlowType`; supabase_flutter default is PKCE — the comment is stale/misleading.

### 1.4 What is NOT found (verified clean)
- No `service_role` values in any `.dart`, `.sql`, `.yaml`, CI config (the only SQL hits are policy comments at `supabase/05_new_modules.sql:329,333` — `TO service_role` role names, not keys).
- No `assets/.env` in the repo or in git. No keystore (`.jks`/`.keystore`), no `key.properties`, no `google-services.json`, no `GoogleService-Info.plist` anywhere.
- `README.md` setup section (`:148`) uses placeholders (`SUPABASE_URL=https://your-project-id.supabase.co`), no real keys.

---

## 2. Hard-Coded Institution Identity (SaaS blocker analysis)

| String found | File:line | Context | Action for generic SaaS |
|---|---|---|---|
| `name: al_markaz_al_islami` | `pubspec.yaml:1` | Dart package name (imports everywhere, e.g. `lib/presentation/widgets/attendance/student_attendance_tile.dart:2-5`) | **Rename package** → e.g. `madrasa_360`; mechanical but repo-wide (imports, widget_test, Info.plist) |
| `description: "Al Markaz al Islami Kasur - A unified ERP…"` | `pubspec.yaml:2` | Pub metadata | Rewrite generic |
| `android:label="المرکز الاسلامی قصور"` | `android/app/src/main/AndroidManifest.xml:7` | App name shown on Android launcher | Must come from per-tenant build flavor / `--dart-define` |
| `com.madrasa360.madrasa_360` | `android/app/build.gradle.kts:9,24` | namespace / applicationId | Fine as vendor ID (Madrasa 360 is the product), keep |
| `<string>المرکز الاسلامی قصور</string>` (CFBundleDisplayName) | `ios/Runner/Info.plist:10` | iOS home-screen name | Same as Android label — flavorize |
| `<string>al_markaz_al_islami</string>` (CFBundleName) | `ios/Runner/Info.plist:16` | iOS bundle name | Rename with package |
| `PRODUCT_BUNDLE_IDENTIFIER = com.madrasa360.madrasa360` | `ios/Runner.xcodeproj/project.pbxproj:371` | iOS bundle ID | Keep (product ID, not institution) |
| `VALUE "CompanyName", "com.madrasa360"` etc. | `windows/runner/Runner.rc:55-60` | Windows version resource: CompanyName/ProductName/FileDescription/`madrasa_360` | CompanyName fine; ProductName generic — OK |
| `set(BINARY_NAME "madrasa_360")`, `APPLICATION_ID "com.madrasa360.madrasa_360"` | `linux/CMakeLists.txt:7,10` | Linux build | Generic — OK |
| `PRODUCT_NAME = madrasa_360`, bundle `com.madrasa360.madrasa360` | `macos/Runner/Configs/AppInfo.xcconfig:8,11` | macOS | Generic — OK |
| `"name": "madrasa_360"` / `apple-mobile-web-app-title: madrasa_360` | `web/manifest.json:2-3`, `web/index.html:26,32` | Web PWA | Generic — OK |
| `admin@almarkazalislamikasur.pk` (+ teacher/parent variants) | `supabase/04_seed.sql:201-214` | Seed SQL role-setup block | **Inside `/* */` comment** — not executed, but institution-specific; parameterize or drop |
| `expect(find.text('Al Markaz al Islami Kasur'), …)` | `test/widget_test.dart:20` | Widget test asserts the OLD institution name | Will fail against current `MadrassaConfig`; rewrite against generic |
| Header comments "Al Markaz al Islami Kasur Urdu Strings"/"Color Palette" | `lib/core/constants/app_strings.dart:2`, `app_colors.dart:4` | Comments only | Cosmetic; rewrite |
| README title `# 🕌 Madrasa 360 — Al Markaz al Islami Kasur`; plan header `> **App:** Al Markaz al Islami Kasur — Madrasa 360` | `README.md:1,22`, `SUPABASE_INTEGRATION_PLAN.md:3` | Docs | Rewrite generic |

**Already-generic or acceptable:** all bundle/application IDs under `com.madrasa360.*` (product vendor, not institution); Windows/macOS/Linux product metadata (`madrasa_360`); web manifest/title; Android deep-link scheme `io.supabase.madrasa360` (`AndroidManifest.xml:41`).

**The Khawaja split (Finding #8):** `lib/core/config/madrassa_config.dart` — the documented "single source of truth … edit ONE file to deploy for a new madrassa" — currently contains a **different, real-looking** identity: `Khawaja Educational System`, `Qili Piranwali` (`قلعی پیرانوالی`), `info@khawajaeducational.com`, `https://khawajaeducational.com`, and placeholder phone `+92-300-1234567`. So the running app brands itself Khawaja while its package/manifests still say Al Markaz. For true SaaS this config must become either (a) fetched per-tenant from the backend at login, or (b) injected via `--dart-define`/flavors — never requiring a source edit per customer.

**Note on `app_config.dart` docstring:** `lib/core/config/app_config.dart:1-11` claims identity "read from MadrassaConfig — single source of truth" — true for strings, but platform labels/bundle names bypass it entirely (see table).

---

## 3. Auth Security

- **Mock credential store (HIGH, #3):** `lib/core/services/auth_service.dart:55-84` — `_mockUsers` with `'password': 'admin123'` / `'teacher123'` / `'parent123'`, emails `admin@madrasa360.pk` etc., phones `03001234567/8/9` (`:65,73,81`). `login()` (`:92-127`) does plaintext comparison with a 1s artificial delay. Dead under `kUseSupabase = true` but present in shipped source.
- **Live auth path:** `lib/data/repositories/auth_repository.dart:144` `signInWithPassword(email:, password:)` — delegates to Supabase (bcrypt server-side, no local hashing — correct). `_mapAuthError` (`:213`) returns generic Urdu messages — good (no user-enumeration beyond Supabase defaults).
- **No password-reset flow implemented** in Dart: `ApiEndpoints.forgotPassword`/`resetPassword` (`app_config.dart:112-113`) are dead legacy strings; no `resetPasswordForEmail` call anywhere in `lib/`. Users cannot reset passwords from the app.
- **Password policy:** `minPasswordLength = 6` (`app_config.dart:45`), enforced in user creation at `user_management_provider.dart:119-121`. Weak by modern standards; no complexity rules.
- **Session:** Supabase session restore via `auth_provider.dart:78-85` + `auth_repository.getSessionUser()` (`:177-189`). Session persists by SDK default in plaintext SharedPreferences — see #4. `sessionTimeoutMinutes = 30` (`app_config.dart:65`) is declared but **no enforcement code** found (no timer/invalidator in `lib/`).
- **Biometric/PIN:** none. `enableBiometricAuth = false`; no `local_auth` dep; no PIN storage code.

## 4. Input / Upload Validation

- Photo upload (`student_provider.dart:89-98`) — **no** extension allow-list check, **no** size check, extension from attacker-influenced filename, `studentId` interpolated into storage path. Staff/profile photos follow the same unvalidated pattern (`staff_provider.dart`, `profile_screen.dart` import `image_picker`).
- No WebView usage anywhere in `lib/` (grep clean) — no JS-bridge risk.
- No raw SQL in Dart (no `sqflite` in deps; no `execute(`/`rawQuery(`/SELECT strings). All queries go through the Supabase client builder (parameterized).
- Storage buckets/policies: `supabase/03_storage.sql` defines buckets; **RLS policies on `storage.objects` were not reviewed** — flag for Phase 15 (if `student-photos` bucket is public-read/write with anon key, any key holder can enumerate/replace photos).

## 5. Platform Configs

| Platform | Finding |
|---|---|
| Android | `android:label="المرکز الاسلامی قصور"` hard-codes institution (Medium). `INTERNET` + `ACCESS_NETWORK_STATE` permissions declared (expected). `signingConfig = signingConfigs.getByName("debug")` in release block (`build.gradle.kts:37`) — debug signing for release builds; **no release keystore configured** (keystore itself absent — fine for now, must be set up pre-release). No `debuggable=true`, no `usesCleartextTraffic` found anywhere |
| iOS | Display name + bundle name hard-code Al Markaz (Medium). Bundle ID `com.madrasa360.madrasa360` (fine). No ATS exceptions found |
| Windows | `Runner.rc` — CompanyName `com.madrasa360`, ProductName `madrasa_360`, icon `resources\app_icon.ico` — generic, OK. No institution-specific branding |
| macOS / Linux / Web | Product-name only (`madrasa_360`), generic — OK. Web title/meta is default Flutter placeholder text — cosmetic |
| Signing assets | No keystore/key.properties/firebase configs in repo or git — clean |

## 6. `.gitignore` Audit

**Verdict: good, with two small gaps.**
- Correctly excluded: `*.env`, `*.env.*`, `assets/.env`, `assets/*.env` (with `!*.env.example` / `!assets/.env.example` re-includes — the tracked example file is placeholder-only, verified clean); `**/android/key.properties`, `*.jks`, `*.keystore`, `*.key`, `*.pem`, `*.p12`, `*.p8`, `google-services.json`, `GoogleService-Info.plist`, build dirs, `.dart_tool/`.
- **Gap 1 (Low):** no `*.mobileprovision` exclusion is present… actually it IS (`*.mobileprovision` line 91). Real gap: **no exclusion for service-account JSONs** (e.g. `*-firebase-adminsdk-*.json`, `serviceAccountKey.json`) — a common Firebase admin-key leak vector.
- **Gap 2 (Low):** `assets/.env.example` is tracked and clean, but the committed `SUPABASE_INTEGRATION_PLAN.md` proves policy alone doesn't stop secret commits — consider a pre-commit hook (e.g. gitleaks) in Phase 15.

## 7. Logging / PII

- `grep` for `print(`/`debugPrint(` across `lib/`: only **1 raw `print(`** (`lib/providers/attendance_provider.dart`) and no `debugPrint` near auth prints tokens/passwords. Auth-adjacent logs are metadata-only: `'[Auth] resolved role: …'` (`auth_repository.dart:83`), `'[Auth] login error: $e'` (`:166` — could echo a Supabase error string containing the email; low), `'[UserMgmt] Auth user created: $authUserId'` (`user_management_provider.dart:166`), `'[UserMgmt] Auth delete failed: $e'` (`:249`). No token/password/key material logged.
- **Caution:** `debugPrint` is active in all builds (no `kDebugMode` guards on these lines) — visible via `adb logcat` on any connected device. Low severity today since no secrets are printed, but wrap auth logs in `kDebugMode` in Phase 15.

## 8. Assets

- `assets/` contains **exactly 2 files** — both fonts: `assets/Jameel Noori Nastaleeq Regular - [UrduFonts.com].ttf`, `assets/Jameel Noori Nastaleeq Kasheeda - [UrduFonts.com].ttf`. **No institution logo or branding image assets exist** in the repo (`AppConfig.logoImage` points to `assets/images/logo.png` which does not exist — missing asset, will throw at runtime if rendered).
- `windows/runner/resources/app_icon.ico` exists (app icon); content not visually inspected — flag for brand check in the identity rename pass.
- Institution-specific logo count: **0** (good — nothing to strip; but the missing `logo.png` must be resolved).

## 9. Dependency Risk (light)

`pubspec.yaml` deps: `supabase_flutter`, `flutter_dotenv`, `flutter_riverpod`, `shared_preferences`, `image_picker`, `cached_network_image`, `uuid`, `url_launcher`, `http`, `connectivity_plus`, `intl`, `google_fonts`. Nothing exotic or known-malicious; no WebView, no printing, no crypto packages. Two notes: (a) **`flutter_dotenv` + bundled `.env` is the wrong vehicle for secrets** (see §1.3); (b) **`shared_preferences` holds session/auth state** — migrate auth persistence to `flutter_secure_storage` (Android Keystore / iOS Keychain).

---

## Remediation Priority List (for Phase 2 / Phase 15 security hardening)

**P0 — do before any further distribution:**
1. **Rotate the Supabase anon key AND service_role key** (both committed at `SUPABASE_INTEGRATION_PLAN.md:105,107`), then purge the file from git history (`git filter-repo`) — a delete-commit is insufficient.
2. **Remove the service_role key from the client**: delete `SUPABASE_SERVICE_KEY` usage from `lib/providers/user_management_provider.dart:129,240`; move user create/delete to a Supabase Edge Function with server-side role checks.
3. **Delete** `lib/core/services/auth_service.dart` mock store (`admin123`/`teacher123`/`parent123`) — dead code with live credentials.

**P1 — hardening sprint:**
4. Migrate session/auth-token persistence to `flutter_secure_storage`; remove `StorageKeys.userToken` plaintext pattern; enforce the declared 30-min session timeout (currently unenforced).
5. Add server-side upload validation (validate MIME + magic bytes + size in the `student-photos` bucket policy or an Edge Function) and sanitize `studentId`/extension in `uploadPhoto` (`student_provider.dart:89`).
6. Strengthen password policy (min 8-10, complexity) and **implement password reset** (`resetPasswordForEmail`) — currently no reset path exists.
7. Audit `supabase/03_storage.sql` RLS policies on `storage.objects` for the photo buckets.

**P2 — SaaS identity work:**
8. Rename package `al_markaz_al_islami` → product name; move Android `label`, iOS `CFBundleDisplayName`/`CFBundleName` to build flavors or `--dart-define`; parameterize `supabase/04_seed.sql` emails; rewrite `test/widget_test.dart` expectation and README/plan headers.
9. Replace `madrassa_config.dart` source-edit deployment with per-tenant config from backend (or build-time defines); resolve the Khawaja-vs-AlMarkaz split; move developer contact PII out of the shipped About screen (or gate behind a build flag).
10. Add `*-firebase-adminsdk-*.json` / `serviceAccount*.json` to `.gitignore`; add a pre-commit secret scanner (gitleaks); wrap auth `debugPrint`s in `kDebugMode`; replace `via.placeholder.com` URLs; add the missing `assets/images/logo.png` (or drop the reference).
