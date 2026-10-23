import Foundation

/// The buyer's country and language, sent with every Storefront operation (`@inContext`): prices, currency and translated
/// content follow it. Nil parts mean the shop's defaults. Codes are Shopify's (`CA`, `EN`, `PT_BR`).
struct StorefrontContext: Equatable, Sendable {
    var country: String? = nil
    var language: String? = nil

    /// The device's country and language, each only when the shop has it in `localization` (a picker can set others later).
    static func device(_ localization: Localization, locale: Locale = .current) -> StorefrontContext {
        let region = locale.region?.identifier.uppercased()
        let country = localization.availableCountries.first { $0.isoCode == region }
        let languages = country?.availableLanguages ?? localization.availableLanguages
        // Shopify names some languages by region (PT_BR, ZH_TW), the rest by language alone (FR)
        let language = locale.language.languageCode?.identifier.uppercased()
        let regional = language.flatMap { language in region.map { "\(language)_\($0)" } }
        let picked = [regional, language].compactMap { $0 }.first { code in languages.contains { $0.isoCode == code } }
        return StorefrontContext(country: country?.isoCode, language: picked)
    }
}

/// The B2B buyer the Storefront API prices for (`@inContext(buyer:)`): the signed-in customer's Customer Account API access
/// token and the company location they buy for. Catalogues, prices and quantity rules follow it.
struct Buyer: Encodable, Equatable, Sendable {
    let customerAccessToken: String
    var companyLocationId: String? = nil
}

/// Every Storefront API operation in `queries/`, as typed calls. `transport` runs a named operation and returns the response
/// body (`Storefront.query` in the app, canned answers in tests). Lists come back as `Page`s: pass `endCursor` as `after` for
/// the next (Storefront lists come 24 to a page). `shop`, `localization`, `policies` and `menu` are kept for the session.
/// Failures are `ArgonAPIError`s; a cart mutation that Shopify refuses throws its `userErrors`, and its warnings come back on
/// the cart (`Cart.warnings`).
@MainActor
final class StorefrontAPI {
    /// Sent with every operation. A different one forgets what was kept (it is translated, and priced, for the old one).
    var context = StorefrontContext() {
        didSet { if context != oldValue { forget() } }
    }

    /// Sent with every operation as `$buyer` (nil: a retail shopper). `BuyerStore` sets it; a different one forgets what
    /// was kept, like `context`.
    var buyer: Buyer? = nil {
        didSet { if buyer != oldValue { forget() } }
    }

    private let transport: GraphQLTransport
    /// The template the app was built with for a screen handle (a theme's `built-in/screen-<handle>.json`), shown when the
    /// store has no `app_screen` of its own.
    var builtInScreen: (String) -> String? = { _ in nil }
    private var keptShop: Shop? = nil
    private var keptLocalization: Localization? = nil
    private var keptPolicies: ShopPolicies? = nil
    private var keptMenus: [String: StoreMenu?] = [:]
    /// Counts the times the context or the buyer changed: an answer asked for before a change isn't kept.
    private var changes = 0

    init(transport: @escaping GraphQLTransport) {
        self.transport = transport
    }

    // MARK: Shop

    func shop() async throws -> Shop {
        if let kept = keptShop { return kept }
        let asked = changes
        let shop: Shop = try await run("Shop", root: "shop")
        if changes == asked { keptShop = shop }
        return shop
    }

    /// The countries the shop sells to and its languages, `country` and `language` being the shop's defaults: it runs
    /// without the context, which `StorefrontContext.device` picks from it.
    func localization() async throws -> Localization {
        if let kept = keptLocalization { return kept }
        let localization: Localization = try await fetchField(transport, "Localization", [:], root: "localization")
        keptLocalization = localization
        return localization
    }

    func policies() async throws -> ShopPolicies {
        if let kept = keptPolicies { return kept }
        let asked = changes
        let policies: ShopPolicies = try await run("ShopPolicies", root: "shop")
        if changes == asked { keptPolicies = policies }
        return policies
    }

