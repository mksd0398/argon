import Foundation
import Observation

/// The app's single owner of shared objects (no DI framework). Per-store values come from Config.xcconfig through Info.plist.
enum AppGraph {
    static let shopDomain = info("ShopDomain")
    static let storefrontToken = info("StorefrontToken")
    static let customerClientId = info("CustomerClientId")
    static let shopId = info("ShopId")
    static let apiVersion = info("ApiVersion")
    static let pdpMetafields = info("PdpMetafields")

    static let storefront = Storefront(domain: shopDomain, token: storefrontToken, apiVersion: apiVersion, loadDocument: AppGraph.document)

    @MainActor static let wishlist = WishlistStore(defaults: .standard)
    @MainActor static let cart = CartStore(
        query: { name, variables in try await AppGraph.storefront.query(name, variables) },
        defaults: .standard
    )

    /// The loaded brand (nil until `loadBrand` succeeds); the theme follows it.
    @MainActor static let brand = BrandState()
    @MainActor private static let brandLock = AsyncLock()

    /// Shop name, logo, accent and link hosts. Fetched once; a failed fetch is retried by the next caller.
    @MainActor
    static func loadBrand() async throws -> Brand {
        await brandLock.lock()
        defer { brandLock.unlock() }
        if let loaded = brand.value { return loaded }
        guard let shop = try await storefront.query("Shop").obj("shop") else {
            throw StorefrontException(messages: ["Shop not found"], status: nil)
        }
        let loaded = try parseBrand(shop, configDomain: shopDomain)
        brand.value = loaded
        return loaded
    }

    /// The GraphQL document `queries/<name>.graphql` (written by the CLI from contract/queries).
    static func document(_ name: String) throws -> String {
        // a synchronized folder may copy queries/ flat into the bundle
        guard let url = Bundle.main.url(forResource: name, withExtension: "graphql", subdirectory: "queries")
            ?? Bundle.main.url(forResource: name, withExtension: "graphql", subdirectory: nil) else {
            throw StorefrontException(messages: ["Missing query \(name)"], status: nil)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}

/// Holds the shop's brand once `AppGraph.loadBrand()` has fetched it, so views observe it.
@MainActor
@Observable
final class BrandState {
    var value: Brand? = nil
}
