# Screens v2 in the apps: the platform plan

The spec is `docs/superpowers/specs/2026-10-19-screens-v2-design.md`. Read it fully first: it decides everything below.
The contract side is done (`contract/screens.js`, the four queries `AppScreen`, `SectionNodes`, `CollectionMetafields`,
`ShopMetafields`, fixtures in `contract/fixtures/`, sample templates in `contract/fixtures/screens/`, Liquid cases in
`contract/fixtures/liquid/cases.json`). `npm test` passes. The CLI copies `contract/fixtures` (subfolders included) into
each app's test fixtures, and the resolved queries into the app's bundled `queries/`.

Both platforms mirror each other type for type and name for name (the rule in `templates/shared/AGENTS.md`); read
that file and follow its conventions, comment style and naming. Write code that reads like the code around it.

## Phase A: screens from sections

1. **Template model** (`data/Screens.kt` / `Data/Screens.swift`): `ScreenTemplate { sections, metafields }`,
   `ScreenSection { id, type, settings, blocks, platforms, hidden, track }`, `SectionBlock { id, type, settings }`.
   Decode leniently from the template string: invalid JSON → no template; a section without a string id or type is
   skipped; `hidden` and other-platform sections are dropped at decode time; unknown types are kept out of rendering
   (skipped) but decoding never throws. Typed setting readers with the spec's defaults and limits, value by value: a
   wrong type or out-of-range value falls back to the default (`text`, `richtext`, `image`, `link`, `gid`, `gids`,
   `number` clamped, `boolean`, `color`, `choice`, `datetime`). Main-section placement: `above` / `main` / `below`
   split per the spec table (missing `main` = at the end; for collection and search everything goes above).
   Product `main.blocks`: the PDP block order and hidden set, unknown block names ignored, missing blocks keep their
   default place (append them in their default order after the listed ones).
2. **API**: facade calls `appScreen(handle)`, `sectionNodes(ids)`, `collectionMetafields(handle, identifiers)`,
   `shopMetafields(identifiers)`, decoded like the other facade calls, each with a case in the fixture-coverage test
   (Android `ContractFixturesTest`, iOS `FixtureTests` — both fail on a fixture without a case). Make sure the
   coverage tests still only look at top-level `*.json` fixtures (the new `screens/` and `liquid/` subfolders hold
   other files).
3. **Liquid** (`data/Liquid.kt` / `Data/Liquid.swift`): an interpreter for exactly the spec's subset, no dependency.
   Values: nil, bool, int, double (a literal with a decimal point is a double; integer ÷ integer is integer
   division), string, list, map. Context lookup through maps, `.size` / `.first` / `.last`. Lenient rules: unknown
   filter → the output is empty; unknown tag → nothing; a syntax error → the template with every Liquid tag removed
   (an unterminated tag removed to the end). `date` formats in a time zone the caller passes (tests use UTC);
   `money` uses the shop currency from the context (`shop.currency`) with the symbols table in
   `test/liquid.test.js` (`USD CAD AUD NZD SGD → $`, `INR ₹`, `EUR €`, `GBP £`, `JPY ¥`, else `9.90 XYZ`).
   A test runs **every** case in `liquid/cases.json` (lenient ones too) and must pass all of them.
   Build the context from the screen: `shop` (name, currency, metafields), `product` / `collection` when the
   screen has one (fields in the spec), `customer` when signed in, `cart` (item_count, total_price), and per
   section `section { id, settings }` / `block { id, settings }`. Metafield values: JSON types parsed (lists,
   numbers, booleans), others as text. Evaluate only strings that contain `{{` or `{%` (fast path).
4. **Section renderers**: one composable / view per section type in `ui/sections/` / `UI/Sections/`, built from the
   component library (`app.argon.ui` / `ArgonUI`) and the shared blocks (`ProductCardView`, `StoreImage`,
   `HtmlText`, `SectionHeader`, ...). A `SectionList` that draws a list of sections with their loaded data. A loader
   that collects every product/collection GID in a screen's sections (including `custom` nodes) and runs **one**
   `SectionNodes` query; a section whose nodes are missing draws what it can or nothing. Products section: explicit
   products, else the collection's first `limit`; "See all" opens the collection. Video: Android `VideoView` via
   `AndroidView` (no new dependency; muted through `MediaPlayer.setVolume` on prepare), iOS `AVPlayer` /
   `VideoPlayer`. Countdown ticks every second and hides when over if `hide_when_over`.
5. **Custom section**: `render == native` with `nodes` → draw the nodes natively (heading, paragraph runs with bold,
   italic, link; lists; image; button; divider; product card; collection rail), Liquid evaluated per text. Unknown
   nodes skipped. `web`, or native without nodes → a WebView (`android.webkit.WebView` / `WKWebView`) of the whole
   html after Liquid, in a document with `<meta name=viewport content="width=device-width, initial-scale=1">`, the
   theme's font and colours as CSS variables `--accent`, `--text`, `--background`, `body{margin:0}`,
   `img{max-width:100%;height:auto}`. JavaScript on. Height: `height` when > 0, else measured from
   `document.documentElement.scrollHeight` after load (and on resize) through a JS bridge / message handler. Every
   navigation from the page goes through `Links.resolve`: an app route opens in the app, anything else in the
   browser (Custom Tab / Safari), and the WebView never navigates itself.