    /// Menu `handle` (`main-menu` is the store's main navigation); nil when the store has none by that handle.
    func menu(_ handle: String) async throws -> StoreMenu? {
        if let kept = keptMenus[handle] { return kept }
        let asked = changes
        let menu: StoreMenu? = try await run("Menu", ["handle": handle], root: "menu")
        if changes == asked { keptMenus[handle] = .some(menu) }
        return menu
    }

    // MARK: Products

    /// The product page's product; nil when there is none by `handle`. `selectedOptions` (option name to value) picks
    /// `selectedOrFirstAvailableVariant` and `adjacentVariants`.
    func product(_ handle: String, selectedOptions: [String: String] = [:]) async throws -> Product? {
        var variables: [String: Any] = ["handle": handle]
        if !selectedOptions.isEmpty { variables["selectedOptions"] = selected(selectedOptions) }
        return try await run("Product", variables, root: "product")
    }

    /// The metafields `identifiers` (PDP_METAFIELDS) that product `handle` has a value for; none are asked for, or there is
    /// no such product: empty. Apart from `product`, because a token without `unauthenticated_read_metafields` is refused
    /// the whole product they are selected on: this call then throws, and the page goes without them.
    func productMetafields(handle: String, identifiers: [MetafieldIdentifier]) async throws -> [Metafield] {
        if identifiers.isEmpty { return [] }
        let product: MetafieldsLookup? = try await run(
            "ProductMetafields",
            ["handle": handle, "metafields": jsonValue(identifiers)],
            root: "product"
        )
        // asked-for metafields the product has no value for come back as null entries
        return (product?.metafields ?? []).compactMap { $0 }
    }

    /// The variant with exactly these options (option name to value), in full (stock, unit price, quantity rule and price
    /// breaks, bundle components, selling plans); nil when there is none.
    func variantBySelectedOptions(productHandle: String, options: [String: String]) async throws -> Variant? {
        let product: VariantLookup? = try await run(
            "VariantBySelectedOptions",
            ["handle": productHandle, "selectedOptions": selected(options)],
            root: "product"
        )
        return product?.variantBySelectedOptions
    }

    /// The catalog (Catalog): every product, or those matching `query` in Shopify's search syntax (`tag:sale`). `sortKey` is a
    /// ProductSortKeys value (BEST_SELLING, PRICE, CREATED_AT, ...).
    func products(query: String? = nil, sortKey: String? = nil, reverse: Bool = false, after: String? = nil, first: Int = 24) async throws -> Page<ProductCard> {
        try await run("Catalog", list(first, after, ["query": query, "sortKey": sortKey, "reverse": reverse]), root: "products")
    }

    /// The cards of products `ids` (Products), in no set order; ids that aren't products (any more) are left out. At most 250.
    func productsByIds(_ ids: [String]) async throws -> [ProductCard] {
        let nodes: [Node?] = try await run("Products", ["ids": ids], root: "nodes")
        return nodes.compactMap { $0?.productCard }
    }

    func recommendations(productId: String, intent: RecommendationIntent = .related) async throws -> [ProductCard] {
        let cards: [ProductCard]? = try await run(
            "ProductRecommendations",
            ["productId": productId, "intent": intent.rawValue],
            root: "productRecommendations"
        )
        return cards ?? []
    }

    /// Collection `handle` with a page of its products; nil when there is none. `filters` are `FilterValue.input`s;
    /// `sortKey` is a ProductCollectionSortKeys value (COLLECTION_DEFAULT, BEST_SELLING, PRICE, CREATED, ...).
    func collection(_ handle: String, filters: [String] = [], sortKey: String? = nil, reverse: Bool = false, after: String? = nil, first: Int = 24) async throws -> ProductCollection? {
        var variables = list(first, after, ["handle": handle, "sortKey": sortKey, "reverse": reverse])
        if !filters.isEmpty { variables["filters"] = productFilters(filters) }
        return try await run("Collection", variables, root: "collection")
    }

    func collections(after: String? = nil, first: Int = 24) async throws -> Page<CollectionCard> {
        try await run("Collections", list(first, after), root: "collections")
    }

    // MARK: Search

