import Foundation

// Typed models of contract/fragments.graphql and the Storefront queries, decoded straight from responses (StorefrontAPI).
// Money amounts stay Shopify's decimal strings and dates ISO-8601 strings; formatting is the UI's job. Types the screens
// already used keep their names and fields: `available` is `availableForSale`, `price` the minimum variant price, `image` a
// card's featured image. Polymorphic results are enums read on `__typename`.

struct Money: Codable, Equatable, Sendable {
    let amount: String
    let currencyCode: String
}

struct Img: Decodable, Equatable, Sendable {
    let url: String
    let alt: String?
    let width: Int?
    let height: Int?

    private enum CodingKeys: String, CodingKey {
        case url
        case alt = "altText"
        case width
        case height
    }
}

/// One page of a list. Pass `endCursor` as `after` to get the next one while `hasNextPage`.
struct Page<T> {
    let items: [T]
    let endCursor: String?
    let hasNextPage: Bool
}

extension Page: Equatable where T: Equatable {}

extension Page: Sendable where T: Sendable {}

private enum PageKeys: String, CodingKey {
    case pageInfo
    case nodes
}

private struct PageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}

/// A connection: `{ pageInfo { hasNextPage endCursor } nodes }`.
extension Page: Decodable where T: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PageKeys.self)
        let info = try c.decode(PageInfo.self, forKey: .pageInfo)
        try self.init(items: c.decode([T].self, forKey: .nodes), endCursor: info.endCursor, hasNextPage: info.hasNextPage)
    }
}

struct SEO: Decodable, Equatable, Sendable {
    let title: String?
    let description: String?
}

// Shopify reports "no compare-at price" as null or 0.0; only a higher one is a real discount.
private func discounted(_ price: Money, _ compare: Money?) -> Money? {
    guard let compare = compare,
          let was = Decimal(string: compare.amount),
          let now = Decimal(string: price.amount),
          was > now else { return nil }
    return compare
}

private struct MinPrice: Decodable {
    let minVariantPrice: Money
}

/// `ProductCard` fragment.
struct ProductCard: Equatable, Sendable {
    let id: String
    let handle: String
    let title: String
    let available: Bool
    let image: Img?
    let price: Money
    /// Only when above `price`.
    let compareAt: Money?
}

extension ProductCard: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, handle, title, availableForSale, featuredImage, priceRange, compareAtPriceRange
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let price = try c.decode(MinPrice.self, forKey: .priceRange).minVariantPrice
        let compare = try c.decodeIfPresent(MinPrice.self, forKey: .compareAtPriceRange)?.minVariantPrice
        try self.init(
            id: c.decode(String.self, forKey: .id),
            handle: c.decode(String.self, forKey: .handle),
            title: c.decode(String.self, forKey: .title),
            available: c.decode(Bool.self, forKey: .availableForSale),
            image: c.decodeIfPresent(Img.self, forKey: .featuredImage),
            price: price,
            compareAt: discounted(price, compare)
        )
    }
}

/// `CollectionCard` fragment, with what some queries add to it.
struct CollectionCard: Equatable, Sendable {
    let id: String
    let handle: String
    let title: String
    let image: Img?
    /// Collections only.
    var description: String? = nil
    /// FallbackHome and the HomeScreen collection reference only.
    var products: [ProductCard] = []
}

extension CollectionCard: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, handle, title, image, description, products
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            handle: c.decode(String.self, forKey: .handle),
            title: c.decode(String.self, forKey: .title),
            image: c.decodeIfPresent(Img.self, forKey: .image),
            description: c.decodeIfPresent(String.self, forKey: .description),
            products: c.nodes(.products)
        )
    }
}

/// `Variant` fragment.
struct Variant: Equatable, Sendable {
    let id: String
    let title: String
    let available: Bool
    /// Option name to value: ["Size": "M", "Color": "Red"].
    let options: [String: String]
    let price: Money
    /// Only when above `price`.
    let compareAt: Money?
    let image: Img?
    var sku: String? = nil
}

