# Argon: native iOS + Android storefronts for a Shopify store

**Status:** design approved by delegation ("take your best judgement and complete it"), 2026-10-05.

## Goal

`npx @mksd0398/argon my-store-app` produces two native apps for one Shopify
store: a SwiftUI iOS app and a Jetpack Compose Android app. It is a sibling of
Nitrogen and gives an agency a store-connected app in minutes instead of weeks.

The apps work the way a Liquid theme does. They render whatever the store
contains, and the merchant controls the home screen, navigation, branding and
catalogue from Shopify admin with no app release.

**Success means:**
- Both apps build from a freshly generated project.
- `--demo` runs against `mock.shop` with no credentials.
- A real store runs after one CLI session and one manual Headless-channel step.

## Decisions (and why)

| Topic | Decision | Reason |
|---|---|---|
| Stack | SwiftUI (iOS 17+) and Jetpack Compose (minSdk 26), two codebases | The user asked for truly native apps. |
| Data layer | A hand-written Storefront GraphQL client: URLSession / OkHttp, shared `.graphql` files, hand-written models | Mirrors Shopify's mobile tutorial. No codegen step that can break, and about 12 queries in total. |
| Shopify SDK | Checkout Kit only: `checkout-sheet-kit-swift` 3.9.x, `com.shopify:checkout-sheet-kit` 3.6.x | It is the SDK Shopify maintains. The Mobile Buy SDK lags at 2026-04. |
| API version | Storefront `2026-10` | Latest stable, supported until 2027-10. |
| Login | Customer Account API only: OAuth 2.0 + PKCE with a **Mobile** client from the Headless channel; callback `shop.<shop_id>.app://callback` | Legacy accounts were deprecated on 2026-02-26. The Headless Mobile client gets refresh tokens. |
| Checkout | Checkout Kit `present(checkoutUrl)`, after attaching the customer token to the cart | Shopify owns payment, tax, shipping, discounts and order creation. |
| Admin control | Home = an ordered list of section metaobjects. PLP, PDP and cart have fixed layouts with live data. | The closest native equivalent of theme `index.json` sections. |
| Provisioning | `shopify store auth` + `shopify store execute --allow-mutations` (as a staff user), plus one manual Headless-channel stop | `shopify app execute` refuses mutations outside dev stores. The Storefront token can't be minted by the CLI. |
| Demo store | `mock.shop` at the standard path `https://mock.shop/api/2026-10/graphql.json` | Needs no token. Menu, catalogue and cart work. Metaobjects return null, which exercises the fallback home. |

## 1. CLI and generated output

### Repo layout (this folder)

```
bin/create.js                 entry → lib/index.js run(argv)
lib/index.js                  flow, prompts, scaffold, config writing
lib/shopify.js                store auth/execute wrappers, provisioning, health checks
contract/queries/*.graphql    single source of every Storefront + Customer Account query
contract/sections.js          metaobject definitions (data) + seed builder
templates/android/            Compose project (copied verbatim, then config written)
templates/ios/                SwiftUI project (copied verbatim, then config written)
templates/shared/             AGENTS.md, CLAUDE.md, gitignore
test/*.test.js                node --test
.github/workflows/ci.yml      generate --demo, then build Android (Linux) + iOS (macOS)
```

The CLI is plain ESM Node 18+ with a single dependency, `prompts`. It uses
Nitrogen's ANSI helpers and code style.

### Flow

1. **Preflight.** Node ≥ 18 is required. The Shopify CLI is required unless
   `--demo` or `--skip-content` is given (provisioning needs it). A missing Xcode or Android SDK
   only produces a warning.
2. **Project name** → directory, app display name, and bundle/application ID
   (`com.<org>.<slug>`, with `--bundle-id` to override).
3. **Store.** `--demo` sets the domain to `mock.shop` and skips steps 4–6.
   Otherwise the CLI prompts for the `*.myshopify.com` domain, or takes `--store`.
4. **Admin session.**
   `shopify store auth --store <shop> --scopes read_products,write_metaobject_definitions,write_metaobjects`.
5. **Provision** via `shopify store execute --allow-mutations --json`:
   - Read `shop { id }` and derive the numeric shop ID for the callback scheme.
   - **Health checks** (warnings only):
     - The storefront password is on: an HTTP GET to `/` redirects to `/password`.
       Checkout Kit can't open checkout while it's on.
     - Legacy customer accounts: `shop { customerAccountsV2 { customerAccountsVersion } }`.
       If the query is refused, the check is skipped with a note.
   - Create the four metaobject definitions if missing (query first, so it is idempotent).
   - If `mobile_screen/home` is missing, seed it from real data (see §2).
   - `--skip-content` skips this step.
6. **Headless channel (manual).** The CLI prints numbered steps:
   1. Install the Headless channel.
   2. Create a storefront.
   3. Copy the **public** Storefront token.
   4. In Customer Account API settings, add a **Mobile** client with callback
      `shop.<id>.app://callback`, then copy its client ID.

   The CLI prompts for both values, or takes `--token` / `--client-id`. It checks
   the token with a live `{ shop { name } }` call. The client ID can be skipped,
   which hides login in the apps.
