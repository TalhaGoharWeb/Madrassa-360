# Dependency & Package-Manager Audit — Madrassa-360

**Date:** 2026-10-03 · **Branch:** `redesign/ux-v2` · **Scope:** read-only (no upgrades/removals performed)
**Method:** `pubspec.yaml` + `pubspec.lock` analysis, import-usage grep, pub.dev API (latest versions, publish dates), OSV.dev batch query (19 packages), Android manifest / iOS plist / Gradle / CI workflow / Edge Function import review.

**Headline:** No known CVEs in any pinned Dart/Flutter dependency (OSV 0/19). No git/path dependencies — all 179 packages from pub.dev, 8 from SDK. Supply-chain risk concentrates in **build reproducibility** (stale lockfile, unfrozen installs) and **CI action pinning**, not in the package set itself.

---

## (a) Dependency table — direct dependencies

| Package | Pinned (lock) | Latest stable | Status | Notes |
|---|---|---|---|---|
| `google_fonts` | 6.3.2 | 9.0.0 | **UNUSED — remove** | Zero imports in `lib/`, `test/`, `tool/`, `android/`, `ios/`. Dead weight; if ever imported it would download fonts at runtime (network + privacy + offline breakage). |
| `flutter_riverpod` | 2.6.1 | 3.4.3 | Outdated (major) — **intentional** | 2.6.1 is the last 2.x; Riverpod 3.x is breaking. Remain on 2.x; document. |
| `shared_preferences` | 2.5.3 | 2.5.5 | Patch behind | Safe upgrade. |
| `connectivity_plus` | **5.0.2 (lock) vs `^6.1.5` (pubspec)** | 7.3.2 | **STALE/INVALID LOCKFILE** | Lock violates the pubspec constraint (see H1). App code is version-tolerant (`result is List ? … : […]`). |
| `intl` | 0.20.3 | 0.20.3 | OK | |
| `supabase_flutter` | 2.12.0 | 2.18.0 | Minor behind | Safe within `^2.5.0`; test after bump. Do NOT jump to 3.0.0-dev. |
| `flutter_dotenv` | 5.2.1 | 6.0.1 | Major behind | 6.x maintained (2026-04). Evaluate breaking changes before upgrading. |
| `cached_network_image` | 3.4.1 | 4.0.4 | Major behind | 4.x released 2026-09-23+; breaking. Needs code changes. |
| `image_picker` | 1.2.1 | 1.2.3 | Patch behind | Safe upgrade. |
| `uuid` | 4.5.3 | 4.6.0 | Minor behind | Safe upgrade. |
| `url_launcher` | 6.3.2 | 6.3.3 | Patch behind | Safe upgrade. |
| `http` | 1.6.0 | 1.6.0 | OK | |
| `drift` | 2.35.0 | 2.35.1 | Patch behind | Safe. NOTE: pubspec comment claims "pinned to 2.31.x line" but constraint `^2.31.0` allows 2.35.x — comment is stale/misleading. |
| `sqlite3_flutter_libs` | 0.5.42 | 0.6.0 | Minor behind | pub.dev flags 0.6.0 oddly (`0.6.0+eol` in API); verify before upgrading. |
| `path_provider` | 2.1.5 | 2.1.6 | Patch behind | Safe upgrade. |
| `path` | 1.9.1 | (stable) | OK | |
| `pdf` | 3.12.0 | 3.13.1 | **Intentionally pinned** | 3.13 needs Dart ≥3.12; document. |
| `printing` | 5.14.3 | 5.15.1 | **Intentionally pinned** | Same Dart constraint; document. |
| `excel` | 4.0.6 | 4.0.6 | OK | |
| `crypto` | 3.0.7 | 3.0.7 | OK | SHA-256 only, no native code. |
| `firebase_core` | 3.15.2 | 4.15.0 | Major behind — **intentional** | messaging 15.x requires core 3.x. |
| `firebase_messaging` | 15.2.10 | 16.7.0 | Major behind — **intentional** | 16.x needs firebase_core 4.x. |
| `flutter_lints` | 4.0.0 | — | OK (dev) | |
| `drift_dev` / `build_runner` | 2.35.0 / 2.16.1 | — | OK (dev) | Versions track each other correctly. |

Key transitive versions (all current, no OSV hits): `gotrue` 2.18.0, `postgrest` 2.6.0, `realtime_client` 2.7.0, `storage_client` 2.4.1, `functions_client` 2.5.0, `archive` 3.6.1, `image` 4.3.0, `xml` 6.5.0, `yaml` 3.1.4, `sqflite` 2.4.2 (via `flutter_cache_manager` 3.4.1).

---

## (b) Findings

