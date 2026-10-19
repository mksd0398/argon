import Foundation

// Screens v2 (docs/superpowers/specs/2026-10-19-screens-v2-design.md): every screen can be an `app_screen` metaobject
// whose `template` is JSON, a list of sections. This file reads a template, leniently: decoding never fails a screen,
// and a setting that is missing, of the wrong type or out of range is its default, value by value. The same rules on
// Android (Screens.kt).

/// A JSON value as JSONSerialization reads it, typed: a template's settings, and every value Liquid works with (an
/// integer and a number with a decimal point stay apart, as Liquid keeps them).
enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// A JSONSerialization result (or any plain Swift value of the same kinds) as a value; anything else is null.
    init(any value: Any?) {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                let double = number.doubleValue
                self = .double(double)
            } else {
                self = .int(number.intValue)
            }
        case let text as String: self = .string(text)
        case let list as [Any]: self = .array(list.map { JSONValue(any: $0) })
        case let map as [String: Any]: self = .object(map.mapValues { JSONValue(any: $0) })
        case let value as JSONValue: self = value
        default: self = .null
        }
    }

    /// `text` parsed as JSON (a bare string, number or boolean too); nil when it isn't JSON.
    init?(json text: String) {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) else { return nil }
        self.init(any: parsed)
    }

    var string: String? {
        if case let .string(text) = self { return text }
        return nil
    }

    var object: [String: JSONValue]? {
        if case let .object(map) = self { return map }
        return nil
    }

    var array: [JSONValue]? {
        if case let .array(list) = self { return list }
        return nil
    }

    var bool: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    /// An integer or a number.
    var number: Double? {
        switch self {
        case let .int(value): return Double(value)
        case let .double(value): return value
        default: return nil
        }
    }

    subscript(key: String) -> JSONValue? { object?[key] }
}

/// Any JSON, from a Decodable container (RemoteSettings' app shell parts).
extension JSONValue: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Int.self) {
            self = .int(value)
        } else if let value = try? c.decode(Double.self) {
            self = .double(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }
}

/// A section's (or block's) settings, read by type. Each reader gives the setting's default for a missing value, a value
/// of the wrong type, or one outside the type's rules.
struct SectionSettings: Equatable, Sendable {
    let values: [String: JSONValue]

    init(_ values: [String: JSONValue] = [:]) {
        self.values = values
    }

    /// `text`, `richtext`, `html`: the string, which may hold Liquid; nil when missing or not a string.
    func text(_ key: String) -> String? { values[key]?.string }

    /// `image`: `{ url, alt, width, height }` with an https `url`.
    func image(_ key: String) -> Img? {
        guard let map = values[key]?.object, let url = map["url"]?.string, url.lowercased().hasPrefix("https://") else { return nil }
        let width = map["width"]?.number.flatMap { boundedInt($0, 0...100_000) }
        let height = map["height"]?.number.flatMap { boundedInt($0, 0...100_000) }
        return Img(url: url, alt: map["alt"]?.string, width: width.flatMap { $0 > 0 ? $0 : nil }, height: height.flatMap { $0 > 0 ? $0 : nil })
    }