extension Variant: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, title, availableForSale, selectedOptions, price, compareAtPrice, image, sku
    }

    private struct SelectedOption: Decodable {
        let name: String
        let value: String
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var options: [String: String] = [:]
        for option in try c.decode([SelectedOption].self, forKey: .selectedOptions) {
            options[option.name] = option.value
        }
        let price = try c.decode(Money.self, forKey: .price)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            title: c.decode(String.self, forKey: .title),
            available: c.decode(Bool.self, forKey: .availableForSale),
            options: options,
            price: price,
            compareAt: discounted(price, c.decodeIfPresent(Money.self, forKey: .compareAtPrice)),
            image: c.decodeIfPresent(Img.self, forKey: .image),
            sku: c.decodeIfPresent(String.self, forKey: .sku)
        )
    }
}

struct PriceRange: Decodable, Equatable, Sendable {
    let minVariantPrice: Money
    let maxVariantPrice: Money
}

/// `Media` fragment: the fields every media type has, and what its own type adds.
struct Media: Equatable, Sendable {
    let id: String
    let alt: String?
    let previewImage: Img?
    let content: Content

    enum Content: Equatable, Sendable {
        case image(Img?)
        case video([MediaSource])
        case externalVideo(host: String, embedUrl: String, originUrl: String)
        case model3d([MediaSource])
        /// A media type this app doesn't know (its `__typename`).
        case other(String)
    }
}

/// A video (`width`, `height`) or 3D model (`filesize`) file.
struct MediaSource: Decodable, Equatable, Sendable {
    let url: String
    let mimeType: String
    let format: String
    var width: Int? = nil
    var height: Int? = nil
    var filesize: Int? = nil
}

extension Media: Decodable {
    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case id, alt, previewImage, image, sources, host, embedUrl, originUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let content: Content
        switch try c.decode(String.self, forKey: .typename) {
        case "MediaImage":
            content = try .image(c.decodeIfPresent(Img.self, forKey: .image))
        case "Video":
            content = try .video(c.decode([MediaSource].self, forKey: .sources))
        case "ExternalVideo":
            content = try .externalVideo(
                host: c.decode(String.self, forKey: .host),
                embedUrl: c.decode(String.self, forKey: .embedUrl),
                originUrl: c.decode(String.self, forKey: .originUrl)
            )
        case "Model3d":
            content = try .model3d(c.decode([MediaSource].self, forKey: .sources))
        case let typename:
            content = .other(typename)
        }
        try self.init(
            id: c.decode(String.self, forKey: .id),
            alt: c.decodeIfPresent(String.self, forKey: .alt),
            previewImage: c.decodeIfPresent(Img.self, forKey: .previewImage),
            content: content
        )
    }
}

struct ProductOption: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let optionValues: [ProductOptionValue]
}

struct ProductOptionValue: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let swatch: Swatch?
    let firstSelectableVariant: Variant?
}

/// A colour (`#RRGGBB`) and/or image for an option value.
struct Swatch: Equatable, Sendable {
    let color: String?
    let image: Img?
}

extension Swatch: Decodable {
    private enum CodingKeys: String, CodingKey {
        case color, image
    }

    private struct Preview: Decodable {
        let previewImage: Img?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            color: c.decodeIfPresent(String.self, forKey: .color),
            image: c.decodeIfPresent(Preview.self, forKey: .image)?.previewImage
        )
    }
}

struct SellingPlanGroup: Equatable, Sendable {
    let name: String
    let appName: String?
    let options: [SellingPlanGroupOption]
    let sellingPlans: [SellingPlan]
}

struct SellingPlanGroupOption: Decodable, Equatable, Sendable {
    let name: String
    let values: [String]
}

struct SellingPlan: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let description: String?
    let recurringDeliveries: Bool
}

