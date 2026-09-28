# Windows Build & Release Guide — Madrasa-360

How to build the Windows desktop app, package the installer, sign it, and
ship a version that the in-app auto-updater (`lib/core/update/`) recognises.

Related: `docs/DEPLOYMENT.md` §5–6 (CI/CD + release process),
`supabase/migrations/018_platform_config.sql` (update backend),
`lib/core/device/device_service.dart` (per-install device registry).

---

## 1. Prerequisites

| Tool | Required version / notes |
|---|---|
| Flutter SDK | **3.47.4 (stable)** — pinned via the `FLUTTER_VERSION` env in all four `.github/workflows/*.yaml`. Bump it in all four files together when upgrading. `pubspec.yaml` requires Dart `^3.5.0`. |
| Visual Studio | **Build Tools 2022** (or full VS 2022) with the **"Desktop development with C++"** workload — needed for the C++ Windows runner. |
| Inno Setup | **6.x** — compiles `installer/madrassa360.iss` into the setup EXE. CLI: `iscc`. |
| Windows SDK `signtool` | Ships with the Windows SDK / VS Build Tools — used for code-signing (see §5). |

Verify once:

```powershell
flutter --version      # expect 3.47.4, channel stable
iscc /?                # Inno Setup compiler responds
where signtool         # path to signtool.exe
```

> `installer/madrassa360.iss` is produced by the Windows packaging
> workstream. The `build-windows.yaml` workflow fails fast if it is missing.

---

## 2. Build the app

From the repo root:

```powershell
flutter pub get
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\` — contains `madrasa_360.exe`
plus its DLLs and the `data\` asset bundle. The EXE is **not** redistributable
on its own; always ship the installer (§3).

Debug iteration (no installer needed):

```powershell
flutter run -d windows
```

---

## 3. Build the installer (Inno Setup)

```powershell
iscc installer\madrassa360.iss /O+ /O"installer\Output" /F"Madrassa360-Setup-<version>"
```

This mirrors exactly what `.github/workflows/build-windows.yaml` does on
`windows-latest` (via `Minionguyjpro/Inno-Setup-Action`). The version comes
from root `version.json` unless overridden by the workflow's `version` input.

Result: `installer\Output\Madrassa360-Setup-<version>.exe`.

---

## 4. Version bump procedure

Four places must agree on every release. Bump them **in one commit**:

1. **`version.json`** (repo root) — `version` and `build`, e.g.
   `{"version": "1.0.1", "build": 2}`. The release workflow verifies the git
   tag equals `v` + this version and fails otherwise.
2. **`pubspec.yaml`** — `version: 1.0.1+2` (must match `version.json`).
3. **`windows/runner/Runner.rc`** — the `#define VERSION_AS_STRING "1.0.0"`
   fallback and `#define VERSION_AS_NUMBER 1,0,0,0` fallback (used when the
   `FLUTTER_VERSION_*` defines are absent). Keep them in sync so the EXE's
   file-properties version is correct.
4. **`platform_config` row in Supabase** (after the release is published):

   ```sql
   update public.platform_config
   set latest_version            = '1.0.1',
       minimum_supported_version = '1.0.0',  -- raise to '1.0.1' to FORCE the update
       download_url              = 'https://github.com/TalhaGoharWeb/Madrassa-360/releases/download/v1.0.1/Madrassa360-Setup-1.0.1.exe',
       release_notes             = 'Short English notes…',
       release_notes_urdu        = 'اردو میں ریلیز نوٹس…',
       updated_at                = now()
   where key = 'default';
   ```

   Semantics (enforced client-side by `UpdateService`):
   * `latest_version` — the newest published build. Clients older than this
     get the *optional* update dialog (dismissible, once per version).
   * `minimum_supported_version` — clients older than this get the
     **blocking** forced-update screen with no dismiss. Raising this is the
     "everyone must update" lever — use it deliberately.
   * The seed migration sets both to `1.0.0` and `download_url` to the
     Releases page as a placeholder; **the release workflow owns this row
     afterwards** (the seed is `ON CONFLICT DO NOTHING` and never overwrites).

