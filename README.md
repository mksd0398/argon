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
- **Product lists** with sorting and filters, **product pages** with variants and metafields, a persisted **cart**
- **Checkout** through Checkout Kit: Shopify owns payment, tax, shipping, discounts and orders
- **Login** with the Customer Account API (OAuth 2.0 + PKCE), orders, and the *Delete account* entry both app stores require
- **A home screen the merchant edits**: an ordered list of metaobject sections ([Content model](#content-model))
- **Branding** from the store's own colours and logo
- **One Shopify SDK**: Checkout Kit. A hand-written GraphQL client, no Mobile Buy SDK, no Apollo, no DI framework
- **`AGENTS.md`, `CLAUDE.md` and a README** in every generated project, so an AI coding agent follows the same rules with nothing installed

`--demo` runs against `mock.shop` with no credentials. A real store takes one CLI session and one manual Headless-channel step.

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

The apps use `mock.shop`: no account, no token. Menu, catalogue and cart work. Metaobjects return null there, so Home shows the fallback home, and login is hidden. **`mock.shop` doesn't implement `nodes(ids:)`, so the Wishlist tab stays empty on it.** It works on real stores.

### A real store

```bash
npx @mksd0398/argon my-store-app
```

1. **Name**: the directory and the bundle / application ID (`com.<store>.<project>`).
2. **Store**: your `*.myshopify.com` domain.
3. **Admin session**: `shopify store auth` as a staff user, with `read_products`, `write_metaobject_definitions` and `write_metaobjects`.
4. **Provision**: creates the four content definitions if missing, and seeds the `home` screen from your collections and products if it doesn't exist. Warns if the storefront password is on or legacy customer accounts are in use. Existing definitions and an existing `home` entry are left as they are.
5. **Headless channel**: the one manual step ([below](#the-headless-channel-step)). Argon checks the token with a live call.
6. **Generate** both apps, write the config, run `git init` and commit.

Argon never stores Admin credentials and never changes your Shopify CLI config.

For an agent or CI, pass everything as flags. With no terminal, nothing is asked, and a missing `--store` or `--token` stops with exit code 1:

```bash
npx @mksd0398/argon my-store-app --store=my-store --token=PUBLIC_TOKEN --client-id=CLIENT_ID --yes
```

### The Headless channel step

Argon prints these with your store's values filled in:

1. In Shopify admin, install the **Headless** channel and create a storefront.
2. Make your products and collections available to the **Headless** channel, and keep the storefront's metaobject read permission on. Otherwise the app shows an empty or fallback home.
3. Copy the **public** Storefront access token.
4. In its **Customer Account API** settings, add a **Mobile** client with the callback `shop.<shop id>.app://callback`, then copy its client ID.

The client ID can be skipped: login is then hidden until `CUSTOMER_CLIENT_ID` is set.

### Store prerequisites

- **New customer accounts are on** (Settings → Customer accounts). Legacy accounts are not supported.
- **The storefront password is off.** Checkout Kit can't open checkout while it's on.
- **Products and collections are available to the Headless channel**, and its storefront keeps the metaobject read permission. Without them the app shows an empty or fallback home.
- **Search & Discovery filters are configured.** Product-list and search filters appear only after that.

### Run the apps

```bash
cd my-store-app
```

- **iOS**: open `ios/App.xcodeproj` in Xcode 16+, pick a simulator, Run.
- **Android**: open `android/` in Android Studio, or `cd android && ./gradlew assembleDebug`.

Per-store values live in `ios/Config.xcconfig` and `android/shopify.properties`, with the same eight keys on both (`SHOP_DOMAIN`, `STOREFRONT_TOKEN`, `CUSTOMER_CLIENT_ID`, `SHOP_ID`, `API_VERSION`, `APP_NAME`, `BUNDLE_ID`, `PDP_METAFIELDS`). The generated README explains each. With an empty token on a store other than `mock.shop`, the app shows a setup screen naming the missing key instead of failing at run time.

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
| `--skip-content` | Don't create the metaobject definitions or the `home` entry. |
| `--yes` | Accept defaults and ask nothing. |
| `--help` | Show help. |

---

## What's inside

```
my-store-app/
├── README.md, AGENTS.md, CLAUDE.md, .gitignore
├── android/     # Jetpack Compose, package app.storefront, shopify.properties
└── ios/         # SwiftUI, target App, Config.xcconfig
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

Markets (`@inContext` and currency switching), Shop Pay / Apple Pay buttons, discount codes in the cart (checkout already accepts them), wishlist sync to the customer account, push notifications, universal links, section types beyond the three, and an Argon agent skill.

---

## Development

```bash
npm ci
npm test            # CLI, scaffolding, provisioning (stubbed), link parser
npm run test:live   # also runs every contract query against mock.shop
```

The tests need Node 22+ (the CLI itself runs on Node 18+).

CI (`.github/workflows/ci.yml`) has three jobs. `cli` runs the two commands above on Node 22. `android` and `ios` each generate a `--demo` project and build and test it: Gradle `testDebugUnitTest assembleDebug` on Linux, `xcodebuild build test` on macOS. The `ios` job runs twice: with Xcode 16, which must pass, and with the latest stable Xcode (26), which App Store uploads require and which may fail without failing CI. Each run picks an iPhone simulator on the newest iOS runtime (17 or later) that its Xcode supports. Swift can't be built on Windows or Linux, so the iOS job is what verifies the iOS app.

---

## License

MIT

---

<p align="center">
  <sub>Argon is an independent community project. Not affiliated with or endorsed by Shopify Inc.<br/>
  Shopify is a trademark of Shopify Inc.</sub>
</p>
