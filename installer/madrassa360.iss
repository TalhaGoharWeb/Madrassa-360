; ─────────────────────────────────────────────────────────────────────────
; Madrassa 360 — Windows installer (Inno Setup 6)
;
; Build from the repo root:
;     iscc installer\madrassa360.iss
; (install Inno Setup 6 first — see installer/README.md)
;
; VERSION SOURCE OF TRUTH: version.json at the repo root.
; Release workflow: bump version.json {"version","build"} AND pubspec.yaml,
; then mirror the version in the {#Version} define below. The AppId GUID is
; FIXED forever — it is what makes upgrades replace the old install instead
; of creating a parallel one.
; ─────────────────────────────────────────────────────────────────────────

#define Version "1.0.0"
#define Build "1"

[Setup]
; FIXED AppId — never change this GUID. Recorded here as the single source.
AppId={{0D1951C1-1D4E-4229-9EB3-8AEB0486928E}
AppName=Madrassa 360
AppVersion={#Version}.{#Build}
AppVerName=Madrassa 360 {#Version}
AppPublisher=Madrassa 360
DefaultDirName={autopf}\Madrassa360
DefaultGroupName=Madrassa 360
DisableProgramGroupPage=no
OutputDir=..\dist
OutputBaseFilename=Madrassa360-Setup-{#Version}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Versioned upgrades: same AppId + higher AppVersion replaces in place.
UsePreviousAppDir=yes
DirExistsWarning=no
; Keep the uninstaller from offering to reboot; nothing we install needs it.
RestartIfNeededByRun=no
; Per-machine install under Program Files — requires elevation.
PrivilegesRequired=admin
UninstallDisplayName=Madrassa 360
; Displayed version in "Add/Remove Programs".
VersionInfoVersion={#Version}.{#Build}
VersionInfoDescription=Madrassa 360 — Madrasa Management Platform installer

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce
Name: "startmenuentry"; Description: "Create a &Start Menu entry"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[Dirs]
; Per-user data directory. uninsneveruninstall => the uninstaller NEVER
; deletes it, so the Drift database, logs and crash reports survive both
; upgrades and uninstalls. (See installer/README.md for manual removal.)
Name: "{userappdata}\Madrassa360"; Flags: uninsneveruninstall
Name: "{userappdata}\Madrassa360\logs"; Flags: uninsneveruninstall
Name: "{userappdata}\Madrassa360\logs\crashes"; Flags: uninsneveruninstall

[Files]
; Release build output of `flutter build windows --release`.
; The exe is madrasa_360.exe (package name); branding is "Madrassa 360".
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Madrassa 360"; Filename: "{app}\madrasa_360.exe"; Tasks: startmenuentry
Name: "{autodesktop}\Madrassa 360"; Filename: "{app}\madrasa_360.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\madrasa_360.exe"; Description: "Launch Madrassa 360"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Intentionally EMPTY: user data under %APPDATA%\Madrassa360 is preserved.
; Type=filesandordirs would nuke the database — never add {userappdata} here.
; To fully remove all traces, delete %APPDATA%\Madrassa360 manually
; (documented in installer/README.md).
