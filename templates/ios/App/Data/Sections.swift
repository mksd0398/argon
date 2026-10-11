import Foundation

/// What a home template lays out (`Sections.content`): banners, the categories to shop by, and product rails.
struct HomeContent: Equatable {
    /// A `Section.banner`'s parts. `image.url` may be a bundled file (`StockImages`): show it with `StoreImage`.
    struct Banner: Equatable {
        var style: String
        var image: Img?
        var heading: String?
        var text: String?
        var buttonLabel: String?
        var link: Route?
    }

    /// A `Section.products`' parts: a heading over a row or grid of products.
    struct Rail: Equatable {
        var heading: String?
        var style: String
        var items: [ProductCard]
    }

    let banners: [Banner]
    let categories: [CollectionCard]
    let rails: [Rail]

    /// Nothing but banners: the page says "Nothing to show yet." under them.
    var isEmpty: Bool { categories.isEmpty && rails.isEmpty }
}

enum Sections {
    /// The home sections from the `mobile_screen`'s section metaobjects (`StorefrontAPI.homeScreen`). Unknown types, broken
    /// references and empty product/collection sections are skipped. `hosts` (`Brand.hosts`) keeps full shop URLs in banner
    /// links in-app.
    static func fromHome(_ nodes: [Metaobject], hosts: [String] = []) -> [Section] {
        nodes.compactMap { section($0, hosts) }
    }

    private static func section(_ node: Metaobject, _ hosts: [String]) -> Section? {
        func text(_ key: String) -> String? {
            guard let value = node.field(key)?.value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        func references(_ key: String) -> [Node] { node.field(key)?.references ?? [] }

        // Admin field definitions have no defaults, so blank style/limit fall back here.
        switch node.type {
        case "mobile_banner":
            var image: Img? = nil
            if case let .image(found)? = node.field("image")?.reference { image = found }
            return .banner(
                style: text("style") ?? "hero",
                image: image,
                heading: text("heading"),
                text: text("text"),
                buttonLabel: text("button_label"),
                link: Links.resolve(text("link"), hosts: hosts)
            )
        case "mobile_products":
            let limit = Int(text("limit") ?? "").map { min(max($0, 1), 24) } ?? 8
            var items = references("products").compactMap { $0.productCard }
            if items.isEmpty { items = node.field("collection")?.reference?.collectionCard?.products ?? [] }
            if items.isEmpty { return nil }
            return .products(heading: text("heading"), style: text("style") ?? "carousel", items: Array(items.prefix(limit)))
        case "mobile_collections":
            let items = references("collections").compactMap { $0.collectionCard }
            if items.isEmpty { return nil }
            return .collections(heading: text("heading"), items: items)
        default:
            return nil
        }
    }

    /// What a home template shows, from the store's `sections` (`fromHome`; empty without a `mobile_screen`) and its first
    /// `collections` (`StorefrontAPI.fallbackHome`), which fill in whatever the sections don't give:
    /// - banners: the store's, else the template's three stock banners (`image(template, index)`, `StockImages.url` in the
    ///   app) with the template's own heading and button, linking to the first collection that has products (nowhere
    ///   without one);
    /// - categories: the collections of the store's collection sections, else the collections that have products;
    /// - rails: the store's product sections, else one per collection that has products, headed by its title.
    /// `brand` isn't read yet: the content is the same whatever the shop's branding.
    static func content(
        _ template: HomeTemplate,
        _ brand: Brand,
        _ sections: [Section],
        _ collections: [CollectionCard],
        image: (HomeTemplate, Int) -> String? = StockImages.url
    ) -> HomeContent {
        let stocked = collections.filter { !$0.products.isEmpty }
        var banners: [HomeContent.Banner] = []
        var categories: [CollectionCard] = []
        var rails: [HomeContent.Rail] = []
        for section in sections {
            switch section {
            case let .banner(style, image, heading, text, buttonLabel, link):
                banners.append(HomeContent.Banner(style: style, image: image, heading: heading, text: text, buttonLabel: buttonLabel, link: link))
            case let .products(heading, style, items):
                rails.append(HomeContent.Rail(heading: heading, style: style, items: items))
            case let .collections(_, items):
                // each collection once: a list keyed by id must not get one twice
                for item in items where !categories.contains(where: { $0.id == item.id }) { categories.append(item) }
            }
        }
        if banners.isEmpty {
            let link = stocked.first.map { Route.collection($0.handle) }
            banners = template.bannerCopy.enumerated().map { index, copy in
                let stock = image(template, index + 1).map { Img(url: $0, alt: nil, width: nil, height: nil) }
                return HomeContent.Banner(style: "hero", image: stock, heading: copy.heading, text: nil, buttonLabel: copy.button, link: link)
            }
        }
        if categories.isEmpty { categories = stocked }
        if rails.isEmpty { rails = stocked.map { HomeContent.Rail(heading: $0.title, style: "carousel", items: $0.products) } }
        return HomeContent(banners: banners, categories: categories, rails: rails)
    }

    /// The home screen built from the store's first collections (`StorefrontAPI.fallbackHome`) when it has no usable
    /// `mobile_screen`.
    static func fallback(_ brand: Brand, _ collections: [CollectionCard]) -> [Section] {
        let stocked = collections.filter { !$0.products.isEmpty }
        var sections: [Section] = []
        if let cover = brand.cover {
            sections.append(.banner(style: "hero", image: cover, heading: nil, text: nil, buttonLabel: nil, link: nil))
        }
        if !stocked.isEmpty { sections.append(.collections(heading: nil, items: stocked)) }
        if let first = stocked.first {
            sections.append(.products(heading: first.title, style: "carousel", items: first.products))
        }
        return sections
    }
}
