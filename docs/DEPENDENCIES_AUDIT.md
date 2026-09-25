# DEPENDENCIES_AUDIT.md — Dependencies, Tests, CI & Build Config Audit

**Repo:** `~/workspace/madrassa-360` · **Audited:** 2026-09-25 (PKT) · **Scope:** audit only, no code changes
**Mission context:** MASTER MISSION §39/§61/§65–66 requires a production Windows .exe + installer, GitHub Actions CI (analyze/format/test/build for Windows + Android), code signing, no secrets in client, version management.

---

## 1. Executive Summary (5 bullets)

1. **Dependency graph is small and healthy:** 12 direct runtime deps, all within their current major lines (verified against `pubspec.lock`, 125 resolved packages). One advisory checked: `image_picker_android` resolves to `0.8.13+1`, which is *above* the patched `0.8.12+18` for CVE-2024-54462 — **not vulnerable**. No other confirmed advisories on resolved versions.
2. **Test coverage is functionally zero:** exactly one test file (`test/widget_test.dart`) containing a single smoke test that pumps the full app — no unit tests, no widget tests beyond login-screen strings, no `mockito`/`mocktail`, no `integration_test`. CI has nothing meaningful to run.
3. **CI is absent:** there is no `.github/` directory at all — no workflows for analyze, format, test, or builds (file:line N/A, verified via `ls`).
4. **Android release build is NOT shippable:** `release` block signs with the **debug key** (`android/app/build.gradle.kts:36-37`, with a TODO comment admitting it), no `key.properties`/`.jks` exists in-repo, `versionCode` is `1` (from `1.0.0+1` in `pubspec.yaml:5`), minify+ProGuard is enabled but `image_picker` has no `CAMERA`/`READ_MEDIA_IMAGES` permissions declared — photo upload will break on Android 13+ unless Photo Picker is used.
5. **Windows release build has no distribution path:** `BINARY_NAME "madrasa_360"` builds, but `Runner.rc:92-98` carries placeholder branding (`CompanyName "com.madrasa360"`, `FileDescription "madrasa_360"`), and there is **no installer config of any kind** (no Inno Setup `.iss`, no MSIX packaging) and **no code signing** (verified via `find` across repo).

---

## 2. pubspec.yaml — Full Dependency Table

Source: `pubspec.yaml:1-58`. Resolved versions: `pubspec.lock`.

| Package | Constraint (`pubspec.yaml`) | Resolved (`pubspec.lock`) | Purpose | Risk notes |
|---|---|---|---|---|
| `flutter` (sdk) | sdk | — | Framework | — |
| `flutter_localizations` (sdk) | sdk | — | RTL/Urdu localization | — |
| `google_fonts` | `^6.1.0` (line 15) | 6.3.2 | UI typography | Runtime font downloads require network; fine. Minor line current. |
| `flutter_riverpod` | `^2.4.9` (line 18) | 2.6.1 | State management | Riverpod 3.x is a newer major (breaking); caret pins to 2.x so this is safe but ageing. No advisory. |
| `shared_preferences` | `^2.2.2` (line 21) | 2.5.3 | Local storage | Fine. |
| `connectivity_plus` | `^5.0.2` (line 24) | 5.0.2 | Network monitoring | connectivity_plus 6.x exists (breaking major); safe on 5.x. No advisory. |
| `intl` | `^0.19.0` (line 27) | 0.19.0 | i18n/date formatting | Pinned by `flutter_localizations` constraint — do NOT bump independently. |
| `supabase_flutter` | `^2.5.0` (line 30) | 2.12.0 | Backend: Auth + DB + Realtime | Major line current (2.x). Client library only; server-side CVEs (e.g. Supabase Auth CVE-2026-31813) do not apply to the client package. No advisory on resolved version. |
| `flutter_dotenv` | `^5.1.0` (line 31) | 5.2.1 | Loads `assets/.env` | **Architectural note:** `assets/.env` is bundled *inside* the shipped binary — every key in it is client-visible by design (see Security audit). Fine for anon key; must never hold the service_role key. |
| `cached_network_image` | `^3.3.1` (line 32) | 3.4.1 | Student/staff photo caching | CVE-2022-2091 ("Cache Images < 3.2.1") is a *WordPress plugin*, not this Dart package — not applicable. No advisory on 3.4.1. |
| `image_picker` | `^1.1.2` (line 33) | 1.2.1 | Photo capture/selection | **Advisory checked:** GHSA-98v2-f47x-89xw / CVE-2024-54462 (filename sanitization in `image_picker_android` 0.8.5+6–0.8.12+18). Lock resolves `image_picker_android` **0.8.13+1 > patched 0.8.12+18** → **not vulnerable**. Heavy native surface; see §4 permission gap. |
| `uuid` | `^4.4.0` (line 34) | 4.5.3 | Local UUID generation | Fine. |
| `url_launcher` | `^6.3.0` (line 35) | 6.3.2 | Email/phone/web links | Fine; deep-link scheme `io.supabase.madrasa360` registered in manifest (`AndroidManifest.xml:31-38`). |
| `http` | `^1.2.2` (line 36) | 1.6.0 | Direct Supabase Admin Auth REST calls | Calling Admin Auth API from the client implies a service_role key on-device — **critical secret-handling issue**, belongs in Security audit but flagged here because `http`'s only stated purpose (line 36 comment) is that call. |

