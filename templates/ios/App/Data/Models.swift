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

/// One page of a list. Pass `endCursor` as `after` to get the next one while `hasNextPage`. `filters` are the facets a
/// collection's products or search results offer (empty for other lists).
struct Page<T> {
    let items: [T]
    let endCursor: String?
    let hasNextPage: Bool
    var filters: [Filter] = []
}

extension Page: Equatable where T: Equatable {}

extension Page: Sendable where T: Sendable {}

extension Page where T == Node {
    /// The products among the results.
    var products: [ProductCard] { items.compactMap { $0.productCard } }
}

private enum PageKeys: String, CodingKey {
    case pageInfo, nodes, filters, productFilters
}

private struct PageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}

/// A connection: `{ pageInfo { hasNextPage endCursor } nodes }`, with `filters` (collection products) or `productFilters`
/// (search) when it has them.
extension Page: Decodable where T: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PageKeys.self)
        let info = try c.decode(PageInfo.self, forKey: .pageInfo)
        let filters = try c.decodeIfPresent([Filter].self, forKey: .filters) ?? c.decodeIfPresent([Filter].self, forKey: .productFilters)
        try self.init(
            items: c.decode([T].self, forKey: .nodes),
            endCursor: info.endCursor,
            hasNextPage: info.hasNextPage,
            filters: filters ?? []
        )
    }
}

struct SEO: Decodable, Equatable, Sendable {
    let title: String?
    let description: String?
}

/// Whether amount `a` is more than amount `b` (false when either isn't a number).
private func above(_ a: Money, _ b: Money) -> Bool {
    guard let high = Decimal(string: a.amount), let low = Decimal(string: b.amount) else { return false }
    return high > low
}

// Shopify reports "no compare-at price" as null or 0.0; only a higher one is a real discount.
private func discounted(_ price: Money, _ compare: Money?) -> Money? {
    compare.flatMap { above($0, price) ? $0 : nil }
}

private struct MinPrice: Decodable {
    let minVariantPrice: Money
    var maxVariantPrice: Money? = nil
}

/// A `metafield(namespace:key:)` read for its value.
private struct MetafieldValue: Decodable {
    let value: String?
}

/// How many of a variant one order can hold: at least `minimum`, at most `maximum` (nil: no limit), in multiples of
/// `increment`. mock.shop sends 0 where a store sends 1: read `min` and `step`.
struct QuantityRule: Decodable, Equatable, Sendable {
    let minimum: Int
    var maximum: Int? = nil
    let increment: Int

    /// The smallest quantity, never under 1.
    var min: Int { Swift.max(1, minimum) }

    /// What a plus or a minus changes the quantity by, never under 1.
    var step: Int { Swift.max(1, increment) }
}

/// The `rating` and `rating_count` metafields of the `reviews` namespace (the standard ones; Judge.me fills them).
enum Ratings {
    /// A `rating` metafield's stars, 0...5: its value is JSON `{"value":"4.6","scale_min":"1.0","scale_max":"5.0"}` (brought to
    /// a scale of 5 by `scale_max`) or a plain number. Nil when unreadable.
    static func parse(_ value: String?) -> Double? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let plain = Double(text) { return stars(plain, of: 5) }
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let rating = number(object["value"]) else { return nil }
        return stars(rating, of: number(object["scale_max"]) ?? 5)
    }

    /// A `rating_count` metafield's whole number; nil when unreadable.
    static func count(_ value: String?) -> Int? {
        value.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    // the JSON's numbers come as strings ("4.6"), or as numbers from an app that writes them so
    private static func number(_ value: Any?) -> Double? {
        if let text = value as? String { return Double(text) }
        return (value as? NSNumber)?.doubleValue
    }

    private static func stars(_ rating: Double, of top: Double) -> Double? {
        guard rating.isFinite, top.isFinite, top > 0 else { return nil }
        // a rating already out of 5 is kept as written (4.6 stays 4.6, with no rounding on the way)
        return Swift.min(Swift.max(top == 5 ? rating : rating * 5 / top, 0), 5)
    }
}

/// A product card's `firstVariant` (`selectedOrFirstAvailableVariant`): what a quick add puts in the cart.
struct CardVariant: Equatable, Sendable {
    let id: String
    var sku: String? = nil
    let available: Bool
    var quantityRule: QuantityRule? = nil
}

