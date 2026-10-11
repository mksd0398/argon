import XCTest
@testable import ArgonStorefront

/// What each provider is sent for an event (AnalyticsProviders.swift): the same names and numbers as on Android.
final class AnalyticsProvidersTests: XCTestCase {
    private let crewneck = AnalyticsItem(
        productId: "7982905098262",
        variantId: "43696905224214",
        name: "Men's Crewneck",
        brand: "Mock.shop",
        category: "Tops",
        variant: "Small / Green",
        price: 120.0,
        quantity: 2
    )

    /// An item with nothing but what every item has.
    private let gift = AnalyticsItem(productId: "5", name: "Gift")
    private var both: [AnalyticsItem] { [crewneck, gift] }

    private func purchase(tax: Double? = 42.12, shipping: Double? = 15.0) -> AnalyticsEvent {
        .purchase(orderId: "5800467808278", value: 381.12, currency: "CAD", tax: tax, shipping: shipping, coupon: "WELCOME10", items: both)
    }

    /// The four events about one product.
    private var aboutOne: [AnalyticsEvent] {
        [
            .viewItem(crewneck, currency: "CAD"), .addToWishlist(crewneck, currency: "CAD"), .addToCart(crewneck, currency: "CAD"),
            .removeFromCart(crewneck, currency: "CAD"),
        ]
    }

    private func assertEqual(_ actual: [String: Any]?, _ expected: [String: Any], _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(actual.map { $0 as NSDictionary }, expected as NSDictionary, message, line: line)
    }

    // MARK: Google Analytics 4

    private let crewneckItem: [String: Any] = [
        "item_id": "7982905098262", "item_name": "Men's Crewneck", "item_brand": "Mock.shop", "item_category": "Tops",
        "item_variant": "Small / Green", "price": 120.0, "quantity": 2,
    ]
    private let giftItem: [String: Any] = ["item_id": "5", "item_name": "Gift", "quantity": 1]

    func testGoogleAnalyticsGetsEveryEventWithItsItemsAsAList() {
        assertEqual(ga4Params(.screenView("home")), ["screen_name": "home"])
        assertEqual(
            ga4Params(.viewItemList(listId: "1", listName: "Men", items: both)),
            ["item_list_id": "1", "item_list_name": "Men", "items": [crewneckItem, giftItem]]
        )
        // worth the two of it
        for event in aboutOne {
            assertEqual(ga4Params(event), ["currency": "CAD", "value": 240.0, "items": [crewneckItem]], event.name)
        }
        assertEqual(ga4Params(.search("shoes")), ["search_term": "shoes"])
        assertEqual(
            ga4Params(.viewCart(items: both, value: 240.0, currency: "CAD")),
            ["value": 240.0, "currency": "CAD", "items": [crewneckItem, giftItem]]
        )
        assertEqual(
            ga4Params(.beginCheckout(items: both, value: 240.0, currency: "CAD", coupon: "VIP")),
            ["value": 240.0, "currency": "CAD", "coupon": "VIP", "items": [crewneckItem, giftItem]]
        )
        assertEqual(ga4Params(.addShippingInfo(value: 240.0, currency: "CAD")), ["value": 240.0, "currency": "CAD"])
        assertEqual(ga4Params(.addPaymentInfo(value: 240.0, currency: "CAD")), ["value": 240.0, "currency": "CAD"])
        assertEqual(ga4Params(.login), [:])

        assertEqual(ga4Params(.viewItem(gift, currency: "CAD")), ["currency": "CAD", "items": [giftItem]], "no price, no value")
        var three = crewneck
        three.price = 19.99
        three.quantity = 3
        XCTAssertEqual(ga4Params(.addToCart(three, currency: "CAD"))?["value"] as? Double, 59.97, "amounts are decimal")
    }

    func testGoogleAnalyticsPurchaseIsWorthTheOrderWithoutTaxAndShipping() {
        assertEqual(ga4Params(purchase()), [
            "transaction_id": "5800467808278", "value": 324.0, "currency": "CAD", "tax": 42.12, "shipping": 15.0,
            "coupon": "WELCOME10", "items": [crewneckItem, giftItem],
        ])
        XCTAssertEqual(ga4Params(purchase(tax: nil))?["value"] as? Double, 366.12, "only the one that is known")
        XCTAssertEqual(ga4Params(purchase(tax: nil, shipping: nil))?["value"] as? Double, 381.12, "neither: the total")
    }

    func testGoogleAnalyticsIsNotSentThePurchaseTheServerReports() {
        XCTAssertNil(ga4Params(purchase(), serverPurchase: true))
        // everything else as before
        assertEqual(
            ga4Params(.addPaymentInfo(value: 240.0, currency: "CAD"), serverPurchase: true),
            ["value": 240.0, "currency": "CAD"]
        )
        for event in aboutOne {
            assertEqual(ga4Params(event, serverPurchase: true), ga4Params(event) ?? [:], event.name)
        }
    }

    // MARK: Meta

    private func contents(_ id: String, _ content: String, _ count: Int) -> [String: Any] {
        ["fb_content_id": id, "fb_content": content, "fb_content_type": "product", "fb_currency": "CAD", "fb_num_items": count]
    }