    /// `link`: the string as written (`Links.resolve` reads it); nil when blank.
    func link(_ key: String) -> String? {
        guard let text = values[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// `product`, `collection`: a GID of `kind` ("Product", "Collection").
    func gid(_ key: String, _ kind: String) -> String? {
        values[key]?.string.flatMap { isGid($0, kind) ? $0 : nil }
    }

    /// `products`, `collections`: the GIDs of `kind` in the list, each once, up to 24; others are skipped.
    func gids(_ key: String, _ kind: String) -> [String] {
        var seen: Set<String> = []
        let ids = (values[key]?.array ?? []).compactMap { $0.string }.filter { isGid($0, kind) && seen.insert($0).inserted }
        return Array(ids.prefix(24))
    }

    /// `number`: clamped to `range`; `fallback` when missing or not a number.
    func number(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        guard let value = values[key]?.number, value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    func boolean(_ key: String, _ fallback: Bool) -> Bool { values[key]?.bool ?? fallback }

    /// `color`: `#RRGGBB`, upper-cased.
    func color(_ key: String, _ fallback: String) -> String { hex(key) ?? fallback }

    /// `color` without a default: `#RRGGBB`, upper-cased; nil when missing or not a colour.
    func hex(_ key: String) -> String? {
        guard let hex = values[key]?.string, hex.count == 7, hex.first == "#",
              hex.dropFirst().allSatisfy({ $0.isHexDigit }) else { return nil }
        return hex.uppercased()
    }

    /// `choice`: one of `choices`, else `fallback`.
    func choice(_ key: String, _ choices: [String], _ fallback: String) -> String {
        guard let value = values[key]?.string, choices.contains(value) else { return fallback }
        return value
    }

    /// `datetime`: an ISO 8601 date and time.
    func datetime(_ key: String) -> Date? { values[key]?.string.flatMap(parseISODate) }
}

/// `number` clamped to `range`, as an Int; nil when it isn't finite.
func boundedInt(_ number: Double, _ range: ClosedRange<Int>) -> Int? {
    guard number.isFinite else { return nil }
    return Int(min(max(number, Double(range.lowerBound)), Double(range.upperBound)))
}

/// `text` as `gid://shopify/<kind>/<number>`.
func isGid(_ text: String, _ kind: String) -> Bool {
    let prefix = "gid://shopify/\(kind)/"
    guard text.hasPrefix(prefix) else { return false }
    let tail = text.dropFirst(prefix.count)
    return !tail.isEmpty && tail.allSatisfy { $0.isASCII && $0.isNumber }
}

/// An ISO 8601 date and time (with or without fractions of a second), or a date alone (midnight UTC).
func parseISODate(_ text: String) -> Date? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withFullDate]
    return formatter.date(from: value)
}

/// A block of a section: a slideshow's slide, a FAQ's question, a feature, an image grid's tile.
struct SectionBlock: Equatable, Sendable {
    let id: String
    let type: String
    let settings: SectionSettings
}

/// One section of a template. `type` is one of `ScreenSection.types` (others are dropped as the template is read).
struct ScreenSection: Equatable, Sendable {
    let id: String
    let type: String
    var settings = SectionSettings()
    var blocks: [SectionBlock] = []
    /// Where it shows; nil: both platforms.
    var platforms: [String]? = nil
    var hidden = false
    var track: String? = nil

    /// The section types this app draws, and `main` (a system screen's own content).
    static let types: Set<String> = [
        "main", "banner", "slideshow", "products", "collections", "rich_text", "image_with_text", "video", "countdown",
        "spacer", "custom", "marquee", "faq", "features", "image_grid",
    ]

    /// Analytics' `promotion_name`: `track`, else the type.
    var promotionName: String { track ?? type }

    /// Whether it runs edge to edge: a hero banner (the default style), a slideshow, a marquee, a video, or any section
    /// with a `background`. Nothing parts it from its neighbours (`gapBefore`).
    var fullBleed: Bool {
        switch type {
        case "slideshow", "marquee", "video": return true
        case "banner" where settings.choice("style", ["hero", "card"], "hero") == "hero": return true
        default: return background != nil
        }
    }

    /// Every type's style: its `background` (`#RRGGBB`; nil: none, but a marquee's strip is #111111 without one) and
    /// its `padding`, the points of room above and below inside that colour (`none` 0, `small` 12, `medium` 24,
    /// `large` 40).
    var background: String? { settings.hex("background") ?? (type == "marquee" ? "#111111" : nil) }

    var padding: Double {
        switch settings.choice("padding", ["none", "small", "medium", "large"], "none") {
        case "small": return 12
        case "medium": return 24
        case "large": return 40
        default: return 0
        }
    }
}

/// A template's `screen`: how the screen itself looks. `topBar`: `solid` or `transparent` (the bar over the first
/// section, solid once that has scrolled under it), nil when the template doesn't say (on home the settings'
/// `transparentOnHome` then decides); home and custom pages only. `tint`: the clear bar's title, icons and status bar,
/// `light` (over dark pictures) or `dark`. `background`: `#RRGGBB` behind the sections; nil: the theme's.
struct ScreenLook: Equatable, Sendable {
    var topBar: String? = nil
    var tint = "light"
    var background: String? = nil

