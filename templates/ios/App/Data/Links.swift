import Foundation

/// The one link parser for banner links, menu items and deep links.
enum Links {
    // A leading locale folder such as /fr or /en-in
    private static let locale = "^/[a-zA-Z]{2}(-[a-zA-Z]{2})?(?=/)"

    /// Maps a store path, or a full URL on one of `hosts`, to an in-app route. Any other http(s) URL, and a store path
    /// that isn't a product, collection or search (such as `/pages/shipping`), becomes `.web`; other schemes give nil.
    /// `hosts` is ordered: the first is the configured SHOP_DOMAIN, which relative paths are opened against.
    static func resolve(_ link: String?, hosts: [String]) -> Route? {
        let raw = (link ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "%20")
        guard let url = URLComponents(string: raw) else { return nil }
        let scheme = url.scheme?.lowercased()
        let absolute = scheme != nil
        if let scheme = scheme, scheme != "http" && scheme != "https" { return nil }
        if absolute {
            let host = url.host ?? ""
            if !hosts.contains(where: { $0.caseInsensitiveCompare(host) == .orderedSame }) { return .web(raw) }
        }
        var path = url.path
        if let prefix = path.range(of: locale, options: .regularExpression) { path.removeSubrange(prefix) }
        let segments = path.split(separator: "/").map { String($0) }

        if segments.count >= 2 && segments[segments.count - 2] == "products" { return .product(segments[segments.count - 1]) } // also /collections/<c>/products/<h>
        if segments.count == 2 && segments[0] == "collections" { return .collection(segments[1]) }
        if segments == ["search"] { return .search(param(url, "q") ?? "") }
        if segments.isEmpty { return nil }
        if absolute { return .web(raw) }
        guard let shop = hosts.first else { return nil }
        let rest = String(raw.drop(while: { $0 == "/" }))
        return .web("https://\(shop)/\(rest)")
    }

    /// The menu's items as in-app routes: through their linked product or collection, else through `resolve`. Unroutable
    /// leaves are dropped.
    static func menu(_ items: [StoreMenu.Item], hosts: [String]) -> [MenuItem] {
        var routed: [MenuItem] = []
        for item in items {
            let children = menu(item.items, hosts: hosts)
            var route: Route?
            switch item.resource {
            case let .product(handle)?: route = .product(handle)
            case let .collection(handle)?: route = .collection(handle)
            default: route = resolve(item.url, hosts: hosts)
            }
            // ponytail: a pure header item (url "#") keeps its children behind a placeholder web route; the UI expands it
            if route == nil && !children.isEmpty { route = .web(item.url ?? "") }
            guard let target = route else { continue }
            routed.append(MenuItem(title: item.title, route: target, children: children))
        }
        return routed
    }

    // Form decoding, as URLDecoder does: `+` is a space.
    private static func param(_ url: URLComponents, _ name: String) -> String? {
        let pairs = (url.percentEncodedQuery ?? "").split(separator: "&").map { String($0) }
        guard let pair = pairs.first(where: { $0.hasPrefix("\(name)=") }) else { return nil }
        return String(pair.dropFirst(name.count + 1)).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }
}