extension CardVariant: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, sku, availableForSale, quantityRule
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            sku: c.decodeIfPresent(String.self, forKey: .sku),
            available: c.decode(Bool.self, forKey: .availableForSale),
            quantityRule: c.decodeIfPresent(QuantityRule.self, forKey: .quantityRule)
        )
    }
}

/// Whether an option (or filter) named `name` chooses a colour: "Colour", "Color" or "Shade", in any case.
func isColorName(_ name: String) -> Bool {
    ["colour", "color", "shade"].contains(name.trimmingCharacters(in: .whitespaces).lowercased())
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
    var vendor: String = ""
    /// The dearest variant's price.
    var maxPrice: Money? = nil
    /// The first three options, with their values' swatches (no ids, no variants).
    var options: [ProductOption] = []
    var firstVariant: CardVariant? = nil
    /// Stars out of 5 and the number of reviews, when the store has them (`Ratings`).
    var rating: Double? = nil
    var ratingCount: Int? = nil

    /// Variants at different prices: `price` is then "From".
    var hasPriceRange: Bool { maxPrice.map { above($0, price) } ?? false }

    /// The values of the first colour option (`isColorName`); empty without one.
    var colors: [ProductOptionValue] { options.first { isColorName($0.name) }?.optionValues ?? [] }

    /// The variant an "Add" button adds without opening the product: the first one, when it is available and no option
    /// offers a choice. Nil otherwise.
    var quickAddVariantId: String? {
        guard let variant = firstVariant, variant.available, options.allSatisfy({ $0.optionValues.count == 1 }) else { return nil }
        return variant.id
    }
}

extension ProductCard: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, handle, title, vendor, availableForSale, featuredImage, priceRange, compareAtPriceRange, options, firstVariant
        case rating, ratingCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let range = try c.decode(MinPrice.self, forKey: .priceRange)
        let compare = try c.decodeIfPresent(MinPrice.self, forKey: .compareAtPriceRange)?.minVariantPrice
        try self.init(
            id: c.decode(String.self, forKey: .id),
            handle: c.decode(String.self, forKey: .handle),
            title: c.decode(String.self, forKey: .title),
            available: c.decode(Bool.self, forKey: .availableForSale),
            image: c.decodeIfPresent(Img.self, forKey: .featuredImage),
            price: range.minVariantPrice,
            compareAt: discounted(range.minVariantPrice, compare),
            vendor: c.decodeIfPresent(String.self, forKey: .vendor) ?? "",
            maxPrice: range.maxVariantPrice,
            options: c.decodeIfPresent([ProductOption].self, forKey: .options) ?? [],
            firstVariant: c.decodeIfPresent(CardVariant.self, forKey: .firstVariant),
            rating: Ratings.parse(c.decodeIfPresent(MetafieldValue.self, forKey: .rating)?.value),
            ratingCount: Ratings.count(c.decodeIfPresent(MetafieldValue.self, forKey: .ratingCount)?.value)
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

/// `Variant` fragment. Everything from `barcode` on comes with `variantBySelectedOptions` only (the selected variant in
/// full); it is nil, false or empty on the variants of a product's own list.
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
    var barcode: String? = nil
    /// Nil when the store's token can't read inventory (`unauthenticated_read_product_inventory`).
    var quantityAvailable: Int? = nil
    /// Sold while out of stock: it ships when it is back.
    var currentlyNotInStock = false
    /// The price of one `unitPriceMeasurement` reference unit ("$6.00 / item").
    var unitPrice: Money? = nil
    var unitPriceMeasurement: UnitPriceMeasurement? = nil
    var quantityRule: QuantityRule? = nil
    /// Volume pricing: the price of each from `minimumQuantity` up, lowest quantity first.
    var quantityPriceBreaks: [QuantityPriceBreak] = []
    /// A bundle: it is bought as its `components`.
    var requiresComponents = false
    var components: [VariantComponent] = []
    /// The bundles this variant is a part of.
    var groupedBy: [ComponentVariant] = []
    var sellingPlanAllocations: [SellingPlanAllocation] = []
}

