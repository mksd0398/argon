# Argon: API catalog research (Storefront + Customer Account API 2026-10)

Date: 2026-10-09. Purpose: a verified operation catalog for the prebuilt API layer, so app developers never write data-access code.

## 1. Schema source and version

| | Source | Version | Notes |
|---|---|---|---|
| Storefront | `@shopify/hydrogen@2026.10.0`, file `dist/storefront.schema.json` (package export `@shopify/hydrogen/storefront.schema.json`) | **2026-10** (`STOREFRONT_API_VERSION = "2026-10"` in the package) | MIT. Published to npm 2026-10-09 16:02 UTC |
| Customer Account | same package, `dist/customer-account.schema.json` (export `@shopify/hydrogen/customer-account.schema.json`) | **2026-10** (`CUSTOMER_ACCOUNT_API_VERSION = "2026-10"`) | |

- `@shopify/hydrogen-react` is **not** the right package any more. Its newest release is `2026.4.4`, built for **2026-04**. Hydrogen 2026.10.0 no longer depends on hydrogen-react and ships the schemas itself. I extracted hydrogen-react 2026.4.4 as well, but only to diff 2026-04 against 2026-10.
- sha256 values: `storefront.schema.json` `29a080c4cf2560ba55471850e3e27de443b6e3b704143fc7d117ed2ed3650e94`, `customer-account.schema.json` `a9c03194694fe06aec414901fc350ed9f048a5a72b0cf6a562e3b520d75a29b9`. Tarball integrity is `sha512-bKWEixHbsRVP6pLvp56xUPdZqE8E/veqqOJZSR7YlLw3pR/1RR036qW7LglrhMJ4gOovcTr0PuMZOiZWWMr0qQ==`.

### Cross-checks (live, read-only, no tokens)

- **`https://shopify.dev/storefront-graphql-direct-proxy/2026-10`** (introspection POST): matches the Hydrogen Storefront schema type for type and field for field. The only differences are deprecated input values, which the default introspection query hides. This confirms the Hydrogen file is the real 2026-10 schema.
- **`https://mock.shop/api`** (introspection POST): works, but it serves an older version. 2026-10 tightened `cartNoteUpdate(note: String!)` and `cartDiscountCodesUpdate(discountCodes: [String!]!)`, and mock.shop still has them nullable. It also lacks `CurrencyCode::XCG` and some ShopPay fields. Every recommended Storefront document still validates against mock.shop, so `--demo` keeps working. All 12 read-only queries I smoke-ran on mock.shop returned data with no errors: Localization, Shop, ShopPolicies, Menu, Catalog, Collections, Pages, Blogs, Articles, Locations, PredictiveSearch and Search.
- The Customer Account API has no public, tokenless introspection endpoint, so the Hydrogen file is the only source. I diffed it against the 2026-04 file (see section 4).
- **All 18 existing `contract/queries/*.graphql` validate against 2026-10.** That is 16 Storefront documents plus `Customer` and `Order` against the Customer Account schema.

## 2. Storefront API 2026-10 catalog

Status key: **exists** = same name and arguments as expected; **differs** = exists, but the name, arguments or semantics are not what the catalog assumed; **missing** = no such operation.