    /// By the variant where there is one: what a catalog synced from Shopify lists.
    private var one: [String: Any] { contents("43696905224214", #"[{"id":"43696905224214","quantity":2}]"#, 2) }
    private var two: [String: Any] {
        contents(#"["43696905224214","5"]"#, #"[{"id":"43696905224214","quantity":2},{"id":"5","quantity":1}]"#, 3)
    }

    private func assertMeta(
        _ event: AnalyticsEvent, _ name: String, _ value: Double?, _ params: [String: Any], line: UInt = #line
    ) {
        let mapped = metaEvent(event)
        XCTAssertEqual(mapped?.name, name, line: line)
        XCTAssertEqual(mapped?.value, value, line: line)
        assertEqual(mapped?.params, params, name, line: line)
    }

    func testMetaGetsItsStandardEvents() {
        assertMeta(.viewItem(crewneck, currency: "CAD"), "fb_mobile_content_view", 240.0, one)
        assertMeta(.search("shoes"), "fb_mobile_search", nil, ["fb_search_string": "shoes"])
        assertMeta(.addToWishlist(crewneck, currency: "CAD"), "fb_mobile_add_to_wishlist", 240.0, one)
        assertMeta(.addToCart(crewneck, currency: "CAD"), "fb_mobile_add_to_cart", 240.0, one)
        assertMeta(
            .beginCheckout(items: both, value: 240.0, currency: "CAD", coupon: "VIP"), "fb_mobile_initiated_checkout", 240.0, two
        )
        assertMeta(.addPaymentInfo(value: 240.0, currency: "CAD"), "fb_mobile_add_payment_info", nil, ["fb_success": 1])
    }

    func testMetaPurchaseIsWorthTheOrdersTotalUnderTheIdTheServerSendsItBy() {
        var params = two
        params["event_id"] = "purchase-5800467808278"
        assertMeta(purchase(), "fb_mobile_purchase", 381.12, params)
    }

    func testMetaIsNotSentWhatItHasNoStandardEventFor() {
        let others: [AnalyticsEvent] = [
            .screenView("home"), .viewItemList(listId: "1", listName: "Men", items: both), .removeFromCart(crewneck, currency: "CAD"),
            .viewCart(items: both, value: 240.0, currency: "CAD"), .addShippingInfo(value: 240.0, currency: "CAD"), .login,
        ]
        for event in others { XCTAssertNil(metaEvent(event), event.name) }
    }

    func testMetaExtinfoIsTheSixteenTextsOfTheIosLayout() {
        // empty: the carrier, and the two storage sizes
        XCTAssertEqual(
            metaExtinfo(
                bundleId: "com.mockshop.demo",
                build: "7",
                version: "1.2",
                osVersion: "18.4",
                model: "iPhone17,3",
                locale: "en_CA",
                timezoneAbbreviation: "EDT",
                screenWidth: 393,
                screenHeight: 852,
                screenDensity: 3,
                cores: 6,
                timezone: "America/Toronto"
            ),
            #"["i2","com.mockshop.demo","7","1.2","18.4","iPhone17,3","en_CA","EDT","","393","852","3","6","","","America/Toronto"]"#
        )
    }

    // MARK: MoEngage

    private func assertMoEngage(_ event: AnalyticsEvent, _ name: String, _ attributes: [String: Any], line: UInt = #line) {
        let mapped = moEngageEvent(event)
        XCTAssertEqual(mapped.name, name, line: line)
        XCTAssertEqual(mapped.attributes as NSDictionary, attributes as NSDictionary, name, line: line)
    }

    func testMoEngageGetsEveryEventUnderItsShopifyIntegrationsNames() {
        let product: [String: Any] = [
            "Product ID": "7982905098262", "Product Title": "Men's Crewneck", "Variation ID": "43696905224214",
            "Variation Title": "Small / Green", "Vendor Name": "Mock.shop", "Price": 120.0, "Currency": "CAD", "Quantity": 2,
        ]
        // the gift has no variant, price or vendor to list
        let products: [String: Any] = [
            "Product IDs": ["7982905098262", "5"], "Product Titles": ["Men's Crewneck", "Gift"],
            "Variation IDs": ["43696905224214"], "Product Prices": [120.0], "Product Quantities": [2, 1],
            "Vendor Names": ["Mock.shop"],
        ]
        let total: [String: Any] = ["Total Price": 240.0, "Currency": "CAD"]
        func with(_ own: [String: Any]) -> [String: Any] { own.merging(products) { _, last in last } }

        assertMoEngage(.screenView("home"), "Screen Viewed", ["Screen Name": "home"])
        assertMoEngage(
            .viewItemList(listId: "1", listName: "Men", items: both), "Product List Viewed", with(["List ID": "1", "List Name": "Men"])
        )
        for (event, name) in zip(aboutOne, ["Product Viewed", "Wishlist Added", "Add to Cart", "Removed From Cart"]) {
            assertMoEngage(event, name, product)
        }
        assertMoEngage(.search("shoes"), "Product Searched", ["Search String": "shoes"])
        assertMoEngage(.viewCart(items: both, value: 240.0, currency: "CAD"), "Cart Viewed", with(total))
        assertMoEngage(
            .beginCheckout(items: both, value: 240.0, currency: "CAD", coupon: "VIP"),
            "Checkout Started",
            with(["Total Price": 240.0, "currency": "CAD", "Coupon": "VIP"])
        )
        assertMoEngage(.addShippingInfo(value: 240.0, currency: "CAD"), "Shipping Info Added", total)
        assertMoEngage(.addPaymentInfo(value: 240.0, currency: "CAD"), "Payment Info Added", total)
        assertMoEngage(purchase(), "Order Placed", with([
            "Order ID": "5800467808278", "Total Price": 381.12, "Currency": "CAD", "Tax": 42.12, "Shipping": 15.0,
            "Coupon": "WELCOME10",
        ]))
        assertMoEngage(.login, "Customer Logged In", [:])

        // only what the item has, and no list no item has anything for
        assertMoEngage(
            .viewItemList(listId: nil, listName: "Search results", items: [gift]),
            "Product List Viewed",
            ["List Name": "Search results", "Product IDs": ["5"], "Product Titles": ["Gift"], "Product Quantities": [1]]
        )
    }
}