    /// `value` (the template's `screen`) read value by value: anything missing or invalid is the default.
    static func decode(_ value: JSONValue?) -> ScreenLook {
        let s = SectionSettings(value?.object ?? [:])
        let bar = s.choice("top_bar", ["solid", "transparent"], "")
        return ScreenLook(topBar: bar.isEmpty ? nil : bar, tint: s.choice("top_bar_tint", ["light", "dark"], "light"), background: s.hex("background"))
    }

    /// Whether the bar lies over the first section: `topBar` when set, else `fallback`.
    func transparent(_ fallback: Bool = false) -> Bool { topBar.map { $0 == "transparent" } ?? fallback }
}

/// The blocks of the product page, in their default order: `main.blocks` of the product template reorders and hides them.
enum ProductPageBlock: String, CaseIterable, Sendable {
    case gallery, title, price, options, purchase, bundle, details, reviews, rails
}

/// Where a screen's sections go around its own content (`main`). Home and custom pages have none: all their sections are
/// `above`.
struct SectionPlacement: Equatable, Sendable {
    var above: [ScreenSection] = []
    var main: ScreenSection? = nil
    var below: [ScreenSection] = []
}

/// A screen's template: its sections in order and the metafields its Liquid reads (`owner.namespace.key`).
struct ScreenTemplate: Equatable, Sendable {
    var sections: [ScreenSection] = []
    var metafields: [String] = []
    var screen = ScreenLook()

    /// The template in `text` for this platform: nil when it isn't a JSON object. Sections without a string `id` and
    /// `type`, of a type this app doesn't know, `hidden`, for the other platform only, or with the id of one before
    /// them, are left out.
    static func decode(_ text: String?, platform: String = "ios") -> ScreenTemplate? {
        guard let text = text, let root = JSONValue(json: text)?.object else { return nil }
        // an id is the section's for analytics and the loaded nodes: a repeat of one is left out, the first kept
        var ids: Set<String> = []
        let sections = (root["sections"]?.array ?? []).compactMap { section(from: $0, platform: platform) }
            .filter { ids.insert($0.id).inserted }
        let metafields = (root["metafields"]?.array ?? []).compactMap { $0.string }.filter { metafieldRef($0) != nil }
        return ScreenTemplate(sections: sections, metafields: metafields, screen: ScreenLook.decode(root["screen"]))
    }