7. **Scaffold.**
   - Copy `templates/{ios,android}` into `<dir>/{ios,android}` and
     `templates/shared/*` into `<dir>`.
   - Copy `contract/queries` to `android/app/src/main/assets/queries/` and
     `ios/App/Resources/queries/`.
   - Write the config files:
     - `ios/Config.xcconfig`: `SHOP_DOMAIN`, `STOREFRONT_TOKEN`, `CUSTOMER_CLIENT_ID`,
       `SHOP_ID`, `API_VERSION`, `APP_NAME`, `BUNDLE_ID`, `PDP_METAFIELDS`
       (comma-separated `namespace.key`, empty by default). The domain is written
       without a scheme, because `//` starts a comment in xcconfig.
     - `android/shopify.properties`: the same keys.

   The `.xcodeproj` is never edited. Android changes only `applicationId`, so
   source folders are never renamed.
8. **Finish.** Run `git init` and commit if git is present, then print the next
   steps (open in Xcode or Android Studio, plus the store checklist).

**Flags:** `--demo`, `--store`, `--token`, `--client-id`, `--bundle-id`,
`--skip-content`, `--yes` (accept defaults), `--help`. Running with flags only
and no TTY must work, for agents and CI.

The CLI never stores Admin credentials. It also never changes the user's Shopify
CLI config. For example, it does not toggle auto-upgrade.

## 2. Theme-like content contract (metaobjects)

The CLI creates four **merchant-owned** definitions (not `$app:`), each with
`access.storefront = PUBLIC_READ` and no `publishable` capability, so entries
are live as soon as they are saved.

| Type | Name in admin | Fields |
|---|---|---|
| `mobile_screen` | Mobile screen | `title` (single line, display field), `sections` (`list.mixed_reference` to the three types below, required) |
| `mobile_banner` | Mobile banner | `image` (file_reference, images), `heading`, `text` (multi line), `button_label`, `link` (single line: a store path such as `/collections/sale`, or a full URL), `style` (choice: `hero` \| `card`, default hero) |
| `mobile_products` | Mobile products | `heading`, `collection` (collection_reference), `products` (list.product_reference), `style` (choice: `carousel` \| `grid`), `limit` (integer 1–24, default 8) |
| `mobile_collections` | Mobile collections | `heading`, `collections` (list.collection_reference, required) |

- **Screen lookup.** The app reads `metaobject(handle: {type: "mobile_screen", handle: "home"})`.
  More screens later cost nothing; they're just more handles.
- **Seed.** The seed builds `home` from Admin data (requires `read_products`):
  - a hero banner using the first product's featured `MediaImage`, if one exists;
  - `mobile_collections` with up to 6 collections that have products;
  - a `mobile_products` carousel of the first collection.
- **`link` resolution** is one shared parser, also used for menu items and deep
  links. `/products/<h>` opens the PDP, `/collections/<h>` the PLP, and
  `/search?q=` search. A full URL on the shop's domain is reduced to its path
  first. Anything else opens in the in-app browser.
- **Fallback home.** If the metaobject is missing or has no renderable sections,
  the app builds the same section models in code:
  - a hero from `shop.brand.coverImage` (when there is a cover image);
  - collections from the first 6 collections;
  - a carousel of the first collection.

  Demo mode and half-set-up stores therefore still show a useful home screen.
- **Unknown or broken references** (a deleted product, an unknown section type)
  are skipped. They never crash the screen.

## 3. App structure (both platforms mirror each other)

**Tabs:** Home · Shop · Wishlist · Cart (badge) · Account. A search button sits
in the Home and Shop top bars.

| Screen | Data | Notes |
|---|---|---|
| Home | `HomeScreen.graphql` (screen metaobject plus brand); fallback `FallbackHome.graphql` | The section renderer has one view per section type. The brand logo appears in the top bar. |
| Shop | `Menu.graphql` (`main-menu`, 3 levels) | Expandable tree whose items route through the link parser. If the menu is null, it falls back to a collections list. |
| PLP | `Collection.graphql` (`products(first, after, sortKey, reverse, filters)` plus `filters`) | 2-column grid of product cards, cursor pagination, a sort menu, and a filter sheet (LIST checkboxes, PRICE_RANGE min/max). |
| Search | `PredictiveSearch.graphql` (300 ms debounce), `Search.graphql` (`search(... productFilters)`) | Reuses the PLP grid and filter sheet. |
| PDP | `Product.graphql` (media, options, `variants(first: 250)`, `descriptionHtml`, `metafields(identifiers:)`) | Gallery pager, option chips, variant matched in code, price and compare-at, add to cart, wishlist heart, HTML description. Each platform's config has a metafield "details" list (`PDP_METAFIELDS=custom.material,custom.care`). |
| Product card | Product fragment | Image, title, price and compare-at, sold-out badge, heart. |
| Cart | `Cart*.graphql` (create, get, linesAdd, linesUpdate, linesRemove, buyerIdentityUpdate) | Cart ID is persisted. Quantity stepper, remove, subtotal. Checkout preloads when the cart opens. Checkout: attach the customer token if signed in, then `present(checkoutUrl)`. On completion, clear the cart ID. |
| Account | Customer Account API `Customer.graphql` and `Order.graphql` | Signed out: Sign in. Signed in: name, email, orders, order detail, Sign out, and **Delete account**, which opens `https://<domain>/pages/contact` because no self-delete API exists and both stores require the entry. |
| Wishlist | Local product IDs, then `nodes(ids:)` | UserDefaults / DataStore. Sync to the customer account is out of scope for v1. |

