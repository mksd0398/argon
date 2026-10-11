# Changelog

## Unreleased

### Added

- **Reviews without a Judge.me token:** with `JUDGEME_PUBLIC_TOKEN` empty the apps read the reviews through the endpoint Judge.me's own storefront widget uses (the list and the count; no star breakdown). It is not a documented API, so the token stays the supported route. Android so far.
- **Free shipping only in the shop's currency:** the cart's free-shipping row is hidden when the shopper buys in another currency, because `FREE_SHIPPING_THRESHOLD` is a number in the shop's own. Android so far.
- **Analytics: Google Analytics, Meta and MoEngage**, off unless asked for. An app carries a provider's SDK only when that provider is configured.
  - CLI: `--firebase-android` and `--firebase-ios` (Firebase's own files, copied in), `--meta-app-id` and `--meta-client-token`, `--moengage-workspace-id` and `--moengage-data-center`, or one "Analytics" question when run interactively. New config keys `META_APP_ID`, `META_CLIENT_TOKEN`, `MOENGAGE_WORKSPACE_ID`, `MOENGAGE_DATA_CENTER`, empty by default, and `SERVER_PURCHASE`, `false` by default.
  - Firebase's files are checked against the app's bundle ID before they are copied. A file for another app stops the run with both ids, because Google Analytics would get nothing from it.
  - iOS: the configured providers' Swift packages are written into `ios/Package.swift` and Meta's keys into the xtool Info.plist. In Xcode the packages are added by hand.
  - One hub in the apps that every screen and store reports to, with Google Analytics' event names, and a debug log of each event.
  - Consent: a "Share usage data" switch on the Account screen, on by default.
  - **The purchase from a server:** `server/`, one Cloudflare Worker in one file with no dependencies, written with Google Analytics or Meta, or with `--server`. It takes Shopify's "Order creation" webhook, checks its signature, ignores orders that were not placed in the app, and sends the purchase to Meta (Conversions API) and Google Analytics (Measurement Protocol) with the ids the app uses. Only the purchase goes through it: the keys that report a sale can't be in an app.
    - Meta gets the purchase from the app and from the server, and counts it once.
    - Google Analytics gets it from one side only, because it would count both: the app by default, the server with `--server` (`SERVER_PURCHASE=true`).
  - Not included: MoEngage push notifications and in-app messages.
- **The app icon and the launch screen come from the store's logo.** When it generates a project, the CLI asks the Storefront API for the brand's square logo (else its default logo) as a PNG and writes the Android adaptive icon's logo and background colour, the iOS app icon, and the iOS launch logo and background.
  - The background is the logo's own (its top-left pixel when opaque), else white.
  - Without a usable logo, Android keeps the template's icon and iOS gets a plain one on the brand's primary colour (near-black when the brand has none). A logo never stops a run: a failed download or an unreadable image only warns.
  - No new dependency: a small PNG reader and writer on Node's `zlib` (`lib/png.js`).
  - `ios/xtool.yml` gets `iconPath`, so an xtool build has the same icon.
- **Onboarding:** a three-page welcome before the tabs the first time the app opens, over the home template's stock banners, with Skip, and Sign in on the last page when login is configured. `ONBOARDING=false` turns it off.
- **An edge-to-edge hero on the fashion home:** the hero starts at the top edge of the screen, under a transparent top bar that turns solid as the hero scrolls away. The top bar has a new `overlay` variant for it.
- **Cart:**
  - Progress towards free shipping when `FREE_SHIPPING_THRESHOLD` is set (an amount in the shop's currency; the demo sets 150).
  - Discount codes: a field to apply one, the applied codes as removable tags, and a message for a code that can't be used on the cart.
  - Each line shows its compare-at price and its discounts. The summary shows Subtotal, Discounts, You save and Total.
  - "You may also like": recommendations for the first item, without products already in the cart.
- **Page templates**, built from the component library, the same on both platforms.
  - Home: four layouts picked by `HOME_TEMPLATE`: `fashion`, `beauty`, `grocery`, `b2b`. Each shows the store's own banners, collections and product rows; until the store has banners, three stock photos from Shopify's Burst.
  - Collection: two layouts picked by `COLLECTION_TEMPLATE`: `top` (sticky sort and filter bar) and `bottom` (floating bar). Colour filters and product cards show swatches, from Shopify's swatch data or matched from the colour's name. Price filters use a range slider.
  - Product: variant swatches with unavailable values struck out, bundle contents, unit prices, quantity rules and volume pricing, subscriptions, stock and pickup lines, a sticky add-to-cart bar, Buy now, policies, recommendations and recently viewed.
  - Orders: a list with shipment status, and an order page with tracking, payments, refunds, returns and business details.
  - Returns and exchanges: a three-step request. An exchange is sent as a return whose note names the wanted variant (the Customer Account API has no exchange input).
  - Account: profile, addresses, email offers, company and location, store credit, policies.
- **Reviews from Judge.me**, drawn natively: the rating summary, the reviews with photos and store replies, and a form to write one. Uses Judge.me's Widget API with the store's public token (`JUDGEME_PUBLIC_TOKEN`); empty hides reviews.
- **B2B:** a signed-in company contact sees the company location's catalogue prices everywhere, checks out as the company, and can switch location.
- **A sample account on the demo store:** mock.shop has no customer accounts, so its Account tab can preview the signed-in pages with sample orders, a return and a company.
- CLI: `--home`, `--collection` and `--judgeme-token`, asked for when run interactively.
- `SHOW_VENDOR` (default `false`): product cards and the product page show the vendor only when it is `true`.
- Components: `ArgonRating`, `ArgonQuantityStepper`, `ArgonSwatch`.
- **A native component library in every app:** 29 components (Accordion to Top bar) with a store-themed palette, Instrument Serif and Hanken Grotesk, and a debug-only gallery at Account → Components.
  - Android: a Compose `ui` module.
  - iOS: a local `ArgonUI` Swift package.
  - Each component uses the platform's own control where one exists and is custom only where none does.
  - The carousel runs edge to edge: neighbouring pages peek in by 4% of the width, with a gap between pages.
  - The gallery renders lazily, so off-screen components don't draw or animate.
- **iOS without a Mac:** `ios/Package.swift` and `ios/xtool.yml` let [xtool](https://xtool.sh) build the same sources on Linux or Windows (WSL) and install the app on an iPhone. The app then reads its per-store values from the bundled `Config.xcconfig`.
- **The complete Storefront and Customer Account API, prebuilt and typed** (2026-10).
  - 55 operations: catalogue, search, menus, pages, blogs, metaobjects, store locations, every cart mutation, and the customer's profile, orders, addresses, email marketing and returns.
  - Typed facades on both platforms: `StorefrontApi`/`StorefrontAPI` and `CustomerAccountApi`/`CustomerAccountAPI`.
  - Every operation runs with the buyer's country and language.
- **Contract checks:**
  - Every document is validated offline against the 2026-10 schemas.
  - Every operation has a recorded or schema-correct fixture, and both apps' tests decode every fixture.

### Changed

- A field the store's token isn't allowed to read (Shopify answers `ACCESS_DENIED`) now comes back empty instead of failing the whole request: a token without the inventory permission shows no stock count rather than no product page.
- The product page's `PDP_METAFIELDS` load in their own request, and selling plans come from the selected variant, so neither can blank the page.
- Every Storefront call can run as a B2B buyer (`@inContext(buyer:)`).
- Text on the brand colour is black or white, whichever contrasts more (at least 4.58:1 for any colour).
- The apps decode responses into typed models; the hand-written parsers are gone.
- The Headless channel step is guided:
  - Argon opens the channel in your browser and prints Shopify's exact admin path for each value, including setting the login client type to Public (mobile app).
  - It checks the Storefront token as you paste it and asks again if Shopify rejects it.
  - It confirms that the app can see your products and read the home screen.
  - It warns when a client ID doesn't look like one.

### Fixed

- Checkout no longer reloads about once a second for a signed-in customer. Shopify answers every cart buyer update with a new checkout URL, and the cart attached the customer each time it prepared checkout, which changed the cart and prepared checkout again. A cart's buyer is now attached once.
- A screen that failed to load (offline at launch, or started behind the lock screen) now reloads by itself when the app returns to the foreground. On Android the error reads "Can't reach the store. Check your internet connection." instead of a raw hostname error.
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