    /// A page of search results (`products` picks the products out), with the product filters they offer. Products only
    /// unless `types` (SearchType values: PRODUCT, PAGE, ARTICLE) asks for more. `filters` are `FilterValue.input`s;
    /// `sortKey` is RELEVANCE or PRICE.
    func search(_ query: String, filters: [String] = [], sortKey: String? = nil, reverse: Bool = false, types: [String] = [], after: String? = nil, first: Int = 24) async throws -> Page<Node> {
        var variables = list(first, after, ["query": query, "sortKey": sortKey, "reverse": reverse])
        if !filters.isEmpty { variables["filters"] = productFilters(filters) }
        if !types.isEmpty { variables["types"] = types }
        return try await run("Search", variables, root: "search")
    }

    /// Suggestions for a partly typed `query`: up to `limit` of each kind.
    func predictiveSearch(_ query: String, limit: Int = 8) async throws -> PredictiveSearch {
        let result: PredictiveSearch? = try await run("PredictiveSearch", ["query": query, "limit": limit], root: "predictiveSearch")
        return result ?? .empty
    }

    // MARK: Stores

    /// Where variant `variantId` can be picked up.
    func storeAvailability(variantId: String, first: Int = 24) async throws -> [StoreAvailability] {
        let variant: AvailabilityLookup? = try await run("StoreAvailability", ["variantId": variantId, "first": first], root: "node")
        return variant?.storeAvailability ?? []
    }

    func locations(after: String? = nil, first: Int = 24) async throws -> Page<Location> {
        try await run("Locations", list(first, after), root: "locations")
    }

    // MARK: Content

    func page(_ handle: String) async throws -> StorePage? {
        try await run("Page", ["handle": handle], root: "page")
    }

    func pages(after: String? = nil, first: Int = 24) async throws -> Page<StorePage> {
        try await run("Pages", list(first, after), root: "pages")
    }

    func blogs(after: String? = nil, first: Int = 24) async throws -> Page<Blog> {
        try await run("Blogs", list(first, after), root: "blogs")
    }

    /// Blog `handle` with a page of its articles; nil when there is none.
    func blog(_ handle: String, after: String? = nil, first: Int = 24) async throws -> Blog? {
        try await run("Blog", list(first, after, ["handle": handle]), root: "blog")
    }

    func article(blogHandle: String, articleHandle: String) async throws -> Article? {
        let blog: ArticleLookup? = try await run("Article", ["blogHandle": blogHandle, "articleHandle": articleHandle], root: "blog")
        return blog?.articleByHandle
    }

    /// Articles across blogs, or those matching `query`.
    func articles(query: String? = nil, after: String? = nil, first: Int = 24) async throws -> Page<Article> {
        try await run("Articles", list(first, after, ["query": query]), root: "articles")
    }

    func metaobject(type: String, handle: String) async throws -> Metaobject? {
        try await run("Metaobject", ["type": type, "handle": handle], root: "metaobject")
    }

    func metaobjects(type: String, after: String? = nil, first: Int = 24) async throws -> Page<Metaobject> {
        try await run("Metaobjects", list(first, after, ["type": type]), root: "metaobjects")
    }

    // MARK: Home

    /// The section metaobjects of `mobile_screen` `handle` (HomeScreen), in order; empty when there is no such screen.
    func homeScreen(_ handle: String = "home") async throws -> [Metaobject] {
        let screen: Screen? = try await run("HomeScreen", ["handle": handle], root: "metaobject")
        return (screen?.field?.references ?? []).compactMap { node -> Metaobject? in
            if case let .metaobject(section) = node { return section }
            return nil
        }
    }

    /// The `app_screen` metaobject `handle` (AppScreen: `home`, `product`, ..., or a custom page's handle): its title
    /// and template; else the one the app was built with (`builtInScreen`). Nil when there is neither.
    func appScreen(_ handle: String) async throws -> AppScreen? {
        if let screen: AppScreen = try await run("AppScreen", ["handle": handle], root: "metaobject") { return screen }
        return builtInScreen(handle).map { AppScreen(id: "", handle: handle, title: "", template: $0) }
    }