    private static func section(from value: JSONValue, platform: String) -> ScreenSection? {
        guard let map = value.object, let id = map["id"]?.string, let type = map["type"]?.string,
              ScreenSection.types.contains(type) else { return nil }
        if map["hidden"]?.bool == true { return nil }
        // a list of platforms that isn't one (or is empty) is no limit
        let platforms = map["platforms"]?.array?.compactMap { $0.string }
        if let platforms = platforms, !platforms.isEmpty, !platforms.contains(platform) { return nil }
        let blocks: [SectionBlock] = (map["blocks"]?.array ?? []).compactMap { block in
            guard let b = block.object, let id = b["id"]?.string, let type = b["type"]?.string else { return nil }
            return SectionBlock(id: id, type: type, settings: SectionSettings(b["settings"]?.object ?? [:]))
        }
        let track = map["track"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        return ScreenSection(
            id: id,
            type: type,
            settings: SectionSettings(map["settings"]?.object ?? [:]),
            blocks: blocks,
            platforms: platforms.flatMap { $0.isEmpty ? nil : $0 },
            track: track
        )
    }

    /// The sections there are to draw (all but `main`).
    var content: [ScreenSection] { sections.filter { $0.type != "main" } }

    /// The sections above and below `screen`'s own content: before `main` above, after it below; without `main`, all
    /// above. Collection and search draw nothing below their endless grid, so all of theirs go above.
    func placement(_ screen: String) -> SectionPlacement {
        let main = sections.firstIndex { $0.type == "main" }
        guard let index = main else { return SectionPlacement(above: content) }
        let before = Array(sections[..<index]).filter { $0.type != "main" }
        let after = Array(sections[(index + 1)...]).filter { $0.type != "main" }
        if screen == "collection" || screen == "search" { return SectionPlacement(above: before + after, main: sections[index]) }
        return SectionPlacement(above: before, main: sections[index], below: after)
    }

    /// The position of `section` in the template, for analytics' `creative_slot`.
    func index(of section: ScreenSection) -> Int { sections.firstIndex { $0.id == section.id } ?? 0 }

    /// The product page's blocks for `main.blocks`: those listed, in their order, without the hidden ones; every block not
    /// listed after them in its default order. Unknown names and repeats are ignored.
    static func productBlocks(_ main: ScreenSection?) -> [ProductPageBlock] {
        var listed: [ProductPageBlock] = []
        var hidden: Set<ProductPageBlock> = []
        for entry in main?.settings.values["blocks"]?.array ?? [] {
            guard let map = entry.object, let block = map["type"]?.string.flatMap(ProductPageBlock.init(rawValue:)),
                  !listed.contains(block), !hidden.contains(block) else { continue }
            if map["hidden"]?.bool == true { hidden.insert(block) } else { listed.append(block) }
        }
        return listed + ProductPageBlock.allCases.filter { !listed.contains($0) && !hidden.contains($0) }
    }

    /// The collection template `main.filters` picks (`top`, `bottom`); nil: the app's own.
    static func collectionTemplate(_ main: ScreenSection?) -> CollectionTemplate? {
        main?.settings.text("filters").flatMap { CollectionTemplate(rawValue: $0) }
    }

    /// The metafields of `owner` (`product`, `collection`, `shop`) the template reads.
    func metafieldIdentifiers(_ owner: String) -> [MetafieldIdentifier] {
        metafields.compactMap { metafieldRef($0) }.filter { $0.owner == owner }.map { $0.identifier }
    }

    /// Every product and collection GID the sections show, each once, in order: their settings and the custom section's
    /// nodes. One SectionNodes query loads them all.
    var nodeIds: [String] {
        var seen: Set<String> = []
        var ids: [String] = []
        func add(_ id: String?) {
            if let id = id, seen.insert(id).inserted { ids.append(id) }
        }
        for section in content {
            let s = section.settings
            switch section.type {
            case "products":
                s.gids("products", "Product").forEach { add($0) }
                add(s.gid("collection", "Collection"))
            case "collections":
                s.gids("collections", "Collection").forEach { add($0) }
            case "custom":
                for node in CustomNode.decode(s.values["nodes"]) {
                    switch node {
                    case let .product(id): add(isGid(id, "Product") ? id : nil)
                    case let .collection(id, _): add(isGid(id, "Collection") ? id : nil)
                    default: break
                    }
                }
            default:
                break
            }
        }
        return ids
    }
}

/// `owner.namespace.key` split; nil when the owner isn't `product`, `collection` or `shop`, or a part is missing.
func metafieldRef(_ text: String) -> (owner: String, identifier: MetafieldIdentifier)? {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { String($0) }
    guard parts.count == 3, ["product", "collection", "shop"].contains(parts[0]), !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
    return (parts[0], MetafieldIdentifier(namespace: parts[1], key: parts[2]))
}

// MARK: Custom section nodes

/// A run of a paragraph or list item: text, optionally bold, italic, a link.
struct TextRun: Equatable, Sendable {
    let text: String
    var bold = false
    var italic = false
    var link: String? = nil
}

/// One element of a custom section drawn natively (`render: native`), as Krypton compiles its html. Unknown nodes are
/// skipped.
enum CustomNode: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph([TextRun])
    case list(ordered: Bool, items: [[TextRun]])
    case image(url: String, alt: String, link: String?)
    case button(label: String, link: String?)
    case divider
    case product(String)
    case collection(String, limit: Int)

    /// The nodes in `value` (a list); nodes of an unknown type, or without what they need, are left out.
    static func decode(_ value: JSONValue?) -> [CustomNode] {
        (value?.array ?? []).compactMap { node(from: $0) }
    }

