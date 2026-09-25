# Testing & CI Guards — Madrasa-360

## No-mock-data guard (Phase 6)

User requirement: **no mock/demo/fake data may ship in a release build.**
The CI guard is `tool/no_mock_check.dart` — pure Dart (no Flutter imports),
runnable with the plain `dart` toolchain:

```bash
dart tool/no_mock_check.dart
```

It scans `lib/` and exits non-zero if any mock-ish identifier appears
(`Mock`, `mockData`, `fakeData`, `demoData`, `sampleData`, `dummyData`,
`loremIpsum`), except in `test/` and on lines carrying an explicit
`// mock-guard:allow` comment. Every allow-listing is greppable and
reviewable — use sparingly.

### Wiring into CI

This repo has no `.github/workflows/` yet. When CI is added, include:

```yaml
# .github/workflows/ci.yml
jobs:
  no-mock:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart tool/no_mock_check.dart
```

### Purge policy (what the guard enforces)

1. **Dead code** (mock helpers with zero references) → deleted.
2. **Live screens showing fake data** → rewired to real data (local Drift
   DB via the existing repositories/providers) with proper loading/empty/
   error states. Where a real source genuinely doesn't exist yet, the
   screen shows an explicit empty state + `// TODO(phase-8)` — never
   invented numbers or names.
3. **Legitimate dev-only helpers** (SQL seeds) stay, but must be
   unreachable from production code:
   - `supabase/migrations/010_tenant_seed.sql` carries a
     `DEV / STAGING ONLY — NEVER RUN IN PRODUCTION` banner; nothing in
     `lib/` references or executes it (verified by grep).
   - `supabase/04_seed.sql` is a manual SQL-Editor script and is
     intentionally skipped by the migration runbook (`docs/DATABASE.md`).

### Known gaps (honest list)

- The migration runbook (`docs/DATABASE.md`) applies
  `supabase/migrations/*.sql` with a glob loop; `010_tenant_seed.sql`
  is included in that glob. Production exclusion currently rests on the
  file's dev-only banner and its demo-user guard. Consider excluding
  `010` from the glob (or moving seeds out of `migrations/`).
- `flutter analyze` / `flutter test` were not run for the Phase-6 purge
  (no Flutter toolchain in the sandbox) — run them in CI before merging.