extension Variant: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, title, availableForSale, selectedOptions, price, compareAtPrice, image, sku
        case barcode, quantityAvailable, currentlyNotInStock, unitPrice, unitPriceMeasurement, quantityRule
        case quantityPriceBreaks, requiresComponents, components, groupedBy, sellingPlanAllocations
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
            sku: c.decodeIfPresent(String.self, forKey: .sku),
            barcode: c.decodeIfPresent(String.self, forKey: .barcode),
            quantityAvailable: c.decodeIfPresent(Int.self, forKey: .quantityAvailable),
            currentlyNotInStock: c.decodeIfPresent(Bool.self, forKey: .currentlyNotInStock) ?? false,
            unitPrice: c.decodeIfPresent(Money.self, forKey: .unitPrice),
            unitPriceMeasurement: c.decodeIfPresent(UnitPriceMeasurement.self, forKey: .unitPriceMeasurement),
            quantityRule: c.decodeIfPresent(QuantityRule.self, forKey: .quantityRule),
            quantityPriceBreaks: c.nodes(.quantityPriceBreaks),
            requiresComponents: c.decodeIfPresent(Bool.self, forKey: .requiresComponents) ?? false,
            components: c.nodes(.components),
            groupedBy: c.nodes(.groupedBy),
            sellingPlanAllocations: c.nodes(.sellingPlanAllocations)
        )
    }
}

/// What a unit price is for: `referenceValue` `referenceUnit`s (1 ITEM, 100 G), of the `quantityValue` `quantityUnit`s the
/// variant holds. Units are Shopify's enum values (ITEM, G, KG, ML, L, ...).
struct UnitPriceMeasurement: Decodable, Equatable, Sendable {
    let measuredType: String?
    let quantityUnit: String?
    let quantityValue: Double
    let referenceUnit: String?
    let referenceValue: Int
}

/// From `minimumQuantity` up, each one costs `price`.
struct QuantityPriceBreak: Decodable, Equatable, Sendable {
    let minimumQuantity: Int
    let price: Money
}

/// A product's handle and title, where a variant is shown apart from its product (a bundle's part, a cart line); its
/// `id` too where the document selects it (a cart line).
struct ProductRef: Decodable, Equatable, Sendable {
    let handle: String
    let title: String
    var id: String? = nil
}

/// A variant named with its product: a part of a bundle, or the bundle a variant is part of. `image` is the variant's,
/// else its product's.
struct ComponentVariant: Equatable, Sendable {
    let id: String
    let title: String
    let image: Img?
    let price: Money
    let product: ProductRef
}

extension ComponentVariant: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, title, image, price, product
    }

    private struct ProductImage: Decodable {
        let featuredImage: Img?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let image = try c.decodeIfPresent(Img.self, forKey: .image)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            title: c.decode(String.self, forKey: .title),
            image: image ?? c.decode(ProductImage.self, forKey: .product).featuredImage,
            price: c.decode(Money.self, forKey: .price),
            product: c.decode(ProductRef.self, forKey: .product)
        )
    }
}

/// `quantity` of `variant` in a bundle.
struct VariantComponent: Equatable, Sendable {
    let quantity: Int
    let variant: ComponentVariant
}

extension VariantComponent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case quantity, productVariant
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(quantity: c.decode(Int.self, forKey: .quantity), variant: c.decode(ComponentVariant.self, forKey: .productVariant))
    }
}

/// A subscription or other purchase option (its `id` goes in a cart line's `sellingPlanId`).
struct SellingPlan: Decodable, Equatable, Sendable {
    let id: String
    let name: String
}

/// What a variant costs on `sellingPlan`: the first of `priceAdjustments` applies at purchase (a second, when there is one,
/// after a number of orders).
struct SellingPlanAllocation: Decodable, Equatable, Sendable {
    struct PriceAdjustment: Decodable, Equatable, Sendable {
        let price: Money
        let compareAtPrice: Money?
        let perDeliveryPrice: Money?
    }

    let sellingPlan: SellingPlan
    let priceAdjustments: [PriceAdjustment]
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

/// A product's option and its values. On a product card `id` and `firstSelectableVariant` are nil: its options carry
/// names and swatches only.
struct ProductOption: Decodable, Equatable, Sendable {
    var id: String? = nil
    let name: String
    let optionValues: [ProductOptionValue]
}

struct ProductOptionValue: Decodable, Equatable, Sendable {
    var id: String? = nil
    let name: String
    var swatch: Swatch? = nil
    var firstSelectableVariant: Variant? = nil
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

/// The Product query's product. Its metafields come apart (`StorefrontAPI.productMetafields`): a token that can't read
/// them would lose the whole product. Its selling plans come with the selected variant (`Variant.sellingPlanAllocations`).
struct Product: Equatable, Sendable {
    let id: String
    let handle: String
    let title: String
    let vendor: String
    let productType: String
    let descriptionHtml: String
    let available: Bool
    let isGiftCard: Bool
    /// Sold on a selling plan only: no one-time purchase.
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
    var tags: [String] = []
    /// The product's page on the online store, to share; nil when it isn't published there.
    var onlineStoreUrl: String? = nil
    /// Stars out of 5 and the number of reviews, when the store has them (`Ratings`).
    var rating: Double? = nil
    var ratingCount: Int? = nil

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
        case selectedOrFirstAvailableVariant, adjacentVariants, variants, tags, onlineStoreUrl, rating, ratingCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
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
            tags: c.decodeIfPresent([String].self, forKey: .tags) ?? [],
            onlineStoreUrl: c.decodeIfPresent(String.self, forKey: .onlineStoreUrl),
            rating: Ratings.parse(c.decodeIfPresent(MetafieldValue.self, forKey: .rating)?.value),
            ratingCount: Ratings.count(c.decodeIfPresent(MetafieldValue.self, forKey: .ratingCount)?.value)
        )
    }
}

