# Agent guide

Two native apps for one Shopify store, kept identical screen for screen: `android/` (Kotlin, Jetpack Compose, package `app.storefront`) and `ios/` (Swift, SwiftUI, target `App`). See README.md for running, config and store setup.

## Layout

- `android/shopify.properties`, `ios/Config.xcconfig`: per-store config. Same keys on both (`SHOP_DOMAIN`, `STOREFRONT_TOKEN`, `CUSTOMER_CLIENT_ID`, `SHOP_ID`, `API_VERSION`, `APP_NAME`, `BUNDLE_ID`, `PDP_METAFIELDS`).
- `android/app/src/main/assets/queries/*.graphql` and `ios/App/Resources/queries/*.graphql`: the same GraphQL documents (Storefront and Customer Account API 2026-10), one operation per file, fragments already inlined. Keep the two folders identical.
- **Data:** never call GraphQL from screens. Use the typed facades: `StorefrontApi` / `CustomerAccountApi` (`android/app/src/main/java/app/storefront/data/`) and `StorefrontAPI` / `CustomerAccountAPI` (`ios/App/Data/`). Same method names on both; they return typed models and `Page<T>` for lists, and throw `ArgonApiError` / `ArgonAPIError`.
- **UI:** build views from the component library, not raw platform controls: `android/ui` (Compose module, package `app.argon.ui`, `ArgonTheme`, `Argon*` components) and `ios/ArgonUI` (local Swift package, `.argonTheme(accentHex:)`, `Argon*` components). Debug builds show every component at Account → Components. The library knows nothing about Shopify; pass it plain values.
- Shared names on both platforms: `ProductCard`, `Section`, `Route`, `Links`, `Variants`, `Sections`, `CartStore`, `WishlistStore`, `AuthStore`, `Pkce`.
- The only Shopify SDK is Checkout Kit. No Mobile Buy SDK, no Apollo, no DI framework.
- New Swift files placed in `ios/App/` or `ios/AppTests/` are picked up automatically; don't hand-edit `App.xcodeproj`.

## Add a query

1. Add `<Name>.graphql` to both `queries/` folders (identical, self-contained: copy any fragment it uses into the file). Storefront operations take `$country: CountryCode` and `$language: LanguageCode` with `@inContext(country: $country, language: $language)`; select `__typename` on unions and interfaces.
2. On each platform add the typed model and a facade method with the same name.
3. Add the response's `data` as `<Name>.json` to both fixture folders (`android/app/src/test/resources/fixtures/`, `ios/AppTests/Fixtures/`) and a decoding check in the fixture tests (they fail on a fixture without one).

## Add a home section type

The home screen is the `mobile_screen` metaobject (handle `home`) whose `sections` field lists section entries.

1. In Shopify admin define the new metaobject type (Settings → Custom data → Metaobjects) with storefront access on.
2. Add the type to the `sections` field's allowed types on the `mobile_screen` definition.
3. Select its fields in `HomeScreen.graphql` (both folders).
4. On each platform add it to `Sections` and a view for the new `Section` type built from `Argon*` components. Unknown types are skipped, never crash.

## Rule

Android and iOS stay screen-for-screen and type-for-type identical: same screens, same names, same behavior. Any change lands on both platforms together.
