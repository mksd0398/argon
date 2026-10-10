import Foundation
import os

private let homeLog = Logger(subsystem: "app.storefront", category: "HomeScreen")

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

/// The sections of the `mobile_screen` "home" (`home` loads its section metaobjects); the fallback home (`fallback` loads the
/// first collections) when it has none to render, or when the store refuses the metaobject query with GraphQL errors (a token
/// without metaobject access). HTTP and response-shape failures are rethrown: the screen shows an error with Retry instead
/// of caching a degraded home.
func homeSections(
    _ brand: Brand,
    home: () async throws -> [Metaobject],
    fallback: () async throws -> [CollectionCard]
) async throws -> [Section] {
    var sections: [Section] = []
    do {
        let nodes = try await home()
        sections = Sections.fromHome(nodes, hosts: brand.hosts)
    } catch ArgonAPIError.graphql(let messages) {
        // GraphQL messages name fields and permissions, never a token: logged so a merchant can see why the home fell back
        homeLog.warning("home screen query refused, showing the fallback home: \(messages.joined(separator: "; "), privacy: .public)")
    }
    if !sections.isEmpty { return sections }
    let collections = try await fallback()
    return Sections.fallback(brand, collections)
}
