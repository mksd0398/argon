import XCTest
// from Checkout Kit only what is named here: the whole module's public `CartLine` and `Product` would clash with the app's
import struct ShopifyCheckoutSheetKit.CheckoutCompletedEvent
import struct ShopifyCheckoutSheetKit.CustomEvent
import enum ShopifyCheckoutSheetKit.PixelEvent
import struct ShopifyCheckoutSheetKit.StandardEvent
@testable import ArgonStorefront

final class AnalyticsTests: XCTestCase {
    private let suite = UUID().uuidString

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    @MainActor
    private func fixtureCart() async throws -> Cart {
        let found = try await StubServer().storefront().cart("any")
        return try XCTUnwrap(found)
    }

    /// The fixture cart's line as an item: `quantity` of the crewneck.
    private func crewneck(_ quantity: Int) -> AnalyticsItem {
        AnalyticsItem(
            productId: "7982905098262",
            variantId: "43696905224214",
            name: "Men's Crewneck",
            variant: "Small / Green",
            price: 120.0,
            quantity: quantity
        )
    }

    // MARK: The events

    func testEveryEventHasGoogleAnalyticsName() {
        let item = crewneck(1)
        let events: [AnalyticsEvent] = [
            .screenView("home"), .viewItemList(listId: "1", listName: "Men", items: [item]), .viewItem(item, currency: "CAD"),
            .search("shoes"), .addToWishlist(item, currency: "CAD"), .addToCart(item, currency: "CAD"),
            .removeFromCart(item, currency: "CAD"), .viewCart(items: [item], value: 120.0, currency: "CAD"),
            .beginCheckout(items: [item], value: 120.0, currency: "CAD"), .addShippingInfo(value: 120.0, currency: "CAD"),
            .addPaymentInfo(value: 120.0, currency: "CAD"), .purchase(orderId: "1", value: 120.0, currency: "CAD", items: [item]),
            .login,
        ]
        XCTAssertEqual(events.map { $0.name }, [
            "screen_view", "view_item_list", "view_item", "search", "add_to_wishlist", "add_to_cart", "remove_from_cart", "view_cart",
            "begin_checkout", "add_shipping_info", "add_payment_info", "purchase", "login",
        ])
    }

    private func assertParams(_ event: AnalyticsEvent, _ expected: [String: Any], line: UInt = #line) {
        XCTAssertEqual(event.params as NSDictionary, expected as NSDictionary, line: line)
    }

    func testParamsAreFlatAndLeaveOutWhatAnEventHasNoneOf() {
        assertParams(.screenView("home"), ["screen_name": "home"])
        assertParams(.addToCart(crewneck(2), currency: "CAD"), [
            "item_id": "7982905098262", "variant_id": "43696905224214", "item_name": "Men's Crewneck",
            "item_variant": "Small / Green", "price": 120.0, "quantity": 2, "currency": "CAD",
        ])
        assertParams(
            .purchase(orderId: "9", value: 324.0, currency: "CAD", tax: 0.0, items: [crewneck(3), AnalyticsItem(productId: "5", name: "Gift")]),
            ["transaction_id": "9", "value": 324.0, "currency": "CAD", "tax": 0.0, "items": ["7982905098262/43696905224214 x3", "5 x1"]]
        )
        assertParams(.login, [:])
    }

    // MARK: The mappers

    func testIdsAreTheNumericTailOfTheGid() {
        XCTAssertEqual(gidTail("gid://shopify/Product/123"), "123")
        XCTAssertEqual(gidTail("gid://shopify/Cart/c1-4c87?key=2921"), "c1-4c87")
        XCTAssertEqual(gidTail("123"), "123")
    }

