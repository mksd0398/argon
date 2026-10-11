import XCTest
@testable import ArgonStorefront

final class CartStoreTests: XCTestCase {
    private let suite = UUID().uuidString
    private var cartJson: [String: Any] = [:]
    private let lineId = "gid://shopify/CartLine/49959"

    /// What the store asked Shopify, in order: operation name and variables.
    private var calls: [(name: String, variables: [String: Any])] = []
    private var names: [String] { calls.map { $0.name } }
    private var cartId: String { cartJson["id"] as? String ?? "" }

    override func setUpWithError() throws {
        cartJson = try XCTUnwrap(try fixture("Cart")["cart"] as? [String: Any])
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// A mutation's answer: `{<name>: {cart, userErrors, warnings}}`; the `Cart` query answers `{cart}`.
    private func answer(_ name: String, cart: [String: Any]?, _ errors: String...) throws -> String {
        let value: Any = cart ?? NSNull()
        if name == "Cart" { return try responseBody(["cart": value]) }
        let userErrors: [[String: Any]] = errors.map { ["message": $0] }
        let payload: [String: Any] = ["cart": value, "userErrors": userErrors, "warnings": [Any]()]
        return try responseBody([payloadField(name): payload])
    }

    /// What the store reported to analytics, in order.
    private var events: [AnalyticsEvent] = []

    /// A store on this test's defaults: a new one over the same defaults is the app after a restart. It reports to
    /// `events` and gives a new cart `attributes`.
    @MainActor
    private func store(
        token: String? = nil,
        accessToken: (() async throws -> String?)? = nil,
        attributes: @escaping () async -> [String: String] = { [:] },
        reply: ((String) async throws -> String)? = nil
    ) -> CartStore {
        let cart = cartJson
        let respond: (String) async throws -> String = reply ?? { name in try self.answer(name, cart: cart) }
        let tokenSource: () async throws -> String? = accessToken ?? { token }
        let api = StorefrontAPI(transport: { name, variables in
            self.calls.append((name: name, variables: variables))
            return Data(try await respond(name).utf8)
        })
        return CartStore(
            api: api,
            defaults: UserDefaults(suiteName: suite)!,
            accessToken: tokenSource,
            track: { self.events.append($0) },
            cartAttributes: attributes
        )
    }

    private func lines(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }

    /// The user errors `body` throws; nil when it throws something else, or nothing.
    @MainActor
    private func refusal(_ body: () async throws -> Void) async -> [UserError]? {
        let error = await thrownError(body)
        guard case let .userErrors(errors, _)? = error as? ArgonAPIError else { return nil }
        return errors
    }

    @MainActor
    func testAddWithNoStoredCartCreatesOneAndRemembersIt() async throws {
        try await store().add("gid://shopify/ProductVariant/1", quantity: 2)
        XCTAssertEqual(names, ["CartCreate"])
        let input = calls[0].variables["input"] as? [String: Any]
        let line = try XCTUnwrap(lines(input?["lines"]).first)
        XCTAssertEqual(line["merchandiseId"] as? String, "gid://shopify/ProductVariant/1")
        XCTAssertEqual(line["quantity"] as? Int, 2)

        // a new process: the id was persisted, and it is what load() asks for
        calls.removeAll()
        let again = store()
        try await again.load()
        XCTAssertEqual(names, ["Cart"])
        XCTAssertEqual(calls[0].variables["id"] as? String, cartId)
        XCTAssertEqual(again.cart?.totalQuantity, 3)
    }

    @MainActor
    func testAddToAnExistingCartUsesLinesAdd() async throws {
        let s = store()
        try await s.add("v1", quantity: 1)
        try await s.add("v2", quantity: 3)
        XCTAssertEqual(names, ["CartCreate", "CartLinesAdd"])
        XCTAssertEqual(calls[1].variables["cartId"] as? String, cartId)
        XCTAssertEqual(lines(calls[1].variables["lines"]).first?["quantity"] as? Int, 3)
        XCTAssertEqual(s.cart?.id, cartId)
    }

    @MainActor
    func testAddOnASellingPlanNamesThePlanAndAOneTimePurchaseNamesNone() async throws {
        let s = store()
        try await s.add("v1", quantity: 1)
        try await s.add("v2", quantity: 2, sellingPlanId: "gid://shopify/SellingPlan/1")
        let created = lines((calls[0].variables["input"] as? [String: Any])?["lines"])
        XCTAssertEqual(created.count, 1)
        XCTAssertNil(created.first?["sellingPlanId"])
        let added = lines(calls[1].variables["lines"])
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?["sellingPlanId"] as? String, "gid://shopify/SellingPlan/1")
    }