### HIGH — H1: Committed `pubspec.lock` is stale AND violates `pubspec.yaml`
- **Location:** `pubspec.lock` (root), `pubspec.yaml:26`
- **Problem:** `pubspec.yaml` constrains `connectivity_plus: ^6.1.5` (set 2026-09-28), but the committed lockfile pins **5.0.2** — outside the allowed range. `git log` shows `pubspec.lock` was last regenerated in commit `d84af4f`, *before* the pubspec change. The lockfile is therefore not just old, it is unsatisfiable against the current pubspec.
- **Why it matters:** Every CI job and build workflow runs bare `flutter pub get` (no `--frozen`/`--enforce-lockfile`). Pub silently re-resolves, so two builds from the same commit can ship different dependency trees. "Release from an exact CI-green commit" is undermined when the commit doesn't determine the dependency tree. A future malicious/compromised package release could also slip in between CI runs unnoticed.
- **Scenario:** A patch release of a transitive dep introduces a regression or backdoor; build #1 (morning) and build #2 (evening) from the same commit contain different code, and nobody can tell from the repo.
- **Fix:** Regenerate the lockfile (`flutter pub get`), commit it, and change all workflows to `flutter pub get --enforce-lockfile` so a stale lock fails loudly instead of silently floating. Add a CI check that the lockfile is in sync.

### HIGH — H2: `google_fonts` is a completely unused dependency
- **Location:** `pubspec.yaml` (`google_fonts: ^6.1.0`)
- **Problem:** Zero references in `lib/`, `test/`, `tool/`, `android/`, `ios/`. The app bundles its own fonts (JameelNooriNastaleeq, NotoNaskhArabic) via `pubspec.yaml` font declarations.
- **Why it matters:** Dead dependency bloats the APK and, worse, `google_fonts` fetches font files from Google's CDN at runtime when used — a network/privacy liability for an offline-first app handling children's data. Today it's inert, but any future `GoogleFonts.xxx` call silently introduces runtime downloads.
- **Fix:** Remove from `pubspec.yaml`, regenerate lockfile. (Deletion is safe — verified zero usages.)

### MEDIUM — M1: CI actions float on mutable tags; Windows installer built by a personal-account action
- **Location:** `.github/workflows/*.yaml`
- **Problem:** Every third-party action floats on a major tag: `actions/checkout@v4`, `subosito/flutter-action@v2`, `denoland/setup-deno@v2`, `actions/setup-python@v5`, `actions/setup-java@v4`, `actions/upload-artifact@v4`, `softprops/action-gh-release@v2`, and — highest risk — `Minionguyjpro/Inno-Setup-Action@v1.2.2` (a **personal account**, not an org), which builds the distributable `Madrassa360-Setup-*.exe`.
- **Why it matters:** A mutable tag can be retargeted; a compromised action runs with the workflow's permissions on the build machine. The Inno Setup action is the single highest-value target: it touches the final Windows installer users download.
- **Scenario:** Attacker compromises the personal-account action repo and retags `v1.2.2`; the next Windows build ships a trojanized installer signed by your release process.
- **Fix:** Pin all actions to full commit SHAs (keep the tag as a comment). For the Inno Setup step, prefer SHA-pinning as a minimum; longer-term, vendor the Inno Setup install or use a first-party alternative.

### MEDIUM — M2: Two competing SQLite stacks ship in the app
- **Location:** `pubspec.lock` (`sqflite` 2.4.2 via `flutter_cache_manager` 3.4.1 ← `cached_network_image`)
- **Problem:** The app uses `drift` + `sqlite3` for its offline database, but `cached_network_image` pulls in `flutter_cache_manager`, which pulls in native `sqflite`. Two separate native SQLite implementations, two file formats, larger APK, larger native attack surface.
- **Fix:** Accept and document, or replace `cached_network_image` with a lighter image cache that doesn't drag in sqflite (note: 4.x may change this — check during the 4.x evaluation).

### MEDIUM — M3: iOS `Info.plist` lacks camera/photo-library usage descriptions
- **Location:** `ios/Runner/Info.plist`
- **Problem:** No `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` keys, yet `image_picker` is used in 9 Dart files (student/staff photos).
- **Why it matters:** On iOS, invoking the image picker without these keys crashes the app; App Store review will also reject. Either iOS photo capture is broken in production or the feature is silently dead on iOS.
- **Fix:** Add both usage-description keys with honest Urdu/English strings, then test photo capture on a real iPhone.

### MEDIUM — M4: Deno version floats in CI (`v2.x`)
- **Location:** `.github/workflows/ci.yaml` (deno job)
- **Problem:** `denoland/setup-deno@v2` with `deno-version: v2.x` — Edge Function type-checks/lints run against whatever Deno 2.x is newest that day.
- **Fix:** Pin an exact Deno version (e.g. `v2.4.x`) matching the Supabase Edge Runtime.