    /// `line` as the line `id` holding `quantity`, of the variant titled `variantTitle` (its own when nil).
    private func held(_ line: CartLine, _ id: String, _ quantity: Int, variantTitle: String? = nil) -> CartLine {
        CartLine(
            id: id,
            quantity: quantity,
            variantId: line.variantId,
            variantTitle: variantTitle ?? line.variantTitle,
            productHandle: line.productHandle,
            productTitle: line.productTitle,
            image: line.image,
            price: line.price,
            total: line.total,
            subtotal: line.subtotal,
            unitPrice: line.unitPrice,
            productId: line.productId
        )
    }

    @MainActor
    func testACartLineIsAnItemAtItsUnitPrice() async throws {
        let cart = try await fixtureCart()
        let line = try XCTUnwrap(cart.lines.first)
        XCTAssertEqual(line.analyticsItem(), crewneck(3))
        XCTAssertEqual(line.analyticsItem(quantity: 2), crewneck(2), "a change of two is about two")
        let plain = held(line, line.id, 3, variantTitle: "Default Title")
        XCTAssertNil(plain.analyticsItem().variant, "a product without options has no variant worth naming")
    }

    /// The fixture product, with `change` made to its JSON first.
    @MainActor
    private func fixtureProduct(_ change: (inout [String: Any]) -> Void = { _ in }) async throws -> Product {
        var product = try XCTUnwrap(try fixture("Product")["product"] as? [String: Any])
        change(&product)
        let body = try responseBody(["product": product])
        let found = try await StubServer(reply: { _, _ in body }).storefront().product("men-crewneck")
        return try XCTUnwrap(found)
    }