enum RecommendationIntent: String, Sendable {
    case related = "RELATED"
    case complementary = "COMPLEMENTARY"
}

/// `Filter` fragment. `input` is the value to send back in `filters`: a ProductFilter as a JSON string. `swatch` is the
/// colour or image the store gave the value.
struct FilterValue: Decodable, Equatable, Sendable {
    let id: String
    let label: String
    let count: Int
    let input: String
    var swatch: Swatch? = nil
}

/// `type` is LIST, PRICE_RANGE or BOOLEAN; `presentation` how the store shows it: IMAGE, SWATCH or TEXT.
struct Filter: Decodable, Equatable, Sendable {
    let id: String
    let label: String
    let type: String
    let values: [FilterValue]
    var presentation: String? = nil
}

/// The Collection query's collection, with one page of its products (and the filters they offer, `products.filters`).
struct ProductCollection: Decodable, Equatable, Sendable {
    let id: String
    let handle: String
    let title: String
    let description: String
    let seo: SEO?
    let image: Img?
    let products: Page<ProductCard>
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

/// An `app_screen` metaobject (AppScreen): a screen's title and its template, the JSON text `ScreenTemplate.decode`
/// reads.
struct AppScreen: Equatable, Sendable {
    let id: String
    let handle: String
    let title: String
    let template: String?
    var updatedAt: String? = nil
}

extension AppScreen: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, handle, updatedAt, title, template
    }

    private struct Value: Decodable {
        let value: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            handle: c.decode(String.self, forKey: .handle),
            title: c.decodeIfPresent(Value.self, forKey: .title)?.value ?? "",
            template: c.decodeIfPresent(Value.self, forKey: .template)?.value,
            updatedAt: c.decodeIfPresent(String.self, forKey: .updatedAt)
        )
    }
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

    /// The policies the shop has, in the order a list shows them.
    var all: [ShopPolicy] {
        [privacyPolicy, termsOfService, refundPolicy, shippingPolicy, termsOfSale, legalNotice, contactInformation, subscriptionPolicy]
            .compactMap { $0 }
    }

    /// The policy with `handle` (`privacy-policy`, `terms-of-service`, `refund-policy`, `shipping-policy`, ...).
    func policy(_ handle: String) -> ShopPolicy? { all.first { $0.handle == handle } }
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

// MARK: - B2B

struct CompanyLocation: Decodable, Equatable, Sendable {
    let id: String
    let name: String
}

/// A company that buys from the shop. `locations` come with the customer's company contacts only.
struct Company: Equatable, Sendable {
    let id: String
    let name: String
    var locations: [CompanyLocation] = []
}

extension Company: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, locations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(String.self, forKey: .id), name: c.decode(String.self, forKey: .name), locations: c.nodes(.locations))
    }
}

/// The company, and its location, a cart or an order is for.
struct PurchasingCompany: Decodable, Equatable, Sendable {
    let company: Company
    let location: CompanyLocation
}

// MARK: - App types the screens build from the models above

/// `hosts` is ordered: SHOP_DOMAIN first (relative links open against it), then the primary domain. `shortDescription`
/// and `slogan`: the brand's own words for itself (Shopify admin, Settings > Brand), nil when unset.
struct Brand: Equatable {
    let name: String
    let logo: Img?
    let cover: Img?
    let accent: String?
    let hosts: [String]
    var shortDescription: String? = nil
    var slogan: String? = nil
}