| Catalog item | Exact field / operation (2026-10) | Key args / return | Status |
|---|---|---|---|
| shop basics | `shop: Shop!` → `name`, `description`, `moneyFormat`, `shipsToCountries`, `primaryDomain { host url }`, `brand { logo squareLogo coverImage colors { primary secondary } slogan shortDescription }` | — | exists |
| payment settings | `shop.paymentSettings: PaymentSettings!` → `currencyCode countryCode acceptedCardBrands supportedDigitalWallets enabledPresentmentCurrencies cardVaultUrl` | — | exists |
| policies | `shop.shippingPolicy / refundPolicy / privacyPolicy / termsOfService: ShopPolicy` (`id handle title body url`), `shop.subscriptionPolicy: ShopPolicyWithDefault` (its `id` is nullable) | Also available: `termsOfSale`, `legalNotice`, `contactInformation` | exists |
| localization | `localization: Localization!` → `availableCountries [Country!]!` (each with `currency`, `availableLanguages`, `defaultLanguage`, `unitSystem`), `availableLanguages`, `country`, `language`, `market` | **`Localization.market` and `Country.market` are DEPRECATED** ("will be removed"). Don't select them | exists, `market` deprecated |
| @inContext | `@inContext(country: CountryCode, language: LanguageCode, buyer: BuyerInput, preferredLocationId: ID, visitorConsent: VisitorConsent, channelId: ID)` on QUERY \| MUTATION | `BuyerInput { customerAccessToken: String!, companyLocationId }`, `VisitorConsent { analytics marketing preferences saleOfData }` | exists (`channelId` and `visitorConsent` are newer) |
| product | `product(handle: String, id: ID): Product` | | exists |
| options / optionValues | `Product.options(first: Int): [ProductOption!]!` → `optionValues: [ProductOptionValue!]!` (`id name swatch { color image } firstSelectableVariant`) | **`ProductOption.values` is DEPRECATED.** Use `optionValues` | exists |
| variants | `Product.variants(first, after, last, before, reverse, sortKey: ProductVariantSortKeys)` | Also `variantsCount: Count`, `encodedVariantExistence`, `encodedVariantAvailability` | exists |
| selectedOrFirstAvailableVariant | `Product.selectedOrFirstAvailableVariant(selectedOptions: [SelectedOptionInput!], ignoreUnknownOptions: Boolean, caseInsensitiveMatch: Boolean): ProductVariant` | | exists |
| variantBySelectedOptions | `Product.variantBySelectedOptions(selectedOptions: [SelectedOptionInput!]!, ignoreUnknownOptions, caseInsensitiveMatch): ProductVariant` | `selectedOptions` is **required** here | exists |
| adjacentVariants | `Product.adjacentVariants(selectedOptions: [SelectedOptionInput!], ignoreUnknownOptions, caseInsensitiveMatch): [ProductVariant!]!` | | exists |
| media | `Product.media(first, after, reverse, sortKey: ProductMediaSortKeys): MediaConnection!`, through interface `Media { id alt mediaContentType presentation previewImage }` | `MediaImage.image`; `Video.sources [url mimeType format width height]`; `ExternalVideo { host embedUrl originUrl }` (**`embeddedUrl` is DEPRECATED**); `Model3d.sources [url mimeType format filesize]`. `MediaContentType` = `EXTERNAL_VIDEO IMAGE MODEL_3D VIDEO` | exists |
| metafields | `metafields(identifiers: [HasMetafieldsIdentifier!]!): [Metafield]!` on Product, Variant, Collection, Shop, Page, Blog, Article, Location, Market and Cart | `{ namespace: String, key: String! }`. Entries in the returned list can be **null** | exists |
| selling plans | `Product.sellingPlanGroups(first…)` → `SellingPlanGroup { name appName options sellingPlans }`; `Product.requiresSellingPlan`; `ProductVariant.sellingPlanAllocations` | Add to cart with `CartLineInput.sellingPlanId` | exists |
| seo | `Product.seo: SEO!` (`title description`). Also on Collection, Page, Blog and Article; Metaobject has `MetaobjectSEO` | | exists |
| products | `products(first, after, last, before, query: String, sortKey: ProductSortKeys, reverse)` | `ProductSortKeys` = `BEST_SELLING CREATED_AT ID PRICE PRODUCT_TYPE RELEVANCE TITLE UPDATED_AT VENDOR`. **No `filters` argument on root `products`.** Faceted filters exist only on `collection.products` and `search` | exists |
| productRecommendations | `productRecommendations(productId: ID, productHandle: String, intent: ProductRecommendationIntent): [Product!]` | intent = `RELATED` \| `COMPLEMENTARY`. The result list is nullable | exists |
| collection + filters | `collection(handle: String, id: ID).products(first, after, filters: [ProductFilter!], sortKey: ProductCollectionSortKeys, reverse)`, where `ProductConnection.filters: [Filter!]!` | `ProductCollectionSortKeys` = `BEST_SELLING COLLECTION_DEFAULT CREATED ID MANUAL PRICE RELEVANCE TITLE`. `ProductFilter` fields: `available category price productMetafield productType productVendor tag taxonomyMetafield variantMetafield variantOption`. `Filter` has `presentation`; `FilterValue` has `image` and `swatch` | exists |
| collections | `collections(first, after, query, sortKey: CollectionSortKeys, reverse)` | `CollectionSortKeys` = `ID RELEVANCE TITLE UPDATED_AT` | exists |
| search | `search(query: String!, first, after, types: [SearchType!], productFilters: [ProductFilter!], sortKey: SearchSortKeys, reverse, prefix: SearchPrefixQueryType, unavailableProducts: SearchUnavailableProductsType)` returns `SearchResultItemConnection { totalCount productFilters nodes }` | `SearchType` = `ARTICLE PAGE PRODUCT`; there is **no COLLECTION** type. Node union = `Article \| Page \| Product`. `SearchSortKeys` = `PRICE RELEVANCE` | exists |
| predictiveSearch | `predictiveSearch(query: String!, types: [PredictiveSearchType!], limit: Int, limitScope: PredictiveSearchLimitScope, searchableFields: [SearchableField!], unavailableProducts)` returns `PredictiveSearchResult` (nullable) `{ products collections pages articles queries { text styledText } }` | `types` = `ARTICLE COLLECTION PAGE PRODUCT QUERY`; `limitScope` = `ALL EACH` | exists |
| menu | `menu(handle: String!): Menu { handle title items itemsCount }`; `MenuItem { id title url type resourceId resource tags items }` | `resource` union = `Article Blog Collection Metaobject Page Product ShopPolicy`. `MenuItemType` includes `METAOBJECT`, `CUSTOMER_ACCOUNT_PAGE` and `SHOP_POLICY` | exists |
| page / pages | `page(handle: String, id: ID)`, `pages(first, after, query, sortKey: PageSortKeys, reverse)` | `Page { body bodySummary seo }` | exists |
| blog / blogs | `blog(handle: String, id: ID)`, `blogs(first, after, query, sortKey: BlogSortKeys, reverse)` | `Blog.articles(...)`, `Blog.articleByHandle(handle: String!)` | exists |
| article (by handle) | **`article(id: ID!)` only. Root `article` has no `handle` argument.** To look up by handle, use `blog(handle:).articleByHandle(handle:)` | **`Article.author` is DEPRECATED.** Use `authorV2` (nullable) | **differs** |
| articles | `articles(first, after, query, sortKey: ArticleSortKeys, reverse)` | `ArticleSortKeys` = `AUTHOR BLOG_TITLE ID PUBLISHED_AT RELEVANCE TITLE UPDATED_AT` | exists |
| metaobject(s) | `metaobject(handle: MetaobjectHandleInput, id: ID)`, where `MetaobjectHandleInput { type: String!, handle: String! }`; `metaobjects(type: String!, first, after, sortKey: String, reverse)` | `Metaobject { field(key:) fields { key type value reference references } seo onlineStoreUrl }` | exists |
| locations | `locations(first, after, near: GeoCoordinateInput, sortKey: LocationSortKeys, reverse)` → `Location { id name address: LocationAddress! }` | `LocationAddress { address1 address2 city province provinceCode zip country countryCode phone formatted latitude longitude }`. `LocationSortKeys` = `CITY DISTANCE ID NAME` | exists |
| store availability | `ProductVariant.storeAvailability(first, after, near: GeoCoordinateInput, reverse)` → `StoreAvailability { available pickUpTime quantityAvailable location }` | | exists |
| cart | `cart(id: ID!): Cart` | `Cart.lines` is a `BaseCartLineConnection` (interface `BaseCartLine`, implemented by `CartLine` and `ComponentizableCartLine`). New in 2026-10: `viewKey` and `Cart.discountApplications`. **DEPRECATED:** `Cart.discountAllocations`, `estimatedCost`, `cost.totalTaxAmount`, `cost.totalDutyAmount` | exists |
| cartCreate | `cartCreate(input: CartInput)` | `CartInput { lines attributes buyerIdentity delivery { addresses } discountCodes giftCardCodes note sourceName }` | exists |
| cartLinesAdd | `cartLinesAdd(cartId: ID!, lines: [CartLineInput!]!)` | `CartLineInput { merchandiseId! quantity sellingPlanId attributes parent }` | exists |
| cartLinesUpdate | `cartLinesUpdate(cartId: ID!, lines: [CartLineUpdateInput!]!)` | **2026-10:** `CartLineUpdateInput.id` is now **optional**, and a `viewKey` field was added | differs (compatible) |
| cartLinesRemove | `cartLinesRemove(cartId: ID!, lineIds: [ID!], viewKeys: [String!])` | **2026-10:** `lineIds` is now nullable and `viewKeys` was added. The current `$lineIds: [ID!]!` still validates | differs (compatible) |
| cartBuyerIdentityUpdate | `cartBuyerIdentityUpdate(cartId: ID!, buyerIdentity: CartBuyerIdentityInput!)` | `{ email phone countryCode customerAccessToken companyLocationId preferences }`. **`deliveryAddressPreferences` is DEPRECATED**; use `cart.delivery`. The Customer Account OAuth token goes straight into `customerAccessToken` (the templates already do this) | exists |
| cartDiscountCodesUpdate | `cartDiscountCodesUpdate(cartId: ID!, discountCodes: [String!]!)` | Replaces the whole list; send `[]` to clear. The list is required in 2026-10 | exists |
| gift cards | **All three exist.** `cartGiftCardCodesAdd(cartId: ID!, giftCardCodes: [String!]!)` appends; `cartGiftCardCodesUpdate(cartId: ID!, giftCardCodes: [String!]!)` replaces all; `cartGiftCardCodesRemove(cartId: ID!, appliedGiftCardIds: [ID!]!)` removes by **`AppliedGiftCard.id`**, not by code | Read state from `Cart.appliedGiftCards { id lastCharacters amountUsed balance }` | exists |
| cartNoteUpdate | `cartNoteUpdate(cartId: ID!, note: String!)` | `note` is required in 2026-10 | exists |
| cartAttributesUpdate | `cartAttributesUpdate(cartId: ID!, attributes: [AttributeInput!]!)` | | exists |
| delivery addresses | `cartDeliveryAddressesAdd(cartId: ID!, addresses: [CartSelectableAddressInput!]!)`, `cartDeliveryAddressesUpdate(cartId: ID!, addresses: [CartSelectableAddressUpdateInput!]!)`, `cartDeliveryAddressesRemove(cartId: ID!, addressIds: [ID!]!)`, plus `cartDeliveryAddressesReplace(cartId: ID!, addresses: [CartSelectableAddressInput!]!)` | `CartSelectableAddressInput { address: CartAddressInput! selected oneTimeUse validationStrategy (COUNTRY_CODE_ONLY \| STRICT) }`. `CartAddressInput { deliveryAddress: CartDeliveryAddressInput \| copyFromCustomerAddressId }`. The update input requires `id`. Maximum 20 addresses, and only one can be selected. Read them from `Cart.delivery.addresses(selected:)` | exists (4 ops) |
| cartSelectedDeliveryOptionsUpdate | `cartSelectedDeliveryOptionsUpdate(cartId: ID!, selectedDeliveryOptions: [CartSelectedDeliveryOptionInput!]!)` | `{ deliveryGroupId: ID!, deliveryOptionHandle: String! }`. Options come from `Cart.deliveryGroups(first, withCarrierRates)` → `deliveryOptions { handle title estimatedCost deliveryMethodType }` | exists |
| cart payloads (all) | `{ cart userErrors: [CartUserError { field message code: CartErrorCode }] warnings: [CartWarning { code message target }] }` | The current contract selects neither `code` nor `warnings` | exists |
| newsletter signup | **None for new customer accounts.** The only Storefront path is `customerCreate(input: CustomerCreateInput { email! password! firstName lastName phone acceptsMarketing })`, and the schema's own description says **"For legacy customer accounts only and requires an email address and password."** Legacy accounts have been unavailable to new stores since Feb 2026 (Shopify changelog, 2026-02-26), and Shopify says the Storefront customer mutations "will be deprecated" | | **missing** (legacy only) |
| contact form | No mutation in either API. Storefront mutations are only `cart*`, the legacy `customer*` set, and `shopPayPaymentRequestSession*` | | **missing** |