6. **Links**: `Route.Page(handle)` and `Route.Screen(handle)`; `Links.resolve` gains `/pages/<h>` → Page,
   `app://screens/<h>` → Screen, `/cart`, `/account`, `/wishlist`, `/` → those tabs (however the platform
   represents a tab switch through a route). `PageScreen` / `PageView`: the Shopify page (existing `Page` query),
   title in the top bar, body through HtmlText. `ScreenScreen` / `CustomScreenView` (name it well): the
   `app_screen` with that handle, its title in the top bar, its sections; not found → the standard empty state.
7. **Home**: `app_screen/home` first (with its sections); if it has no template or no renderable sections, the v1
   home exactly as today. The template's top bar is kept either way.
8. **System screens**: product (sections above and below the PDP, inside its scroll; `main.blocks` order and hidden),
   collection and search (sections above the grid, scrolling with it; collection `main.filters` overrides the
   collection template), cart, account, orders, wishlist (above and below their content, inside their scroll). Each
   screen loads `app_screen/<screen>` once per visit, quietly: a failure or no template means the screen is
   exactly as today. Liquid context: product screen has `product`, collection screen has `collection`.
9. **Analytics**: `AnalyticsEvent.ViewPromotion` / `SelectPromotion` with GA4 names `view_promotion` /
   `select_promotion` and params `promotion_id`, `promotion_name`, `creative_name`, `creative_slot` (spec). View:
   once per section per screen visit, when it first becomes visible (Android: when its LazyColumn item is first
   composed in the viewport is acceptable; iOS: `onAppear` in a lazy stack). Select: every tap that follows a
   section link, button, product or collection. Sinks get them like any event (MoEngage/Meta map by name).
10. **Tests** (pure logic, like the existing suites): template decoding over `screens/home.json`, `product.json`,
    `about.json` (hidden dropped, platform filtering, unknown types and nodes skipped, bad values defaulted,
    main placement, product block order); every Liquid case; metafield context building; `Links.resolve`
    additions; promotion event params; the node decoding of the custom section; the GID collection for
    `SectionNodes`; the four new facade calls in the coverage test.

## Phase B: the app shell (after Phase A)

The spec's "App shell" section: RemoteSettings gains `navigation`, `announcement`, `appearance`, decoded leniently;
tabs from settings (2-5, home first, ids and icons from the spec, invalid → built-in five); labels on/off; top bar
style and transparent-on-home; drawer from a Shopify menu (`ArgonSideMenu` exists on both); announcement bar on tab
roots, rotating, dismissible for the session; appearance mode light/dark/system. Tests for the decoding and the
fallbacks.

## Phase C: push notifications (after Phase B)

Through the store's own Firebase project (the one whose config files the app is built with). Krypton sends
campaigns to the FCM topics `all`, `ios` and `android`, with `data.link`.

- **CLI** (`lib/`, owned by the lead, not the agents): a `--push` flag, refused without the platform's Firebase file;
  it becomes `PUSH=true` in the config, and on Android selects the messaging dependency, on iOS adds the
  `FirebaseMessaging` product to `Package.swift` and an `App.entitlements` with `aps-environment` to the Xcode
  project. `DEVICES_URL` is derived from `SETTINGS_URL` (`/v1/settings/` → `/v1/devices/`).
- **Both apps**, only when `PUSH` is on:
  - `PushStore` / `Push` (data layer): an anonymous install id (UUID, kept on disk), the opt-in state; `enable()`
    asks the OS permission (Android 13+ `POST_NOTIFICATIONS`; iOS `UNUserNotificationCenter`), registers for remote
    notifications (iOS), subscribes to the topics `all` and `ios` / `android`; `disable()` unsubscribes. Both report
    to `DEVICES_URL` (`{ installId, platform, optedIn }`, fire and forget). Analytics consent does not gate push:
    the OS permission does.
  - When to ask: an Account row "Notifications" with a switch, and once after the first purchase (a sheet that
    explains, then the OS prompt). Never on first launch.
  - A notification's `link` opens through `Links.resolve` when tapped: Android, the launcher intent's extras (FCM
    puts `data` there in the background; in the foreground `onMessageReceived` shows the notification itself with a
    PendingIntent carrying the link); iOS, `UNUserNotificationCenterDelegate.didReceive`, foreground presentation as
    a banner. Images show on Android; iOS needs a notification service extension (not in this phase: note it).
- **Tests**: the install id persists; enable/disable call the topic and report functions they're given (fakes);
  the link from a notification payload resolves; without `PUSH` nothing is wired.

## Rules

- Don't commit. Leave the changes in the working tree; the lead commits.
- Only touch your platform's folder (`templates/android/` or `templates/ios/`), plus `templates/shared/AGENTS.md`
  (add short recipes "Add a section type", "Add a Liquid filter") — the Android agent writes AGENTS.md; the iOS
  agent leaves it alone. If something outside your folder must change, stop and report it instead.
- Before finishing, append one row to `C:\Users\arjun\mksd\argon-dev\wt-screens\SESSION_LOG.csv` (columns
  `date,project,task,start_time,end_time,status`; project `create-shopify-app-storefront`; double-quote the task;
  prefix it `subagent:`; IST times from `Get-Date -Format HH:mm` / `date +%H:%M`).
- Report: what was built, file list, test counts, anything not done or not verified, and any deviation from the
  spec with the reason.
