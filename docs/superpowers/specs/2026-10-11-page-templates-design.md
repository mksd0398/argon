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

A fourth key, `SHOW_VENDOR` (`true` / `false`, default `false`, `AppGraph.showVendor`), decides whether cards and the product page show the vendor: many stores' vendor is their own name or an internal label, and Shopify's themes hide it by default.

An unknown value falls back to the default. Android reads them through `BuildConfig` (add to `app/build.gradle.kts` beside `PDP_METAFIELDS`); iOS through `AppGraph.info` (Info.plist keys `HomeTemplate`, `CollectionTemplate`, `JudgemePublicToken`, which fall back to the bundled `Config.xcconfig`).

Enums, same names on both platforms: `HomeTemplate { fashion, beauty, grocery, b2b }`, `CollectionTemplate { top, bottom }`.

## Data contract (already in `contract/`, fixtures in `contract/fixtures/`)

55 operations (41 Storefront, 14 Customer Account). What changed since phase 2:

- **Every Storefront operation** takes `$buyer: BuyerInput` in `@inContext(country:, language:, buyer:)`.
- **`ProductCard`** (fragment, so every product list): `vendor`, `priceRange.maxVariantPrice`, `options(first: 3) { name optionValues { name swatch } }`, `firstVariant: selectedOrFirstAvailableVariant { id sku availableForSale quantityRule }`, `rating` / `ratingCount` (the standard `reviews.rating` and `reviews.rating_count` metafields).
- **`Filter`**: `presentation` (`IMAGE` | `SWATCH` | `TEXT`), `values.swatch { color image { previewImage } }`.
- **`Cart`**: `buyerIdentity.purchasingCompany { company location }`; per line `sellingPlanAllocation.sellingPlan`, merchandise `sku` and `quantityRule`, and `lineComponents` on `ComponentizableCartLine` (a bundle's parts).
- **`Product`**: `tags`, `onlineStoreUrl`, `rating`, `ratingCount`. It no longer selects `metafields(identifiers:)` or `sellingPlanGroups`: both are non-null, so a request that is refused either one (`ACCESS_DENIED`) gets a null product. Seen with a tokenless request; a token without the selling-plans permission would hit the same.
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

A request without a permission is answered 200 with `data` and `errors` of code `ACCESS_DENIED` (seen on tokenless requests for `quantityAvailable`, which needs `unauthenticated_read_product_inventory`, and for `metafield`; a token whose permissions were trimmed in the Headless channel gets the same). In the shared GraphQL send (`graphQL` on Android, its Swift twin): when **every** error has `extensions.code == "ACCESS_DENIED"` **and** `data`'s value at each error's `path[0]` is non-null, return `data` (the denied fields are null) and log each distinct message once. Anything else throws `GraphQL` as today. Result: no stock count and no rating stars instead of a broken page; the home screen's metaobject fallback still works (its denied root field is null, so it still throws).

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

## Round 2 (2026-10-11): icon and launch screen, onboarding, overlay top bar, cart

### Fixed in this round

Checkout reloaded about once a second for a signed-in customer. Shopify answers every cart buyer update with a checkout URL under a new key; `CartStore.checkoutUrl()` attached the customer on every call, so the cart changed each time, and the cart screen prepares checkout whenever the cart changes. The store now remembers the buyer a cart already has (`attached`: cart id, token, company location) and attaches it once.

### App icon and launch screen from the store's logo

The app already shows `shop.brand` in its top bar. The CLI now also builds the app icon and the launch screen from it, at generation time (they are part of the binary; nothing can set them at run time).

**CLI.** After the Storefront token is verified (and for `--demo`), it asks the Storefront API for `shop.brand.squareLogo.image` and `shop.brand.logo.image`, each as a PNG through `url(transform: { maxWidth, maxHeight, preferredContentType: PNG })`, so Shopify's CDN does the resizing and the conversion. It prefers the square logo. A pure-JS PNG reader/writer in `lib/png.js` (Node's `zlib`, no dependency) decodes it, takes the background colour (the top-left pixel when it is opaque, else white), and writes:

| File | Content |
|---|---|
| `android/app/src/main/res/drawable-xxxhdpi/launcher_logo.png` | the logo, at most 264×264 px (66 dp, the adaptive icon's safe zone), transparent as downloaded |
| `android/app/src/main/res/values/launcher.xml` | `<color name="launcher_background">#RRGGBB</color>` |
| `ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | 1024×1024, opaque: the logo centred within 62% of the side on the background colour |
| `ios/App/Assets.xcassets/LaunchLogo.imageset/LaunchLogo.png` | the logo, at most 600×600 px, transparent |
| `ios/App/Assets.xcassets/LaunchBackground.colorset/Contents.json` | the background colour |

When the CLI writes `launcher_logo.png` it deletes the template's `res/drawable/launcher_logo.xml` (a resource can't be both). Without a logo (none set, the download fails, or an image it can't read) it keeps the template's Android vector and draws a plain default for iOS (the brand's primary colour, else ink, with a paper square), and says so in one line. `ios/xtool.yml` gets `iconPath: App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

**Android template** (minSdk 26, so adaptive icons only):
- `res/mipmap-anydpi-v26/ic_launcher.xml` and `ic_launcher_round.xml`: background `@color/launcher_background`, foreground `@drawable/launcher_foreground`.
- `res/drawable/launcher_foreground.xml`: a layer list with `@drawable/launcher_logo` centred (gravity center, never scaled up).
- `res/drawable/launcher_logo.xml`: the default mark, a vector bag in ink, 66 dp.
- `res/values/launcher.xml`: `launcher_background` `#FFFFFF`.
- `res/values/themes.xml`: `Theme.App` (parent `android:Theme.Material.Light.NoActionBar`) with `android:windowBackground` = `@drawable/launch_screen` (the background colour with the logo centred), for Android 8 to 11.
- `res/values-v31/themes.xml`: the same theme with `android:windowSplashScreenBackground` = `@color/launcher_background` and `android:windowSplashScreenAnimatedIcon` = `@drawable/launcher_foreground` (Android 12+ shows the system splash).
- Manifest: `android:icon="@mipmap/ic_launcher"`, `android:roundIcon="@mipmap/ic_launcher_round"`, `android:theme="@style/Theme.App"`.

**iOS template:** `App/Assets.xcassets` with `AppIcon.appiconset` (one 1024 universal icon), `LaunchLogo.imageset`, `LaunchBackground.colorset` (their `Contents.json`; the PNGs come from the CLI). Build settings `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` on the app target, and the launch screen in `Info.plist`: `UILaunchScreen` = `{ UIColorName: LaunchBackground, UIImageName: LaunchLogo }` (replacing `INFOPLIST_KEY_UILaunchScreen_Generation`). `Package.swift` excludes `Assets.xcassets` (xtool can't compile asset catalogs; its icon comes from `iconPath`, and its launch screen stays plain).

### Onboarding

A first-launch welcome, shown once before the tabs. Config key `ONBOARDING` (`true` default / `false`), `AppGraph.onboarding`.

- Three pages in a full-screen pager with page dots: a full-bleed image (the home template's three stock banners, `StockImages`), a display heading and one line of text over a bottom shade.
  1. "Welcome to <shop name>" / the brand's short description, else its slogan, else "Everything from <shop name>, in one app."
  2. "Find it fast" / "Search, filter and save what you love."
  3. "Checkout in a few taps" / "Track your orders and returns from your account."
- "Skip" at the top end on pages 1 and 2. Bottom button: "Next" on pages 1 and 2, "Get started" on page 3. On page 3, when sign-in is configured, a second button "Sign in" opens the Account tab.
- Finishing or skipping stores `onboarding.done` (`OnboardingStore`, prefs/UserDefaults) and shows the tabs. The page list is a pure `Onboarding.pages(brand, template)`, tested.
- Debug builds: a row "Show onboarding" on the Account screen runs it again.

### Overlay top bar and an edge-to-edge hero

`ArgonTopBar` gets a variant `Overlay` (`.overlay`): no background, its logo, title and actions in white over a short dark shade, drawn on top of content that runs to the top edge of the screen, status bar included. A parameter `solid: Float` (0...1) fades in the normal surface and ink content as the content under it scrolls away. Gallery entry.

The fashion home uses it: the hero carousel starts at the very top of the screen (under the status bar and the bar), the bar is transparent over it and turns solid once the hero has scrolled most of the way out. Status bar icons are light over the hero and follow the theme once solid. The other three home templates keep their bars. The product page keeps its bar.

### Cart

Top bar "Cart". One scrolling list, then a pinned summary.

1. **Free shipping progress** when `FREE_SHIPPING_THRESHOLD` is set (a number in the shop's currency; empty hides it; the demo sets 150): `ArgonProgressBar` with "Add <amount> more for free shipping" or, once reached, "You've unlocked free shipping". Pure `freeShipping(subtotal, threshold)`: remaining amount and progress 0...1, tested. It compares the cart's total (after discounts).
2. **Lines**, as now (image, title, variant, plan, bundle parts, stepper, remove), plus: the line's compare-at price struck beside its price when it has one, and under it each discount on the line ("WELCOME10 −$12.00", the code or the automatic discount's title).
3. **Discount code**: an `ArgonInput` "Discount code" with an "Apply" button. Applied codes show as removable `ArgonTag`s. `CartStore.applyDiscount(code)` / `removeDiscount(code)` use `updateDiscountCodes` with the full list. A code Shopify reports as not applicable is removed again and the row shows "This code can't be used on your cart" under the field.
4. **You may also like**: `recommendations(productId, RELATED)` for the first line's product, without products already in the cart, `compact` cards with `QuickAdd` in a `ProductCardRow`. Hidden when empty or it fails.
5. **Summary** (pinned): "Subtotal" (the lines before discounts), "Discounts" (−amount, hidden at zero), "You save" (compare-at savings plus discounts, in the success colour, hidden at zero), "Total" (headline), the note "Taxes and shipping are calculated at checkout", then "Checkout". Pure `cartSummary(cart)`, tested with the `Cart` fixture (360.00, −36.00, save 126.00, total 324.00).
6. Empty: "Your cart is empty" and a "Start shopping" button (Shop tab).

Models: `CartLine` gains `subtotal`, `unitPrice`, `compareAtUnitPrice: Money?`, `discounts: [CartDiscount(amount, label)]`, `productId`. New config key `FREE_SHIPPING_THRESHOLD` → `AppGraph.freeShippingThreshold: Double?`.

## Round 3 (2026-10-11): analytics (Google Analytics, Meta, MoEngage), reviews without a token

### Analytics core (both platforms, no SDK): `data/Analytics.kt`, `Data/Analytics.swift`

One hub that every screen and store reports into; providers plug in behind it.

- `AnalyticsItem(productId, variantId?, name, brand?, category?, variant?, price: Double?, quantity: Int = 1)`. Ids are the numeric tail of the Shopify gid ("gid://shopify/Product/123" → "123"): what Google's and Meta's catalogs use.
- `AnalyticsEvent` (a sealed type, one case per event; the wire name is GA4's):

| Case | GA4 name | Fired from |
|---|---|---|
| `ScreenView(screen)` | `screen_view` | every navigation destination (one place on Android: the nav controller's destination listener; a `trackScreen(name)` view modifier on iOS) |
| `ViewItemList(listId?, listName, items)` | `view_item_list` | a collection's first page; search results |
| `ViewItem(item, currency)` | `view_item` | the product page, once the product is loaded |
| `Search(term)` | `search` | a submitted search |
| `AddToWishlist(item, currency)` | `add_to_wishlist` | `WishlistStore` when a product is added |
| `AddToCart(item, currency)` | `add_to_cart` | `CartStore`, after Shopify accepted the change (covers the product page, quick add and the cart's steppers going up) |
| `RemoveFromCart(item, currency)` | `remove_from_cart` | `CartStore`, after a line was removed or its quantity went down |
| `ViewCart(items, value, currency)` | `view_cart` | the cart screen, each time it is opened with a cart |
| `BeginCheckout(items, value, currency, coupon?)` | `begin_checkout` | when the checkout sheet is presented (not from the pixel event: the app has the whole cart) |
| `AddShippingInfo(value, currency)` | `add_shipping_info` | Checkout Kit pixel event `checkout_shipping_info_submitted` |
| `AddPaymentInfo(value, currency)` | `add_payment_info` | Checkout Kit pixel event `payment_info_submitted` |
| `Purchase(orderId, value, currency, tax?, shipping?, coupon?, items)` | `purchase` | Checkout Kit's completed callback (`orderDetails`), not the pixel event, so it is sent once |
| `Login` | `login` | a completed sign-in |

  `orderId` is the numeric tail of `orderDetails.id`; it is GA4's `transaction_id` and the tail of Meta's event id (`purchase-<orderId>`), the same on the server (below), which is what stops double counting.
- `AnalyticsUser(id, email?, phone?, firstName?, lastName?)`: the signed-in customer (numeric id), or null after sign-out.
- `interface AnalyticsSink { track(event); identify(user?); suspend cartAttributes(): Map<String, String> }` (defaults: nothing, empty).
- `Analytics(sinks, allowed: () -> Boolean)`: `track` and `identify` do nothing while `allowed()` is false and never throw into the caller (a sink's exception is logged). `cartAttributes()` merges the sinks' maps, plus `_argon_platform` = `android` | `ios` when any sink is configured; empty when not allowed.
- Consent: `AnalyticsConsentStore` (a persisted flag, on by default) and a switch "Share usage data" under a "Privacy" heading on the Account screen, with the note "Helps improve the app and the offers you see." ponytail: one switch, on by default; a store selling in the EU needs a prompt before the first event, and iOS's tracking prompt (ATT) is not shown, so Meta gets no advertising id on iOS.
- `LogSink`: debug builds only; one line per event (`Analytics: add_to_cart {…}`) to logcat / the Xcode console. It is how the events are checked without any provider account.
- `CartStore` passes `analytics.cartAttributes()` as `CartInput.attributes` when it creates a cart (never afterwards: a cart mutation changes the checkout URL, see the Round 2 fix). They become the order's note attributes, which the server reads.
- Tests: the pure mappers (cart line → item, completed order → `Purchase`, pixel event name → event), `Analytics` gating on consent and surviving a throwing sink, `CartStore` emitting add/remove with the right quantities and sending the attributes on cart creation only.

### Providers (SDKs), each compiled in only when it is configured

| Provider | Configured by | Android | iOS |
|---|---|---|---|
| Google Analytics 4 | `android/app/google-services.json`, `ios/App/GoogleService-Info.plist` (Firebase's own files) | Firebase Analytics | `FirebaseAnalytics` |
| Meta | `META_APP_ID`, `META_CLIENT_TOKEN` | `facebook-core` (App Events) | `FacebookCore` |
| MoEngage | `MOENGAGE_WORKSPACE_ID`, `MOENGAGE_DATA_CENTER` (1...6, default 1) | `moe-android-sdk` | `MoEngage-iOS-SDK` |

- Android: `app/build.gradle.kts` decides from the files and keys above. For each provider it adds the dependency and one of two source folders: `src/<provider>/java` (the real `FirebaseSink` / `MetaSink` / `MoEngageSink`) or `src/no<Provider>/java` (a stub of the same factory function returning null). `AppGraph` calls the three factories; no reflection. The Google services plugin is applied only when `google-services.json` exists. An app with none configured carries no SDK.
- iOS: the CLI writes the package dependencies into `Package.swift` for the chosen providers; each sink's file is wrapped in `#if canImport(<module>)`. (Xcode users add the same packages in Xcode; the README says which.)
- Mapping: GA4 gets the names above with `items`. Meta gets its standard events (`fb_mobile_content_view`, `fb_mobile_search`, `fb_mobile_add_to_cart`, `fb_mobile_add_to_wishlist`, `fb_mobile_initiated_checkout`, `fb_mobile_add_payment_info`, `fb_mobile_purchase` through `logPurchase`) with `fb_content_id`, `fb_content_type` = `product`, `fb_currency`, and `event_id` on the purchase. MoEngage gets the names its Shopify integration uses for the same actions where documented, else Title Case ("Product Viewed"), plus user attributes from `identify` (unique id, email, mobile, first and last name) and its logout.
- `cartAttributes()`: Firebase gives `_ga_app_instance_id`; Meta gives `_meta_anon_id`, `_meta_extinfo` (the Conversions API's `extinfo` array as JSON) and `_meta_tracking` (`1`/`0`).
- MoEngage push and in-app messages are not in this round (they need FCM/APNs keys).

### CLI
Flags and prompts (all optional; the prompt is one multi-select "Analytics"): `--firebase-android=<google-services.json>`, `--firebase-ios=<GoogleService-Info.plist>` (copied in), `--meta-app-id`, `--meta-client-token`, `--moengage-workspace-id`, `--moengage-data-center`. New config keys `META_APP_ID`, `META_CLIENT_TOKEN`, `MOENGAGE_WORKSPACE_ID`, `MOENGAGE_DATA_CENTER`, empty by default. `--server` (implied by Firebase or Meta) also writes `server/`.

### Server side: `server/` (a Cloudflare Worker, one file, no dependencies)
Argon has no backend, and the keys that let a server report a sale (GA4's API secret, Meta's access token) must never be in an app. So the purchase, the one event ad platforms want from a server, is sent by a small Worker the store deploys:
- `POST /webhooks/orders` receives Shopify's `orders/create` webhook, checks `X-Shopify-Hmac-Sha256` against `SHOPIFY_WEBHOOK_SECRET` (401 otherwise), and ignores orders without the `_argon_platform` note attribute (the store's web pixels already report web orders).
- GA4: Measurement Protocol `purchase` for the app stream (`firebase_app_id` + `api_secret`, `app_instance_id` from `_ga_app_instance_id`), `transaction_id` = the order's id.
- Meta: Conversions API `Purchase` with `action_source: "app"`, `event_id` = `purchase-<order id>`, hashed email and phone, `external_id`, `anon_id`, `app_data` from the attributes.
- Secrets are Worker secrets (`wrangler secret put`): `SHOPIFY_WEBHOOK_SECRET`, `GA4_API_SECRET`, `GA4_FIREBASE_APP_ID_ANDROID`, `GA4_FIREBASE_APP_ID_IOS`, `META_DATASET_ID`, `META_ACCESS_TOKEN`. A provider without its secrets is skipped.
- Only the purchase goes through the server. Sending every event from both sides would double count in GA4, which de-duplicates purchases (by `transaction_id`) and nothing else.
- Tests (`node --test`, `fetch` stubbed): the signature check, the skip rule, both payloads from a recorded order.

### Reviews without a token
With `JUDGEME_PUBLIC_TOKEN` empty (and no sample file), `JudgeMe` reads the endpoint Judge.me's own storefront widget pages through: `GET https://api.judge.me/reviews/reviews_for_widget?url=<shop>&shop_domain=<shop>&platform=shopify&page=&per_page=&product_id=<numeric id>` → `{ html, total_count, page }`, where `html` holds the same `jdgm-rev` blocks the token route returns (no summary header). The count is `total_count`; the average is the product's `rating` metafield when the store exposes it, else the mean of the reviews when they all fit on the loaded pages, else not shown; no star breakdown. The endpoint is not a documented API (a `ponytail:` comment says so); the token stays the supported route. A store without Judge.me answers with zero reviews, and the section stays hidden as before.

### Free shipping in the shop's currency only
The progress row is shown only when the cart's currency is the shop's (`shop.paymentSettings.currencyCode`): the threshold is a number in that currency.

## Not in this change

Order editing, payment-method management, subscriptions management, native sign-in, review photo upload, wishlist sync to the account, push notifications, gift cards in the cart.