Also present but not in the catalog, and not recommended because Checkout Kit owns checkout: `cartBillingAddressUpdate`, `cartMetafieldsSet`, `cartMetafieldDelete`, `cartClone`, `cartRemovePersonalData`, `cartPaymentUpdate`, `cartPrepareForCompletion`, `cartSubmitForCompletion`, `shopPayPaymentRequestSession{Create,Submit}`, `sitemap`, `urlRedirects`, and the legacy `customer(customerAccessToken:)` query.

## 3. Customer Account API 2026-10 catalog

| Catalog item | Exact field / operation (2026-10) | Key args / return | Status |
|---|---|---|---|
| customer | `customer: Customer!` → `id firstName lastName displayName imageUrl creationDate tags emailAddress { emailAddress marketingState: EmailMarketingState! } phoneNumber { phoneNumber smsMarketingConsent whatsAppMarketingConsent } defaultAddress addresses(first, after, reverse, skipDefault)` | `EmailMarketingState` = `INVALID NOT_SUBSCRIBED PENDING REDACTED SUBSCRIBED UNSUBSCRIBED`. **`CustomerPhoneNumber.marketingState` is DEPRECATED**; use `smsMarketingConsent.state` | exists |
| orders | `Customer.orders(first, after, last, before, query: String, sortKey: OrderSortKeys, reverse)` | `OrderSortKeys` = `CREATED_AT ID ORDER_NUMBER PROCESSED_AT TOTAL_PRICE UPDATED_AT` | exists |
| order | `order(id: ID!): Order` (root) | | exists |
| order line items | `Order.lineItems(first, after…)` → `LineItem { id title variantTitle quantity image price totalPrice currentTotalPrice productId variantId sku vendor variantOptions giftCard refundableQuantity }` | | exists |
| fulfillments + tracking | `Order.fulfillments(first, after, query, sortKey: FulfillmentSortKeys, reverse)` → `Fulfillment { status: FulfillmentStatus, latestShipmentStatus: FulfillmentEventStatus, estimatedDeliveryAt, trackingInformation: [TrackingInformation { company number url }]!, fulfillmentLineItems { quantity lineItem }, events, isPickedUp, pickupAddress }` | **`FulfillmentStatus.OPEN` and `.PENDING` are deprecated** | exists |
| totals | `Order.subtotal totalShipping totalTax totalPrice totalRefunded totalDiscountedShipping totalDuties totalTip subtotalBeforeDiscounts`, `discountApplications(first…)`, `currencyCode` | `totalPrice`, `totalShipping` and `totalRefunded` are non-null; the rest are nullable | exists |
| addresses on order | `Order.shippingAddress`, `Order.billingAddress` (both `CustomerAddress`) | **`Order.shippingTitle` was REMOVED in 2026-10.** Use `shippingLine` / `shippingLineGroups` | exists |
| statuses | `Order.financialStatus: OrderFinancialStatus` (nullable), `Order.fulfillmentStatus: OrderFulfillmentStatus!` | financial = `AUTHORIZED EXPIRED PAID PARTIALLY_PAID PARTIALLY_REFUNDED PENDING REFUNDED VOIDED`; fulfillment = `FULFILLED IN_PROGRESS ON_HOLD OPEN PARTIALLY_FULFILLED PENDING_FULFILLMENT READY_FOR_DELIVERY READY_FOR_PICKUP RESTOCKED SCHEDULED UNFULFILLED` | exists |
| cancellation | `Order.cancelledAt: DateTime`, `Order.cancelReason: OrderCancelReason` | Customers **cannot** cancel an order through this API; there is no order-cancel mutation. The closest is `orderRequestEdit` (new in 2026-10) | read-only exists; cancel **missing** |
| misc order | `name number confirmationNumber processedAt statusPageUrl reorderPath edited`; **`Order.market` is DEPRECATED** | | exists |
| customerUpdate | `customerUpdate(input: CustomerUpdateInput!)` → `{ customer userErrors }` | `CustomerUpdateInput` = **`{ firstName lastName }` only.** Email and phone cannot be changed through this API | exists (limited) |
| address create | `customerAddressCreate(address: CustomerAddressInput!, defaultAddress: Boolean)` → `{ customerAddress userErrors }` | `CustomerAddressInput { firstName lastName company address1 address2 city zoneCode zip countryCode phoneNumber }` | exists |
| address update | `customerAddressUpdate(addressId: ID!, address: CustomerAddressInput, defaultAddress: Boolean)` | `address` is optional, so you can send just `defaultAddress: true` | exists |
| address delete | `customerAddressDelete(addressId: ID!)` → `{ deletedAddressId userErrors }` | | exists |
| set default address | **No dedicated mutation**; the legacy Storefront `customerDefaultAddressUpdate` has no Customer Account equivalent. Pass `defaultAddress: true` to create or update | Error codes `DELETING_CUSTOMER_DEFAULT_ADDRESS_NOT_ALLOWED` and `DEMOTING_CUSTOMER_DEFAULT_ADDRESS_NOT_ALLOWED`: to delete or demote the default, promote another address first | differs |
| address input rename | **`CustomerAddressInput.territoryCode` → `countryCode`** (2026-04 had `territoryCode`; 2026-10 removed it). `CustomerAddress.territoryCode` is deprecated in favor of `countryCode`. Province uses `zoneCode`, phone uses `phoneNumber` | | **renamed** |
| email marketing | `customerEmailMarketingSubscribe` and `customerEmailMarketingUnsubscribe` (no args; act on the signed-in customer) → `{ emailAddress { emailAddress marketingState } userErrors { field message code } }` | Codes: `CUSTOMER_ALREADY_SUBSCRIBED EMAIL_ADDRESS_NOT_FOUND FAILED_TO_SUBSCRIBE FAILED_TO_UNSUBSCRIBE`. Scope `customer_write_customers`. `customerEmailMarketingOptIn` is also in the schema (since 2026-04 at least), but shopify.dev has **no page for it (404)**, so don't use it | exists (signed-in only) |
| WhatsApp marketing | `customerWhatsAppMarketingConsentUpdate(input: CustomerWhatsAppMarketingConsentUpdateInput!)` | New in 2026-10 | exists (extra) |
| returns | `orderRequestReturn(orderId: ID!, requestedLineItems: [RequestedLineItemInput!]!)` → `{ return { id name status } userErrors: [ReturnUserError] }` | `RequestedLineItemInput { lineItemId: ID! quantity: Int! returnReasonDefinitionId: ID customerNote }`. There is **no `returnReason` enum input**; reasons come from `LineItem.suggestedReturnReasonDefinitions` (**`supportedReturnReasons` is DEPRECATED**). Returnable items come from `Order.returnInformation.returnableLineItems`. Read back with `Order.returns`, root `return(id:)` and `returnCalculate` | exists |
| cart sign-in link | **`storefrontCustomerAccessTokenCreate` is DEPRECATED.** Per the Shopify changelog, since 2025-01 the Storefront API accepts the Customer Account token directly (`CartBuyerIdentityInput.customerAccessToken` / `@inContext(buyer:)`) | Argon already sends the token directly | n/a |
| shop (CA) | `shop { name email url myshopifyDomain shopPolicies addressFormSettings }` | `addressFormSettings` is useful for address forms | exists (extra) |

