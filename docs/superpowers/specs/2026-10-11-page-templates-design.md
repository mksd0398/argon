# Page templates

Date: 2026-10-11. Status: building.

## Goal

Every generated app ships finished pages built from the ArgonUI components, for any store:

- **Home**: four templates by kind of store (fashion, beauty, grocery, industrial & B2B), with stock banners until the store has its own.
- **Collection**: two templates (sticky filter bar at the top; floating bar at the bottom), both with colour swatches.
- **Product**: one page with Shopify's variants, bundles, prices, B2B catalogue pricing, a sticky add-to-cart bar, Judge.me reviews and the usual conversion blocks.
- **Orders**: list, detail, and a returns and exchange flow.
- **Account**: profile, addresses, company, marketing, store credit.

Android (Compose) and iOS (SwiftUI) stay screen for screen, name for name identical (AGENTS.md rule). All UI comes from `Argon*` components and theme tokens (`ArgonTheme.colors/type/spacing/radius`), never raw Material or SwiftUI styling constants.

## Configuration

Three new keys in `android/shopify.properties` and `ios/Config.xcconfig` (the CLI writes them; `--home`, `--collection`, `--judgeme-token`):

| Key | Values | App property |
|---|---|---|
| `HOME_TEMPLATE` | `fashion` (default), `beauty`, `grocery`, `b2b` | `AppGraph.homeTemplate` |
| `COLLECTION_TEMPLATE` | `top` (default), `bottom` | `AppGraph.collectionTemplate` |
| `JUDGEME_PUBLIC_TOKEN` | Judge.me public token, empty hides reviews | `AppGraph.judgeMeToken` |

An unknown value falls back to the default. Android reads them through `BuildConfig` (add to `app/build.gradle.kts` beside `PDP_METAFIELDS`); iOS through `AppGraph.info` (Info.plist keys `HomeTemplate`, `CollectionTemplate`, `JudgemePublicToken`, which fall back to the bundled `Config.xcconfig`).

Enums, same names on both platforms: `HomeTemplate { fashion, beauty, grocery, b2b }`, `CollectionTemplate { top, bottom }`.

## Data contract (already in `contract/`, fixtures in `contract/fixtures/`)

55 operations (41 Storefront, 14 Customer Account). What changed since phase 2:

- **Every Storefront operation** takes `$buyer: BuyerInput` in `@inContext(country:, language:, buyer:)`.
- **`ProductCard`** (fragment, so every product list): `vendor`, `priceRange.maxVariantPrice`, `options(first: 3) { name optionValues { name swatch } }`, `firstVariant: selectedOrFirstAvailableVariant { id sku availableForSale quantityRule }`, `rating` / `ratingCount` (the standard `reviews.rating` and `reviews.rating_count` metafields).
- **`Filter`**: `presentation` (`IMAGE` | `SWATCH` | `TEXT`), `values.swatch { color image { previewImage } }`.
- **`Cart`**: `buyerIdentity.purchasingCompany { company location }`; per line `sellingPlanAllocation.sellingPlan`, merchandise `sku` and `quantityRule`, and `lineComponents` on `ComponentizableCartLine` (a bundle's parts).
- **`Product`**: `tags`, `onlineStoreUrl`, `rating`, `ratingCount`. It no longer selects `metafields(identifiers:)` or `sellingPlanGroups`: a token without the permission gets `ACCESS_DENIED` on those non-null fields, which nulls the whole product (seen live on 2026-10-11, on the released app too).
- **`ProductMetafields`** (new): `product { id metafields(identifiers:) }`, for the Details block only. `productMetafields(handle, identifiers) -> [Metafield]`: no request for an empty list, nulls dropped; the page ignores its failure.
- **`VariantBySelectedOptions`**: the selected variant in full: `barcode`, `quantityAvailable`, `currentlyNotInStock`, `unitPrice`, `unitPriceMeasurement`, `quantityRule`, `quantityPriceBreaks`, `requiresComponents`, `components`, `groupedBy`, `sellingPlanAllocations`.
- **`FallbackHome`**: 8 collections.
- **Customer Account**: `Order` (payment, transactions, shipping line, PO number, purchasing company, fulfilment events, refunds, returns with exchange items, `returnInformation`), `Orders` (item count, first titles and images, shipment status, delivery date), `OrderReturnOptions` (fees, shipping method, non-returnable summary, line details), new `CustomerCompanies` and `CustomerStoreCredit`.

### Models (same names and optionality on both platforms)

- `QuantityRule(minimum: Int, maximum: Int?, increment: Int)` with `min`, `step` computed: `max(1, minimum)`, `max(1, increment)` (mock.shop sends 0).
- `ProductCard` gains `vendor: String`, `options: [ProductOption]`, `firstVariant: CardVariant?` (`id`, `sku`, `available`, `quantityRule`), `rating: Double?`, `ratingCount: Int?`, and computed:
  - `hasPriceRange`: max variant price above the min.
  - `colors: [ProductOptionValue]`: the values of the first option whose name is colour, color, or shade (case-insensitive); empty otherwise.
  - `quickAddVariantId: String?`: `firstVariant.id` when it is available and every option has exactly one value (nothing to choose); else nil (the card then opens the product).
- `Ratings.parse(value: String?) -> Double?`: a `rating` metafield is JSON `{"value":"4.6","scale_min":"1.0","scale_max":"5.0"}`; accept that or a plain number; scale to 0...5; nil when unreadable.
- `Variant` gains (all optional or defaulted, filled only by `variantBySelectedOptions`): `barcode`, `quantityAvailable: Int?`, `currentlyNotInStock: Bool`, `unitPrice: Money?`, `unitPriceMeasurement: UnitPriceMeasurement?`, `quantityRule: QuantityRule?`, `quantityPriceBreaks: [QuantityPriceBreak]`, `requiresComponents: Bool`, `components: [VariantComponent]` (`quantity`, `variant: ComponentVariant` with `id title image price product`), `groupedBy: [ComponentVariant]`, `sellingPlanAllocations: [SellingPlanAllocation]` (`sellingPlan { id name }`, `priceAdjustments[].price/compareAtPrice/perDeliveryPrice`).
- `Filter.presentation: String?`, `FilterValue.swatch: Swatch?`.
- `Cart` line: `sellingPlanName: String?`, `components: [CartLineComponent]`, merchandise `sku`, `quantityRule`; `Cart.purchasingCompany: PurchasingCompany?`. `CartBuyerIdentityInput.companyLocationId: String?`.
- Customer: `Order` and `OrderSummary` gain the fields above; `OrderReturnOptions` gains fees and line details; new `CompanyContact(id, title, company: Company(id, name, locations: [CompanyLocation(id, name)]))`, `StoreCreditAccount(id, balance)`.
- Facades: `StorefrontApi.buyer: Buyer?` (`customerAccessToken`, `companyLocationId`), sent as `$buyer` on every call; setting it drops the session cache like `context`. `CustomerAccountApi.companies(): [CompanyContact]`, `storeCredit(): [StoreCreditAccount]`.

### Access-denied fields are optional

A Headless token without a permission answers 200 with `data` and `errors` of code `ACCESS_DENIED` (seen live: `quantityAvailable` needs `unauthenticated_read_product_inventory`, `metafield` needs `unauthenticated_read_metafields`). In the shared GraphQL send (`graphQL` on Android, its Swift twin): when **every** error has `extensions.code == "ACCESS_DENIED"` **and** `data`'s value at each error's `path[0]` is non-null, return `data` (the denied fields are null) and log each distinct message once. Anything else throws `GraphQL` as today. Result: no stock count and no rating stars instead of a broken page; the home screen's metaobject fallback still works (its denied root field is null, so it still throws).

### B2B buyer

Shopify deprecated `storefrontCustomerAccessTokenCreate`: the Customer Account API access token goes straight into `BuyerInput.customerAccessToken`.

`BuyerStore` (both platforms, owned by `AppGraph.buyer`):

- State `company: BuyerCompany?` (`contactId`, `companyName`, `locations`, `locationId`), observable.
- `refresh()`: when signed in, `customerAccount.companies()`; no contact → `storefront.buyer = nil`. Else pick the stored `companyLocationId` (prefs/UserDefaults key `buyer.location`) if it is still offered, else the first location; set `storefront.buyer = Buyer(token, locationId)` and call `cart.setBuyer(locationId)` (cart buyer identity with `customerAccessToken` + `companyLocationId`).
- `select(locationId)`: store, re-apply.
- `clear()` on sign-out.
- Called after sign-in, at app start when a session exists, and when the token refreshes. Any failure leaves the app in the retail context and is logged, never shown.

### Reviews (Judge.me, headless)

Judge.me's documented headless path is its Widget API with the **public** token (the private token must never ship in an app). Client `JudgeMe` (both platforms), used only when `judgeMeToken` is not empty:

- `reviews(productId: String, page: Int = 1, perPage: Int = 5) -> ReviewPage`: `GET https://api.judge.me/api/v1/widgets/product_review?shop_domain=<SHOP_DOMAIN>&external_id=<numeric id from the product GID>&page=&per_page=` with header `X-Api-Token: <public token>`. The JSON answer's `widget` string is HTML.
- `submit(productId, name, email, rating, title, body)`: `POST https://api.judge.me/api/v1/reviews` with JSON `{shop_domain, platform: "shopify", id: <numeric id>, name, email, rating, title, body}` (Judge.me needs no token for this call).
- `JudgeMeHtml.parse(html, page, perPage) -> ReviewPage`: pure, tested against `fixtures/JudgeMeWidget.html` (real markup shape):
  - summary from attributes `data-average-rating`, `data-number-of-reviews`; histogram from each `jdgm-histogram__row` with `data-rating` (1...5) and `data-frequency`.
  - each review: the chunk starting at `class='jdgm-rev ` with `data-review-id`, `data-verified-buyer`, `jdgm-rev__rating` `data-score`, `jdgm-rev__timestamp` (`datetime` attribute, else `data-content` "YYYY-MM-DD HH:MM:SS UTC"), `jdgm-rev__author`, `jdgm-rev__title`, `jdgm-rev__body`, pictures from `jdgm-rev__pic-link` `href`, reply from `jdgm-rev__reply-content`.
  - text: strip tags (`</p>` and `<br>` become a newline), decode `&amp; &lt; &gt; &quot; &#39; &nbsp; &mdash;` and numeric entities, trim.
  - `ReviewPage(summary: ReviewSummary?, reviews: [Review], page, hasNextPage)`; `hasNextPage = summary.count > page * perPage`. `ReviewSummary(average: Double, count: Int, histogram: [Int: Int])`. `Review(id, rating: Int, title: String?, body, author, verified: Bool, date: String? (ISO-8601), pictures: [String], reply: String?)`.
  - Mark it `ponytail:`: it reads Judge.me's class names, so a markup change on their side shows fewer fields, never a crash (every field is optional but `id` and `rating`).

Stars on product cards come from the `rating` / `ratingCount` metafields (Judge.me fills the standard ones), so lists need no extra call.

### Recently viewed

`RecentlyViewedStore` (prefs/UserDefaults, like `WishlistStore`): `ids` newest first, at most 12, `add(productId)` moves it to the front. The product page adds itself and shows the others through `productsByIds`.

### Sample account (demo store only)

mock.shop has no customer accounts, so the demo app can't show the signed-in pages. When the bundle has `Customer.sample.json` (the CLI copies the 14 Customer Account fixtures as `<Operation>.sample.json` for `mock.shop` only: `assets/sample/` on Android, bundle resources on iOS), the signed-out Account screen offers **Preview with a sample account**. `AppGraph.sampleAccount` (observable Bool) then makes `AppGraph.customerAccount` answer every operation from those files (mutations answer their fixture too) and the account screens treat the shopper as signed in. A tag reads "Sample account: nothing is saved". Sign out leaves the preview.

### Home content

`Sections.content(template, brand, sections, collections) -> HomeContent`, pure and tested:

- `banners`: the store's `Section.Banner`s, else the template's three stock banners (`Banner` with a local image, see below, and the template's default heading and button, linking to the first stocked collection, or nowhere when there is none).
- `categories`: the collections of the store's `Section.Collections`, else the stocked fallback collections.
- `rails`: the store's `Section.Products`, else one per stocked fallback collection (`heading` = its title, its products).

The loader runs `homeScreen("home")` and `fallbackHome()` side by side (a refused metaobject query still means empty sections, as today).

Stock banners are bundled as `home-<template>-<1...3>.jpg` (`assets/home/` on Android, bundle resources on iOS, from `templates/images/`). `StockImages.url(template, index)` returns `file:///android_asset/home/home-fashion-1.jpg` on Android and the bundle file URL on iOS. All images render through one app view, `StoreImage(image/url, …)`, which loads `file:` URLs from disk (iOS: `UIImage(contentsOfFile:)`, not `AsyncImage`) and everything else as today.

Default banner copy (heading / button): fashion "The new season" / "Shop now", "Everyday essentials" / "Explore", "Made to last" / "Discover"; beauty "Your daily ritual" / "Shop now", "Skin first" / "Explore", "Colour that stays" / "Discover"; grocery "Fresh today" / "Shop now", "Fill your basket" / "Start shopping", "Baked this morning" / "Order now"; b2b "Stocked and ready to ship" / "Browse the catalogue", "Tools for the trade" / "Shop now", "Order by the pallet" / "View bulk pricing".

## UI library additions (`android/ui`, `ios/ArgonUI`; gallery entries and tests)

- `ArgonRating(value: Double, count: Int? = nil, size: ArgonSize = .S)`: five stars with a partial fill, then "(128)". Accessibility label "4.6 out of 5, 128 reviews".
- `ArgonQuantityStepper(value: Int, onChange, min: Int = 1, max: Int? = nil, step: Int = 1, size: ArgonSize = .M, isEnabled = true)`: minus, value, plus; clamps to `min...max` on the `step` grid; minus disabled at `min`, plus at `max`. Pure helper `steppedQuantity(value, delta, min, max, step)` tested.
- `ArgonSwatch(colorHex: String?, imageUrl: String?, label: String, isSelected: Bool = false, isAvailable: Bool = true, size: ArgonSize = .M, onClick: (() -> Void)? = nil)`: a circle in the colour or image, a ring when selected, a diagonal strike when unavailable, the label as its accessibility name (and under it at size L).

## App blocks (`ui/Blocks.kt`, `UI/Blocks.swift`): shared by every page

- `StoreImage`, `StockImages` (above).
- `PriceView(price: Money, compareAt: Money?, size: ArgonSize = .M, prefix: String? = nil)`: price, struck compare-at, and a "Save 20%" sale tag when there is one (`discountPercent(price, compareAt)` pure and tested: rounded whole percent, nil under 1).
- `SectionHeader(title: String, actionLabel: String? = nil, onAction)`: heading style, optional "View all".
- `SwatchColors.hex(name: String) -> String?`: for stores without swatch data. A table of about 40 colour names (black, white, grey/gray, silver, red, maroon, pink, rose, orange, peach, yellow, gold, mustard, green, olive, teal, turquoise, blue, navy, sky, purple, violet, lavender, magenta, brown, tan, beige, cream, ivory, khaki, coral, mint, lime, burgundy, wine, charcoal, copper, bronze, multi → nil); match the whole name, else its last word, else any word (case-insensitive). Tested ("Peacock Blue" → blue's hex, "Off White" → white's).
- `swatch(for value)`: Shopify's `swatch.color` or `swatch.image`, else `SwatchColors.hex(value.name)`.
- `ProductCardView(card, style: ProductCardStyle = .standard, onOpen)`, styles:
  - `standard`: 4:5 image, wishlist heart, "Sold out" / "Sale" tag, vendor (caption), title (2 lines), `ArgonRating` when rated, `PriceView` ("From" prefix when `hasPriceRange`), up to 4 colour swatch dots (+N).
  - `compact` (grocery): square image, title (2 lines), price, and `QuickAdd`.
  - `row` (B2B and dense lists): thumbnail, title, "SKU …" when present, price, "Min. N · Multiples of M" when the quantity rule says so, `QuickAdd`.
- `QuickAdd(card)`: when `quickAddVariantId` is nil, an "Options" button that opens the product. Else "Add"; once the variant is in the cart it becomes an `ArgonQuantityStepper` bound to the cart line's quantity (0 removes the line), stepping by the quantity rule. Cart writes go through `CartStore` on the app's scope; failures show a snackbar/toast and leave the quantity as it was.
- `TrustRow`: "Secure checkout" (lock), "Shipping policy" (truck), "Returns policy" (returns): the two policy items appear only when the shop has that policy and open `policy/<handle>`.
- `displayDate`, `displayStatus`, `Money.display()` stay where they are.

## Navigation

Tab bar becomes `ArgonBottomBar` (same five tabs, cart badge). New pushed routes, same names on both platforms: `orders`, `return/{orderId}`, `profile`, `addresses`, `policy/{handle}` (privacy-policy, terms-of-service, refund-policy, shipping-policy from `policies()`; body rendered as the product description is).

## Pages

### Home (`HomeScreen` + `home/HomeFashion|HomeBeauty|HomeGrocery|HomeB2B`)

Each template is one composable/view taking `HomeContent` and `onOpen(Route)`. Top bars use `ArgonTopBar`.

- **Fashion** (editorial): centred logo top bar with search. Full-bleed hero `ArgonCarousel` (no peek, 4:5, autoplay 5 s) with display-serif heading and button over a bottom gradient. "Shop by category": horizontally scrolling 3:4 image tiles with the title under. First rail as a carousel of `standard` cards (160 wide) with "View all". Second banner as an inset editorial card. Second rail as a two-column grid of 4. Remaining rails as carousels. `TrustRow`.
- **Beauty** (soft): logo-left top bar with search. Inset rounded hero carousel (16:10, peek, indicators). "Shop by category": circular `ArgonAvatar` (L) with collection image and label. "Bestsellers": first rail, `standard` cards. "Shop by routine": `ArgonTabs` of the first four categories; under it the selected category's first 4 products in a two-column grid and "View all". Second banner card. Remaining rails. `TrustRow`.
- **Grocery** (dense): top bar with a search field (tapping opens search). Short banner carousel (21:9 cards, peek). Category grid, 4 columns × 2 rows of small image tiles with labels, "See all" → Shop tab. Each rail: `compact` cards (132 wide) with `QuickAdd`. After the second rail, the first rail's products again as `row` list items under "Popular" (first 5).
- **Industrial & B2B** (utilitarian): top bar with a search field ("Search by name or SKU"). Trade card: signed out → "Sign in for your trade prices" + button (Account tab); signed in with a company → company name, location, "Your catalogue prices are shown" (and a location `ArgonDropdown` when there are several); signed in without a company → nothing. One slim banner (3:1). Categories as `ArgonListItem` rows with thumbnail and chevron (first 6) + "All categories" → Shop tab. Each rail as `row` cards (first 5) with "View all". Closing card "Need a quote?" → the store's contact page.

Empty content (no categories, no rails) keeps the banners and shows "Nothing to show yet." under them.

### Collection (`CollectionScreen` + `Listing` + `FilterSheet`)

Shared: title top bar with search and cart actions; collection description (3 lines, "Read more"); two-column grid of `standard` cards, load-more footer; active filters as removable `ArgonTag`s with "Clear all"; `FilterSheet` (`ArgonBottomSheet`, large): one section per filter: `PRICE_RANGE` → `ArgonRangeSlider` with the two prices; `BOOLEAN` → `ArgonSwitch`; `LIST` → `ArgonCheckbox` rows with counts, except colour filters (presentation `SWATCH`, any value with a swatch, or a label matching colour/color/shade) → a wrapping grid of `ArgonSwatch` (L, label under); "Show N products"-style apply button and "Clear".

- **`top`**: a sticky bar under the top bar: Sort `ArgonDropdown`-style button, a "Filters (n)" button, then horizontally scrolling chips, one per filter, each opening the sheet scrolled to that filter. Stays pinned while the grid scrolls.
- **`bottom`**: nothing sticky at the top; a floating pill bar above the bottom edge: "Sort" | "Filter (n)". Sort opens a bottom sheet of `ArgonRadioGroup`; the result count shows above the grid.

Search results and the all-products list use the same template (the catalogue has no filters; search has its own sorts).

### Product (`ProductScreen` + `product/*`)

Top bar: back, share (the `onlineStoreUrl`, else `https://<domain>/products/<handle>`), wishlist heart, cart with badge. Scrolling content, in order; each block hides when it has nothing to show:

1. **Gallery**: edge-to-edge 4:5 pager with indicators; tap opens a full-screen zoomable pager. Tags over it: "Sale −20%", "Sold out", "Bundle".
2. **Title**: vendor (caption), title, `ArgonRating` (tap scrolls to reviews) from the reviews summary, else the rating metafields.
3. **Price**: `PriceView` (L). Unit price ("$6.00 / item", from `unitPrice` and `unitPriceMeasurement`). In a company context: tag "Your price for <company>". Volume pricing table from `quantityPriceBreaks` ("10+" → price each), the row matching the quantity highlighted. Quantity rule line: "Minimum 2 · Maximum 40 · Sold in multiples of 2" (only the parts that differ from 1 / none).
4. **Options**: per option (not the lone `Title: Default Title`): label with the selected value; colour options as `ArgonSwatch` (M), others as `ArgonTag` choices; values that make no available variant with the rest of the selection are struck/disabled but still selectable (to reach "Sold out"). Selecting an option whose image belongs to a variant scrolls the gallery to it.
5. **Availability**: "Only N left" (warning colour) when `quantityAvailable` is 1...5; "Ships when back in stock" when `currentlyNotInStock`; "In stock" otherwise when available; pickup line "Pickup available at <location>" from `storeAvailability` when there is one.
6. **Purchase options** (when the selected variant has `sellingPlanAllocations`): `ArgonRadioGroup`: "One-time purchase" (hidden when `requiresSellingPlan`) and each plan with its price.
7. **Quantity + Buy now**: `ArgonQuantityStepper` on the quantity rule; "Buy now" (secondary, full width): adds, then opens checkout.
8. **Bundle**: "This bundle includes": each component's image, product title, variant title, "× n". "Also sold in": `groupedBy` rows opening that product.
9. **Details**: `ArgonAccordion`s: Description (first one open), Details (the `PDP_METAFIELDS`, from `productMetafields`; hidden when empty or refused), Shipping policy, Returns policy (bodies from `policies()`).
10. `TrustRow`.
11. **Reviews** (when `judgeMeToken` is set): summary (average, `ArgonRating`, count, five histogram bars with `ArgonProgressBar`), "Write a review" (a sheet: star picker, title, review, name, email → `submit`; success message "Thanks. Your review appears once it's approved."), the reviews (rating, title, body, author, "Verified" tag, date, photos, store reply), "Load more". A failed load shows a quiet "Reviews couldn't load" with Retry; it never blocks the page.
12. **Pairs well with**: `recommendations(intent: COMPLEMENTARY)`, `compact` cards with `QuickAdd`.
13. **You may also like**: `recommendations(intent: RELATED)`, `standard` cards.
14. **Recently viewed**.

**Sticky bar** pinned at the bottom (above the system inset): the price (and struck compare-at) on the left, the main button on the right: "Add to cart" / "Adding…" / "Added" (2 s) / "Sold out" / "Unavailable". It adds the stepper's quantity and the selected plan.

On every selection change the page calls `variantBySelectedOptions(handle, selection)` (latest wins) and uses the richer variant for blocks 3, 5, 6, 8; until it answers, the variant from the product's own list shows price and availability. Failure of that call is silent (the basic variant stays).

Cart: lines show a bundle's components, the selling plan name, and step by the quantity rule.

### Orders (`OrdersScreen`, `OrderScreen`, `ReturnScreen`)

- **Orders** (`orders`): `ArgonCard` per order: up to three thumbnails (+N), order name, date, total, item count, a status `ArgonTag` (below), and when shipping: "Arrives <date>" or "Delivered <date>". Load more. Empty state with a "Start shopping" button.
- **Status label** (pure `orderStatus(...)`, tested): cancelled → "Cancelled"; else latest shipment status DELIVERED → "Delivered", OUT_FOR_DELIVERY → "Out for delivery", IN_TRANSIT / CARRIER_PICKED_UP / LABEL_* / CONFIRMED → "On its way", ATTEMPTED_DELIVERY / DELAYED / FAILURE → "Delivery issue", READY_FOR_PICKUP / PICKED_UP → the same words; else by fulfilment status: FULFILLED → "Shipped", PARTIALLY_FULFILLED → "Partly shipped", ON_HOLD → "On hold", otherwise "Confirmed".
- **Order** (`order/{id}`): header (name, date, status tag, "Edited" tag); **progress** (`ArgonProgressBar` + four steps Confirmed, Shipped, Out for delivery, Delivered, from the fulfilment events); a card per fulfilment (carrier, tracking number, "Track package" → the URL, estimated delivery, its events newest first); items (image, title, variant, SKU, quantity, price); totals (subtotal, discounts, shipping with the method, tax, total, refunded, outstanding with "Pay now" → `paymentCollectionUrl`); payment (card brand and last 4 or the type, payment terms and due date); addresses; business details (PO number, company and location); note; returns (name, status, date, items, exchange items, decline reason); actions: "Return or exchange items" (when something is returnable), "Buy again" (adds the lines' variants; unavailable ones are named in a message), "View order status page" (`statusPageUrl`, in the in-app browser: whatever the store's apps add to customer accounts shows there), "Need help?" → contact page.
- **Return / exchange** (`return/{orderId}`): three steps in one screen with `ArgonProgressBar`:
  1. Choose items and quantities (`ArgonCheckbox` + `ArgonQuantityStepper` up to the returnable quantity). Non-returnable summary shown.
  2. Per chosen item: `ArgonButtonGroup` "Refund" | "Exchange"; reason (`ArgonDropdown` of the suggested reasons); for an exchange, the replacement variant, picked from the product's options (the product comes from `productsByIds([productId])` then `product(handle)`; when it can't load, a free-text "What would you like instead?"); optional note (`ArgonTextArea`).
  3. Review: the items, fees ("Return shipping: $8.00", restocking fee), the shipping method note, then "Submit request".
  - Submits `requestReturn(orderId, lines)`; an exchange is a return line whose `customerNote` starts with `Exchange for: <product title> - <variant title> (SKU <sku>)` followed by the shopper's note: the Customer Account API has no exchange input, so the merchant sees the wanted item on the return request and completes the exchange in admin. The screen says so: "The store confirms exchanges by email."
  - Success: the return's name and status, and "Back to order".

### Account (`AccountScreen`, `ProfileScreen`, `AddressesScreen`, `PolicyScreen`)

- **Signed out**: heading "Your account", three benefit rows (track orders, faster checkout, returns in a few taps), "Sign in" (primary). On the demo store also "Preview with a sample account". Policies and Help rows stay available.
- **Signed in**: header (`ArgonAvatar` from `imageUrl` or initials, name, email); company card (name, location, `ArgonDropdown` to switch when several); store credit row when a balance exists; latest order card → the order, "All orders" → `orders`; list: Profile, Addresses, Wishlist, Email offers (`ArgonSwitch`: subscribe / unsubscribe), policies (each that exists), Help (contact page), "Manage account on the web" (`https://shopify.com/<SHOP_ID>/account`, in-app browser), Sign out, Delete account (as today). Debug builds keep the Components row.
- **Profile** (`profile`): first and last name (`ArgonInput`) with Save (`updateName`); email and phone read-only with "Change these in your web account".
- **Addresses** (`addresses`): cards with the formatted address, "Default" tag, Edit, Delete (`ArgonModal` confirm; the default can't be deleted: the button is disabled with that hint), "Make default"; "Add address" opens a sheet form: first name, last name, company, address 1, address 2, city, state/province code, ZIP/postal code, country (`ArgonDropdown` of `localization().availableCountries`), phone, "Default address" switch. User errors show under the form.

## Testing

- CLI: contract and scaffold tests (done).
- Each platform: fixture decoding of every changed and new operation (the fixture tests fail on a fixture without a check); `JudgeMeHtml.parse` against `JudgeMeWidget.html`; `Ratings.parse`; `QuantityRule`; `Sections.content`; `SwatchColors`; `discountPercent`; `steppedQuantity`; `orderStatus`; the ACCESS_DENIED rule; `BuyerStore`; the exchange note text; `RecentlyViewedStore`.
- Android: `:app:testDebugUnitTest :ui:testDebugUnitTest assembleDebug`, then a walkthrough on the emulator against mock.shop (all four home templates, both collection templates, product, sample account → orders → return) and against the live test store.
- iOS: compiled on this PC through xtool/WSL (app target only); unit tests run in CI on macOS.

## Not in this change

Order editing, payment-method management, subscriptions management, native sign-in, review photo upload, wishlist sync to the account, push notifications.
