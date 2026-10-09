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

    private static let client = Storefront(domain: shopDomain, token: storefrontToken, apiVersion: apiVersion, loadDocument: AppGraph.document)

    /// Every Storefront API operation, typed.
    @MainActor static let storefront = StorefrontAPI(transport: { name, variables in try await AppGraph.client.query(name, variables) })

    /// The signed-in customer's Customer Account API operations, sent with `auth`'s token.
    @MainActor static let customerAccount = CustomerAccountAPI(transport: { name, variables in
        try await AppGraph.auth.customerQuery(name, variables)
    })

    @MainActor static let wishlist = WishlistStore(defaults: .standard)
    @MainActor static let cart = CartStore(
        api: AppGraph.storefront,
        defaults: .standard,
        accessToken: { try await AppGraph.auth.validAccessToken() }
    )

    @MainActor private static let browser = BrowserSignIn()
    // The callback scheme shop.<SHOP_ID>.app is the one Shopify allows a mobile client; the browser session catches it.
    @MainActor static let auth = AuthStore(
        domain: shopDomain,
        clientId: customerClientId,
        redirectUri: "shop.\(shopId).app://callback",
        loadDocument: AppGraph.document,
        open: { url in try await AppGraph.browser.open(url, scheme: "shop.\(AppGraph.shopId).app") }
    )

    /// The loaded brand (nil until `loadBrand` succeeds); the theme follows it.
    @MainActor static let brand = BrandState()
    @MainActor private static let brandLock = AsyncLock()

    /// Shop name, logo, accent and link hosts. Fetched once; a failed fetch is retried by the next caller. First, the
    /// Storefront context follows the device's country and language where the shop has them (Home and Shop wait for the
    /// brand, so their queries go out in it); without the shop's localization the shop's defaults stay.
    @MainActor
    static func loadBrand() async throws -> Brand {
        await brandLock.lock()
        defer { brandLock.unlock() }
        if let loaded = brand.value { return loaded }
        if let localization = try? await storefront.localization() {
            storefront.context = StorefrontContext.device(localization)
        }
        let shop = try await storefront.shop()
        let loaded = Brand(shop: shop, configDomain: shopDomain)
        brand.value = loaded
        return loaded
    }

    /// The GraphQL document `queries/<name>.graphql` (written by the CLI from contract/).
    static func document(_ name: String) throws -> String {
        // a synchronized folder may copy queries/ flat into the bundle
        guard let url = Bundle.main.url(forResource: name, withExtension: "graphql", subdirectory: "queries")
            ?? Bundle.main.url(forResource: name, withExtension: "graphql", subdirectory: nil) else {
            throw NotFound(what: "Query \(name)")
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