### Newsletter / contact, bottom line
- **Signed-in customer:** use the Customer Account API's `customerEmailMarketingSubscribe` / `Unsubscribe`.
- **Guest:** no Storefront or Customer Account API path in 2026-10. `customerCreate` is legacy-only, needs a password, and creates an account. A guest signup needs the merchant's own backend (Admin API `customerEmailMarketingConsentUpdate` / `customerCreate`), an ESP endpoint, or the checkout's own marketing checkbox. Argon should expose a pluggable `NewsletterSubscriber`-style hook with no default implementation rather than call `customerCreate`.
- **Contact form:** no API. Use `mailto:` or a merchant-configured URL.

## 4. 2026-04 → 2026-10 changes that touch the catalog
- Storefront: `cartLinesRemove.lineIds` became nullable and `viewKeys` was added; `CartLineUpdateInput.id` became optional and `viewKey` was added; `BaseCartLine.viewKey`, `discountAllocations(lineLevelOnly:)` and `Cart.discountApplications` were added; `CartInput.sourceName` was added; `CartWarningCode::PRODUCT_UNAVAILABLE_IN_BUYER_LOCATION` was added; `CartBuyerIdentityInput.deliveryAddressPreferences` became deprecated.
- Customer Account: `CustomerAddressInput.territoryCode` was removed and `countryCode` added; `Order.shippingTitle` was removed; `Customer.lastIncompleteCheckout` was removed; `orderRequestEdit`, `requestedOrderEditCalculate`, `customerWhatsAppMarketingConsentUpdate`, `Customer.marketCurrencyCode` and `LineItem.presentmentName` were added. The draft `CustomerAddress` fragment below **fails on 2026-04** because of `countryCode`, so pin the version.