extension Brand {
    /// `configDomain` is SHOP_DOMAIN; together with the primary domain it decides which links stay in the app. `accent`
    /// (the merchant's settings) replaces the shop's brand colour.
    init(shop: Shop, configDomain: String, accent: String? = nil) {
        var hosts = [configDomain]
        if !hosts.contains(shop.primaryDomain.host) { hosts.append(shop.primaryDomain.host) }
        self.init(
            name: shop.name,
            logo: shop.brand?.logo,
            cover: shop.brand?.coverImage,
            accent: accent ?? shop.brand?.primaryColors.first?.background,
            hosts: hosts,
            shortDescription: shop.brand?.shortDescription,
            slogan: shop.brand?.slogan
        )
    }
}

/// One page of the first-launch welcome: a full-screen `image` (a URL) with a `heading` and a line of `text` over it;
/// `video` (an mp4 or HLS URL) plays muted on a loop over the image; `button`: the page's button, nil for Next / Get started.
struct OnboardingPage: Equatable {
    let image: String?
    let heading: String
    let text: String
    var video: String? = nil
    var button: String? = nil
}

/// What the `onboarding` screen says about the welcome: `off`, or its own `pages`.
enum Welcome: Equatable {
    case off
    case pages([OnboardingPage])
}

enum Onboarding {
    /// The three welcome pages, over `template`'s three stock banners: the shop in its own words (its brand's short
    /// description, else its slogan, else a line with its name), then what the app is good for. A non-empty heading or
    /// text in `words` (the merchant's settings, page by page) replaces that page's own.
    static func pages(
        brand: Brand,
        template: HomeTemplate,
        words: [RemoteSettings.Page] = [],
        image: (HomeTemplate, Int) -> String? = StockImages.url
    ) -> [OnboardingPage] {
        let own = [brand.shortDescription, brand.slogan]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return [
            ("Welcome to \(brand.name)", own ?? "Everything from \(brand.name), in one app."),
            ("Find it fast", "Search, filter and save what you love."),
            ("Checkout in a few taps", "Track your orders and returns from your account."),
        ].enumerated().map { index, own in
            let set = index < words.count ? words[index] : RemoteSettings.Page()
            return OnboardingPage(image: image(template, index + 1), heading: nonEmpty(set.heading) ?? own.0, text: nonEmpty(set.text) ?? own.1)
        }
    }

    /// The welcome in the `onboarding` screen's `json` (its template): its `onboarding` section's pages, a page without a
    /// picture over `template`'s stock picture for its place; `.off` when the section is hidden or not `enabled`. Nil
    /// when there is no such section, or it has no pages: the app's own welcome then.
    static func fromScreen(
        _ json: String?,
        template: HomeTemplate,
        image: (HomeTemplate, Int) -> String? = StockImages.url
    ) -> Welcome? {
        guard let json, let root = JSONValue(json: json)?.object,
              let section = (root["sections"]?.array ?? []).compactMap(\.object).first(where: { $0["type"]?.string == "onboarding" })
        else { return nil }
        let settings = SectionSettings(section["settings"]?.object ?? [:])
        if section["hidden"]?.bool == true || !settings.boolean("enabled", true) { return .off }
        let pages = (section["blocks"]?.array ?? []).compactMap(\.object).filter { $0["type"]?.string == "page" }
            .enumerated().map { index, block in
                let page = SectionSettings(block["settings"]?.object ?? [:])
                return OnboardingPage(
                    image: page.image("image")?.url ?? image(template, index % 3 + 1),
                    heading: nonEmpty(page.text("heading")) ?? "",
                    text: nonEmpty(page.text("text")) ?? "",
                    video: nonEmpty(page.text("video")).flatMap { $0.lowercased().hasPrefix("https://") ? $0 : nil },
                    button: nonEmpty(page.text("button_label"))
                )
            }
        return pages.isEmpty ? nil : .pages(pages)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

/// Where a tap leads: a pushed screen, or a web page (`web`, in the in-app browser).
enum Route: Hashable {
    case product(String)
    case collection(String)
    case search(String)
    /// A shop policy's page by its handle (`shipping-policy`, `refund-policy`, ...): the route `policy/<handle>`.
    case policy(String)
    /// An online store page, drawn in the app (`page/<handle>`).
    case page(String)
    /// A custom page of the store's own, the `app_screen` metaobject with this handle (`screen/<handle>`).
    case screen(String)
    /// A switch to the tab with this id: `home`, `cart`, `account` or `wishlist` (`AppTab`'s raw values).
    case tab(String)
    case web(String)
}