> NOTE: `docs/DEPLOYMENT.md` §6 step 5 shows an older example UPDATE with
> `windows_download_url` / `android_download_url` and `where id = 'platform'`.
> That predates the real schema — use the SQL above (`key = 'default'`,
> single `download_url`) until DEPLOYMENT.md is refreshed.

---

## 5. Code-signing the installer

Unsigned installers trigger Windows SmartScreen warnings. The pipeline:

1. **Real certificate (production):** an EV or OV code-signing certificate.
   Its PFX is stored in **GitHub Secrets** (e.g. `WINDOWS_CERT_PFX_B64` +
   `WINDOWS_CERT_PASSWORD`) and imported at release time by the signing job —
   **never committed to the repo**, never in build logs.
2. **Self-signed / test certificate (local dev only):** creates a cert your
   own machine trusts, so you can exercise the signing step end-to-end
   without buying anything:

   ```powershell
   # 1. Create a self-signed code-signing cert in the Current User store
   $cert = New-SelfSignedCertificate `
     -Type CodeSigningCert `
     -Subject "CN=Madrassa-360 Test" `
     -CertStoreLocation "Cert:\CurrentUser\My" `
     -NotAfter (Get-Date).AddYears(2)

   # 2. Export it (protect the PFX with a password)
   $pw = ConvertTo-SecureString "test-only-password" -AsPlainText -Force
   Export-PfxCertificate -Cert $cert `
     -FilePath "$env:USERPROFILE\madrassa360-test.pfx" -Password $pw

   # 3. Trust it locally (dev machines only — never on user machines)
   Import-Certificate -FilePath "$env:USERPROFILE\madrassa360-test.cer" `
     -CertStoreLocation "Cert:\CurrentUser\Root"

   # 4. Sign the installer (SHA-256, RFC 3161 timestamp)
   signtool sign /fd SHA256 /a `
     /f "$env:USERPROFILE\madrassa360-test.pfx" /p "test-only-password" `
     /tr http://timestamp.digicert.com /td SHA256 `
     "installer\Output\Madrassa360-Setup-1.0.0.exe"

   # 5. Verify
   signtool verify /pa /v "installer\Output\Madrassa360-Setup-1.0.0.exe"
   ```

   A self-signed signature proves the *process* works; it does **not** earn
   SmartScreen reputation — only the production cert in Secrets does that.

Current status: `build-windows.yaml` / `release.yaml` do **not** sign yet —
wiring the Secrets-based signing step into the release workflow is a
follow-up for the CI workstream.

---

## 6. Auto-update behaviour (what the app does)

* On every start, `UpdateGate` (see `lib/core/update/update_service.dart`)
  fetches the `platform_config` row **anonymously** (the row is public-read;
  the check works pre-login).
* **Offline / error → `unknown` → app starts normally.** No dialogs, no
  blocking, no retry loop. Offline users are never bricked by this check.
* `local < latest` → dismissible "update available" dialog, once per version
  (dismissal in SharedPreferences).
* `local < minimum_supported_version` → full-screen blocking gate with
  release notes (Urdu + English) and a "Download update" button
  (`url_launcher`, external browser). No dismiss, back-button disabled.
* Device identity: first run mints a random UUID stored at
  `%APPDATA%\Madrassa360\device.json` (**not** a hardware fingerprint);
  `DeviceService.registerOnLogin()` upserts it into the `devices` table and
  opens a revocable `device_sessions` row. Users are never locked out by
  device binding — revocation is admin-initiated only.

---

## 7. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `flutter build windows` → "Visual Studio not found" | Install VS Build Tools 2022 with C++ workload; run `flutter doctor`. |
| `iscc` not recognised | Reinstall Inno Setup 6 and tick "Add to PATH", or use its full path. |
| Installer runs but app shows "update required" immediately | `platform_config.minimum_supported_version` is newer than the installed build — check the row, then rebuild with the bumped version (§4). |
| Update check never fires | `UpdateGate` must wrap the app above `MaterialApp` in `main.dart` (one-line wiring — see the doc comment in `update_service.dart`). |
| `signtool` timestamp fails | Timestamp server unreachable — retry; the signature is still valid, only the counter-signature is missing. |
