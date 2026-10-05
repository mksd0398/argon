import XCTest
@testable import ArgonStorefront

final class CartStoreTests: XCTestCase {
    private let suite = UUID().uuidString
    private var cartJson: [String: Any] = [:]
    private let lineId = "gid://shopify/CartLine/34639"

    /// What the store asked Shopify, in order: operation name and variables.
    private var calls: [(name: String, variables: [String: Any])] = []
    private var names: [String] { calls.map { $0.name } }
    private var cartId: String { cartJson["id"] as? String ?? "" }

    override func setUpWithError() throws {
        cartJson = try XCTUnwrap(try fixture("cart").obj("cart"))
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// A mutation answer: `{<name>: {cart, userErrors}}`; the `Cart` query answers `{cart}`.
    private func answer(_ name: String, cart: [String: Any]?, _ errors: String...) -> [String: Any] {
        let value: Any = cart ?? NSNull()
        if name == "Cart" { return ["cart": value] }
        let payload: [String: Any] = ["cart": value, "userErrors": errors.map { ["message": $0] }]
        return [name.prefix(1).lowercased() + String(name.dropFirst()): payload]
    }

    /// A store on this test's defaults: a new one over the same defaults is the app after a restart.
    @MainActor
    private func store(
        token: String? = nil,
        accessToken: (() async throws -> String?)? = nil,
        reply: ((String) async throws -> [String: Any])? = nil
    ) -> CartStore {
        let cart = cartJson
        let respond: (String) async throws -> [String: Any] = reply ?? { name in self.answer(name, cart: cart) }
        let tokenSource: () async throws -> String? = accessToken ?? { token }
        return CartStore(
            query: { name, variables in
                self.calls.append((name: name, variables: variables))
                return try await respond(name)
            },
            defaults: UserDefaults(suiteName: suite)!,
            accessToken: tokenSource
        )
    }

    private func lines(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }

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
    func testAnExpiredCartIsDroppedWithoutAnError() async throws {
        try await store().add("v1", quantity: 1)
        calls.removeAll()

        let s = store(reply: { name in name == "Cart" ? self.answer(name, cart: nil) : self.answer(name, cart: self.cartJson) })
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
            self.answer(name, cart: name == "CartBuyerIdentityUpdate" ? identityCart : self.cartJson)
        })
        try await s.add("v1", quantity: 1)
        let url = await s.checkoutUrl()
        XCTAssertEqual(url, "https://shop.test/checkout?buyer=1")
        XCTAssertEqual(names, ["CartCreate", "CartBuyerIdentityUpdate"])
        let variables = calls[1].variables
        XCTAssertEqual(variables["cartId"] as? String, cartId)
        XCTAssertEqual((variables["buyerIdentity"] as? [String: Any])?["customerAccessToken"] as? String, "tok")
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
        var identityReply: () throws -> [String: Any] = {
            self.answer("CartBuyerIdentityUpdate", cart: self.cartJson, "Customer access token is invalid")
        }
        let s = store(
            accessToken: {
                if let failure = tokenFailure { throw failure }
                return "tok"
            },
            reply: { name in
                if name == "CartBuyerIdentityUpdate" { return try identityReply() }
                return self.answer(name, cart: self.cartJson)
            }
        )
        try await s.add("v1", quantity: 1)
        let guest = cartJson["checkoutUrl"] as? String

        // the token provider throws: no identity update is tried
        var url = await s.checkoutUrl()
        XCTAssertEqual(url, guest)
        XCTAssertEqual(names, ["CartCreate"])

        // Shopify refuses the token (a userError), then the request itself fails
        tokenFailure = nil
        url = await s.checkoutUrl()
        XCTAssertEqual(url, guest)
        identityReply = { throw StorefrontException(messages: ["Throttled"], status: 200, isGraphQL: true) }
        url = await s.checkoutUrl()
        XCTAssertEqual(url, guest)
        XCTAssertEqual(names, ["CartCreate", "CartBuyerIdentityUpdate", "CartBuyerIdentityUpdate"])
        XCTAssertEqual(s.cart?.id, cartId, "the cart is kept")
    }

    @MainActor
    func testUserErrorsBecomeACartException() async throws {
        let s = store(reply: { name in
            self.answer(name, cart: name == "CartCreate" ? nil : self.cartJson, "Not enough stock")
        })
        do {
            try await s.add("v1", quantity: 99)
            XCTFail("expected a CartException")
        } catch let e as CartException {
            XCTAssertEqual(e.message, "Not enough stock")
        }
        XCTAssertNil(s.cart)
    }

    @MainActor
    func testUserErrorsOnAnUpdateKeepTheReturnedCart() async throws {
        let s = store(reply: { name in
            name == "CartLinesUpdate"
                ? self.answer(name, cart: self.cartJson, "Not enough stock")
                : self.answer(name, cart: self.cartJson)
        })
        try await s.add("v1", quantity: 1)
        do {
            try await s.update(lineId, quantity: 50)
            XCTFail("expected a CartException")
        } catch let e as CartException {
            XCTAssertEqual(e.message, "Not enough stock")
        }
        XCTAssertNotNil(s.cart)
    }

    @MainActor
    func testADeadStoredCartIsReplacedOnAdd() async throws {
        try await store().add("v1", quantity: 1)
        calls.removeAll()

        // a cold start whose load() never ran (offline): the id is stored, but Shopify no longer has the cart
        let s = store(reply: { name in
            switch name {
            case "CartLinesAdd": return self.answer(name, cart: nil, "The specified cart does not exist")
            case "Cart": return self.answer(name, cart: nil)
            default: return self.answer(name, cart: self.cartJson)
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
            name == "CartLinesAdd"
                ? self.answer(name, cart: nil, "The merchandise does not exist")
                : self.answer(name, cart: self.cartJson)
        })
        try await s.add("v1", quantity: 1)
        do {
            try await s.add("bad", quantity: 1)
            XCTFail("expected a CartException")
        } catch let e as CartException {
            XCTAssertEqual(e.message, "The merchandise does not exist")
        }
        // the lookup found the cart, so it was not replaced
        XCTAssertEqual(names, ["CartCreate", "CartLinesAdd", "Cart"])
        XCTAssertEqual(s.cart?.id, cartId)
    }

    @MainActor
    func testAnUpdateOnAGoneCartForgetsItAndSaysSo() async throws {
        let s = store(reply: { name in
            switch name {
            case "CartLinesUpdate": return self.answer(name, cart: nil, "The specified cart does not exist")
            case "Cart": return self.answer(name, cart: nil)
            default: return self.answer(name, cart: self.cartJson)
            }
        })
        try await s.add("v1", quantity: 1)
        do {
            try await s.update(lineId, quantity: 2)
            XCTFail("expected a CartException")
        } catch let e as CartException {
            XCTAssertEqual(e.message, "The specified cart does not exist")
        }
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

    @MainActor
    func testRapidAddsShareOneCart() async throws {
        let s = store(reply: { name in
            if name == "CartCreate" { try await Task.sleep(nanoseconds: 100_000_000) }
            return self.answer(name, cart: self.cartJson)
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
}
