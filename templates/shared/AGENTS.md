# Agent guide

Two native apps for one Shopify store, kept identical screen for screen: `android/` (Kotlin, Jetpack Compose, package `app.storefront`) and `ios/` (Swift, SwiftUI, target `App`). See README.md for running, config and store setup.

## Layout

- `android/shopify.properties`, `ios/Config.xcconfig`: per-store config. Same keys on both (`SHOP_DOMAIN`, `STOREFRONT_TOKEN`, `CUSTOMER_CLIENT_ID`, `SHOP_ID`, `API_VERSION`, `APP_NAME`, `BUNDLE_ID`, `PDP_METAFIELDS`).
- `android/app/src/main/assets/queries/*.graphql` and `ios/App/Resources/queries/*.graphql`: the same GraphQL documents, one operation per file, fragments already inlined. Keep the two folders identical.
- Shared names on both platforms: `Storefront`, `ProductCard`, `Section`, `Route`, `Links`, `Variants`, `Sections`, `CartStore`, `WishlistStore`, `AuthStore`, `Pkce`.
- The only Shopify SDK is Checkout Kit. No Mobile Buy SDK, no Apollo, no DI framework.
- New Swift files placed in `ios/App/` are picked up automatically; don't hand-edit `App.xcodeproj`.

## Add a query

1. Add `<Name>.graphql` to both `queries/` folders (identical, self-contained: copy any fragment it uses into the file).
2. On each platform add a model and a parser for the response.
3. Call `storefront.query("Name", vars)`.

## Add a home section type

The home screen is the `mobile_screen` metaobject (handle `home`) whose `sections` field lists section entries.

1. In Shopify admin define the new metaobject type (Settings → Custom data → Metaobjects) with storefront access on.
2. Add the type to the `sections` field's allowed types on the `mobile_screen` definition.
3. Select its fields in `HomeScreen.graphql` (both folders).
4. On each platform add a parser (in `Sections`) and a view for the new `Section` type. Unknown types are skipped, never crash.

## Rule

Android and iOS stay screen-for-screen and type-for-type identical: same screens, same names, same behavior. Any change lands on both platforms together.