## 5. Recommended document list

Every operation below was written out and **validated against the 2026-10 schemas**: 37 Storefront operations and 12 Customer Account operations, with no errors. A negative test confirmed the validator rejects bad fields and arguments. The Storefront set also validates against mock.shop and 2026-04. Drafts are in the session scratchpad: `…\scratchpad\drafts\storefront.graphql` and `…\scratchpad\drafts\customer-account.graphql` (each operation = one `contract/queries/<Name>.graphql`).

### Storefront (`contract/queries/`)
- **Keep unchanged:** `HomeScreen`, `FallbackHome`, `Products` (`nodes(ids:)`).
- **Extend:**
  - `Shop`: add `description moneyFormat shipsToCountries brand.squareLogo/slogan paymentSettings`.
  - `Menu`: resource also covers `Page`, `Blog`, `Article { blog { handle } }`, `ShopPolicy` and `Metaobject`.
  - `Catalog`: add `$query`.
  - `Product`: add `selectedOrFirstAvailableVariant`, `adjacentVariants`, `optionValues { firstSelectableVariant swatch }`, all four media types, `sellingPlanGroups`, `seo`, `encodedVariant*`, `requiresSellingPlan`, `isGiftCard`.
  - `Collection`: add `handle seo image`.
  - `Search`: add `$types` and `$unavailableProducts`, plus `Page` and `Article` nodes.
  - `PredictiveSearch`: take `$limit` and `$types` as variables, use `limitScope: EACH`, add `pages` and `articles`.
  - `Cart`: add `...CartDeliveryGroups`.
  - `CartCreate`, `CartLinesAdd`, `CartLinesUpdate`, `CartLinesRemove`, `CartBuyerIdentityUpdate`: select `userErrors { field message code }` and `warnings { code message target }`.
