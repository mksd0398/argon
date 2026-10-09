# Argon API layer — design

Date: 2026-10-09. Phase 2, project 2 of 4. Catalog verified in `2026-10-09-api-catalog-research.md` (schemas from `@shopify/hydrogen@2026.10.0`, API version 2026-10).

## Goal

Every Storefront API and Customer Account API operation a store app needs is prebuilt in both generated apps, behind one typed facade per API, so no one writes GraphQL, JSON parsing or request code to build screens or sections. Native on both platforms (Swift / Kotlin), one shared set of GraphQL documents.

Success: the 37 Storefront and 12 Customer Account operations from the research doc exist as documents, validate offline against the vendored 2026-10 schemas in `npm test`, and are callable as typed methods returning typed models on iOS and Android; recorded responses for every operation decode in both apps' tests.

Out of scope (no API exists or not needed now): guest newsletter signup and contact forms (no Storefront/Customer Account operation — handled by sections, project 3, with a configurable destination), order cancellation (no customer mutation), Admin API, offline storage, 3D model rendering (decoded, not shown).

## Approach

Keep v0.1's hand-written HTTP client and shared documents; replace hand-written JSON parsing (`Parse.kt`, `Parse.swift`) with typed decoding: Kotlin `@Serializable` models (adds the `org.jetbrains.kotlin.plugin.serialization` Gradle plugin at the Kotlin version; `kotlinx-serialization-json` is already a dependency) and Swift `Codable`. No code generation, no new libraries. Rejected: Apollo codegen on both platforms (two heavy toolchains in every generated project); keeping manual parsing (most code, drifts).

## Contract

- `contract/queries/*.graphql` + `contract/fragments.graphql`: Storefront operations (the research doc's §5 list: 16 existing, extended, plus the new ones — Localization, ShopPolicies, VariantBySelectedOptions, ProductRecommendations, Collections, StoreAvailability, Locations, Page, Pages, Blogs, Blog, Article, Articles, Metaobject, Metaobjects, CartDiscountCodesUpdate, CartGiftCardCodesAdd, CartGiftCardCodesRemove, CartNoteUpdate, CartAttributesUpdate, CartDeliveryAddressesAdd/Update/Remove, CartSelectedDeliveryOptionsUpdate).
- `contract/customer/*.graphql` + `contract/customer/fragments.graphql`: Customer Account operations (Customer, Orders, Order, CustomerAddresses, CustomerUpdate, CustomerAddressCreate/Update/Delete, CustomerEmailMarketingSubscribe/Unsubscribe, OrderReturnOptions, OrderRequestReturn). Separate fragment namespace, so names never clash.
- `lib/contract.js` loads both folders into one map (operation names are unique across both); the CLI keeps copying every resolved document to `android/app/src/main/assets/queries/` and `ios/App/Resources/queries/`, so app loading doesn't change.
- Every Storefront operation declares `$country: CountryCode` and `$language: LanguageCode` and carries `@inContext(country: $country, language: $language)`; the client fills them in.
- Polymorphic results select `__typename` (media, menu item resources, search/predictive results, metaobject field references).
- Every cart mutation selects `userErrors { field message code }` and `warnings { code message target }`.
- Deprecated fields are never selected (`localization.market`, `Country.market`, `ProductOption.values`, `Article.author`, Cart `estimatedCost`, `discountAllocations` on Cart, `ExternalVideo.embeddedUrl`).

## Facades

One per API, same method names on both platforms (`suspend fun` on Android, `async throws` on iOS):

- `StorefrontApi` / `StorefrontAPI`: `shop()`, `localization()`, `policies()`, `menu(handle)`, `product(handle)`, `variantBySelectedOptions(productHandle, options)`, `products(query?, sortKey?, after?)`, `recommendations(productId, intent)`, `collection(handle, filters, sortKey, reverse, after?)`, `collections(after?)`, `search(query, filters, sortKey, after?)`, `predictiveSearch(query, limit)`, `storeAvailability(variantId)`, `locations(after?)`, `page(handle)`, `pages(after?)`, `blogs()`, `blog(handle, after?)`, `article(blogHandle, articleHandle)`, `articles(query?, after?)`, `metaobject(type, handle)`, `metaobjects(type, after?)`, and the cart: `cart(id)`, `cartCreate(...)`, `addLines`, `updateLines`, `removeLines`, `updateBuyerIdentity`, `updateDiscountCodes`, `addGiftCards`, `removeGiftCards`, `updateNote`, `updateAttributes`, `addDeliveryAddresses`, `updateDeliveryAddresses`, `removeDeliveryAddresses`, `selectDeliveryOptions`.
- `CustomerAccountApi` / `CustomerAccountAPI` (uses the signed-in customer's token from `AuthStore`): `customer()`, `orders(after?)`, `order(id)`, `addresses(after?)`, `updateName(first, last)`, `createAddress(input, isDefault)`, `updateAddress(id, input, isDefault)`, `deleteAddress(id)`, `subscribeEmailMarketing()`, `unsubscribeEmailMarketing()`, `returnOptions(orderId)`, `requestReturn(orderId, lines)`.
- Lists return `Page<T>(items, endCursor, hasNextPage)`.
- Context: `StorefrontContext(country?, language?)`, picked once from the device locale when it's in `localization.availableCountries` / `availableLanguages`, otherwise nil (shop default); settable later by a picker.
- Caching: `shop`, `localization`, `policies` and `menu(handle)` are cached in memory for the session.
- Errors: one `ArgonApiError` — `network`, `http(status)`, `graphql(messages)`, `userErrors([field, code, message])`, `decoding(operation, detail)`. Cart warnings are returned with the cart, not thrown.

Existing app code moves onto the facades (CartStore, WishlistStore, Sections, screens); models keep their current names where screens use them, so screen changes stay small.

## Testing

- `npm test`: every document (with fragments resolved) validates against the vendored schemas `test/schema/storefront-2026-10.json` and `test/schema/customer-account-2026-10.json` (copied from `@shopify/hydrogen@2026.10.0`, sha256 recorded in the research doc; test-only, not in the npm package) using `graphql` as a pinned devDependency. A test also asserts every operation has a fixture.
- `npm run test:live` keeps running every Storefront query against mock.shop.
- Fixtures: `contract/fixtures/<Operation>.json` (a response's `data`), recorded from mock.shop for Storefront reads and cart mutations, hand-written to the schema for Customer Account operations and data mock.shop lacks (metaobjects, locations, store availability). The CLI copies them into `android/app/src/test/resources/fixtures/` and `ios/AppTests/Fixtures/`; each app's tests decode every fixture through the facade's decoder and spot-check fields.
- CI: unchanged jobs (cli, android, iOS Xcode 16 required / 26 watched).

## Build order

1. Contract branch: documents, folders, loader, schema vendoring + validation, fixtures, CLI fixture copy. (Both platforms depend on it.)
2. Android and iOS branches in parallel: models, decoding, facades, migration of existing callers, fixture tests.