    @MainActor
    func testAnExpiredCartIsDroppedWithoutAnError() async throws {
        try await store().add("v1", quantity: 1)
        calls.removeAll()

        let s = store(reply: { name in try name == "Cart" ? self.answer(name, cart: nil) : self.answer(name, cart: self.cartJson) })
        try await s.load()
        XCTAssertNil(s.cart)
        XCTAssertEqual(names, ["Cart"])

        // the id is gone for good: the next add creates a cart
        try await s.add("v1", quantity: 1)
        XCTAssertEqual(names, ["Cart", "CartCreate"])

        // ...and a later start has nothing to look up once the cart is completed
        await s.completed()
        calls.removeAll()
        try await store().load()
        XCTAssertEqual(names, [])
    }

    @MainActor
    func testCheckoutUrlAttachesTheBuyerWhenSignedIn() async throws {
        var signedIn = cartJson
        signedIn["checkoutUrl"] = "https://shop.test/checkout?buyer=1"
        let identityCart = signedIn
        let s = store(token: "tok", reply: { name in
            try self.answer(name, cart: name == "CartBuyerIdentityUpdate" ? identityCart : self.cartJson)
        })
        try await s.add("v1", quantity: 1)
        let url = await s.checkoutUrl()
        XCTAssertEqual(url, "https://shop.test/checkout?buyer=1")
        XCTAssertEqual(names, ["CartCreate", "CartBuyerIdentityUpdate"])
        let variables = calls[1].variables
        XCTAssertEqual(variables["cartId"] as? String, cartId)
        XCTAssertEqual((variables["buyerIdentity"] as? [String: Any])?["customerAccessToken"] as? String, "tok")
    }

    // Shopify answers every buyer update with a checkout URL under a new key. Attaching the same customer to the same
    // cart again would change the cart each time, and the cart screen, which prepares checkout whenever the cart
    // changes, would reload checkout without end (seen on a phone with a signed-in customer).
    @MainActor
    func testCheckoutUrlAttachesTheSameBuyerToACartOnlyOnce() async throws {
        var key = 0
        var token = "tok"
        let s = store(
            accessToken: { token },
            reply: { name in
                guard name == "CartBuyerIdentityUpdate" else { return try self.answer(name, cart: self.cartJson) }
                key += 1
                var keyed = self.cartJson
                keyed["checkoutUrl"] = "https://shop.test/checkout?key=\(key)"
                return try self.answer(name, cart: keyed)
            }
        )
        try await s.add("v1", quantity: 1)
        let first = await s.checkoutUrl()
        XCTAssertEqual(first, "https://shop.test/checkout?key=1")

        let again = await s.checkoutUrl()
        XCTAssertEqual(again, "https://shop.test/checkout?key=1", "asked again: the same URL")
        XCTAssertEqual(s.cart?.checkoutUrl, "https://shop.test/checkout?key=1", "and the cart is as it was")
        XCTAssertEqual(names, ["CartCreate", "CartBuyerIdentityUpdate"], "nothing more was sent")

        // a refreshed token is attached once more
        token = "tok2"
        let refreshed = await s.checkoutUrl()
        XCTAssertEqual(refreshed, "https://shop.test/checkout?key=2")
        let refreshedAgain = await s.checkoutUrl()
        XCTAssertEqual(refreshedAgain, "https://shop.test/checkout?key=2")
        XCTAssertEqual(names, ["CartCreate", "CartBuyerIdentityUpdate", "CartBuyerIdentityUpdate"])
        XCTAssertEqual((calls[2].variables["buyerIdentity"] as? [String: Any])?["customerAccessToken"] as? String, "tok2")
    }

    @MainActor
    func testCheckoutUrlSkipsTheBuyerWhenSignedOut() async throws {
        let s = store(token: nil)
        let none = await s.checkoutUrl()
        XCTAssertNil(none, "no cart, no url")
        try await s.add("v1", quantity: 1)
        let url = await s.checkoutUrl()
        XCTAssertEqual(url, cartJson["checkoutUrl"] as? String)
        XCTAssertEqual(names, ["CartCreate"])
    }

