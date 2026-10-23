# Crashlytics and the self-heal workflow

2026-10-23. The apps' half of Krypton's App health and self-healing fixes
(`krypton/docs/specs/2026-10-23-app-health-self-healing.md`, which has the whole pipeline and the data-route choice).

## Crash reporting in the apps

- **On with Firebase.** An app built with the store's Firebase file reports crashes; no flag of its own. Android: the
  `firebase` source set gets `CrashReports.kt` (Crashlytics), `noFirebase` a stub; the Crashlytics Gradle plugin is
  applied with google-services (the SDK refuses to start without the build id it writes, and it uploads R8 mappings for
  minified release builds). iOS: the CLI adds the `FirebaseCrashlytics` product next to `FirebaseAnalytics` in
  Package.swift; `#if canImport(FirebaseCrashlytics)` compiles the reporter in. dSYMs: `upload-symbols` from the
  firebase-ios-sdk checkout, documented in README (xtool) — an Xcode-project build has no Firebase packages yet, which
  is a gap of its own (analytics and push too).
- **One reporter, always compiled:** `CrashReports` (Android object / iOS enum) with `setKey`, `log`, `record(error,
  where)`; it holds an optional backend, nil without Firebase, so every call site is unconditional and JVM tests see a
  no-op.
- **Keys:** `shop`, `app_version`, `argon_version` (the CLI writes Argon's version into the build config) at start;
  `screen` on each screen view; `section` (type and id) while a section loads.
- **Breadcrumbs:** a `CrashSink` in the analytics hub logs each event's name and its flat text/number params
  (`screen_view {screen=product}`), so breadcrumbs follow the shopper's analytics choice like every other sink. Items and
  customer ids are left out.
- **Non-fatals:** Liquid's catch (a template that fails to parse or render), a section that fails to load (the
  `quietly` wrapper), and the screen loaders' caught failures. Not network errors: they are not bugs.
- **Crash collection itself** is not tied to the analytics switch: a crash report has no personal data (keys above,
  no user id), and stability is the merchant's legitimate interest. ponytail: a store selling in the EU may want it
  behind the consent prompt too — one call in the reporter.
- **Test crash, debug builds only:** launching with `--ez argon_test_crash true` (Android) or the launch argument
  `-ArgonTestCrash` (iOS) throws `ArgonTestCrash` after the first frame; release builds ignore both.

## The self-heal workflow (`.github/workflows/self-heal.yml`)

`workflow_dispatch` with input `job` (Krypton's signed fix-job URL). Steps: fetch the job → check out the Argon commit
the store's app was built from on a `self-heal/<issue>` branch → write `job.json` → `anthropics/claude-code-action`
(`claude-opus-5-5`, `ANTHROPIC_API_KEY` secret) with a fixed prompt: reproduce as a failing unit test (Android: JVM /
Robolectric-free tests in the generated demo; iOS: XCTest, which only macOS CI runs, so the iOS path writes the test
and leaves its run to CI), fix in `templates/`, run the tests, write `EXPLAINER.md`, open a PR → POST the result to
Krypton. The crash data is a file the prompt calls untrusted. Video: designed in Krypton's spec, not built.
