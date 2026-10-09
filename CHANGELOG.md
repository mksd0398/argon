# Changelog

## Unreleased

### Added

- **A native component library in every app:** 29 components (Accordion to Top bar) with a store-themed palette, Instrument Serif and Hanken Grotesk, and a debug-only gallery at Account → Components.
  - Android: a Compose `ui` module.
  - iOS: a local `ArgonUI` Swift package.
  - Each component uses the platform's own control where one exists and is custom only where none does.
- **The complete Storefront and Customer Account API, prebuilt and typed** (2026-10).
  - 52 operations: catalogue, search, menus, pages, blogs, metaobjects, store locations, every cart mutation, and the customer's profile, orders, addresses, email marketing and returns.
  - Typed facades on both platforms: `StorefrontApi`/`StorefrontAPI` and `CustomerAccountApi`/`CustomerAccountAPI`.
  - Every operation runs with the buyer's country and language.
- **Contract checks:**
  - Every document is validated offline against the 2026-10 schemas.
  - Every operation has a recorded or schema-correct fixture, and both apps' tests decode every fixture.

### Changed

- Text on the brand colour is black or white, whichever contrasts more (at least 4.58:1 for any colour).
- The apps decode responses into typed models; the hand-written parsers are gone.

- The Headless channel step is guided:
  - Argon opens the channel in your browser and prints Shopify's exact admin path for each value, including setting the login client type to Public (mobile app).
  - It checks the Storefront token as you paste it and asks again if Shopify rejects it.
  - It confirms that the app can see your products and read the home screen.
  - It warns when a client ID doesn't look like one.

### Fixed

- Checkout now shows the store's own checkout branding. Checkout Kit uses the `web` color scheme (Android `ColorScheme.Web()`, iOS `.web`) instead of its default generic light/dark theme.

## 0.1.0 — 2026-10-05

First release.

### Added

- `npx @mksd0398/argon my-store-app` generates a SwiftUI iOS app (iOS 17+) and a
  Jetpack Compose Android app (minSdk 26) for one Shopify store, kept screen for
  screen identical. Both use Storefront API `2026-10` through a hand-written
  GraphQL client, and Checkout Kit (Swift 3.9.1, Android 3.6.3) for checkout.
- Tabs for Home, Shop, Wishlist, Cart and Account, with search, product lists
  with sorting and filters, product pages with variants and metafields, and a
  persisted cart.
- Customer Account API login (OAuth 2.0 + PKCE, Mobile client) with orders and a
  *Delete account* entry. Tokens are stored encrypted.
- A home screen the merchant edits from Shopify admin: an ordered list of
  `mobile_banner`, `mobile_products` and `mobile_collections` metaobjects under
  a `mobile_screen` entry. Without one, the apps build a fallback home from the
  store's brand, collections and products.
- Store provisioning through the Shopify CLI: creates the four metaobject
  definitions, seeds the `home` entry, and warns about a storefront password or
  legacy customer accounts. One manual Headless-channel step, printed with the
  store's values.
- `--demo` runs against `mock.shop` with no credentials. Flags: `--store`,
  `--token`, `--client-id`, `--bundle-id`, `--skip-content`, `--yes`. With no
  terminal, nothing is asked.
- Every generated project carries a README, an `AGENTS.md` and a `CLAUDE.md`
  that points to it.
- GitHub Actions: the CLI tests (including the live `mock.shop` contract test),
  a Gradle test and build of a generated Android app, and an `xcodebuild` build
  and test of a generated iOS app on macOS.

### Known limits

- `mock.shop` doesn't implement `nodes(ids:)`, so the Wishlist tab stays empty
  on the demo store. It works on real stores.
- Not in this release: Markets, Shop Pay and Apple Pay buttons, discount codes
  in the cart, wishlist sync to the customer account, push notifications,
  universal links and App Links.