### Dev dependencies (`pubspec.yaml:38-41`)

| Package | Constraint | Resolved | Verdict |
|---|---|---|---|
| `flutter_test` (sdk) | sdk | — | Present. The only test infra in the project. |
| `flutter_lints` | `^4.0.0` | 4.0.0 | Present but **1 major behind** current line (5.x/6.x); see §3 for how far the lint config is relaxed anyway. |
| `mockito` / `mocktail` | absent | — | **Missing.** No mocking library — unit-testing services/repos is not set up. |
| `integration_test` (sdk) | absent | — | **Missing.** No on-device/E2E test scaffolding. |

**Transitive-only packages worth noting:** `sqflite 2.4.2` (+ android/darwin variants) is in the lock via transitive deps; `realtime_client 2.7.0`, `gotrue`, `postgrest`, `storage_client` come in via `supabase_flutter 2.12.0` — all within current majors.

---

## 3. Tests — Coverage Verdict

| Item | Finding | Evidence |
|---|---|---|
| Test files in repo | **Exactly 1** | `find . -name '*_test.dart'` → `./test/widget_test.dart` only |
| `test/widget_test.dart` | Single smoke test, 30 lines, **not** the default counter template — custom: pumps `ProviderScope(child: Madrasa360App())` and asserts login-screen strings `'المرکز الاسلامی قصور'` and `'Al Markaz al Islami Kasur'` | `test/widget_test.dart:1-30` |
| Fragility risk | High: pumps the **entire app** (including Supabase init in `main()`), so the test fails without a configured `assets/.env`; also hard-codes exact UI strings — any copy change breaks it | `test/widget_test.dart:23-28` |
| Unit tests (services, repos, validators) | **0** | absent — verified via `ls test/` |
| Widget tests per screen | **0** | absent |
| `mockito`/`mocktail` | **Absent** | `pubspec.yaml` grep: absent |
| `integration_test` package / `integration_test/` dir | **Absent** | absent |
| CI test step | N/A — no CI | §6 |

**Verdict:** `flutter test` currently runs 1 fragile smoke test. Coverage of business logic (auth, RBAC, fees, attendance, Supabase repos) is **0%**. Before any CI `flutter test` gate is meaningful, the suite needs: (a) the smoke test decoupled from real Supabase init (env injection / test bootstrap), (b) unit tests for services/validators with `mocktail`, (c) the full-app pump kept but made hermetic.

---

## 4. `analysis_options.yaml` — Lint Strictness

File: `analysis_options.yaml` (37 lines). Includes `package:flutter_lints/flutter.yaml` (line 5), then **relaxes most of the value**:

| Rule | Setting | Note |
|---|---|---|
| `avoid_print` | `false` — allowed | "for debugging in Phase 1" (`analysis_options.yaml:20`) — print statements ship to release logs |
| `prefer_const_constructors` | `false` | Relaxed (`:21`) |
| `prefer_final_locals` | `false` | Relaxed (`:24`) |
| `use_key_in_widget_constructors` | `true` | Kept (`:34`) |
| `public_member_api_docs` | `false` | Relaxed (`:29`) |
| `avoid_dynamic_calls` | `false` | Relaxed (`:32`) |
| Excludes | `**/*.g.dart`, `**/*.freezed.dart` | For codegen that doesn't exist yet — harmless but aspirational |

**Verdict:** the config is `flutter_lints` **in name only** — the productive rules (`avoid_print`, const constructors, final locals) are disabled with "Phase 1" comments. A CI `flutter analyze` gate will pass on nearly anything today. Recommendation (for parent): flip to the full `flutter_lints` set (or `very_good_analysis`) before wiring the CI gate, or the gate is theater.

---

## 5. Android Build Audit

### 5a. `android/app/build.gradle.kts` (full read)