extension SellingPlanGroup: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, appName, options, sellingPlans
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: c.decode(String.self, forKey: .name),
            appName: c.decodeIfPresent(String.self, forKey: .appName),
            options: c.decode([SellingPlanGroupOption].self, forKey: .options),
            sellingPlans: c.nodes(.sellingPlans)
        )
    }
}

struct Metafield: Decodable, Equatable, Sendable {
    let namespace: String
    let key: String
    let type: String
    let value: String
}

/// A metafield to ask for: `custom.material` is namespace "custom", key "material".
struct MetafieldIdentifier: Encodable, Equatable, Sendable {
    let namespace: String
    let key: String
}

/// The Product query's product.
struct Product: Equatable, Sendable {
    let id: String
    let handle: String
    let title: String
    let vendor: String
    let productType: String
    let descriptionHtml: String
    let available: Bool
    let isGiftCard: Bool
    let requiresSellingPlan: Bool
    let encodedVariantExistence: String?
    let encodedVariantAvailability: String?
    let seo: SEO?
    let priceRange: PriceRange
    let media: [Media]
    let options: [ProductOption]
    let selectedOrFirstAvailableVariant: Variant?
    let adjacentVariants: [Variant]
    /// The first 250 variants.
    let variants: [Variant]
    let sellingPlanGroups: [SellingPlanGroup]
    /// The asked-for metafields this product has a value for.
    let metafields: [Metafield]

    /// The images among `media`, in order.
    var images: [Img] {
        media.compactMap { media in
            if case let .image(image) = media.content { return image }
            return nil
        }
    }
}

extension Product: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, handle, title, vendor, productType, descriptionHtml, availableForSale, isGiftCard, requiresSellingPlan
        case encodedVariantExistence, encodedVariantAvailability, seo, priceRange, media, options
        case selectedOrFirstAvailableVariant, adjacentVariants, variants, sellingPlanGroups, metafields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // asked-for metafields the product has no value for come back as null entries
        let metafields = try c.decodeIfPresent([Metafield?].self, forKey: .metafields) ?? []
        try self.init(
            id: c.decode(String.self, forKey: .id),
            handle: c.decode(String.self, forKey: .handle),
            title: c.decode(String.self, forKey: .title),
            vendor: c.decodeIfPresent(String.self, forKey: .vendor) ?? "",
            productType: c.decodeIfPresent(String.self, forKey: .productType) ?? "",
            descriptionHtml: c.decodeIfPresent(String.self, forKey: .descriptionHtml) ?? "",
            available: c.decode(Bool.self, forKey: .availableForSale),
            isGiftCard: c.decodeIfPresent(Bool.self, forKey: .isGiftCard) ?? false,
            requiresSellingPlan: c.decodeIfPresent(Bool.self, forKey: .requiresSellingPlan) ?? false,
            encodedVariantExistence: c.decodeIfPresent(String.self, forKey: .encodedVariantExistence),
            encodedVariantAvailability: c.decodeIfPresent(String.self, forKey: .encodedVariantAvailability),
            seo: c.decodeIfPresent(SEO.self, forKey: .seo),
            priceRange: c.decode(PriceRange.self, forKey: .priceRange),
            media: c.nodes(.media),
            options: c.decodeIfPresent([ProductOption].self, forKey: .options) ?? [],
            selectedOrFirstAvailableVariant: c.decodeIfPresent(Variant.self, forKey: .selectedOrFirstAvailableVariant),
            adjacentVariants: c.decodeIfPresent([Variant].self, forKey: .adjacentVariants) ?? [],
            variants: c.nodes(.variants),
            sellingPlanGroups: c.nodes(.sellingPlanGroups),
            metafields: metafields.compactMap { $0 }
        )
    }
}

enum RecommendationIntent: String, Sendable {
    case related = "RELATED"
    case complementary = "COMPLEMENTARY"
}