    private static func node(from value: JSONValue) -> CustomNode? {
        guard let map = value.object, let type = map["type"]?.string else { return nil }
        let link = map["link"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        switch type {
        case "heading":
            let level = map["level"]?.number.flatMap { boundedInt($0, 1...3) } ?? 2
            return .heading(level: level, text: map["text"]?.string ?? "")
        case "paragraph":
            return .paragraph(runs(map["runs"]))
        case "list":
            return .list(ordered: map["ordered"]?.bool ?? false, items: (map["items"]?.array ?? []).map { runs($0) })
        case "image":
            guard let url = map["url"]?.string, !url.isEmpty else { return nil }
            return .image(url: url, alt: map["alt"]?.string ?? "", link: link)
        case "button":
            return .button(label: map["label"]?.string ?? "", link: link)
        case "divider":
            return .divider
        case "product":
            return map["id"]?.string.map { .product($0) }
        case "collection":
            guard let id = map["id"]?.string else { return nil }
            let limit = map["limit"]?.number.flatMap { boundedInt($0, 1...24) } ?? 8
            return .collection(id, limit: limit)
        default:
            return nil
        }
    }

    private static func runs(_ value: JSONValue?) -> [TextRun] {
        (value?.array ?? []).compactMap { run in
            guard let map = run.object, let text = map["text"]?.string else { return nil }
            return TextRun(
                text: text,
                bold: map["bold"]?.bool ?? false,
                italic: map["italic"]?.bool ?? false,
                link: map["link"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }
}

// MARK: Liquid context

/// The Liquid objects of a screen (the spec's table): `shop` everywhere, `product` / `collection` on their screens,
/// `customer` when signed in, `cart`. Metafields are those the template asked for, by namespace and key
/// (`metafieldValues`). `shop.currency` is the currency prices are in (`money` writes it).
enum ScreenContext {
    static func build(
        shop: Shop?,
        shopMetafields: [Metafield] = [],
        product: Product? = nil,
        productMetafields: [Metafield] = [],
        collection: (title: String, handle: String, description: String)? = nil,
        collectionMetafields: [Metafield] = [],
        customer: Customer? = nil,
        cart: Cart? = nil
    ) -> [String: JSONValue] {
        var context: [String: JSONValue] = [:]
        // the currency prices are in: the buyer's country's (Storefront `@inContext`), else the shop's own
        let currency = product?.priceRange.minVariantPrice.currencyCode ?? cart?.total.currencyCode ?? shop?.paymentSettings.currencyCode ?? ""
        context["shop"] = .object([
            "name": .string(shop?.name ?? ""),
            "currency": .string(currency),
            "metafields": metafieldValues(shopMetafields),
        ])
        if let product = product {
            let variant = product.selectedOrFirstAvailableVariant
            context["product"] = .object([
                "title": .string(product.title),
                "handle": .string(product.handle),
                "vendor": .string(product.vendor),
                "type": .string(product.productType),
                "tags": .array(product.tags.map { .string($0) }),
                "price": .string(variant?.price.amount ?? product.priceRange.minVariantPrice.amount),
                "compare_at_price": variant?.compareAt.map { .string($0.amount) } ?? .null,
                "available": .bool(product.available),
                "url": .string("/products/\(product.handle)"),
                "metafields": metafieldValues(productMetafields),
            ])
        }
        if let collection = collection {
            context["collection"] = .object([
                "title": .string(collection.title),
                "handle": .string(collection.handle),
                "description": .string(collection.description),
                "url": .string("/collections/\(collection.handle)"),
                "metafields": metafieldValues(collectionMetafields),
            ])
        }
        if let customer = customer {
            context["customer"] = .object([
                "first_name": customer.firstName.map { .string($0) } ?? .null,
                "last_name": customer.lastName.map { .string($0) } ?? .null,
                "email": customer.email.map { .string($0) } ?? .null,
            ])
        }
        context["cart"] = .object([
            "item_count": .int(cart?.totalQuantity ?? 0),
            "total_price": .string(cart?.total.amount ?? "0.0"),
        ])
        return context
    }

    /// `metafields.<namespace>.<key>`: each value as text, except the types whose value is JSON (lists, numbers,
    /// booleans, json, ratings, ...), which are parsed.
    static func metafieldValues(_ metafields: [Metafield]) -> JSONValue {
        var namespaces: [String: [String: JSONValue]] = [:]
        for field in metafields {
            namespaces[field.namespace, default: [:]][field.key] = metafieldValue(field)
        }
        return .object(namespaces.mapValues { .object($0) })
    }

    // the types whose value is a plain string (a reference's is a GID)
    private static let textTypes: Set<String> = [
        "single_line_text_field", "multi_line_text_field", "url", "color", "date", "date_time", "id", "string",
    ]

    static func metafieldValue(_ field: Metafield) -> JSONValue {
        if textTypes.contains(field.type) || field.type.hasSuffix("_reference") { return .string(field.value) }
        return JSONValue(json: field.value) ?? .string(field.value)
    }
}
