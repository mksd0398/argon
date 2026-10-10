# Argon phase 2 — plan (projects 1 and 2)

Date: 2026-10-09. The user asked to build fully without stopping for spec review; specs are written first as the record.

Specs:
- Project 1, UI library: `docs/superpowers/specs/2026-10-09-argon-ui-library-design.md`
- Project 2, API layer: `docs/superpowers/specs/2026-10-09-argon-api-layer-design.md` (written after the schema research in `2026-10-09-api-catalog-research.md`)

Projects 3 (24 sections) and 4 (core screens rebuilt) get their own specs after these land.

## Branches

All work branches from `phase2-ui-api` and merges back into it; `phase2-ui-api` goes to `main` by PR when both projects are green.

| Branch | Owner | Scope |
|---|---|---|
| `phase2-ui-android` | builder agent | `templates/android/ui` module, theme, 29 components, gallery, `:ui` tests, Account debug row |
| `phase2-ui-ios` | builder agent | `templates/ios/ArgonUI` package + pbxproj wiring, theme, 29 components, gallery, AppTests, Account debug row |
| `phase2-api-contract` | builder agent | `contract/queries/*.graphql` + fragments for the full catalog; vendored schemas; offline schema validation in `npm test` |
| `phase2-api-android` / `phase2-api-ios` | builder agents | typed models + facades on each platform, replacing hand parsing; fixture decoding tests |

UI and API work touch disjoint files (UI: new module/package + Theme + Account row; API: `data/`, `Data/`, `contract/`), so they run in parallel. The two API platform branches start after the contract branch merges.

## Steps

1. UI library, Android and iOS in parallel (CI is the iOS compiler: every push runs the macOS jobs).
2. API research → API spec → contract documents with offline validation against the vendored 2026-10 schemas.
3. API layer, Android and iOS in parallel, against the merged contract.
4. Merge all into `phase2-ui-api`; full CI green (cli, android, iOS Xcode 16 required, Xcode 26 watched).
5. Generate the Nalli test project from the branch, install on the phone, review the gallery and run the Headless connection test (catalogue, checkout opens, sign-in → orders).
6. PR `phase2-ui-api` → `main`.

## Verification per branch

- Android: `node bin/create.js <dir> --demo --yes`, then `./gradlew testDebugUnitTest assembleDebug` in `<dir>/android`.
- iOS: push → CI `ios (Xcode 16.x)` build + test must pass.
- CLI: `npm test` (and `npm run test:live` in CI).