/// `Filter` fragment. `input` is the value to send back in `filters`: a ProductFilter as a JSON string.
struct FilterValue: Decodable, Equatable, Sendable {
    let id: String
    let label: String
    let count: Int
    let input: String
}

struct Filter: Decodable, Equatable, Sendable {
    let id: String
    let label: String
    let type: String
    let values: [FilterValue]
}

/// The Collection query's collection, with one page of its products and the filters they offer.
struct ProductCollection: Equatable, Sendable {
    let id: String
    let handle: String
    let title: String
    let description: String
    let seo: SEO?
    let image: Img?
    let filters: [Filter]
    let products: Page<ProductCard>
}

extension ProductCollection: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, handle, title, description, seo, image, products
    }

    private struct Filters: Decodable {
        let filters: [Filter]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            handle: c.decode(String.self, forKey: .handle),
            title: c.decode(String.self, forKey: .title),
            description: c.decodeIfPresent(String.self, forKey: .description) ?? "",
            seo: c.decodeIfPresent(SEO.self, forKey: .seo),
            image: c.decodeIfPresent(Img.self, forKey: .image),
            filters: c.decode(Filters.self, forKey: .products).filters,
            products: c.decode(Page<ProductCard>.self, forKey: .products)
        )
    }
}

/// An online store page. `body`, `bodySummary`, `seo` and `updatedAt` are nil where the query doesn't select them.
struct StorePage: Decodable, Equatable, Sendable {
    let id: String
    let handle: String
    let title: String
    var body: String? = nil
    var bodySummary: String? = nil
    var seo: SEO? = nil
    var updatedAt: String? = nil
}

/// `ArticleCard` fragment; `contentHtml`, `tags` and `seo` come with the Article query only.
struct Article: Equatable, Sendable {
    let id: String
    let handle: String
    let title: String
    let excerpt: String?
    let publishedAt: String
    let image: Img?
    let author: String?
    let blogHandle: String
    var contentHtml: String? = nil
    var tags: [String] = []
    var seo: SEO? = nil
}

extension Article: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, handle, title, excerpt, publishedAt, image, authorV2, blog, contentHtml, tags, seo
    }

    private struct Author: Decodable {
        let name: String
    }

    private struct BlogHandle: Decodable {
        let handle: String
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            handle: c.decode(String.self, forKey: .handle),
            title: c.decode(String.self, forKey: .title),
            excerpt: c.decodeIfPresent(String.self, forKey: .excerpt),
            publishedAt: c.decode(String.self, forKey: .publishedAt),
            image: c.decodeIfPresent(Img.self, forKey: .image),
            author: c.decodeIfPresent(Author.self, forKey: .authorV2)?.name,
            blogHandle: c.decode(BlogHandle.self, forKey: .blog).handle,
            contentHtml: c.decodeIfPresent(String.self, forKey: .contentHtml),
            tags: c.decodeIfPresent([String].self, forKey: .tags) ?? [],
            seo: c.decodeIfPresent(SEO.self, forKey: .seo)
        )
    }
}

/// A blog; `seo` and a page of `articles` come with the Blog query only.
struct Blog: Decodable, Equatable, Sendable {
    let id: String
    let handle: String
    let title: String
    var seo: SEO? = nil
    var articles: Page<Article>? = nil
}

struct Metaobject: Decodable, Equatable, Sendable {
    let id: String
    let type: String
    /// Not selected by HomeScreen.
    var handle: String? = nil
    var updatedAt: String? = nil
    let fields: [MetaobjectField]

    func field(_ key: String) -> MetaobjectField? { fields.first { $0.key == key } }
}

struct MetaobjectField: Equatable, Sendable {
    let key: String
    /// Not selected by HomeScreen.
    let type: String?
    let value: String?
    let reference: Node?
    /// The `references` list; empty when the field has none or the query doesn't select it.
    let references: [Node]
}