**Branding.** The accent colour comes from
`shop.brand.colors.primary[0].background` and the logo from `shop.brand.logo`.
Both fall back to platform defaults.

**Auth.**
- Endpoints come from `https://<domain>/.well-known/openid-configuration`
  (authorize, token, end_session). The GraphQL URL comes from
  `https://<domain>/.well-known/customer-account-api`.
- PKCE uses S256 with scope `openid email customer-account-api:full`.
- iOS uses `ASWebAuthenticationSession`. Android uses Custom Tabs with a
  callback activity whose intent-filter scheme comes from `manifestPlaceholders`.
- Tokens are stored encrypted: Keychain on iOS, and on Android an Android Keystore
  AES-GCM key with the ciphertext in DataStore.
- Access tokens refresh on expiry or 401. If the refresh fails, the app signs
  out locally.

**Platform specifics**

| | iOS | Android |
|---|---|---|
| Minimum OS | iOS 17 | minSdk 26, targetSdk 36 |
| UI and state | SwiftUI with `@Observable` stores | Compose, Navigation Compose |
| Images | `AsyncImage` | Coil 3 |
| JSON | `JSONSerialization`/Codable | kotlinx-serialization |
| HTTP | URLSession | OkHttp |
| Dependency injection | None: one `App` object owns `Storefront`, `CartStore`, `AuthStore`, `WishlistStore` | Same |
| Project setup | Committed Xcode 16 project (objectVersion 77) with one synchronized `App/` folder; `Info.plist` outside it; all per-store values via `Config.xcconfig` → build settings → Info.plist `$(VAR)` keys | Plain Gradle; per-store values read from `shopify.properties` into `BuildConfig` (`buildFeatures.buildConfig = true`) |

**Missing configuration.** If the token is empty and the domain isn't
`mock.shop`, the app shows a setup screen naming the missing key instead of
failing at runtime.

## 4. Errors and testing

**Errors**
- Network or GraphQL `errors` show a per-screen error state with Retry.
- Cart `userErrors` show a snackbar or alert with Shopify's message.
- A null cart (expired ID) is handled by dropping the ID and creating a new cart
  on the next add.
- If checkout is unavailable (password-protected store, `checkoutUnavailable`),
  the app shows Checkout Kit's message and keeps the cart.
- If the auth refresh fails, the app signs out and stays on the Account tab.

**Testing**
- **CLI (`node --test`):**
  - `--demo --yes` generation in a temp dir. Checks the files, the config
    values, that queries are present in both apps, and that no `__PLACEHOLDER__`
    is left.
  - Provisioning with an injected `exec` stub, covering idempotency (existing
    definitions are skipped) and seed construction.
  - Link parser and slug and bundle-ID rules.
- **Contract:** every `contract/queries/*.graphql` operation is executed against
  `mock.shop` in an opt-in live test (`ARGON_LIVE=1`). Customer Account and
  metaobject queries are skipped there.
- **Android:**
  - JVM unit tests for response parsing (fixture JSON), section mapping and
    fallback, variant matching, the link parser, and PKCE (RFC 7636 test vector).
  - `./gradlew testDebugUnitTest assembleDebug` runs locally on Windows.
  - A manual smoke test on the emulator against mock.shop.
- **iOS:**
  - XCTest covers the same pure logic.
  - CI runs `xcodebuild build test` on a macOS runner. iOS can't be built on the
    user's Windows machine; pushing to GitHub for CI needs the user's go-ahead.

## Out of scope for v1 (add when a client needs it)

- Markets: `@inContext(country:)` and currency switching.
- Shop Pay / Apple Pay accelerated buttons (iOS only today).
- Discount codes in the cart (checkout already accepts them).
- Wishlist sync to customer metafields.
- Push notifications.
- Universal links / App Links.
- Section types beyond the three.
- Apollo migration.
- An Argon agent skill.

## Store-publishing notes for the generated README

- Each client's app must ship from **the client's own** Apple Developer and Play
  Console accounts (Apple guideline 4.2.6). The agency is added as a team member.
- The store needs new customer accounts on, and no storefront password, for
  login and checkout to work.
- PLP filters appear only after the merchant configures the Search & Discovery app.
