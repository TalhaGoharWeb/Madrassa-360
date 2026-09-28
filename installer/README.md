# Madrassa 360 — Windows installer

Builds `Madrassa360-Setup-<version>.exe` with [Inno Setup 6](https://jrsoftware.org/isinfo.php).

## 1. Install Inno Setup

Download and install **Inno Setup 6** (the `iscc.exe` command-line compiler
ships with it). No other dependencies.

## 2. Build the Flutter release bundle first

From the repo root:

```bat
flutter build windows --release
```

This produces `build\windows\x64\runner\Release\` (contains
`madrasa_360.exe`, `flutter_windows.dll`, `data\`, …). The installer script
packages that directory verbatim.

## 3. Compile the installer

From the repo root:

```bat
iscc installer\madrassa360.iss
```

The setup exe lands in `dist\` as `Madrassa360-Setup-1.0.0.exe`.

## What the installer does

| Step | Detail |
|---|---|
| Install location | `{autopf}\Madrassa360` (i.e. `C:\Program Files\Madrassa360`) |
| Data directory | Creates `%APPDATA%\Madrassa360` (database, logs, crash reports live here — **never** under Program Files) |
| Shortcuts | Desktop shortcut + Start Menu entry (both optional, checked by default) |
| Upgrades | Same fixed `AppId` → a newer setup replaces the old install in place, keeping data |

## Uninstall behaviour — data is PRESERVED

Uninstalling removes the program files but **keeps `%APPDATA%\Madrassa360`**
(the Drift database, file logs and crash reports). This is deliberate:
reinstalling or upgrading never loses a madrassa's data.

To fully remove all traces (after uninstall), delete manually:

```bat
rmdir /s "%APPDATA%\Madrassa360"
```

## Versioning

The version lives in **`version.json`** at the repo root
(`{"version": "1.0.0", "build": 1}`). Release checklist:

1. Bump `version.json` **and** `pubspec.yaml` (`version: 1.0.0+1`).
2. Mirror the numbers in `installer/madrassa360.iss` (`#define Version/Build`).
3. Mirror them in `windows/runner/Runner.rc` fallback defines
   (used only when `flutter build` doesn't pass `FLUTTER_VERSION_*`).
4. Keep `lib/main.dart`'s `kAppVersion` in sync (session-start log marker).

The `AppId` GUID in the `.iss` (`0D1951C1-1D4E-4229-9EB3-8AEB0486928E`)
must **never** change — it is what Windows uses to recognise upgrades.

## Code signing (optional, recommended before public distribution)

An unsigned installer triggers SmartScreen warnings. To sign:

1. Buy/issue a code-signing certificate (or self-sign for internal use).
2. In Inno Setup: *Tools → Configure Sign Tools*, then add
   `SignTool=mysign` + `SignedUninstaller=yes` to the `[Setup]` section.

The `.iss` intentionally contains **no keys, passwords or certificates** —
signing is a build-machine concern, never committed.