extension MetaobjectField: Decodable {
    private enum CodingKeys: String, CodingKey {
        case key, type, value, reference, references
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: c.decode(String.self, forKey: .key),
            type: c.decodeIfPresent(String.self, forKey: .type),
            value: c.decodeIfPresent(String.self, forKey: .value),
            reference: c.decodeIfPresent(Node.self, forKey: .reference),
            references: c.nodes(.references)
        )
    }
}

/// A result whose type is known only at runtime, read on its `__typename`: search results, `nodes(ids:)`, metaobject
/// references. A type the query selects no fields for, or one that came back without them (a broken reference), is `other`.
indirect enum Node: Equatable, Sendable {
    case product(ProductCard)
    case collection(CollectionCard)
    case page(StorePage)
    case article(Article)
    case metaobject(Metaobject)
    /// A MediaImage's image.
    case image(Img?)
    case other(String)

    var productCard: ProductCard? {
        if case let .product(card) = self { return card }
        return nil
    }

    var collectionCard: CollectionCard? {
        if case let .collection(card) = self { return card }
        return nil
    }
}

extension Node: Decodable {
    private enum Keys: String, CodingKey {
        case typename = "__typename"
        case id, image
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let typename = try c.decode(String.self, forKey: .typename)
        if typename == "MediaImage" {
            self = try c.contains(.image) ? .image(c.decodeIfPresent(Img.self, forKey: .image)) : .other(typename)
            return
        }
        guard c.contains(.id) else {
            self = .other(typename)
            return
        }
        switch typename {
        case "Product": self = try .product(ProductCard(from: decoder))
        case "Collection": self = try .collection(CollectionCard(from: decoder))
        case "Page": self = try .page(StorePage(from: decoder))
        case "Article": self = try .article(Article(from: decoder))
        case "Metaobject": self = try .metaobject(Metaobject(from: decoder))
        default: self = .other(typename)
        }
    }
}

/// The Search query's results: one page of matches (products unless other `types` were asked for) and the product filters.
struct SearchResults: Equatable, Sendable {
    let totalCount: Int
    let filters: [Filter]
    let results: Page<Node>

    var products: [ProductCard] { results.items.compactMap { $0.productCard } }
}

extension SearchResults: Decodable {
    private enum CodingKeys: String, CodingKey {
        case totalCount, productFilters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            totalCount: c.decode(Int.self, forKey: .totalCount),
            filters: c.decodeIfPresent([Filter].self, forKey: .productFilters) ?? [],
            results: Page<Node>(from: decoder)
        )
    }
}

/// Suggestions while typing; `empty` when Shopify has none (a null result).
struct PredictiveSearch: Decodable, Equatable, Sendable {
    struct Query: Decodable, Equatable, Sendable {
        let text: String
        let styledText: String
    }

    let queries: [Query]
    let products: [ProductCard]
    let collections: [ResourceLink]
    let pages: [ResourceLink]
    let articles: [ResourceLink]

    static let empty = PredictiveSearch(queries: [], products: [], collections: [], pages: [], articles: [])
}

/// A handle and title to link to; an article's link also needs its blog's handle.
struct ResourceLink: Equatable, Sendable {
    let handle: String
    let title: String
    var blogHandle: String? = nil
}

extension ResourceLink: Decodable {
    private enum CodingKeys: String, CodingKey {
        case handle, title, blog
    }

    private struct BlogHandle: Decodable {
        let handle: String
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            handle: c.decode(String.self, forKey: .handle),
            title: c.decode(String.self, forKey: .title),
            blogHandle: c.decodeIfPresent(BlogHandle.self, forKey: .blog)?.handle
        )
    }
}

struct Shop: Decodable, Equatable, Sendable {
    struct Domain: Decodable, Equatable, Sendable {
        let host: String
        let url: String
    }

