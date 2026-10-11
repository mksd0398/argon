# Argon: native iOS and Android storefronts for Shopify

**One command generates a SwiftUI iOS app and a Jetpack Compose Android app for one Shopify store.**
Storefront API, Customer Account login, Shopify's Checkout Kit. No framework, no backend.

> A sibling of [Nitrogen](https://www.npmjs.com/package/@mksd0398/nitrogen). Nitrogen scaffolds Shopify apps on Firebase; Argon scaffolds a store's own mobile apps.

[![npm version](https://img.shields.io/npm/v/%40mksd0398%2Fargon.svg)](https://www.npmjs.com/package/@mksd0398/argon)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

```bash
npx @mksd0398/argon my-store-app
```

<p align="center">
  <img src="https://img.shields.io/badge/Storefront%20API-2026--10-7AB55C?logo=shopify&logoColor=white" />
  <img src="https://img.shields.io/badge/iOS-17%2B-000000?logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Android-minSdk%2026-3DDC84?logo=android&logoColor=white" />
  <img src="https://img.shields.io/badge/Node-18%2B-339933?logo=nodedotjs&logoColor=white" />
</p>

---

## What is this?

The apps work the way a Liquid theme does. They render whatever the store contains, and the merchant controls the home screen, navigation, branding and catalogue from Shopify admin, with no app release.

- **Two native codebases**, SwiftUI (iOS 17+) and Jetpack Compose (Android minSdk 26), kept screen for screen identical
- **Tabs**: Home, Shop, Wishlist, Cart, Account, with search from Home and Shop
- **Page templates**, picked in the config: four home screens (fashion, beauty, grocery, industrial & B2B) and two collection layouts (sticky filter bar at the top, floating bar at the bottom), with colour swatches ([Page templates](#page-templates))
- **A product page built to sell**: variant swatches, bundles, unit prices, volume pricing and quantity rules, B2B catalogue prices, subscriptions, a sticky add-to-cart bar, recommendations, recently viewed, and Judge.me reviews
- **Orders and returns**: tracking, payments, refunds, and a return or exchange request, from the Customer Account API
- A persisted **cart** with a free-shipping progress bar, discount codes, the savings on each line and in the summary, and recommendations
- **Checkout** through Checkout Kit: Shopify owns payment, tax, shipping, discounts and orders
- **Onboarding**: a three-page welcome the first time the app opens, shown once
- **Login** with the Customer Account API (OAuth 2.0 + PKCE), profile, addresses, company, store credit, and the *Delete account* entry both app stores require
- **A home screen the merchant edits**: an ordered list of metaobject sections ([Content model](#content-model))
- **Branding** from the store's own colours and logo
- **The app icon and the launch screen**, made from the store's logo when the project is generated ([App icon and launch screen](#app-icon-and-launch-screen))
- **Analytics**, only when asked for: Google Analytics, Meta and MoEngage behind one event hub, a consent switch, and a small server that reports the purchase ([Analytics](#analytics))
- **A native component library**: 29 themed components on each platform (Compose `ui` module, `ArgonUI` Swift package), with a debug gallery at Account → Components
- **The full Storefront and Customer Account API, prebuilt**: 55 typed operations behind `StorefrontApi` and `CustomerAccountApi` (same names on iOS), checked against Shopify's 2026-10 schemas
- **One Shopify SDK**: Checkout Kit. A hand-written GraphQL client, no Mobile Buy SDK, no Apollo, no DI framework
- **`AGENTS.md`, `CLAUDE.md` and a README** in every generated project, so an AI coding agent follows the same rules with nothing installed

`--demo` runs against `mock.shop` with no credentials. A real store takes one CLI session and a few clicks in the Headless channel; Argon opens it and checks each value you paste.

> Argon is an independent community project. **Not affiliated with or endorsed by Shopify.**

---

## Quick Start

### Prerequisites

| Tool | For | Required? |
|------|-----|-----------|
| Node.js 18+ | The CLI | Yes |
| [Shopify CLI](https://shopify.dev/docs/api/shopify-cli) (`npm i -g @shopify/cli`) | Creating the home screen content on a real store | Not with `--demo` or `--skip-content` |
| Android Studio Quail 4 (2026.1.4)+, the first to support AGP 9.4 ([table](https://developer.android.com/build/releases/about-agp)) | Building and running the Android app | To run Android |
| A Mac with Xcode 16+ | Building and running the iOS app | To run iOS |
| git | The initial commit | Optional |

A missing Xcode or Android SDK only produces a warning. You can generate the project on any OS, but **running the iOS app needs a Mac**. The iOS app is built and tested on every push by the macOS CI job, so a generated project is verified without one.

### Try the demo

```bash
npx @mksd0398/argon demo-app --demo --yes
```

The apps use `mock.shop`: no account, no token. Menu, catalogue and cart work, and the app icon is mock.shop's logo. Metaobjects return null there, so Home shows the template's stock banners over the store's collections. It has no customer accounts and no reviews app, so the Account tab offers **Preview with a sample account** (sample orders, a return and a company) and product pages show sample reviews, to see those pages. **`mock.shop` doesn't implement `nodes(ids:)`, so the Wishlist tab stays empty on it.** It works on real stores.

### A real store

```bash
npx @mksd0398/argon my-store-app
```

1. **Name**: the directory and the bundle / application ID (`com.<store>.<project>`).
2. **Store**: your `*.myshopify.com` domain.
3. **Admin session**: `shopify store auth` as a staff user, with `read_products`, `write_metaobject_definitions` and `write_metaobjects`.
4. **Provision**: creates the four content definitions if missing, and seeds the `home` screen from your collections and products if it doesn't exist. Warns if the storefront password is on or legacy customer accounts are in use. Existing definitions and an existing `home` entry are left as they are.
5. **Headless channel**: the part Shopify only allows in admin ([below](#the-headless-channel-step)). Argon opens it in your browser and checks the token with live calls.
6. **Generate** both apps, make the app icon and launch screen from the store's logo, write the config, run `git init` and commit.

Argon never stores Admin credentials and never changes your Shopify CLI config.

For an agent or CI, pass everything as flags. With no terminal, nothing is asked, and a missing `--store` or `--token` stops with exit code 1:

```bash
npx @mksd0398/argon my-store-app --store=my-store --token=PUBLIC_TOKEN --client-id=CLIENT_ID --yes
```

### The Headless channel step

Shopify has no API to create a Headless storefront or its login client, so these are clicks in admin. The Hydrogen CLI's automatic setup only works through Shopify's own CLI and sets up a web login client, not the Mobile one a native app needs, so Argon uses the Headless channel. Argon opens the [Headless channel](https://apps.shopify.com/headless) and prints these with your store's values filled in:

1. Install the **Headless** channel and create a storefront (Sales channels → Headless).
2. Make your products and collections available to the storefront. Each Headless storefront is its own sales channel, listed by its name (Products → filter by Online Store → select all → Include in sales channels).
3. In **Storefront API**, copy the **public** access token. Its permissions allow reading metaobjects (the home screen) by default. The apps leave out whatever a permission you turn off would have fed: without `unauthenticated_read_product_inventory`, for example, the product page shows no "Only 3 left".
   Argon checks it as you paste it, asks again if Shopify rejects it, and then checks that the app can see your products and read the home screen.
4. In **Customer Account API**, edit Client type to **Public (mobile app)** and save. Shopify fills in the Callback URI `shop.<shop id>.app://callback`; check it, then copy the **Client ID**.

The client ID can be skipped: login is then hidden until `CUSTOMER_CLIENT_ID` is set. Argon only checks its format (a UUID); Shopify doesn't let scripts test a login client, so the first sign-in in the app is the real check.

### Store prerequisites

- **New customer accounts are on** (Settings → Customer accounts). Legacy accounts are not supported.
- **The storefront password is off.** Checkout Kit can't open checkout while it's on.
- **Products and collections are available to the storefront's sales channel**, and its Storefront API keeps the metaobject read permission. Without them the app shows an empty or fallback home.
- **Search & Discovery filters are configured.** Product-list and search filters appear only after that.

### Run the apps

```bash
cd my-store-app
```

- **iOS**: open `ios/App.xcodeproj` in Xcode 16+, pick a simulator, Run.
- **Android**: open `android/` in Android Studio, or `cd android && ./gradlew assembleDebug`.

Per-store values live in `ios/Config.xcconfig` and `android/shopify.properties`, with the same eighteen keys on both (`SHOP_DOMAIN`, `STOREFRONT_TOKEN`, `CUSTOMER_CLIENT_ID`, `SHOP_ID`, `API_VERSION`, `APP_NAME`, `BUNDLE_ID`, `PDP_METAFIELDS`, `HOME_TEMPLATE`, `COLLECTION_TEMPLATE`, `JUDGEME_PUBLIC_TOKEN`, `SHOW_VENDOR`, `ONBOARDING`, `FREE_SHIPPING_THRESHOLD`, `META_APP_ID`, `META_CLIENT_TOKEN`, `MOENGAGE_WORKSPACE_ID`, `MOENGAGE_DATA_CENTER`). The generated README explains each. With an empty token on a store other than `mock.shop`, the app shows a setup screen naming the missing key instead of failing at run time.

---

## Page templates

Every app carries all of them; two config keys pick what it shows, so switching is a one-line change and a rebuild.

| Key | Values |
|---|---|
| `HOME_TEMPLATE` | `fashion` (editorial, image-led), `beauty` (soft cards, ratings, shop by routine), `grocery` (search first, dense, quick add), `b2b` (SKUs, trade prices, bulk quantities) |
| `COLLECTION_TEMPLATE` | `top` (sort and filters in a sticky bar), `bottom` (a floating bar) |

- **Home** shows the store's own banners, collections and product rows from the [content model](#content-model) in the template's layout. Until the store has banners, each template shows three stock photos from Shopify's [Burst](https://www.shopify.com/stock-photos) (`templates/images/CREDITS.md`). On the `fashion` home the hero runs to the top edge of the screen, under a transparent top bar that turns solid as the hero scrolls away.
- **Onboarding** (`ONBOARDING`, `true` by default): three full-screen pages over the home template's stock photos, shown once before the tabs, with Skip, and Sign in on the last page when login is configured. `false` turns it off.
- **Cart**: a progress bar towards free shipping when `FREE_SHIPPING_THRESHOLD` is set (an amount in the shop's currency; the demo sets 150), a discount code field with the applied codes as removable tags, each line's compare-at price and discounts, "You may also like", and a summary with Subtotal, Discounts, You save and Total.
- **Colour swatches** use Shopify's swatch data, and fall back to the colour's name ("Peacock Blue" is shown blue) for stores that have none.
- **Reviews** come from [Judge.me](https://judge.me)'s Widget API with the store's *public* token (`JUDGEME_PUBLIC_TOKEN`, from Judge.me admin → Settings → Integrations → View API tokens), drawn natively. Leave it empty to hide reviews. Never use the private token: it would ship inside the app.
- **B2B**: when the signed-in customer is a company contact, every price is the company location's catalogue price, with quantity rules and volume pricing on the product page.
- **Returns and exchanges** use Shopify's self-serve returns. The Customer Account API takes return requests only, so an exchange is sent as a return whose note names the wanted variant; the merchant completes it in admin.

---

## App icon and launch screen

Both are part of the app binary, so nothing can set them at run time. Argon makes them when it generates the project, from the logo in the store's brand settings (Shopify admin → Settings → Brand). It asks the Storefront API for the square logo, or the default logo when there is none, as a PNG of at most 1024 px, and writes:

| File | Content |
|---|---|
| `android/app/src/main/res/drawable-xxxhdpi/launcher_logo.png` | The logo, at most 264×264 px (66 dp, the adaptive icon's safe zone), transparent as downloaded |
| `android/app/src/main/res/values/launcher.xml` | `launcher_background`, the colour behind the logo |
| `ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | 1024×1024, opaque: the logo scaled to fit 62% of the side (a small logo is enlarged), on the background colour |
| `ios/App/Assets.xcassets/LaunchLogo.imageset/LaunchLogo.png` | The logo, at most 600×600 px, transparent |
| `ios/App/Assets.xcassets/LaunchBackground.colorset/Contents.json` | The background colour |

The background colour is the logo's top-left pixel when that pixel is opaque (a logo on its own background), else white. A light logo on a transparent background would vanish on white, so it goes on the brand's primary colour when that is dark, else on near-black.

Without a usable logo (none set, the download fails, or a file the built-in PNG reader can't decode, such as an interlaced PNG), Android keeps the template's own icon and iOS gets a plain one on the brand's primary colour (near-black when the brand has none). Argon prints whether the logo was used; a logo never stops a run.

To change them later, replace those files (the generated README lists them), or set the logo in Shopify and generate the project again.

---

## Analytics

Off unless asked for. An app carries a provider's SDK only when that provider is configured: pick the providers in the Analytics question, or pass their flags.

| Provider | Flags | What the store brings |
|---|---|---|
| Google Analytics 4 | `--firebase-android`, `--firebase-ios` | Firebase's own files, `google-services.json` and `GoogleService-Info.plist`: one for each app, downloaded from the Firebase console for an app registered with this project's bundle ID |
| Meta | `--meta-app-id`, `--meta-client-token` | The Meta app's ID and its client token (`META_APP_ID`, `META_CLIENT_TOKEN`) |
| MoEngage | `--moengage-workspace-id`, `--moengage-data-center` | The workspace ID and the data center, 1 to 6: the number in the dashboard's address (`MOENGAGE_WORKSPACE_ID`, `MOENGAGE_DATA_CENTER`) |

- **One hub.** Every screen and store reports to it, and the providers plug in behind it: screen views, product lists and product pages, search, wishlist and cart changes, the checkout steps, the purchase and sign-in, under Google Analytics' event names. Product ids are Shopify's numeric ids, the ones Google's and Meta's catalogues use. Debug builds log each event (`Analytics: add_to_cart {…}`), so the events can be checked with no provider account.
- **Firebase's files are checked before they are copied.** Each must be for this app's bundle ID. A file for another app stops the run with both ids, because Google Analytics would get nothing from it.
- **iOS packages.** Argon writes the configured providers' Swift packages into `ios/Package.swift` (the xtool build), and Meta's keys into its Info.plist. It never edits `App.xcodeproj`: in Xcode, add the same packages to the App target (the generated README lists them). On Android the build adds an SDK when its file or its keys are there.
- **Consent.** A "Share usage data" switch under Privacy on the Account screen, on by default; while it is off nothing is reported. It is one switch: a store selling in the EU needs a prompt before the first event, and iOS's tracking prompt (ATT) is not shown, so Meta gets no advertising id on iOS.
- **MoEngage** push notifications and in-app messages are not included: they need FCM and APNs keys.

### The purchase, from a server

The keys that let a server report a sale (Google Analytics' API secret, Meta's access token) must never be in an app, and Argon has no backend. So with Google Analytics or Meta configured, or with `--server`, the project gets `server/`: one Cloudflare Worker in one file with no dependencies, which the store deploys to its own account.

- It receives Shopify's "Order creation" webhook and checks Shopify's signature on it.
- It ignores orders that were not placed in the app: the store's web pixels already report those. The app marks its carts with a few attributes (`_argon_platform` and each provider's ids), which reach the server as the order's additional details.
- It sends the purchase to Google Analytics (Measurement Protocol) and to Meta (Conversions API) with the ids the app uses: Google Analytics' `transaction_id` is the order's numeric id, Meta's event id is `purchase-<order id>`. A provider whose secrets are not set is skipped.

Only the purchase goes through the server. Every other event comes from the app alone: from both sides it would be counted twice, since only a purchase carries an id, the order's, that a platform can match. Meta counts the app's and the server's purchase once. Google Analytics de-duplicates purchases for web streams only, not for apps, so read `server/README.md` before giving the Worker its Google Analytics secrets. That file also has the deploy steps and where each secret is found.

---

## Content model

Argon creates four **merchant-owned** metaobject definitions with storefront read access and no publish step: an entry is live as soon as it is saved.

| Type | Name in admin | Fields |
|---|---|---|
| `mobile_screen` | Mobile screen | `title`, `sections` (a mixed list of the three types below, required) |
| `mobile_banner` | Mobile banner | `image`, `heading`, `text`, `button_label`, `link`, `style` (`hero` or `card`) |
| `mobile_products` | Mobile products | `heading`, `collection`, `products`, `style` (`carousel` or `grid`), `limit` (1–24, default 8) |
| `mobile_collections` | Mobile collections | `heading`, `collections` (required) |

Edit them under **Content → Metaobjects**. The home screen is the `mobile_screen` entry with the handle `home`.

- **Links** (`link`, menu items) go through one parser: `/products/<handle>` opens the product page, `/collections/<handle>` the collection, `/search?q=` search. A full URL on the store's domain is reduced to its path. Anything else opens in the in-app browser.
- **Fallback home.** If `home` is missing or has nothing renderable, the apps build the same sections in code from the store's cover image, first six collections and first collection's products.
- **Broken references** (a deleted product, an unknown section type) are skipped, never a crash.
- **Navigation** is the `main-menu` (three levels). **Branding** is `shop.brand` (primary colour, logo).

---

## Flags

| Flag | |
|---|---|
| `--demo` | Use the `mock.shop` demo store. No Shopify account, token or Shopify CLI needed. |
| `--store=DOMAIN` | Your `*.myshopify.com` domain, or just the handle. |
| `--token=TOKEN` | Public Storefront API access token. |
| `--client-id=ID` | Customer Account API client ID. Omit to hide login. |
| `--bundle-id=ID` | Bundle / application ID. Default `com.<store>.<project>`. |
| `--home=TEMPLATE` | Home screen: `fashion` (default), `beauty`, `grocery` or `b2b`. |
| `--collection=TEMPLATE` | Collection layout: `top` (default) or `bottom`. |
| `--judgeme-token=TOKEN` | Judge.me public API token. Omit to hide reviews. |
| `--firebase-android=FILE` | Google Analytics: the path to the Android app's `google-services.json`. Copied to `android/app/`. |
| `--firebase-ios=FILE` | Google Analytics: the path to the iOS app's `GoogleService-Info.plist`. Copied to `ios/App/`. |
| `--meta-app-id=ID` | Meta: the app ID. Needs `--meta-client-token` too. |
| `--meta-client-token=TOKEN` | Meta: the app's client token. |
| `--moengage-workspace-id=ID` | MoEngage: the workspace ID. |
| `--moengage-data-center=N` | MoEngage: the data center, `1` to `6`. Default `1`. |
| `--server` | Write `server/`, the Worker that reports purchases. Always written with Google Analytics or Meta. |
| `--skip-content` | Don't create the metaobject definitions or the `home` entry. |
| `--yes` | Accept defaults and ask nothing. |
| `--help` | Show help. |

---

## What's inside

```
my-store-app/
├── README.md, AGENTS.md, CLAUDE.md, .gitignore
├── android/     # Jetpack Compose, package app.storefront, shopify.properties
├── ios/         # SwiftUI, target App, Config.xcconfig
└── server/      # only with Google Analytics, Meta or --server: the Worker that reports purchases
```

Both apps carry the same GraphQL documents (`queries/`) and the same names (`Storefront`, `ProductCard`, `Section`, `Route`, `Links`, `CartStore`, `WishlistStore`, `AuthStore` and more). Argon never edits `App.xcodeproj`, and on Android only `applicationId` varies, so no source folder is renamed.

| | |
|---|---|
| Storefront API | `2026-10` |
| Checkout Kit | Swift 3.9.1 (`checkout-sheet-kit-swift`), Android 3.6.3 (`com.shopify:checkout-sheet-kit`) |
| iOS | 17+, built with Xcode 16+ |
| Android | minSdk 26, targetSdk and compileSdk 36; Kotlin 2.4.20, AGP 9.4.1, Gradle 9.8.0, JDK 21 |
| Login | Customer Account API, OAuth 2.0 + PKCE (S256), scope `openid email customer-account-api:full` |

---

## Publishing

- **Ship each client's app from the client's own** Apple Developer and Google Play Console accounts (Apple guideline 4.2.6: an app built from a template or generator must be submitted by the owner of its content). Add the agency as a team member.
- Both stores require an in-app way to start **account deletion**. The Account screen's *Delete account* opens `https://<domain>/pages/contact`, because there is no customer self-delete API. Make sure that page exists on the store and that someone handles the requests.
- Login and checkout need new customer accounts on and no storefront password (see [Store prerequisites](#store-prerequisites)).

---

## Not in v1

Markets (`@inContext` and currency switching), Shop Pay / Apple Pay buttons, gift cards in the cart (checkout already accepts them), wishlist sync to the customer account, push notifications, universal links, section types beyond the three, and an Argon agent skill.

---

## Development

```bash
npm ci
npm test            # CLI, scaffolding, the PNG reader, provisioning (stubbed), the purchase server (stubbed), link parser, contract vs the 2026-10 schemas
npm run test:live   # also runs every Storefront contract document against mock.shop
```

The tests need Node 22+ (the CLI itself runs on Node 18+).

The GraphQL contract is in `contract/`: Storefront API documents in `queries/` (fragments in `fragments.graphql`), Customer Account API documents in `customer/` (its own `fragments.graphql`), one operation per file, and `fixtures/<Operation>.json`, one response `data` per operation, which the CLI copies into both apps for their decoding tests. `npm test` validates every document against the schemas in `test/schema/` (from `@shopify/hydrogen@2026.10.0`) and every fixture against its document. With `ARGON_RECORD=1`, `npm run test:live` re-records the fixtures mock.shop can answer; the rest are hand-written.

CI (`.github/workflows/ci.yml`) has three jobs. `cli` runs the two commands above on Node 22. `android` and `ios` each generate a `--demo` project and build and test it: Gradle `testDebugUnitTest assembleDebug` on Linux, `xcodebuild build test` on macOS. The `ios` job runs twice: with Xcode 16, which must pass, and with the latest stable Xcode (26), which App Store uploads require and which may fail without failing CI. Each run picks an iPhone simulator on the newest iOS runtime (17 or later) that its Xcode supports. Without a Mac, [xtool](https://xtool.sh) can compile the iOS app on Linux or Windows (the generated README explains how), but only this job runs its tests.

---

## License

MIT

---

<p align="center">
  <sub>Argon is an independent community project. Not affiliated with or endorsed by Shopify Inc.<br/>
  Shopify is a trademark of Shopify Inc.</sub>
</p>