### LOW — L1: Stale comments in `pubspec.yaml` misdescribe pinning
- **Location:** `pubspec.yaml` (drift, pdf, printing, firebase comments)
- **Problem:** The drift comment says "Pinned to the 2.31.x line" while the constraint `^2.31.0` resolved 2.35.0. Misleading comments cause future maintainers to misjudge upgrade safety.
- **Fix:** Correct comments to describe actual constraints and the real reason for each pin.

### LOW — L2: `deno.json` check-task omits `manage-users`
- **Location:** `supabase/functions/deno.json`
- **Problem:** The `tasks.check` script lists 4 functions but not `manage-users/index.ts` — the most privilege-sensitive function.
- **Why it matters:** Anyone running `deno task check` locally gets a false green. (CI's shell loop *does* check all functions, so this is local-DX only.)
- **Fix:** Add `manage-users/index.ts` to the task.

### Verified GOOD
- **No known CVEs:** OSV.dev batch query over 19 key packages (incl. `http`, `archive`, `image`, `crypto`, `gotrue`, `postgrest`, `drift`, `pdf`, `excel`, `sqflite`, `yaml`) — **0 hits**.
- **No suspicious sources:** all 179 packages from `pub.dev` (hosted), 8 from the SDK; zero git/path dependencies. No typosquatting candidates among direct deps.
- **Edge Function imports:** the only remote import across all functions is `https://esm.sh/@supabase/supabase-js@2.44.4` — exact-version pinned, and `supabase/functions/deno.lock` records its content hash. (Verify Supabase deploy honors the lockfile.)
- **Android permissions minimal:** only `INTERNET` + `ACCESS_NETWORK_STATE`; no location/contacts/SMS/camera permissions. (Camera is used via `image_picker` without a manifest permission — correct for Android 13+ photo picker, but see M3 for iOS.)
- **Native toolchain current:** Gradle 8.14.3, AGP 8.13.0, Kotlin 2.2.20, Flutter pinned to 3.47.4 in CI.
- **Installer script clean:** `installer/madrassa360.iss` downloads nothing remote.
- **No remote scripts** in `web/index.html`.

---

## (c) Lockfile & reproducibility verdict

**NOT reproducible today.** The committed `pubspec.lock` is stale (predates the `connectivity_plus ^6.1.5` constraint and is unsatisfiable against it), and every workflow runs unfrozen `flutter pub get`, so CI/builds silently re-resolve. The dependency tree of a "CI-green commit" is determined by *when* the job ran, not by the commit. Fix per H1.

---

## (d) Permission audit

| Platform | Permission | Justification | Verdict |
|---|---|---|---|
| Android | `INTERNET` | Supabase/API calls | OK |
| Android | `ACCESS_NETWORK_STATE` | Connectivity checks | OK |
| Android | *(camera — none declared)* | `image_picker` | OK on Android 13+ (system picker); verify on older API levels |
| iOS | *(none declared)* | `image_picker` in 9 files | **FAIL — see M3** |

No location, contacts, SMS, microphone, or background-location permissions anywhere. Minimal and appropriate for a school app.

---

## (e) Safe upgrade plan (do NOT blindly upgrade)

**Safe now (patch/minor, no breaking changes expected — run full test suite after):**
`shared_preferences` 2.5.5 · `image_picker` 1.2.3 · `uuid` 4.6.0 · `url_launcher` 6.3.3 · `path_provider` 2.1.6 · `drift` 2.35.1 · `supabase_flutter` 2.18.0 (minor; exercise auth/realtime paths in tests)

**Evaluate first (major versions, breaking changes likely):**
- `flutter_dotenv` 6.x — review changelog; only 1 file imports it, blast radius is small.
- `cached_network_image` 4.x — breaking; check whether 4.x still pulls `sqflite` (may resolve M2 as a side effect).

**Must REMAIN pinned (document the reason in pubspec.yaml):**
- `flutter_riverpod` 2.x — Riverpod 3.x is a breaking rewrite; migration is a project, not a bump.
- `pdf` 3.12.0 / `printing` 5.14.3 — need Dart ≥3.12; the app's SDK floor is ^3.5.0.
- `firebase_messaging` 15.x + `firebase_core` 3.x — 16.x requires firebase_core 4.x; coordinated major bump only.
- `supabase_flutter` 2.x — 3.0.0 is still in dev previews.

**Remove:** `google_fonts` (unused).

**Process fixes (independent of versions):** regenerate + freeze the lockfile (H1), SHA-pin GitHub Actions (M1), pin Deno version (M4), fix iOS usage descriptions (M3), correct stale pin comments (L1), add `manage-users` to the deno check task (L2).
