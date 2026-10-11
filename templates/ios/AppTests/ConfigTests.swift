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
    }

    func testReadsKeyValueLinesAndDropsTheEmptySubstitution() {
        let text = """
        // written by Argon
        SHOP_DOMAIN = nalli.myshopify.com
        STOREFRONT_TOKEN =
        APP_NAME = Nalli = Silks
        PDP_METAFIELDS = https:/$()/example.com/a
        not a setting
        """
        let values = xcconfigValues(text)
        XCTAssertEqual(values["SHOP_DOMAIN"], "nalli.myshopify.com")
        XCTAssertEqual(values["STOREFRONT_TOKEN"], "", "an empty value stays empty")
        XCTAssertEqual(values["APP_NAME"], "Nalli = Silks", "only the first = separates")
        XCTAssertEqual(values["PDP_METAFIELDS"], "https://example.com/a")
        XCTAssertEqual(values.count, 4)
    }
}