    /// The products and collections `ids` (SectionNodes), each collection with its first 24 products: everything a
    /// screen's sections show, in one call. Ids that aren't products or collections (any more) are left out; none asked
    /// for, no call.
    func sectionNodes(_ ids: [String]) async throws -> [Node] {
        if ids.isEmpty { return [] }
        let nodes: [Node?] = try await run("SectionNodes", ["ids": ids], root: "nodes")
        return nodes.compactMap { $0 }
    }

    /// The metafields `identifiers` that collection `handle` has a value for (CollectionMetafields), as
    /// `productMetafields`: none asked for, or no such collection, is empty.
    func collectionMetafields(handle: String, identifiers: [MetafieldIdentifier]) async throws -> [Metafield] {
        if identifiers.isEmpty { return [] }
        let collection: MetafieldsLookup? = try await run(
            "CollectionMetafields",
            ["handle": handle, "metafields": jsonValue(identifiers)],
            root: "collection"
        )
        return (collection?.metafields ?? []).compactMap { $0 }
    }

    /// The shop's metafields `identifiers` that have a value (ShopMetafields).
    func shopMetafields(identifiers: [MetafieldIdentifier]) async throws -> [Metafield] {
        if identifiers.isEmpty { return [] }
        let shop: MetafieldsLookup? = try await run("ShopMetafields", ["metafields": jsonValue(identifiers)], root: "shop")
        return (shop?.metafields ?? []).compactMap { $0 }
    }

    /// The store's first collections, each with its first products (FallbackHome): the home of a store without a screen.
    func fallbackHome() async throws -> [CollectionCard] {
        let collections: Nodes<CollectionCard> = try await run("FallbackHome", root: "collections")
        return collections.nodes
    }

    // MARK: Cart

    /// Cart `id`; nil when Shopify no longer has it (expired, or checked out).
    func cart(_ id: String) async throws -> Cart? {
        try await run("Cart", ["id": id], root: "cart")
    }

    func cartCreate(_ input: CartInput = CartInput()) async throws -> Cart {
        try await mutate("CartCreate", ["input": jsonValue(input)])
    }

    func addLines(cartId: String, lines: [CartLineInput]) async throws -> Cart {
        try await mutate("CartLinesAdd", ["cartId": cartId, "lines": jsonValue(lines)])
    }

    func updateLines(cartId: String, lines: [CartLineUpdateInput]) async throws -> Cart {
        try await mutate("CartLinesUpdate", ["cartId": cartId, "lines": jsonValue(lines)])
    }

    func removeLines(cartId: String, lineIds: [String]) async throws -> Cart {
        try await mutate("CartLinesRemove", ["cartId": cartId, "lineIds": lineIds])
    }

    func updateBuyerIdentity(cartId: String, buyerIdentity: CartBuyerIdentityInput) async throws -> Cart {
        try await mutate("CartBuyerIdentityUpdate", ["cartId": cartId, "buyerIdentity": jsonValue(buyerIdentity)])
    }

    /// Replaces the cart's discount codes; `[]` clears them.
    func updateDiscountCodes(cartId: String, codes: [String]) async throws -> Cart {
        try await mutate("CartDiscountCodesUpdate", ["cartId": cartId, "discountCodes": codes])
    }

    func addGiftCards(cartId: String, codes: [String]) async throws -> Cart {
        try await mutate("CartGiftCardCodesAdd", ["cartId": cartId, "giftCardCodes": codes])
    }

    /// `ids` are `AppliedGiftCard.id`s, not codes.
    func removeGiftCards(cartId: String, ids: [String]) async throws -> Cart {
        try await mutate("CartGiftCardCodesRemove", ["cartId": cartId, "appliedGiftCardIds": ids])
    }

    func updateNote(cartId: String, note: String) async throws -> Cart {
        try await mutate("CartNoteUpdate", ["cartId": cartId, "note": note])
    }

    func updateAttributes(cartId: String, attributes: [CartAttribute]) async throws -> Cart {
        try await mutate("CartAttributesUpdate", ["cartId": cartId, "attributes": jsonValue(attributes)])
    }

    func addDeliveryAddresses(cartId: String, addresses: [CartSelectableAddressInput]) async throws -> Cart {
        try await mutate("CartDeliveryAddressesAdd", ["cartId": cartId, "addresses": jsonValue(addresses)])
    }