| Item | Value | File:line | Verdict |
|---|---|---|---|
| `applicationId` | `com.madrasa360.madrasa_360` | `build.gradle.kts:25` | OK (underscore form). Note `namespace` = same value (`:16`); Kotlin source dir `com/madrasa360/madrasa_360` matches. |
| `versionCode` / `versionName` | From `flutter.versionCode`/`versionName` → **1 / 1.0.0** | `build.gradle.kts:29-30`, `pubspec.yaml:5` (`version: 1.0.0+1`) | ⚠️ `versionCode 1` on a 1.0.0-branded app — Play Console rejects re-uploads of the same code; adopt a monotonic scheme (e.g. build number from CI) before first store upload. |
| `minSdk` / `targetSdk` | Deferred: `flutter.minSdkVersion` / `flutter.targetSdkVersion` | `build.gradle.kts:26-27` | Not pinned. On Flutter 3.22+ defaults → minSdk 23, targetSdk = latest. |
| Release signing | `signingConfig = signingConfigs.getByName("debug")` with `// TODO: Add your own signing config for the release build.` | `build.gradle.kts:34-37` | ❌ **Not production-shippable.** Release APK/AAB is signed with the debug key. No `key.properties` in repo (verified absent via `find`), no `.jks`/`.keystore` (absent; both gitignored in `.gitignore`). |
| Minify / shrink | `isMinifyEnabled = true`, `isShrinkResources = true`, ProGuard files wired | `build.gradle.kts:38-43` | OK; `proguard-rules.pro` has Flutter + Ktor/OkHttp keep rules (Supabase's underlying HTTP stack) — `proguard-rules.pro:1-18`. |
| Java/Kotlin | source/target 11, jvmTarget 11 | `build.gradle.kts:18-23` | OK. |
| NDK | `27.0.12077973` pinned | `build.gradle.kts:17` | OK (matches AGP/Flutter expectations). |

### 5b. `AndroidManifest.xml` (`android/app/src/main/AndroidManifest.xml`)

| Item | Value | Line | Verdict |
|---|---|---|---|
| `android:label` | `المرکز الاسلامی قصور` (Arabic) | 7 | OK for product; RTL launcher label fine. |
| Permissions | `INTERNET`, `ACCESS_NETWORK_STATE` only | 3-4 | ⚠️ **No `CAMERA` / `READ_MEDIA_IMAGES` / `READ_EXTERNAL_STORAGE`.** `image_picker` (`pubspec.yaml:33`) photo selection from gallery on Android 13+ requires `READ_MEDIA_IMAGES` (or the no-permission Photo Picker path — not guaranteed). Camera capture will crash without `CAMERA`. |
| Deep link | `io.supabase.madrasa360://login-callback` with `autoVerify` | 31-38 | OK — PKCE callback wired. |
| Impeller | `io.flutter.embedding.android.EnableImpeller = false` | 47-49 | Deliberate Skia fallback — perf tradeoff, documented choice. |
| `debuggable` | Not set in `main` manifest (debug manifests use default tooling) | — | OK — no `android:debuggable="true"` in release path. |

---

## 6. Windows Build Audit

| Item | Value | File:line | Verdict |
|---|---|---|---|
| `BINARY_NAME` | `madrasa_360` → `madrasa_360.exe` | `windows/CMakeLists.txt:7` | Builds. |
| App version in binary | From `FLUTTER_VERSION*` macros → 1.0.0+1 | `windows/runner/CMakeLists.txt:24-28` | OK — tracks `pubspec.yaml`. |
| `Runner.rc` branding | `CompanyName "com.madrasa360"` · `FileDescription "madrasa_360"` · `ProductName "madrasa_360"` · `OriginalFilename "madrasa_360.exe"` · `LegalCopyright "Copyright (C) 2026 com.madrasa360..."` | `windows/runner/Runner.rc:92-98` | ⚠️ Placeholder branding — the shipped .exe's Properties dialog shows `madrasa_360` / `com.madrasa360`, not "Madrasa 360" / "Al Markaz al Islami Kasur". Should be updated before release. |
| Installer (Inno Setup `.iss`) | **Absent** | verified via `find . -iname '*.iss'` | ❌ No installer config. |
| MSIX packaging | **Absent** | verified via `find` for `*msix*` | ❌ |
| Code signing (Authenticode) | **Not configured anywhere** | — | ❌ Unsigned .exe → Windows SmartScreen warnings on distribution. |
| Icon | `windows/runner/resources/app_icon.ico` exists | `windows/runner/resources/` | OK. |
| `GeneratedPluginRegistrant` / `generated_plugins.cmake` | Present, standard template | `windows/flutter/` | OK. |

**Verdict:** `flutter build windows` will produce an unsigned `madrasa_360.exe` with placeholder metadata and no installer — the mission's "production Windows .exe with installer" requires: (1) an Inno Setup `.iss` (or MSIX) added to the repo, (2) Authenticode signing wired (cert via CI secrets), (3) `Runner.rc` branding fixed, (4) version bumping automated.

---

## 7. CI Verdict

| Check | Result |
|---|---|
| `.github/` directory | **Does not exist** — verified via `ls` (file:line N/A) |
| `.github/workflows/` | **Does not exist** (consequence of above) |
| Analyze workflow | Absent |
| Format (`dart format --set-exit-if-changed`) workflow | Absent |
| Test (`flutter test`) workflow | Absent |
| Build workflows (windows / android) | Absent |
| Any other CI config (`.gitlab-ci.yml`, `azure-pipelines`, `codemagic.yaml`, `bitrise`) | Absent — repo root listing shows none |

**Verdict:** Zero CI. `IMPROVEMENTS.md:120` honestly lists "❌ Implement CI/CD pipeline" as an open item — consistent with reality. The remediation checklist (§9) gives the parent a concrete workflow spec.

---

## 8. SDK / Toolchain Constraints

| Item | Value | Evidence |
|---|---|---|
| Dart SDK constraint | `sdk: ^3.5.0` | `pubspec.yaml:7-8` |
| Assessment | **Very loose floor.** `^3.5.0` permits anything `<4.0.0`, so the lockfile can resolve against Dart 3.5-era toolchains. The mission target is Flutter 3.35+ / Dart 3.10. **Flutter is not installed in this sandbox**, so the actual local toolchain version could not be verified. | `flutter --version` → no output |
| README guidance | "Flutter SDK (3.5.0 or later)" | `README.md:130` |
| Recommendation | Raise constraint to `sdk: '>=3.10.0 <4.0.0'` (or `^3.10.0`) once the team standardizes on the mission toolchain, and pin the CI workflow to a specific Flutter channel/version. | — |

---

## 9. `.gitignore` Coverage

File: `.gitignore` (75 lines). Verdict: **thorough and correct.**

| Pattern | Present? | Line(s) |
|---|---|---|
| `build/` (`/build/`) | ✅ | 42 |
| `.dart_tool/` | ✅ | 40 |
| `*.jks`, `*.keystore` | ✅ | 52-53 |
| `**/android/key.properties` | ✅ | 50 |
| `*.env`, `*.env.*`, `assets/.env`, `assets/*.env` (+ `!*.env.example` keep) | ✅ | 60-68 |
| `*.key`, `*.pem`, `*.p12`, `*.p8` | ✅ | 70-73 |
| `google-services.json`, `GoogleService-Info.plist` | ✅ | 74-75 |
| `/android/app/debug|profile|release` build outputs | ✅ | 47-49 |
| `**/windows/flutter/ephemeral`, `**/linux/flutter/ephemeral` | ✅ | 57-58 |

**However** — `.gitignore` cannot protect against what is *already committed*. See §10, mismatch #1.

---

## 10. Docs-vs-Reality Mismatch Table

| # | Doc claim (quote) | Reality | Severity |
|---|---|---|---|
| 1 | `README.md:152` — "Never commit `assets/.env` to source control. It is explicitly ignored in [.gitignore](.gitignore) to prevent credential leakage." | `SUPABASE_INTEGRATION_PLAN.md:105-107` **commits a live `SUPABASE_ANON_KEY` and the `service_role` key in plaintext** inside the repo (`Service role key=eyJhbGciOi…` line 107). The ignore rule is honored for `.env` but the doc itself leaks both keys. Rotate both keys. | 🔴 Critical — secret leak, contradicts own README |
| 2 | `README.md:180` — "🤖 **Android**: Phones and Tablets (Android API 21+)" | `android/app/build.gradle.kts:26` defers to `flutter.minSdkVersion` (23 on Flutter ≥3.22; unverifiable here — Flutter not installed). The "21+" claim is at best unverified, likely wrong. | 🟡 Medium |
| 3 | `SUPABASE_INTEGRATION_PLAN.md:76-94` — dependency block: `supabase_flutter: ^2.5.0`, `flutter_dotenv: ^5.1.0`, `cached_network_image: ^3.3.1`, `image_picker: ^1.1.2`, `uuid: ^4.4.0` | Matches `pubspec.yaml:30-34` exactly (plus `url_launcher`/`http` added later). Consistent. Resolved versions (2.12.0 / 5.2.1 / 3.4.1 / 1.2.1 / 4.5.3) are newer minors — expected. | 🟢 Consistent |
| 4 | `IMPROVEMENTS.md:136-146` — "New Dependencies Added" lists `flutter_riverpod/shared_preferences/connectivity_plus/google_fonts/intl` with constraints | Matches `pubspec.yaml:15-27`. Consistent. | 🟢 Consistent |
| 5 | `IMPROVEMENTS.md:120` — "❌ Implement CI/CD pipeline" (open item) | True — no `.github/` exists. Honest. | 🟢 Consistent |
| 6 | `README.md:165-168` — setup: `flutter pub get` then `flutter run` | Works in principle, but `assets/.env.example` exists (`assets/.env.example`) while `README` step 2's `cp assets/.env.example assets/.env` is the only path to real credentials; running without `.env` fails at Supabase init — worth a troubleshooting note in README. | 🟡 Low |
| 7 | `web/manifest.json:2-3` — `"name": "madrasa_360"` | Placeholder PWA name, same branding gap as `Runner.rc`. README claims Web support (`README.md:182`). | 🟡 Low |

---

## 11. Remediation Checklist — CI/CD + Release Pipeline

For the parent to fold into PRODUCTION_READINESS / SAAS_GAP_ANALYSIS. Ordered by dependency:

**CI foundation**
- [ ] Add `.github/workflows/ci.yaml`: jobs `analyze` (`flutter analyze`), `format` (`dart format --output=none --set-exit-if-changed .`), `test` (`flutter test`) on `ubuntu-latest`, pinned Flutter version (e.g. `subosito/flutter-action` with explicit `flutter-version`).
- [ ] Fix `analysis_options.yaml` first — re-enable `avoid_print`, `prefer_const_constructors`, `prefer_final_locals` (currently disabled at `analysis_options.yaml:20-24`) or the analyze gate is theater.
- [ ] Make the one smoke test hermetic: inject test env / skip Supabase init in tests, or CI `flutter test` fails on missing `assets/.env`.
- [ ] Add `mocktail` to `dev_dependencies` and require unit tests for services/validators before the test gate is meaningful.

**Android release**
- [ ] Generate upload keystore **outside** the repo; store as GitHub Actions secret (`ANDROID_KEYSTORE_BASE64`, `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD`); add `android/key.properties` creation step in the workflow. Replace `signingConfigs.getByName("debug")` (`android/app/build.gradle.kts:36`) with the release signing config.
- [ ] Adopt monotonic `versionCode`: derive from CI run number or `git rev-list --count` instead of `pubspec` `+1`.
- [ ] Add `android:uses-permission` for `CAMERA` and `READ_MEDIA_IMAGES` (or document Photo Picker-only flow) — required by `image_picker` usage (`AndroidManifest.xml:3-4` gap).
- [ ] Build AAB (`flutter build appbundle --release`) in CI; Play App Signing handles final signing.

**Windows release**
- [ ] Add Inno Setup `.iss` installer script to repo (e.g. `windows/installer/madrasa360.iss`) — app name, version from CI, license file, start-menu/desktop shortcuts.
- [ ] Authenticode-sign the `.exe` and installer in CI (cert in secrets, e.g. Azure Trusted Signing — free tier — or a purchased cert; self-signed is not shippable).
- [ ] Fix `Runner.rc:92-98` branding: `CompanyName`, `FileDescription`, `ProductName` → real product names ("Madrasa 360", "Al Markaz al Islami Kasur").
- [ ] CI job `build-windows` on `windows-latest`: `flutter build windows --release`, sign, run Inno, upload installer artifact.

**Version management**
- [ ] Raise Dart constraint: `sdk: '>=3.10.0 <4.0.0'` (`pubspec.yaml:7-8`) to match the mission toolchain (Flutter 3.35+/Dart 3.10); pin the same version in CI.
- [ ] Automate version bumps (e.g. `pubspec.yaml:5` `1.0.0+N` driven by CI or a release script) — manual `+1` will collide on the Play Console.

**Secrets hygiene (cross-ref SECURITY_AUDIT)**
- [ ] 🔴 **Immediately:** rotate the Supabase `anon` and `service_role` keys leaked in `SUPABASE_INTEGRATION_PLAN.md:105-107`, then scrub/redact the doc. `.gitignore` is correct but cannot un-commit.
- [ ] Never put the service_role key in any client-reachable asset (`flutter_dotenv` bundles `assets/.env` into the binary); the `http`-to-Admin-Auth pattern (`pubspec.yaml:36` comment) must move server-side.

---

*End of DEPENDENCIES_AUDIT.md. Audit-only; no files were modified. All claims cite `file:line` or an explicit verified-absent check.*