- **New queries:** `Localization`, `ShopPolicies`, `VariantBySelectedOptions`, `ProductRecommendations`, `Collections`, `StoreAvailability` (`node(id:)` on `ProductVariant`), `Locations`, `Page`, `Pages`, `Blogs`, `Blog`, `Article` (blog handle + article handle), `Articles`, `Metaobject`, `Metaobjects`.
- **New mutations:** `CartDiscountCodesUpdate`, `CartGiftCardCodesAdd`, `CartGiftCardCodesRemove`, `CartNoteUpdate`, `CartAttributesUpdate`, `CartDeliveryAddressesAdd`, `CartDeliveryAddressesUpdate`, `CartDeliveryAddressesRemove`, `CartSelectedDeliveryOptionsUpdate`.
  - Skipped on purpose: `cartGiftCardCodesUpdate` and `cartDeliveryAddressesReplace` duplicate Add+Remove with replace-all semantics; add them if a screen needs that. The delivery-address and delivery-option operations matter only if an app shows shipping estimates before Checkout Kit, since checkout already handles both.
- **`fragments.graphql` additions:** `Variant`, `Media`, `Policy`, `LocationAddress`, `ArticleCard`, `CartDeliveryGroups`, `CartUserError`, `CartWarning`. Extend `Cart` with `note attributes discountCodes appliedGiftCards buyerIdentity delivery.addresses lines.attributes lines.discountAllocations`.

