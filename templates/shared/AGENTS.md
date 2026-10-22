# Agent guide

Two native apps for one Shopify store, kept identical screen for screen: `android/` (Kotlin, Jetpack Compose, package `app.storefront`) and `ios/` (Swift, SwiftUI, target `App`). See README.md for running, config and store setup.

## Layout

- `android/shopify.properties`, `ios/Config.xcconfig`: per-store config. Same keys on both (`SHOP_DOMAIN`, `STOREFRONT_TOKEN`, `CUSTOMER_CLIENT_ID`, `SHOP_ID`, `API_VERSION`, `APP_NAME`, `BUNDLE_ID`, `PDP_METAFIELDS`, `HOME_TEMPLATE`, `COLLECTION_TEMPLATE`, `JUDGEME_PUBLIC_TOKEN`, `SHOW_VENDOR`, `ONBOARDING`, `FREE_SHIPPING_THRESHOLD`, `META_APP_ID`, `META_CLIENT_TOKEN`, `MOENGAGE_WORKSPACE_ID`, `MOENGAGE_DATA_CENTER`, `SERVER_PURCHASE`, `SETTINGS_URL`, `CUSTOMER_REDIRECT_URI`, `PUSH`, `DEVICES_URL`, `CHECKOUT`, `LOGIN`, `GOKWIK_MERCHANT_ID`, `GOKWIK_ENVIRONMENT`). With `SETTINGS_URL` set, the settings it serves override the built-in values at the next launch (`RemoteSettings`), the app shell too: tabs, top bar, drawer, announcement strip, light/dark, the heading and body fonts (`Navigation`, `Announcement`, `Appearance`, `appearance.fonts`: fonts.gstatic.com TTFs, downloaded in the background and used from the launch after; empty or invalid settings keep the built-in five tabs and the template's bar).
- **GoKwik** (`CHECKOUT=gokwik`, `LOGIN=kwikpass`, each on its own, with `GOKWIK_MERCHANT_ID`): GoKwik's hosted checkout in a web view where Shopify's Checkout Kit would open (the cart's id and the storefront token go to it; `orderSuccess` spends the cart; non-http links such as UPI apps go to the OS), and KwikPass phone + OTP login in place of customer accounts (GoKwik's backend finds or creates the Shopify customer; the app keeps GoKwik's tokens and `{phone, email, shopifyCustomerId}`, passes the session to GoKwik checkout and the email and phone to the cart's buyer identity; orders and addresses, which need the Customer Account API, are hidden). With both `shopify` (the default) none of it runs.
- **Delivery dates** (`delivery.enabled` in the settings, nothing at build time): `DeliveryStore` (`data/Delivery.kt`, `Data/Delivery.swift`) keeps the customer's pincode and city on the device and asks Krypton's `/v1/delivery/{shop}` (`SETTINGS_URL` with `settings` → `delivery`) for `{ pincode, serviceable, cod, date, city }`, once per pincode a session. The product page's "purchase" group shows it under availability (`ProductDelivery`); its sheet takes a typed pincode, the device's location (permission asked only on that tap; geocoded on the device, only the pincode leaves it) or a saved address. With none set, the default address fills it in, else the device's location when permission was already granted (`fill` never replaces a chosen one). Off: none of it runs and no location is ever asked for.
- **Push** (`PUSH=true`, needs Firebase): `PushStore` (`data/Push.kt`, `Data/Push.swift`) subscribes to the FCM topics `all` and `android` / `ios` once the shopper turns notifications on (Account, or the one offer after a first purchase; never at first launch) and reports `{ installId, platform, optedIn }` to `DEVICES_URL`. A notification's `link` opens through `Links.resolve`. Without `PUSH` nothing of it is wired.
- The app icon and the launch screen are files, made from the store's logo when the project was generated; README.md, "App icon and launch screen", lists them.
- `android/app/src/main/assets/queries/*.graphql` and `ios/App/Resources/queries/*.graphql`: the same GraphQL documents (Storefront and Customer Account API 2026-10), one operation per file, fragments already inlined. Keep the two folders identical.
- **Data:** never call GraphQL from screens. Use the typed facades: `StorefrontApi` / `CustomerAccountApi` (`android/app/src/main/java/app/storefront/data/`) and `StorefrontAPI` / `CustomerAccountAPI` (`ios/App/Data/`). Same method names on both; they return typed models and `Page<T>` for lists, and throw `ArgonApiError` / `ArgonAPIError`.
- **UI:** build views from the component library, not raw platform controls: `android/ui` (Compose module, package `app.argon.ui`, `ArgonTheme`, `Argon*` components) and `ios/ArgonUI` (local Swift package, `.argonTheme(accentHex:)`, `Argon*` components). Debug builds show every component at Account → Components. The library knows nothing about Shopify; pass it plain values.
- **Pages** are templates built from shared blocks. Home: one view per `HomeTemplate` (`fashion`, `beauty`, `grocery`, `b2b`) taking a `HomeContent`. Collection: one screen, two `CollectionTemplate`s (`top`, `bottom`). Blocks every page shares (`Blocks`): `ProductCardView` (styles `standard`, `compact`, `row`), `PriceView`, `QuickAdd`, `SectionHeader`, `TrustRow`, `StoreImage`.
- **Optional data stays optional.** A field the store's token can't read comes back null (`ACCESS_DENIED` is tolerated), and secondary calls on a page (reviews, recommendations, product metafields, the selected variant's details) fail silently: the page still shows.
- **Analytics:** screens and stores report an `AnalyticsEvent` to the one hub, `Analytics` (`data/Analytics.kt`, `Data/Analytics.swift`); never call a provider's SDK from a screen. Providers (Google Analytics, Meta, MoEngage) are `AnalyticsSink`s, each compiled in only when it is configured: Android's `app/build.gradle.kts` decides from `app/google-services.json` and the config keys, and on iOS each sink sits in `#if canImport(...)` with its package in `ios/Package.swift` (in Xcode the package is added by hand). `Analytics` does nothing while the "Share usage data" switch is off. Debug builds log every event (`Analytics: add_to_cart {…}`). README.md, "Analytics", has the setup.
- `server/` (there when Google Analytics or Meta was configured, or it was asked for): a Cloudflare Worker in one file, `worker.js`, with no dependencies. It reports app purchases from Shopify's order webhook, and only purchases. It reads the attributes the app puts on a cart when it creates it (`_argon_platform`, `_ga_app_instance_id`, `_meta_anon_id`, `_meta_extinfo`, `_meta_tracking`) and uses the apps' ids: Google Analytics' `transaction_id` is the order's numeric id, Meta's event id is `purchase-<order id>`. Change those names or ids in the apps and in the Worker together.
- **One purchase per provider.** Meta gets it from the app and from the Worker and counts it once (same event id). Google Analytics would count both, so `SERVER_PURCHASE` picks one side: with `false` the app's Firebase sink sends the purchase and puts no `_ga_app_instance_id` on the cart; with `true` it sends no purchase and puts the id on the cart, and the Worker reports to Google Analytics exactly the orders that carry it. Keep it that way: never both for one order.
- Shared names on both platforms: `ProductCard`, `Section`, `Route`, `Links`, `Variants`, `Sections`, `HomeContent`, `CartStore`, `WishlistStore`, `RecentlyViewedStore`, `AuthStore`, `BuyerStore`, `JudgeMe`, `Pkce`, `Analytics`, `AnalyticsEvent`, `AnalyticsSink`.
- The only Shopify SDK is Checkout Kit. No Mobile Buy SDK, no Apollo, no DI framework.
- New Swift files placed in `ios/App/` or `ios/AppTests/` are picked up automatically; don't hand-edit `App.xcodeproj`.

## Add a query

1. Add `<Name>.graphql` to both `queries/` folders (identical, self-contained: copy any fragment it uses into the file). Storefront operations take `$country: CountryCode` and `$language: LanguageCode` with `@inContext(country: $country, language: $language)`; select `__typename` on unions and interfaces.
2. On each platform add the typed model and a facade method with the same name.
3. Add the response's `data` as `<Name>.json` to both fixture folders (`android/app/src/test/resources/fixtures/`, `ios/AppTests/Fixtures/`) and a decoding check in the fixture tests (they fail on a fixture without one).

## Add a home template

1. Add the case to `HomeTemplate` and a view for it on each platform, built from the blocks and `Argon*` components, taking `HomeContent` (banners, categories, rails).
2. Add its three placeholder banners as `home-<template>-1...3.jpg` to both image folders (and to `ios/xtool.yml`), and its default banner copy to `Sections`.

## Add a home section type

The home screen is the `mobile_screen` metaobject (handle `home`) whose `sections` field lists section entries.

1. In Shopify admin define the new metaobject type (Settings → Custom data → Metaobjects) with storefront access on.
2. Add the type to the `sections` field's allowed types on the `mobile_screen` definition.
3. Select its fields in `HomeScreen.graphql` (both folders).
4. On each platform add it to `Sections` and a view for the new `Section` type built from `Argon*` components. Unknown types are skipped, never crash.

## Screens v2: add a section type

A screen is the `app_screen` metaobject with its handle (`home`, `product`, ..., or a custom page); its `template` JSON
lists sections (docs/superpowers/specs/2026-10-19-screens-v2-design.md). Unknown types are skipped, so an old app ignores a new one.

1. Add the type, its settings and defaults to `SECTION_TYPES` in `contract/screens.js` (the editor's strict side) and a case to the sample templates in `contract/fixtures/screens/`.
2. On each platform add it to `ScreenTemplate.TYPES` and a `SectionContent` case read from its settings (`Screens.kt` / `Screens.swift`); every value goes through a lenient `SectionSettings` reader with the spec's default.
3. Draw it in `ui/sections/` / `UI/Sections/` from `Argon*` components and the shared blocks, and add the case to `SectionView`. Text goes through `env.text(...)` (Liquid), taps through `env.open(...)` (it reports `select_promotion`). Products and collections it shows are GIDs: add them to `sectionNodeIds` so the one `SectionNodes` query loads them.
4. Add its decoding to the template tests on both platforms.

## Screens v2: add a Liquid filter

1. Add the case to `contract/fixtures/liquid/cases.json`; when liquidjs lacks it, register it in `test/liquid.test.js` with Shopify's behaviour (`npm test` checks every case against liquidjs).
2. Add it to the filter `when` / `switch` in `Liquid.kt` and `Liquid.swift` (same name, same output). Both apps' Liquid tests run every case.

## Rule

Android and iOS stay screen-for-screen and type-for-type identical: same screens, same names, same behavior. Any change lands on both platforms together.