    struct PaymentSettings: Decodable, Equatable, Sendable {
        let currencyCode: String
        let countryCode: String
        let acceptedCardBrands: [String]
        let supportedDigitalWallets: [String]
        let enabledPresentmentCurrencies: [String]
    }

    let id: String
    let name: String
    let description: String?
    let moneyFormat: String
    let shipsToCountries: [String]
    let primaryDomain: Domain
    let brand: ShopBrand?
    let paymentSettings: PaymentSettings
}

/// The shop's Brand settings. Colours are `#RRGGBB`.
struct ShopBrand: Equatable, Sendable {
    struct Color: Decodable, Equatable, Sendable {
        let background: String?
        let foreground: String?
    }

    let slogan: String?
    let shortDescription: String?
    let logo: Img?
    let squareLogo: Img?
    let coverImage: Img?
    let primaryColors: [Color]
    let secondaryColors: [Color]
}

extension ShopBrand: Decodable {
    private enum CodingKeys: String, CodingKey {
        case slogan, shortDescription, logo, squareLogo, coverImage, colors
    }

    private struct BrandImage: Decodable {
        let image: Img?
    }

    private struct Colors: Decodable {
        let primary: [Color]
        let secondary: [Color]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let colors = try c.decodeIfPresent(Colors.self, forKey: .colors)
        try self.init(
            slogan: c.decodeIfPresent(String.self, forKey: .slogan),
            shortDescription: c.decodeIfPresent(String.self, forKey: .shortDescription),
            logo: c.decodeIfPresent(BrandImage.self, forKey: .logo)?.image,
            squareLogo: c.decodeIfPresent(BrandImage.self, forKey: .squareLogo)?.image,
            coverImage: c.decodeIfPresent(BrandImage.self, forKey: .coverImage)?.image,
            primaryColors: colors?.primary ?? [],
            secondaryColors: colors?.secondary ?? []
        )
    }
}

/// Where the shop sells and in which languages. `country` and `language` are the ones in effect for the query's context.
struct Localization: Decodable, Equatable, Sendable {
    struct Country: Decodable, Equatable, Sendable {
        let isoCode: String
        let name: String
        let currency: Currency
        /// `country` only.
        var unitSystem: String? = nil
        /// `availableCountries` only.
        var defaultLanguage: Language? = nil
        /// `availableCountries` only.
        var availableLanguages: [Language]? = nil
    }

    struct Currency: Decodable, Equatable, Sendable {
        let isoCode: String
        var name: String? = nil
        let symbol: String
    }

    struct Language: Decodable, Equatable, Sendable {
        let isoCode: String
        var endonymName: String? = nil
        var name: String? = nil
    }

    let country: Country
    let language: Language
    let availableCountries: [Country]
    let availableLanguages: [Language]
}

/// The shop's policies; nil where the merchant hasn't written one.
struct ShopPolicies: Decodable, Equatable, Sendable {
    let privacyPolicy: ShopPolicy?
    let refundPolicy: ShopPolicy?
    let shippingPolicy: ShopPolicy?
    let termsOfService: ShopPolicy?
    let termsOfSale: ShopPolicy?
    let legalNotice: ShopPolicy?
    let contactInformation: ShopPolicy?
    let subscriptionPolicy: ShopPolicy?
}

/// `Policy` fragment. `body` is HTML. The subscription policy has no `id`.
struct ShopPolicy: Decodable, Equatable, Sendable {
    let id: String?
    let handle: String
    let title: String
    let body: String
    let url: String
}

/// A navigation menu, three levels deep (`main-menu` is the store's main menu).
struct StoreMenu: Decodable, Equatable, Sendable {
    let id: String
    let handle: String
    let title: String
    let items: [Item]

    /// `MenuItem` fragment. `url` is the item's link; `resource` what it links to, when that is a store resource.
    struct Item: Equatable, Sendable {
        let id: String
        let title: String
        let url: String?
        let type: String
        let resourceId: String?
        let resource: MenuResource?
        let items: [Item]
    }
}

