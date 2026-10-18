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
    /// Where the merchant's settings are (`SETTINGS_URL`, an app Krypton generated); empty: none.
    static let settingsUrl = info("SettingsUrl").trimmingCharacters(in: .whitespaces)
    /// The page Shopify sends the sign-in back to (`CUSTOMER_REDIRECT_URI`, an app Krypton generated): it passes the
    /// callback on to the app. Empty: Shopify sends it to the app's own callback directly.
    static let customerRedirectUri = info("CustomerRedirectUri").trimmingCharacters(in: .whitespaces)
    private static let settingsStore = RemoteSettingsStore(
        file: URL.applicationSupportDirectory.appending(path: "remote-settings.json")
    )
    /// The merchant's settings as the last launch fetched them (`settingsStore`); nil without a `settingsUrl`. Read before
    /// any value below: each one that the merchant can set reads it first, and a set value wins over the built-in one.
    static let remote: RemoteSettings? = settingsUrl.isEmpty ? nil : settingsStore.load()
    /// Which home page and which collection page the app shows; an unknown value is the default.
    static let homeTemplate = remote?.homeTemplate ?? HomeTemplate(config: info("HomeTemplate"))
    static let collectionTemplate = remote?.collectionTemplate ?? CollectionTemplate(config: info("CollectionTemplate"))
    /// Judge.me's public token; empty: reviews without their star breakdown (`judgeMe`).
    static let judgeMeToken = remote?.judgeMeToken ?? info("JudgemePublicToken").trimmingCharacters(in: .whitespaces)
    /// Whether product cards and the product page show the vendor (`SHOW_VENDOR`, false unless it is `true`): many
    /// stores' vendor is their own name on every product, or an internal label.
    static let showVendor = remote?.showVendor ?? (info("ShowVendor").trimmingCharacters(in: .whitespaces).lowercased() == "true")
    /// Whether a first launch starts with the welcome pages (`ONBOARDING`, true unless it is `false`).
    static let onboarding = remote?.onboarding ?? (info("Onboarding").trimmingCharacters(in: .whitespaces).lowercased() != "false")
    /// The order value from which the store ships for free, in the shop's currency (`FREE_SHIPPING_THRESHOLD`); nil when
    /// unset or not a number above zero: the cart then shows no free-shipping progress.
    static let freeShippingThreshold: Double? = {
        let builtIn = Double(info("FreeShippingThreshold").trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        guard let remote = remote else { return builtIn }
        return remote.freeShippingThreshold(over: builtIn)
    }()
    /// Meta's app id and client token (`META_APP_ID`, `META_CLIENT_TOKEN`); without both the app reports nothing to Meta.
    static let metaAppId = info("MetaAppId").trimmingCharacters(in: .whitespaces)
    static let metaClientToken = info("MetaClientToken").trimmingCharacters(in: .whitespaces)
    /// The MoEngage workspace (`MOENGAGE_WORKSPACE_ID`; empty: nothing is reported to MoEngage) and the number of its
    /// data center, 1 to 6 (`MOENGAGE_DATA_CENTER`; empty is 1).
    static let moEngageWorkspaceId = info("MoengageWorkspaceId").trimmingCharacters(in: .whitespaces)
    static let moEngageDataCenter = info("MoengageDataCenter").trimmingCharacters(in: .whitespaces)
    /// Whether the store's server reports the purchase to Google Analytics, and the app leaves it out (`SERVER_PURCHASE`,
    /// false unless it is `true`): Google Analytics would count one from each.
    static let serverPurchase = info("ServerPurchase").trimmingCharacters(in: .whitespaces).lowercased() == "true"
    /// The app's name, as under its icon (`APP_NAME`).
    static let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""

    private static let client = Storefront(domain: shopDomain, token: storefrontToken, apiVersion: apiVersion, loadDocument: AppGraph.document)

    /// Every Storefront API operation, typed.
    @MainActor static let storefront = StorefrontAPI(transport: { name, variables in try await AppGraph.client.query(name, variables) })

    /// The customer's Customer Account API operations: the signed-in customer's, sent with `auth`'s token; the sample
    /// account's bundled answers while `sampleAccount` is on.
    @MainActor static let customerAccount = CustomerAccountAPI(transport: { name, variables in
        try await AppGraph.customerQuery(name, variables)
    })

    @MainActor
    private static func customerQuery(_ name: String, _ variables: [String: Any]) async throws -> Data {
        if sampleAccount { return try SampleAccount.response(name) }
        return try await auth.customerQuery(name, variables)
    }

    @MainActor private static let sample = SampleAccountState()

    /// True while the Account tab previews the sample account (the demo store only; see `SampleAccount`). Observable.
    @MainActor static var sampleAccount: Bool {
        get { sample.active }
        set { sample.active = newValue }
    }

    /// Whether there is a sample account to offer: the signed-out Account screen then shows "Preview with a sample account".
    static let sampleAvailable = SampleAccount.available

    /// Whether there is an account to show: a signed-in customer, or the sample one.
    @MainActor static var hasAccount: Bool { auth.signedIn || sampleAccount }

    /// Product reviews (Judge.me). Without a `judgeMeToken` they are read the way Judge.me's own storefront widget reads
    /// them, and a store that has none shows none (see `JudgeMe`). The demo store's app has bundled sample reviews
    /// instead (`JudgeMeWidget.sample.html`, which the CLI copies for mock.shop only).
    static let judgeMe: JudgeMe = {
        if !judgeMeToken.isEmpty { return JudgeMe(shopDomain: shopDomain, token: judgeMeToken) }
        guard let url = SampleAccount.reviewsURL else { return JudgeMe(shopDomain: shopDomain, token: "") }
        return JudgeMe(shopDomain: shopDomain, token: "", sample: { try String(contentsOf: url, encoding: .utf8) })
    }()

    /// Whether the shopper shares usage data (the Account screen's "Privacy" switch); `analytics` reports only while they do.
    /// Each change of the choice goes on to the providers' SDKs. The type is written out because this and `analytics`
    /// name each other.
    @MainActor static let analyticsConsent: AnalyticsConsentStore = AnalyticsConsentStore(
        defaults: .standard,
        changed: { AppGraph.analytics.consentChanged() }
    )

    /// Where every screen and store reports what the shopper does: `analytics.track(event)`. `sinks` is every sink the
    /// app has: a provider's factory joins the list; it returns nil when the provider isn't configured, or its Swift
    /// package isn't in the app. A factory starts its provider's SDK, so this is built as the app launches (`ArgonApp`).
    @MainActor static let analytics = Analytics(
        sinks: [
            logSink(),
            firebaseSink(),
            metaSink(),
            moEngageSink(),
        ].compactMap { $0 },
        allowed: { AppGraph.analyticsConsent.allowed }
    )

    @MainActor static let wishlist = WishlistStore(defaults: .standard, track: { AppGraph.analytics.track($0) })
    @MainActor static let recentlyViewed = RecentlyViewedStore(defaults: .standard)
    @MainActor static let onboardingStore = OnboardingStore(defaults: .standard)
    @MainActor static let cart = CartStore(
        api: AppGraph.storefront,
        defaults: .standard,
        accessToken: { try await AppGraph.auth.validAccessToken() },
        track: { AppGraph.analytics.track($0) },
        cartAttributes: { await AppGraph.analytics.cartAttributes() }
    )

    /// The company a signed-in B2B customer buys for: it puts `storefront` and `cart` in that company's context.
    /// `AppRoot` refreshes it whenever the session changes.
    @MainActor static let buyer = BuyerStore(
        storefront: AppGraph.storefront,
        cart: AppGraph.cart,
        defaults: .standard,
        accessToken: { try await AppGraph.auth.validAccessToken() },
        companies: { try await AppGraph.customerAccount.companies() },
        sample: { AppGraph.sampleAccount }
    )

    /// The tab on show: set `tabs.selected` to send the shopper to another one ("See all" to Shop, "Sign in" to Account).
    @MainActor static let tabs = TabState()

    /// `toast.show(_:)` tells the shopper something from work that outlives its screen (a cart write that failed): it
    /// shows for a few seconds over the tabs, whichever screen is open.
    @MainActor static let toast = ToastState()

    @MainActor private static let browser = BrowserSignIn()
    // The callback scheme shop.<SHOP_ID>.app is the one Shopify allows a mobile client; the browser session catches it,
    // straight from Shopify or through the `customerRedirectUri` page.
    @MainActor static let auth = AuthStore(
        domain: shopDomain,
        clientId: customerClientId,
        shopId: shopId,
        redirectUri: customerRedirectUri,
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
        let loaded = Brand(shop: shop, configDomain: shopDomain, accent: remote?.accent)
        brand.value = loaded
        return loaded
    }

    /// Fetches the merchant's settings in the background for the next launch (nothing without a `settingsUrl`).
    static func refreshSettings() {
        // this launch's settings are read first: the fetch is only for the next one
        _ = remote
        guard !settingsUrl.isEmpty, let url = URL(string: settingsUrl) else { return }
        Task.detached(priority: .utility) { await settingsStore.refresh(from: url) }
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

    /// A per-store value: from Info.plist (Xcode fills it in from Config.xcconfig), else from Config.xcconfig itself,
    /// which an xtool build bundles as a resource because it has no build settings to substitute.
    private static func info(_ key: String) -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty { return value }
        return bundledConfig[xcconfigKey(key)] ?? ""
    }

    private static let bundledConfig: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "xcconfig"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return xcconfigValues(text)
    }()
}

/// "ShopDomain" -> "SHOP_DOMAIN": the Config.xcconfig key behind an Info.plist key.
func xcconfigKey(_ infoKey: String) -> String {
    infoKey.reduce(into: "") { out, character in
        if character.isUppercase, !out.isEmpty { out.append("_") }
        out.append(contentsOf: character.uppercased())
    }
}

/// The `KEY = value` lines of an xcconfig file. `$()`, the empty substitution the CLI writes to keep `//` in a value,
/// is dropped; comment lines are skipped.
func xcconfigValues(_ text: String) -> [String: String] {
    var values: [String: String] = [:]
    for line in text.split(whereSeparator: \.isNewline) {
        guard !line.hasPrefix("//"), let equals = line.firstIndex(of: "=") else { continue }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        if !key.isEmpty { values[key] = value.replacingOccurrences(of: "$()", with: "") }
    }
    return values
}

/// Holds the shop's brand once `AppGraph.loadBrand()` has fetched it, so views observe it.
@MainActor
@Observable
final class BrandState {
    var value: Brand? = nil
}