    @MainActor
    func testCheckoutFallsBackToTheGuestUrlWhenTheBuyerCantBeAttached() async throws {
        var tokenFailure: Error? = URLError(.cannotConnectToHost)
        var identityReply: () throws -> String = {
            try self.answer("CartBuyerIdentityUpdate", cart: self.cartJson, "Customer access token is invalid")
        }
        let s = store(
            accessToken: {
                if let failure = tokenFailure { throw failure }
                return "tok"
            },
            reply: { name in
                if name == "CartBuyerIdentityUpdate" { return try identityReply() }
                return try self.answer(name, cart: self.cartJson)
            }
        )
        try await s.add("v1", quantity: 1)
        let guest = cartJson["checkoutUrl"] as? String

        // the token provider throws: no identity update is tried
        var url = await s.checkoutUrl()
        XCTAssertEqual(url, guest)
        XCTAssertEqual(names, ["CartCreate"])

        // Shopify refuses the token (a userError beside the cart), then the request itself fails
        tokenFailure = nil
        url = await s.checkoutUrl()
        XCTAssertEqual(url, guest)
        identityReply = { #"{"errors":[{"message":"Throttled"}]}"# }
        url = await s.checkoutUrl()
        XCTAssertEqual(url, guest)
        XCTAssertEqual(names, ["CartCreate", "CartBuyerIdentityUpdate", "CartBuyerIdentityUpdate"])
        XCTAssertEqual(s.cart?.id, cartId, "the cart is kept")
    }

    @MainActor
    func testARefusedCreateThrowsShopifysMessage() async throws {
        let s = store(reply: { name in
            try self.answer(name, cart: name == "CartCreate" ? nil : self.cartJson, "Not enough stock")
        })
        let errors = await refusal { try await s.add("v1", quantity: 99) }
        XCTAssertEqual(errors?.map { $0.message }, ["Not enough stock"])
        XCTAssertNil(s.cart)
        XCTAssertEqual(names, ["CartCreate"])
    }

    @MainActor
    func testARefusedUpdateKeepsTheCartThatCameBackWithTheErrors() async throws {
        var current = cartJson
        current["totalQuantity"] = 7
        let returned = current
        let s = store(reply: { name in
            try name == "CartLinesUpdate"
                ? self.answer(name, cart: returned, "Not enough stock")
                : self.answer(name, cart: self.cartJson)
        })
        try await s.add("v1", quantity: 1)
        let errors = await refusal { try await s.update(self.lineId, quantity: 50) }
        XCTAssertEqual(errors?.first?.message, "Not enough stock")
        XCTAssertEqual(s.cart?.totalQuantity, 7, "the cart as Shopify left it")
        XCTAssertEqual(names, ["CartCreate", "CartLinesUpdate"], "a cart came back: no lookup")
    }

    @MainActor
    func testAnAnswerWithoutCartOrErrorsLooksTheCartUp() async throws {
        let s = store(reply: { name in try self.answer(name, cart: name == "CartLinesRemove" ? nil : self.cartJson) })
        try await s.add("v1", quantity: 1)
        let errors = await refusal { try await s.remove(self.lineId) }
        XCTAssertEqual(errors?.first?.message, "The cart is unavailable")
        XCTAssertEqual(names, ["CartCreate", "CartLinesRemove", "Cart"])
        XCTAssertEqual(s.cart?.id, cartId, "the lookup found it")
    }

    @MainActor
    func testADeadStoredCartIsReplacedOnAdd() async throws {
        try await store().add("v1", quantity: 1)
        calls.removeAll()

        // a cold start whose load() never ran (offline): the id is stored, but Shopify no longer has the cart
        let s = store(reply: { name in
            switch name {
            case "CartLinesAdd": return try self.answer(name, cart: nil, "The specified cart does not exist")
            case "Cart": return try self.answer(name, cart: nil)
            default: return try self.answer(name, cart: self.cartJson)
            }
        })
        try await s.add("gid://shopify/ProductVariant/9", quantity: 2)
        XCTAssertEqual(names, ["CartLinesAdd", "Cart", "CartCreate"])
        let input = calls[2].variables["input"] as? [String: Any]
        let line = try XCTUnwrap(lines(input?["lines"]).first)
        XCTAssertEqual(line["merchandiseId"] as? String, "gid://shopify/ProductVariant/9")
        XCTAssertEqual(line["quantity"] as? Int, 2)
        XCTAssertEqual(s.cart?.id, cartId)
    }

    @MainActor
    func testARefusedAddOnALiveCartKeepsTheCart() async throws {
        let s = store(reply: { name in
            try name == "CartLinesAdd"
                ? self.answer(name, cart: nil, "The merchandise does not exist")
                : self.answer(name, cart: self.cartJson)
        })
        try await s.add("v1", quantity: 1)
        let errors = await refusal { try await s.add("bad", quantity: 1) }
        XCTAssertEqual(errors?.first?.message, "The merchandise does not exist")
        // the lookup found the cart, so it was not replaced
        XCTAssertEqual(names, ["CartCreate", "CartLinesAdd", "Cart"])
        XCTAssertEqual(s.cart?.id, cartId)
    }

    @MainActor
    func testAnUpdateOnAGoneCartForgetsItAndSaysSo() async throws {
        let s = store(reply: { name in
            switch name {
            case "CartLinesUpdate": return try self.answer(name, cart: nil, "The specified cart does not exist")
            case "Cart": return try self.answer(name, cart: nil)
            default: return try self.answer(name, cart: self.cartJson)
            }
        })
        try await s.add("v1", quantity: 1)
        let errors = await refusal { try await s.update(self.lineId, quantity: 2) }
        XCTAssertEqual(errors?.first?.message, "The specified cart does not exist")
        XCTAssertNil(s.cart)
        XCTAssertEqual(names, ["CartCreate", "CartLinesUpdate", "Cart"])
    }

    @MainActor
    func testUpdateSetsTheQuantityAndZeroRemovesTheLine() async throws {
        let s = store()
        try await s.add("v1", quantity: 1)
        try await s.update(lineId, quantity: 2)
        try await s.update(lineId, quantity: 0)
        XCTAssertEqual(names, ["CartCreate", "CartLinesUpdate", "CartLinesRemove"])
        let line = try XCTUnwrap(lines(calls[1].variables["lines"]).first)
        XCTAssertEqual(line["id"] as? String, lineId)
        XCTAssertEqual(line["quantity"] as? Int, 2)
        XCTAssertEqual(calls[2].variables["lineIds"] as? [String], [lineId])
        try await s.remove(lineId)
        XCTAssertEqual(names.last, "CartLinesRemove")
    }

    // MARK: Discount codes

    /// The fixture cart carrying `codes`, each with whether it counts.
    private func withCodes(_ codes: [String], applicable: (String) -> Bool = { _ in true }) -> [String: Any] {
        var cart = cartJson
        cart["discountCodes"] = codes.map { ["code": $0, "applicable": applicable($0)] as [String: Any] }
        return cart
    }

    /// The codes each `CartDiscountCodesUpdate` sent, in order.
    private var sentCodes: [[String]] {
        calls.filter { $0.name == "CartDiscountCodesUpdate" }.map { $0.variables["discountCodes"] as? [String] ?? [] }
    }

    /// A store whose cart starts with `carried` codes; Shopify counts the codes in `valid` and no others.
    @MainActor
    private func discountStore(_ carried: [String] = [], valid: Set<String>) -> CartStore {
        store(reply: { name in
            guard name == "CartDiscountCodesUpdate" else { return try self.answer(name, cart: self.withCodes(carried)) }
            let sent = self.calls.last?.variables["discountCodes"] as? [String] ?? []
            return try self.answer(name, cart: self.withCodes(sent) { valid.contains($0) })
        })
    }

    @MainActor
    func testApplyingADiscountSendsTheWholeListWithTheNewCode() async throws {
        let s = discountStore(["VIP"], valid: ["VIP", "WELCOME10"])
        try await s.add("v1", quantity: 1)
        let applied = try await s.applyDiscount(" WELCOME10 ")
        XCTAssertTrue(applied)
        XCTAssertEqual(sentCodes, [["VIP", "WELCOME10"]])
        XCTAssertEqual(calls.last?.variables["cartId"] as? String, cartId)
        XCTAssertEqual(s.cart?.discountCodes.map { $0.code }, ["VIP", "WELCOME10"])
    }

    @MainActor
    func testACodeThatDoesNotApplyIsTakenOffAgain() async throws {
        let s = discountStore(["VIP"], valid: ["VIP"])
        try await s.add("v1", quantity: 1)
        let applied = try await s.applyDiscount("NOPE")
        XCTAssertFalse(applied)
        XCTAssertEqual(sentCodes, [["VIP", "NOPE"], ["VIP"]], "sent with the code, then without it")
        XCTAssertEqual(s.cart?.discountCodes.map { $0.code }, ["VIP"])
    }

    @MainActor
    func testEnteringACodeAgainDoesNotListItTwice() async throws {
        let s = discountStore(["VIP"], valid: ["VIP", "vip"])
        try await s.add("v1", quantity: 1)
        let applied = try await s.applyDiscount("vip")
        XCTAssertTrue(applied)
        XCTAssertEqual(sentCodes, [["vip"]])
    }

    @MainActor
    func testRemovingADiscountSendsTheListWithoutIt() async throws {
        let s = discountStore(["VIP", "WELCOME10"], valid: ["VIP", "WELCOME10"])
        try await s.add("v1", quantity: 1)
        try await s.removeDiscount("welcome10")
        XCTAssertEqual(sentCodes, [["VIP"]])
        XCTAssertEqual(s.cart?.discountCodes.map { $0.code }, ["VIP"])
        try await s.removeDiscount("VIP")
        XCTAssertEqual(sentCodes.last, [], "the last one leaves an empty list")
    }

    @MainActor
    func testADiscountNeedsACartAndACode() async throws {
        let s = discountStore(valid: ["WELCOME10"])
        let withoutCart = try await s.applyDiscount("WELCOME10")
        XCTAssertFalse(withoutCart, "no cart")
        try await s.removeDiscount("WELCOME10")
        try await s.add("v1", quantity: 1)
        let withoutCode = try await s.applyDiscount("  ")
        XCTAssertFalse(withoutCode, "no code")
        XCTAssertEqual(sentCodes, [])
    }

    @MainActor
    func testRapidAddsShareOneCart() async throws {
        let s = store(reply: { name in
            if name == "CartCreate" { try await Task.sleep(nanoseconds: 100_000_000) }
            return try self.answer(name, cart: self.cartJson)
        })
        async let first: Void = s.add("v1", quantity: 1)
        async let second: Void = s.add("v1", quantity: 1)
        async let third: Void = s.add("v1", quantity: 1)
        try await first
        try await second
        try await third
        XCTAssertEqual(names, ["CartCreate", "CartLinesAdd", "CartLinesAdd"])
    }

    @MainActor
    func testCompletedForgetsTheCart() async throws {
        let s = store()
        try await s.add("v1", quantity: 1)
        await s.completed()
        XCTAssertNil(s.cart)
        try await s.add("v1", quantity: 1)
        XCTAssertEqual(names, ["CartCreate", "CartCreate"])
    }

    // MARK: Analytics

    /// The fixture cart holding `quantity` of its one line; an empty cart for 0.
    private func holding(_ quantity: Int) -> [String: Any] {
        var line = ((cartJson["lines"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first ?? [:]
        line["quantity"] = quantity
        var cart = cartJson
        cart["lines"] = ["nodes": quantity == 0 ? [] : [line]]
        return cart
    }

    /// `quantity` of the fixture line's variant, as analytics hears of it.
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

    @MainActor
    func testEveryChangeOfTheLinesIsReportedByWhatShopifyAnswered() async throws {
        var held = 2
        let s = store(token: "tok", reply: { name in try self.answer(name, cart: self.holding(held)) })
        try await s.add("v1", quantity: 2) // a new cart with 2
        held = 5
        try await s.add("v1", quantity: 3)
        held = 4
        try await s.update(lineId, quantity: 4)
        held = 6
        try await s.update(lineId, quantity: 6)
        held = 0
        try await s.remove(lineId)
        XCTAssertEqual(events, [
            .addToCart(crewneck(2), currency: "CAD"),
            .addToCart(crewneck(3), currency: "CAD"),
            .removeFromCart(crewneck(1), currency: "CAD"),
            .addToCart(crewneck(2), currency: "CAD"),
            .removeFromCart(crewneck(6), currency: "CAD"),
        ])

        // a quantity of 0 removes the line, as the cart's bin does
        held = 1
        try await s.add("v1", quantity: 1)
        events.removeAll()
        held = 0
        try await s.update(lineId, quantity: 0)
        XCTAssertEqual(events, [.removeFromCart(crewneck(1), currency: "CAD")])
    }

    @MainActor
    func testALoadADiscountCodeABuyerChangeAndARefusedChangeReportNothing() async throws {
        var held = 1
        var refused = false
        let s = store(token: "tok", reply: { name in
            let cart = self.holding(held)
            return try refused ? self.answer(name, cart: cart, "Not enough stock") : self.answer(name, cart: cart)
        })
        try await s.add("v1", quantity: 1)
        events.removeAll()

        held = 3 // the cart grew somewhere else (the store's web site): seeing that here is not adding to it
        try await s.load()
        _ = try await s.applyDiscount("WELCOME10")
        try await s.removeDiscount("WELCOME10")
        try await s.setBuyer("gid://shopify/CompanyLocation/1")
        _ = await s.checkoutUrl()
        refused = true
        held = 9
        let errors = await refusal { try await s.update(self.lineId, quantity: 9) }
        XCTAssertEqual(errors?.first?.message, "Not enough stock")
        XCTAssertEqual(events, [])
    }

    @MainActor
    func testACartThatReplacesAnExpiredOneReportsOnlyWhatWasAdded() async throws {
        var gone = false
        var fresh = holding(1)
        fresh["id"] = "gid://shopify/Cart/new"
        let replacement = fresh
        let s = store(token: "tok", reply: { name in
            if !gone { return try self.answer(name, cart: self.holding(3)) }
            switch name {
            case "CartLinesAdd": return try self.answer(name, cart: nil, "The specified cart does not exist")
            case "Cart": return try self.answer(name, cart: nil)
            default: return try self.answer(name, cart: replacement)
            }
        })
        try await s.add("v1", quantity: 3)
        events.removeAll()
        gone = true
        try await s.add("v1", quantity: 1)
        XCTAssertEqual(names, ["CartCreate", "CartLinesAdd", "Cart", "CartCreate"])
        XCTAssertEqual(
            events,
            [.addToCart(crewneck(1), currency: "CAD")],
            "the three that expired with the old cart were not taken out by the shopper"
        )
    }

    @MainActor
    func testAStoredCartThatWasNeverLoadedReportsNothingUntilItsLinesAreKnown() async throws {
        try await store().add("v1", quantity: 1)
        events.removeAll()
        var held = 4
        // a cold start whose load() never ran (offline): the cart held 3 already, so the 4 it answers with says nothing
        let s = store(token: "tok", reply: { name in try self.answer(name, cart: self.holding(held)) })
        try await s.add("v1", quantity: 1)
        XCTAssertEqual(events, [])
        held = 5
        try await s.add("v1", quantity: 1)
        XCTAssertEqual(events, [.addToCart(crewneck(1), currency: "CAD")])
    }

    @MainActor
    func testOnlyANewCartCarriesTheAnalyticsAttributes() async throws {
        var asked = 0
        let s = store(token: "tok", attributes: {
            asked += 1
            return ["_ga_app_instance_id": "abc", "_argon_platform": "ios"]
        })
        try await s.add("v1", quantity: 1)
        try await s.add("v2", quantity: 1)
        try await s.update(lineId, quantity: 2)
        _ = try await s.applyDiscount("WELCOME10")
        _ = await s.checkoutUrl()
        try await s.remove(lineId)

        XCTAssertEqual(names.first, "CartCreate")
        let input = calls[0].variables["input"] as? [String: Any]
        XCTAssertEqual(
            input?["attributes"] as? [[String: String]],
            [["key": "_argon_platform", "value": "ios"], ["key": "_ga_app_instance_id", "value": "abc"]],
            "in the order of their keys"
        )
        // a cart mutation changes the checkout URL: nothing sends them again, least of all a mutation of their own
        XCTAssertEqual(asked, 1, "asked for once, for the one cart that was created")
        XCTAssertEqual(names.dropFirst().filter { $0 == "CartCreate" || $0 == "CartAttributesUpdate" }, [])
        XCTAssertEqual(calls.dropFirst().filter { "\($0.variables)".contains("_argon_platform") }.count, 0)

        // and the cart that follows a placed order is new: it carries them too
        await s.completed()
        try await s.add("v1", quantity: 1)
        XCTAssertEqual(asked, 2)
        XCTAssertNotNil((calls.last?.variables["input"] as? [String: Any])?["attributes"])
    }

    @MainActor
    func testWithoutAnalyticsAttributesANewCartHasNone() async throws {
        try await store().add("v1", quantity: 1)
        XCTAssertNil((calls[0].variables["input"] as? [String: Any])?["attributes"])
    }
}
