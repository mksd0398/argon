import XCTest
@testable import ArgonStorefront

/// The Config.xcconfig fallback an xtool build uses (it has no build settings to fill Info.plist from).
final class ConfigTests: XCTestCase {
    func testInfoKeysMapToXcconfigKeys() {
        XCTAssertEqual(xcconfigKey("ShopDomain"), "SHOP_DOMAIN")
        XCTAssertEqual(xcconfigKey("CustomerClientId"), "CUSTOMER_CLIENT_ID")
        XCTAssertEqual(xcconfigKey("ShopId"), "SHOP_ID")
        XCTAssertEqual(xcconfigKey("PdpMetafields"), "PDP_METAFIELDS")
        XCTAssertEqual(xcconfigKey("HomeTemplate"), "HOME_TEMPLATE")
        XCTAssertEqual(xcconfigKey("CollectionTemplate"), "COLLECTION_TEMPLATE")
        XCTAssertEqual(xcconfigKey("JudgemePublicToken"), "JUDGEME_PUBLIC_TOKEN")
        XCTAssertEqual(xcconfigKey("ShowVendor"), "SHOW_VENDOR")
        XCTAssertEqual(xcconfigKey("Onboarding"), "ONBOARDING")
        XCTAssertEqual(xcconfigKey("FreeShippingThreshold"), "FREE_SHIPPING_THRESHOLD")
        XCTAssertEqual(xcconfigKey("MetaAppId"), "META_APP_ID")
        XCTAssertEqual(xcconfigKey("MetaClientToken"), "META_CLIENT_TOKEN")
        XCTAssertEqual(xcconfigKey("MoengageWorkspaceId"), "MOENGAGE_WORKSPACE_ID")
        XCTAssertEqual(xcconfigKey("MoengageDataCenter"), "MOENGAGE_DATA_CENTER")
        XCTAssertEqual(xcconfigKey("ServerPurchase"), "SERVER_PURCHASE")
        XCTAssertEqual(xcconfigKey("SettingsUrl"), "SETTINGS_URL")
        XCTAssertEqual(xcconfigKey("CustomerRedirectUri"), "CUSTOMER_REDIRECT_URI")
    }

    /// An Xcode build (the one these tests run in) takes the values through Info.plist: it has to name each analytics and
    /// Krypton key `AppGraph` asks for, whatever the store's value is, an empty one too.
    func testInfoPlistNamesTheAnalyticsKeys() {
        for key in [
            "MetaAppId", "MetaClientToken", "MoengageWorkspaceId", "MoengageDataCenter", "ServerPurchase", "SettingsUrl", "CustomerRedirectUri",
        ] {
            XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: key) as? String, "Info.plist has no \(key)")
        }
    }

    func testReadsKeyValueLinesAndDropsTheEmptySubstitution() {
        let text = """
        // written by Argon
        SHOP_DOMAIN = nalli.myshopify.com
        STOREFRONT_TOKEN =
        APP_NAME = Nalli = Silks
        PDP_METAFIELDS = https:/$()/example.com/a
        SETTINGS_URL = https:/$()/krypton-mksd.web.app/v1/settings/nalli.myshopify.com
        CUSTOMER_REDIRECT_URI = https:/$()/krypton-mksd.web.app/customer-account/callback
        not a setting
        """
        let values = xcconfigValues(text)
        XCTAssertEqual(values["SHOP_DOMAIN"], "nalli.myshopify.com")
        XCTAssertEqual(values["STOREFRONT_TOKEN"], "", "an empty value stays empty")
        XCTAssertEqual(values["APP_NAME"], "Nalli = Silks", "only the first = separates")
        XCTAssertEqual(values["PDP_METAFIELDS"], "https://example.com/a")
        XCTAssertEqual(values["SETTINGS_URL"], "https://krypton-mksd.web.app/v1/settings/nalli.myshopify.com")
        XCTAssertEqual(values["CUSTOMER_REDIRECT_URI"], "https://krypton-mksd.web.app/customer-account/callback")
        XCTAssertEqual(values.count, 6)
    }
}