### Customer Account (`contract/queries/`)
- **Change:** `Customer` becomes profile only (`id displayName imageUrl emailAddress.marketingState phoneNumber defaultAddress`); move its embedded `orders(first: 20)` out into `Orders`.
- **Extend:** `Order` adds `number confirmationNumber statusPageUrl fulfillmentStatus cancelledAt cancelReason shippingAddress billingAddress totalShipping totalTax totalRefunded discountApplications lineItems.{id productId variantId price}`, plus `fulfillments { status latestShipmentStatus estimatedDeliveryAt trackingInformation fulfillmentLineItems }`.
- **New queries:** `Orders` (paginated, `sortKey`, `query`), `CustomerAddresses`, `OrderReturnOptions` (returnable items + reason definitions + existing returns).
- **New mutations:** `CustomerUpdate`, `CustomerAddressCreate`, `CustomerAddressUpdate`, `CustomerAddressDelete`, `CustomerEmailMarketingSubscribe`, `CustomerEmailMarketingUnsubscribe`, `OrderRequestReturn`.
- **Fragment names:** `lib/contract.js` keeps one fragment namespace for both APIs, so Customer Account fragments need unique names (the drafts use `CAMoney`, `CustomerAddress`, `AddressError`). With about 12 Customer Account documents, consider a separate folder or a name prefix so the apps pick the endpoint per document without a hard-coded list.

