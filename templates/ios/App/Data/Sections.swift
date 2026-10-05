import Foundation
import os

private let homeLog = Logger(subsystem: "app.storefront", category: "HomeScreen")

enum Sections {
    /// Sections of the `mobile_screen` metaobject in a `HomeScreen` response. Unknown types, broken references and
    /// empty product/collection sections are skipped. `hosts` (`Brand.hosts`) keeps full shop URLs in banner links in-app.
    static func fromHome(_ data: [String: Any], hosts: [String] = []) throws -> [Section] {
        let nodes = data.obj("metaobject")?.obj("field")?.nodes("references") ?? []
        var sections: [Section] = []
        for node in nodes {
            if let parsed = try section(node, hosts) { sections.append(parsed) }
        }
        return sections
    }

    private static func section(_ node: [String: Any], _ hosts: [String]) throws -> Section? {
        var fields: [String: [String: Any]] = [:]
        for field in node.objects("fields") {
            if let key = field.str("key") { fields[key] = field }
        }
        func text(_ key: String) -> String? {
            guard let value = fields[key]?.str("value"), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        func reference(_ key: String) -> [String: Any]? { fields[key]?.obj("reference") }
        func references(_ key: String) -> [[String: Any]] { fields[key]?.nodes("references") ?? [] }

        // Admin field definitions have no defaults, so blank style/limit fall back here.
        switch node.str("type") ?? "" {
        case "mobile_banner":
            return .banner(
                style: text("style") ?? "hero",
                image: img(reference("image")?.obj("image")),
                heading: text("heading"),
                text: text("text"),
                buttonLabel: text("button_label"),
                link: Links.resolve(text("link"), hosts: hosts)
            )
        case "mobile_products":
            let limit = Int(text("limit") ?? "").map { min(max($0, 1), 24) } ?? 8
            var items = try cards(references("products"))
            if items.isEmpty { items = try cards(reference("collection")?.nodes("products") ?? []) }
            if items.isEmpty { return nil }
            return .products(heading: text("heading"), style: text("style") ?? "carousel", items: Array(items.prefix(limit)))
        case "mobile_collections":
            let items = try references("collections").filter { $0["id"] != nil }.map { try parseCollectionCard($0) }
            if items.isEmpty { return nil }
            return .collections(heading: text("heading"), items: items)
        default:
            return nil
        }
    }

    /// The home screen built from a `FallbackHome` response when the store has no usable `mobile_screen`.
    static func fallback(_ brand: Brand, _ data: [String: Any]) throws -> [Section] {
        let collections = data.nodes("collections").filter { !$0.nodes("products").isEmpty }
        var sections: [Section] = []
        if let cover = brand.cover {
            sections.append(.banner(style: "hero", image: cover, heading: nil, text: nil, buttonLabel: nil, link: nil))
        }
        let collectionCards = try collections.map { try parseCollectionCard($0) }
        if !collectionCards.isEmpty { sections.append(.collections(heading: nil, items: collectionCards)) }
        if let first = collections.first {
            let items = try cards(first.nodes("products"))
            sections.append(.products(heading: first.str("title"), style: "carousel", items: items))
        }
        return sections
    }
}

/// The sections of the `mobile_screen` "home" (`home` runs the HomeScreen query); the fallback home (`fallback` runs
/// FallbackHome) when it has none to render, or when the store refuses the metaobject query with GraphQL errors (a token
/// without metaobject access). HTTP and response-shape failures are rethrown: the screen shows an error with Retry
/// instead of caching a degraded home.
func homeSections(
    _ brand: Brand,
    home: () async throws -> [String: Any],
    fallback: () async throws -> [String: Any]
) async throws -> [Section] {
    var sections: [Section] = []
    do {
        let data = try await home()
        sections = try Sections.fromHome(data, hosts: brand.hosts)
    } catch let error as StorefrontException {
        if !error.isGraphQL { throw error }
        // GraphQL messages name fields and permissions, never a token: logged so a merchant can see why the home fell back
        homeLog.warning("home screen query refused, showing the fallback home: \(error.messages.joined(separator: "; "), privacy: .public)")
    }
    if !sections.isEmpty { return sections }
    let data = try await fallback()
    return try Sections.fallback(brand, data)
}