    @MainActor
    func testAProductIsAnItemByTheVariantItsPageOpensOn() async throws {
        let product = try await fixtureProduct()
        // mock.shop is every product's vendor; none has a product type
        var expected = crewneck(1)
        expected.brand = "Mock.shop"
        XCTAssertEqual(product.analyticsItem(), expected)
        XCTAssertEqual(product.analyticsCurrency, "CAD")

        let soldOut = try await fixtureProduct { json in
            json["productType"] = "Tops"
            var variants = (json["variants"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            for index in variants.indices { variants[index]["availableForSale"] = index == 1 }
            json["variants"] = ["nodes": variants]
        }
        XCTAssertEqual(soldOut.analyticsItem().variantId, gidTail(product.variants[1].id), "the first one that can be bought")
        XCTAssertEqual(soldOut.analyticsItem().category, "Tops")

        let bare = try await fixtureProduct { $0["variants"] = ["nodes": [Any]()] }
        expected.variantId = nil
        expected.variant = nil
        XCTAssertEqual(bare.analyticsItem(), expected, "without variants: the product, from its lowest price")
        XCTAssertEqual(bare.analyticsCurrency, "CAD")
    }

    @MainActor
    func testAProductCardIsAnItemByTheVariantTheListShowsItBy() async throws {
        let collection = try await StubServer().storefront().collection("men")
        let card = try XCTUnwrap(collection?.products.items.first)
        XCTAssertEqual(
            card.analyticsItem(),
            AnalyticsItem(productId: "7982904639510", variantId: "43696903847958", name: "Hoodie", brand: "Mock.shop", price: 90.0)
        )
    }

    @MainActor
    func testACustomerIsAUserByTheirNumericId() async throws {
        let customer = try await StubServer().customerAccount().customer()
        XCTAssertEqual(
            customer.analyticsUser(),
            AnalyticsUser(id: "7000001", email: "ada@example.com", phone: "+16135550123", firstName: "Ada", lastName: "Lovelace")
        )
    }

    @MainActor
    func testAChangeOfTheLinesIsAnAddOrARemoveOfEachDifference() async throws {
        let cart = try await fixtureCart()
        let line = try XCTUnwrap(cart.lines.first)
        XCTAssertEqual(
            cartLineEvents(
                before: [held(line, "a", 3), held(line, "b", 2), held(line, "d", 4), held(line, "e", 1)],
                after: [held(line, "a", 5), held(line, "c", 1), held(line, "d", 3), held(line, "e", 1)]
            ),
            [
                .addToCart(crewneck(2), currency: "CAD"), // a: 3, now 5
                .addToCart(crewneck(1), currency: "CAD"), // c: new
                .removeFromCart(crewneck(1), currency: "CAD"), // d: 4, now 3
                .removeFromCart(crewneck(2), currency: "CAD"), // b: gone
            ]
        )
        XCTAssertEqual(cartLineEvents(before: cart.lines, after: cart.lines), [], "nothing changed, nothing to report")
    }

    @MainActor
    func testTheCartIsViewedAndCheckedOutAtItsTotalWithTheCodesThatCount() async throws {
        var cart = try await fixtureCart()
        XCTAssertEqual(viewCart(cart), .viewCart(items: [crewneck(3)], value: 324.0, currency: "CAD"))
        // the fixture's WELCOME10 doesn't apply to it
        XCTAssertEqual(beginCheckout(cart), .beginCheckout(items: [crewneck(3)], value: 324.0, currency: "CAD", coupon: nil))
        cart.discountCodes = [
            CartDiscountCode(code: "VIP", applicable: true),
            CartDiscountCode(code: "NOPE", applicable: false),
            CartDiscountCode(code: "TEN", applicable: true),
        ]
        XCTAssertEqual(beginCheckout(cart), .beginCheckout(items: [crewneck(3)], value: 324.0, currency: "CAD", coupon: "VIP,TEN"))
    }

    /// The order Checkout Kit hands over when a checkout completes, read from JSON as the kit reads it: at `price`,
    /// holding `lines`.
    private func completed(price: String, lines: String) throws -> CheckoutCompletedEvent {
        let json = #"{"orderDetails":{"id":"gid://shopify/OrderIdentity/5800467808278","cart":{"lines":[\#(lines)],"price":\#(price),"token":"t"}}}"#
        return try JSONDecoder().decode(CheckoutCompletedEvent.self, from: Data(json.utf8))
    }

    func testACompletedOrderIsThePurchase() throws {
        func cad(_ amount: Double) -> String { #"{"amount":\#(amount),"currencyCode":"CAD"}"# }
        let ids = #""merchandiseId":"gid://shopify/ProductVariant/43696905224214","productId":"gid://shopify/Product/7982905098262""#
        let line = #""price":\#(cad(120.0)),"quantity":3,"title":"Men's Crewneck""#
        let price = """
        {"discounts":[{"title":"WELCOME10"},{"title":"Summer sale"},{}],"shipping":\(cad(15.0)),"subtotal":\(cad(360.0)),
        "taxes":\(cad(42.12)),"total":\(cad(381.12))}
        """
        let full = try completed(price: price, lines: "{\(ids),\(line)}")
        // the order's line has no variant title
        var item = crewneck(3)
        item.variant = nil
        XCTAssertEqual(
            purchase(full.orderDetails),
            .purchase(
                orderId: "5800467808278",
                value: 381.12,
                currency: "CAD",
                tax: 42.12,
                shipping: 15.0,
                coupon: "WELCOME10,Summer sale",
                items: [item]
            )
        )

        // what an order may leave out: the ids of a line, and every amount but the line's own
        let bare = try completed(price: "{}", lines: "{\(line)}")
        XCTAssertEqual(
            purchase(bare.orderDetails),
            .purchase(
                orderId: "5800467808278",
                value: 0.0,
                currency: "",
                items: [AnalyticsItem(productId: "", name: "Men's Crewneck", price: 120.0, quantity: 3)]
            )
        )
    }

    private let priced = #"{"currencyCode":"CAD","totalPrice":{"amount":324.0,"currencyCode":"CAD"}}"#

    /// A checkout web pixel event as Checkout Kit hands it over, read from JSON: the standard event `name`, about
    /// `checkout` (nil: an event without one).
    private func standard(_ name: String, checkout: String?) throws -> PixelEvent {
        let data = checkout.map { #","data":{"checkout":\#($0)}"# } ?? ""
        let json = #"{"name":"\#(name)"\#(data)}"#
        return .standardEvent(try JSONDecoder().decode(StandardEvent.self, from: Data(json.utf8)))
    }

    func testOnlyTheShippingAndPaymentPixelEventsAreCheckoutSteps() throws {
        let shipping = try standard("checkout_shipping_info_submitted", checkout: priced)
        XCTAssertEqual(checkoutStep(shipping), .addShippingInfo(value: 324.0, currency: "CAD"))
        let payment = try standard("payment_info_submitted", checkout: priced)
        XCTAssertEqual(checkoutStep(payment), .addPaymentInfo(value: 324.0, currency: "CAD"))
        // the app reports these itself: begin_checkout as the sheet opens, the purchase from the completed order
        for name in ["checkout_started", "checkout_completed", "checkout_contact_info_submitted", "page_viewed"] {
            let other = try standard(name, checkout: priced)
            XCTAssertNil(checkoutStep(other), name)
        }
        let custom = try JSONDecoder().decode(CustomEvent.self, from: Data(#"{"name":"payment_info_submitted"}"#.utf8))
        XCTAssertNil(checkoutStep(.customEvent(custom)), "a store's custom event")
        let bare = try standard("payment_info_submitted", checkout: nil)
        XCTAssertNil(checkoutStep(bare), "no total to report")
        let unpriced = try standard("payment_info_submitted", checkout: #"{"currencyCode":"CAD"}"#)
        XCTAssertNil(checkoutStep(unpriced))
        let totalOnly = try standard("payment_info_submitted", checkout: #"{"totalPrice":{"amount":324.0,"currencyCode":"CAD"}}"#)
        XCTAssertEqual(
            checkoutStep(totalOnly),
            .addPaymentInfo(value: 324.0, currency: "CAD"),
            "the currency of the total when the checkout names none"
        )
    }

    func testAScreenGoesByTheFirstPartOfItsRouteOnAndroid() {
        let destinations: [Destination] = [
            .product("h"), .collection("h"), .search("q"), .order("1"), .orders, .return("1"), .profile, .addresses, .policy("h"),
            .components,
        ]
        XCTAssertEqual(
            destinations.map { $0.screenName },
            ["product", "collection", "search", "order", "orders", "return", "profile", "addresses", "policy", "components"]
        )
    }

    // MARK: The hub

    private let ada = AnalyticsUser(id: "7000001", email: "ada@example.com")

    @MainActor
    private final class Recorder: AnalyticsSink {
        var events: [AnalyticsEvent] = []
        var users: [AnalyticsUser?] = []
        var enabled: [Bool] = []
        private let attributes: [String: String]

        init(_ attributes: [String: String] = [:]) {
            self.attributes = attributes
        }

        func track(_ event: AnalyticsEvent) { events.append(event) }

        func identify(_ user: AnalyticsUser?) { users.append(user) }

        func cartAttributes() async -> [String: String] { attributes }

        func setEnabled(_ allowed: Bool) { enabled.append(allowed) }
    }

    @MainActor
    func testNothingIsReportedWhileTheShopperDoesNotAllowIt() async {
        var allowed = false
        let sink = Recorder(["_ga_app_instance_id": "abc"])
        let analytics = Analytics(sinks: [sink], allowed: { allowed })

        analytics.track(.login)
        analytics.identify(ada)
        XCTAssertEqual(sink.events, [])
        XCTAssertEqual(sink.users, [])
        let withheld = await analytics.cartAttributes()
        XCTAssertEqual(withheld, [:], "nor does a new cart say whose it is")

        allowed = true
        analytics.track(.search("shoes"))
        analytics.identify(ada)
        analytics.identify(nil)
        XCTAssertEqual(sink.events, [.search("shoes")])
        XCTAssertEqual(sink.users, [ada, nil])
    }

    @MainActor
    func testEverySinkHearsEverything() {
        let first = Recorder()
        let second = Recorder()
        let analytics = Analytics(sinks: [first, second], allowed: { true })
        analytics.track(.login)
        analytics.identify(ada)
        for sink in [first, second] {
            XCTAssertEqual(sink.events, [.login])
            XCTAssertEqual(sink.users, [ada])
        }
    }

    @MainActor
    func testANewCartCarriesEverySinksAttributesAndThenThePlatform() async {
        let both = Analytics(
            sinks: [Recorder(["_ga_app_instance_id": "abc"]), Recorder(["_meta_anon_id": "xyz", "_meta_tracking": "1"])],
            allowed: { true }
        )
        let attributes = await both.cartAttributes()
        XCTAssertEqual(attributes, ["_ga_app_instance_id": "abc", "_meta_anon_id": "xyz", "_meta_tracking": "1", "_argon_platform": "ios"])
        // the platform alone would mark an order nobody has an id to report for
        let logOnly = await Analytics(sinks: [LogSink()], allowed: { true }).cartAttributes()
        XCTAssertEqual(logOnly, [:], "a sink with none of its own")
        let noSink = await Analytics(sinks: [], allowed: { true }).cartAttributes()
        XCTAssertEqual(noSink, [:])
    }

    @MainActor
    func testTheLogWritesOneLinePerEventAndOfTheCustomerOnlyTheId() {
        var lines: [String] = []
        let log = LogSink(write: { lines.append($0) })
        log.track(.search("shoes"))
        log.track(.viewCart(items: [crewneck(3)], value: 324.0, currency: "CAD"))
        log.track(.login)
        log.identify(ada)
        log.identify(nil)
        XCTAssertEqual(lines, [
            "Analytics: search {search_term=shoes}",
            "Analytics: view_cart {value=324.0, currency=CAD, items=[7982905098262/43696905224214 x3]}",
            "Analytics: login {}",
            "Analytics: identify 7000001",
            "Analytics: identify null",
        ])
    }

    // MARK: Consent

    /// A store on this test's defaults: a new one over the same defaults is the app after a restart.
    @MainActor
    private func consent() -> AnalyticsConsentStore { AnalyticsConsentStore(defaults: UserDefaults(suiteName: suite)!) }

    @MainActor
    func testUsageDataIsSharedUntilTheShopperTurnsItOffAndTheChoiceIsRemembered() {
        let first = consent()
        XCTAssertTrue(first.allowed, "on by default")
        first.set(false)
        XCTAssertFalse(first.allowed)

        let again = consent()
        XCTAssertFalse(again.allowed, "still off after a restart")
        again.set(true)
        XCTAssertTrue(consent().allowed)
    }

    @MainActor
    func testEverySinkIsToldTheChoiceAsTheHubIsBuiltAndEachTimeItChanges() {
        var allowed = false
        let first = Recorder()
        let second = Recorder()
        let analytics = Analytics(sinks: [first, second], allowed: { allowed })
        analytics.track(.login)
        for sink in [first, second] {
            // the gate is closed, and that is the very thing a provider's SDK has to hear
            XCTAssertEqual(sink.enabled, [false], "the choice the hub was built with")
            XCTAssertEqual(sink.events, [])
        }

        allowed = true
        analytics.consentChanged()
        allowed = false
        analytics.consentChanged()
        for sink in [first, second] { XCTAssertEqual(sink.enabled, [false, true, false]) }
    }

    /// The store and the hub tied as `AppGraph` ties them.
    @MainActor
    func testTheSwitchReachesTheSinks() {
        let sink = Recorder()
        var analytics: Analytics?
        let store = AnalyticsConsentStore(defaults: UserDefaults(suiteName: suite)!, changed: { analytics?.consentChanged() })
        analytics = Analytics(sinks: [sink, LogSink(write: { _ in })], allowed: { store.allowed })
        XCTAssertEqual(sink.enabled, [true], "on until the shopper turns it off")
        store.set(false)
        store.set(true)
        XCTAssertEqual(sink.enabled, [true, false, true])
    }
}