    func updateDeliveryAddresses(cartId: String, addresses: [CartSelectableAddressUpdateInput]) async throws -> Cart {
        try await mutate("CartDeliveryAddressesUpdate", ["cartId": cartId, "addresses": jsonValue(addresses)])
    }

    func removeDeliveryAddresses(cartId: String, addressIds: [String]) async throws -> Cart {
        try await mutate("CartDeliveryAddressesRemove", ["cartId": cartId, "addressIds": addressIds])
    }

    /// One option per delivery group, from `Cart.deliveryGroups`.
    func selectDeliveryOptions(cartId: String, options: [CartSelectedDeliveryOptionInput]) async throws -> Cart {
        try await mutate("CartSelectedDeliveryOptionsUpdate", ["cartId": cartId, "selectedDeliveryOptions": jsonValue(options)])
    }

    // MARK: Plumbing

    /// Runs operation `name` in this context, for this buyer, and returns its `root` field.
    private func run<T: Decodable>(_ name: String, _ variables: [String: Any] = [:], root: String) async throws -> T {
        var variables = variables
        if let country = context.country { variables["country"] = country }
        if let language = context.language { variables["language"] = language }
        if let buyer = buyer { variables["buyer"] = try jsonValue(buyer) }
        return try await fetchField(transport, name, variables, root: root)
    }

    /// Runs cart mutation `name` and returns its cart, with the warnings that came with it. User errors are thrown with the
    /// cart that came back beside them; no cart and no errors is "The cart is unavailable".
    private func mutate(_ name: String, _ variables: [String: Any]) async throws -> Cart {
        let payload: CartPayload = try await run(name, variables, root: payloadField(name))
        var cart = payload.cart
        cart?.warnings = payload.warnings
        if !payload.userErrors.isEmpty { throw ArgonAPIError.userErrors(payload.userErrors, cart: cart) }
        guard let changed = cart else {
            throw ArgonAPIError.userErrors([UserError(message: "The cart is unavailable")], cart: nil)
        }
        return changed
    }

    /// A list operation's variables: `first`, `after` once paging, and `more` without its nil values.
    private func list(_ first: Int, _ after: String?, _ more: [String: Any?] = [:]) -> [String: Any] {
        var variables = more.compactMapValues { $0 }
        variables["first"] = first
        if let after = after { variables["after"] = after }
        return variables
    }

    /// SelectedOptionInputs, in a stable order.
    private func selected(_ options: [String: String]) -> [[String: String]] {
        options.sorted { $0.key < $1.key }.map { ["name": $0.key, "value": $0.value] }
    }

    /// ProductFilter inputs from `FilterValue.input` JSON strings; unreadable ones are skipped.
    private func productFilters(_ inputs: [String]) -> [Any] {
        inputs.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
    }

    private func forget() {
        changes += 1
        keptShop = nil
        keptLocalization = nil
        keptPolicies = nil
        keptMenus = [:]
    }
}

private struct CartPayload: Decodable {
    let cart: Cart?
    let userErrors: [UserError]
    let warnings: [CartWarning]
}

private struct VariantLookup: Decodable {
    let variantBySelectedOptions: Variant?
}

private struct ArticleLookup: Decodable {
    let articleByHandle: Article?
}

private struct MetafieldsLookup: Decodable {
    let metafields: [Metafield?]
}

/// A `node(id:)` that is a variant has its store availability; any other node has none.
private struct AvailabilityLookup: Decodable {
    let storeAvailability: [StoreAvailability]

    private enum CodingKeys: String, CodingKey {
        case storeAvailability
    }

    init(from decoder: Decoder) throws {
        storeAvailability = try decoder.container(keyedBy: CodingKeys.self).nodes(.storeAvailability)
    }
}

/// HomeScreen's `mobile_screen`: its `sections` field's references.
private struct Screen: Decodable {
    struct Field: Decodable {
        let references: [Node]

        private enum CodingKeys: String, CodingKey {
            case references
        }

        init(from decoder: Decoder) throws {
            references = try decoder.container(keyedBy: CodingKeys.self).nodes(.references)
        }
    }

    let field: Field?
}
