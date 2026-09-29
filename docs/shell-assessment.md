# Shell Assessment — Phase 6 (2026-09-29)

Branch: `redesign/ux-v2`. Assessment + implementation record.
Full change log: `docs/shell-migration-notes.md`.

## What already exists (keep)

- `lib/presentation/shell/app_shell.dart` — ONE `Scaffold`, responsive
  (desktop right rail ≥1100 / drawer 600–1099 / bottom nav + "مزید" <600),
  top bar with breadcrumb `group › destination`, tenant switcher
  (multi-tenant), notifications bell + badge. `AuthGate` renders `AppShell`
  post-login; the `dashboard` destination builder IS `RoleHomeScreen`
  (role routing preserved).
- `lib/presentation/shell/nav_destinations.dart` — single IA source of truth:
  6 groups, 22 destinations, permission OR-gating + role-key narrowing,
  badge hooks on real providers, `kMobilePrimaryIds`.
- `lib/presentation/shell/app_nav_rail.dart` — collapsible groups, badges,
  user footer; `mobile_nav.dart` — 4 primaries + "مزید".
- `lib/presentation/widgets/global_search.dart` — `GlobalSearchPage`:
  client-side search over students/staff/darjas/fees (honest limitation
  documented in-file).

## What's missing (this phase builds)

1. **Global command search (Ctrl+K)** — explicitly absent (shell doc comment).
   → new `command_palette.dart`: pages + commands + data index, arrow-key
   navigation, Enter/Esc.
2. **ترتیبات (Settings) group** — no settings group in IA; profile only behind
   the rail footer's gear. → add group: profile, notifications (moved),
   backup (relocated orphaned `BackupScreen`), about (moved), logout (action).
3. **Rail visual spec** — current rail is white surface; target is deep teal
   `#0F6B63→#094742` with tenant branding header.
4. **Top bar gaps** — no search trigger, no user profile + role chip, no
   institution name chip, no back affordance for non-root destinations.
5. **Planned placeholders** — 3 destinations render "جلد آرہا ہے" + "جلد" pill.
   → hostel → existing `HostelDashboardScreen` (honest empty state);
   transport/certificates → honest backend-unavailable state (Phase 8 builds
   real screens). No marketing placeholders.
6. **Route fixes** — `TenantPickerScreen` pushes `RoleHomeScreen` (bypasses
   `AppShell`); `MasterAdminShell._backToApp()` falls back to dead
   `MainScreen`; principal dashboard deep-pushes legacy `UserManagementScreen`.
7. **Nested chrome** — all 19 in-shell destination screens return their own
   `Scaffold` (+ `AppBar` on most): duplicate headers under the shell's top
   bar. → strip to `ShellPageBody` (new shared helper), preserving actions
   (refresh, language toggle, mark-read), TabBars, and FABs.

## Deliberately deferred (not this phase)

- Dashboard visual rebuild (Phase 7) — Phase 6 removed the nested chrome
  only: `DashboardScaffold` turned out to BE a Material Scaffold+AppBar
  (the assessment's "layout widget" note was wrong), so it was converted
  to a chromeless body and its actions moved to a slim row. The dashboard
  *look* is Phase 7's job.
- Full `PageContainer`/`PageHeader` conversion of inner screens (Phase 10) —
  `ShellPageBody` is the interim no-chrome wrapper; actions live in a slim
  body toolbar until Phase 10 promotes them to `PageHeader`.
- Server-side search endpoint — palette reuses the client-side index and
  keeps the documented limitation.

## Status: implemented (2026-09-29)

All 7 missing items above were built; see `docs/shell-migration-notes.md`
for the file-by-file record. `dart format --set-exit-if-changed lib` → 0
changed. Flutter SDK is unavailable in this environment, so CI is the
final analyzer/test gate.