## 6. Schema files for CI vendoring

Extracted (session scratchpad, temporary):
- `C:\Users\arjun\AppData\Local\Temp\claude\C--Users-arjun-mksd-create-shopify-app-storefront\cefb3f9b-1856-47bf-90bb-bbbb824a3378\scratchpad\schemas\hydrogen-2026.10.0\pkg\package\dist\storefront.schema.json`
- `...\scratchpad\schemas\hydrogen-2026.10.0\pkg\package\dist\customer-account.schema.json`
- The 2026-04 comparison copies are in `...\scratchpad\schemas\hydrogen-react-2026.4.4\pkg\package\`, and the live introspection dumps are in `...\scratchpad\schemas\live\` (`sfapi-2026-10-devproxy.json`, `mockshop.json`).

To reproduce, with no install scripts run: `npm pack @shopify/hydrogen@2026.10.0 --ignore-scripts`, then `tar -xzf shopify-hydrogen-2026.10.0.tgz package/dist/storefront.schema.json package/dist/customer-account.schema.json`, then check the sha256 values in section 1. Suggested vendored location: `contract/schema/storefront.2026-10.json` and `contract/schema/customer-account.2026-10.json` (about 1.4 MB and 1.7 MB). A CI step can then run `graphql.validate()` on each resolved contract document against its schema, using the same check as `scratchpad\scripts\validate.js`.