extension StoreMenu.Item: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, title, url, type, resourceId, resource, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            title: c.decode(String.self, forKey: .title),
            url: c.decodeIfPresent(String.self, forKey: .url),
            type: c.decode(String.self, forKey: .type),
            resourceId: c.decodeIfPresent(String.self, forKey: .resourceId),
            resource: c.decodeIfPresent(MenuResource.self, forKey: .resource),
            // the third level doesn't select its own items
            items: c.decodeIfPresent([StoreMenu.Item].self, forKey: .items) ?? []
        )
    }
}

/// What a menu item links to, read on `__typename`.
enum MenuResource: Equatable, Sendable {
    case collection(handle: String)
    case product(handle: String)
    case page(handle: String)
    case blog(handle: String)
    case shopPolicy(handle: String)
    case article(handle: String, blogHandle: String)
    case metaobject(handle: String, type: String)
    case other(String)
}

extension MenuResource: Decodable {
    private enum Keys: String, CodingKey {
        case typename = "__typename"
        case handle, blog, type
    }

    private struct BlogHandle: Decodable {
        let handle: String
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let typename = try c.decode(String.self, forKey: .typename)
        func handle() throws -> String { try c.decode(String.self, forKey: .handle) }
        switch typename {
        case "Collection": self = try .collection(handle: handle())
        case "Product": self = try .product(handle: handle())
        case "Page": self = try .page(handle: handle())
        case "Blog": self = try .blog(handle: handle())
        case "ShopPolicy": self = try .shopPolicy(handle: handle())
        case "Article": self = try .article(handle: handle(), blogHandle: c.decode(BlogHandle.self, forKey: .blog).handle)
        case "Metaobject": self = try .metaobject(handle: handle(), type: c.decode(String.self, forKey: .type))
        default: self = .other(typename)
        }
    }
}

struct Location: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let address: LocationAddress
}

/// `LocationAddress` fragment. `formatted` is the address as display lines.
struct LocationAddress: Decodable, Equatable, Sendable {
    let address1: String?
    let address2: String?
    let city: String?
    let province: String?
    let provinceCode: String?
    let zip: String?
    let country: String?
    let countryCode: String?
    let phone: String?
    let formatted: [String]
    let latitude: Double?
    let longitude: Double?
}

/// Whether a variant can be picked up at `location`.
struct StoreAvailability: Decodable, Equatable, Sendable {
    let available: Bool
    let pickUpTime: String
    let quantityAvailable: Int
    let location: Location
}

// MARK: - App types the screens build from the models above

/// `hosts` is ordered: SHOP_DOMAIN first (relative links open against it), then the primary domain.
struct Brand: Equatable {
    let name: String
    let logo: Img?
    let cover: Img?
    let accent: String?
    let hosts: [String]
}

extension Brand {
    /// `configDomain` is SHOP_DOMAIN; together with the primary domain it decides which links stay in the app.
    init(shop: Shop, configDomain: String) {
        var hosts = [configDomain]
        if !hosts.contains(shop.primaryDomain.host) { hosts.append(shop.primaryDomain.host) }
        self.init(
            name: shop.name,
            logo: shop.brand?.logo,
            cover: shop.brand?.coverImage,
            accent: shop.brand?.primaryColors.first?.background,
            hosts: hosts
        )
    }
}

struct MenuItem: Equatable {
    let title: String
    let route: Route
    let children: [MenuItem]
}

// Inside this module `Section` is this type; SwiftUI's container is `SwiftUI.Section`.
enum Section: Equatable {
    case banner(style: String, image: Img?, heading: String?, text: String?, buttonLabel: String?, link: Route?)
    case products(heading: String?, style: String, items: [ProductCard])
    case collections(heading: String?, items: [CollectionCard])
}

enum Route: Hashable {
    case product(String)
    case collection(String)
    case search(String)
    case web(String)
}
