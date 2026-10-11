import XCTest
@testable import ArgonStorefront

/// The B2B buyer: who shops in a company's context, and what that puts on the Storefront API and the cart.
final class BuyerStoreTests: XCTestCase {
    private let suite = UUID().uuidString
    private let ottawa = CompanyLocation(id: "gid://shopify/CompanyLocation/9200001", name: "Ottawa head office")
    private let toronto = CompanyLocation(id: "gid://shopify/CompanyLocation/9200002", name: "Toronto warehouse")

    /// The session and the customer's companies, as the store under test finds them.
    private var token: String? = "tok"
    private var contacts: [CompanyContact] = []
    private var failure: Error? = nil
    private var sample = false

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func contact(_ locations: [CompanyLocation]) -> CompanyContact {
        CompanyContact(
            id: "gid://shopify/CompanyContact/9000001",
            title: "Purchasing lead",
            company: Company(id: "gid://shopify/Company/9100001", name: "Analytical Engines Ltd", locations: locations)
        )
    }

    /// A buyer store over `server`, on this test's defaults: a new one over the same defaults is the app after a restart.
    @MainActor
    private func make(_ server: StubServer) -> (buyer: BuyerStore, api: StorefrontAPI, cart: CartStore) {
        let defaults = UserDefaults(suiteName: suite)!
        let api = server.storefront()
        let cart = CartStore(api: api, defaults: defaults, accessToken: { self.token })
        let buyer = BuyerStore(
            storefront: api,
            cart: cart,
            defaults: defaults,
            accessToken: { self.token },
            companies: {
                if let failure = self.failure { throw failure }
                return self.contacts
            },
            sample: { self.sample }
        )
        return (buyer, api, cart)
    }

    @MainActor
    func testACompanyContactShopsForTheCompanysFirstLocation() async {
        let server = StubServer()
        let (buyer, api, _) = make(server)
        contacts = [contact([ottawa, toronto])]
        await buyer.refresh()
        XCTAssertEqual(
            buyer.company,
            BuyerCompany(
                contactId: "gid://shopify/CompanyContact/9000001",
                companyName: "Analytical Engines Ltd",
                locations: [ottawa, toronto],
                locationId: ottawa.id
            )
        )
        XCTAssertEqual(buyer.company?.location, ottawa)
        XCTAssertEqual(api.buyer, Buyer(customerAccessToken: "tok", companyLocationId: ottawa.id))
        XCTAssertEqual(server.names, [], "no cart yet: nothing to put the buyer on")
    }

    @MainActor
    func testTheCartTakesTheBuyerNowAndWithEveryNewCart() async throws {
        let server = StubServer()
        let (buyer, _, cart) = make(server)
        try await cart.add("v1", quantity: 1)
        contacts = [contact([ottawa, toronto])]
        await buyer.refresh()
        XCTAssertEqual(server.names, ["CartCreate", "CartBuyerIdentityUpdate"])
        let identity = ["customerAccessToken": "tok", "companyLocationId": ottawa.id]
        XCTAssertEqual(server.calls[1].variables["buyerIdentity"] as? [String: String], identity)
        XCTAssertEqual(server.calls[1].variables["buyer"] as? [String: String], identity, "the mutation itself runs for the buyer")
        XCTAssertNil((server.calls[0].variables["input"] as? [String: Any])?["buyerIdentity"], "a retail cart starts without a buyer")

        await buyer.refresh()
        XCTAssertEqual(server.names.count, 2, "nothing changed: nothing sent")

        await cart.completed()
        try await cart.add("v1", quantity: 1)
        XCTAssertEqual(server.names.last, "CartCreate")
        let input = server.calls.last?.variables["input"] as? [String: Any]
        XCTAssertEqual(input?["buyerIdentity"] as? [String: String], identity, "the next cart starts with the buyer")
    }

    @MainActor
    func testTheChosenLocationIsKeptWhileTheCompanyOffersIt() async {
        let (buyer, api, _) = make(StubServer())
        contacts = [contact([ottawa, toronto])]
        await buyer.refresh()
        await buyer.select(toronto.id)
        XCTAssertEqual(buyer.company?.locationId, toronto.id)
        XCTAssertEqual(api.buyer, Buyer(customerAccessToken: "tok", companyLocationId: toronto.id))

        // after a restart
        let (again, apiAgain, _) = make(StubServer())
        await again.refresh()
        XCTAssertEqual(again.company?.locationId, toronto.id)
        XCTAssertEqual(apiAgain.buyer?.companyLocationId, toronto.id)

        // the company no longer offers it: back to the first
        contacts = [contact([ottawa])]
        await again.refresh()
        XCTAssertEqual(again.company?.locationId, ottawa.id)
        XCTAssertEqual(apiAgain.buyer?.companyLocationId, ottawa.id)
    }

    @MainActor
    func testSelectingALocationMovesTheCartToo() async throws {
        let server = StubServer()
        let (buyer, _, cart) = make(server)
        try await cart.add("v1", quantity: 1)
        contacts = [contact([ottawa, toronto])]
        await buyer.refresh()
        await buyer.select(toronto.id)
        XCTAssertEqual(server.names, ["CartCreate", "CartBuyerIdentityUpdate", "CartBuyerIdentityUpdate"])
        XCTAssertEqual((server.calls[2].variables["buyerIdentity"] as? [String: String])?["companyLocationId"], toronto.id)
    }

    @MainActor
    func testAnyoneElseIsARetailShopper() async {
        let (buyer, api, _) = make(StubServer())
        // signed in, but not a company's contact
        await buyer.refresh()
        XCTAssertNil(buyer.company)
        XCTAssertNil(api.buyer)
        // a company with nowhere to buy for
        contacts = [contact([])]
        await buyer.refresh()
        XCTAssertNil(buyer.company)
        XCTAssertNil(api.buyer)

        // a contact, then signed out
        contacts = [contact([ottawa])]
        await buyer.refresh()
        XCTAssertNotNil(api.buyer)
        token = nil
        await buyer.refresh()
        XCTAssertNil(buyer.company)
        XCTAssertNil(api.buyer)

        // signed in again, then cleared
        token = "tok"
        await buyer.refresh()
        XCTAssertNotNil(buyer.company)
        await buyer.clear()
        XCTAssertNil(buyer.company)
        XCTAssertNil(api.buyer)
    }

    @MainActor
    func testANewTokenReplacesTheBuyer() async throws {
        let server = StubServer()
        let (buyer, api, cart) = make(server)
        try await cart.add("v1", quantity: 1)
        contacts = [contact([ottawa])]
        await buyer.refresh()
        token = "tok2"
        await buyer.refresh()
        XCTAssertEqual(api.buyer, Buyer(customerAccessToken: "tok2", companyLocationId: ottawa.id))
        XCTAssertEqual(server.names, ["CartCreate", "CartBuyerIdentityUpdate", "CartBuyerIdentityUpdate"])
        XCTAssertEqual((server.calls[2].variables["buyerIdentity"] as? [String: String])?["customerAccessToken"], "tok2")
    }

    @MainActor
    func testAFailureLeavesTheRetailContext() async throws {
        // the companies can't be loaded
        let (buyer, api, _) = make(StubServer())
        contacts = [contact([ottawa])]
        await buyer.refresh()
        XCTAssertNotNil(api.buyer)
        failure = ArgonAPIError.http(status: 503)
        await buyer.refresh()
        XCTAssertNil(buyer.company)
        XCTAssertNil(api.buyer)

        // the cart refuses the buyer
        failure = nil
        let server = StubServer()
        server.reply = { name, _ in
            if name == "CartBuyerIdentityUpdate" { return #"{"errors":[{"message":"Throttled"}]}"# }
            return try "{\"data\":" + fixtureText(name) + "}"
        }
        let (refused, refusedApi, cart) = make(server)
        try await cart.add("v1", quantity: 1)
        await refused.refresh()
        XCTAssertNil(refused.company)
        XCTAssertNil(refusedApi.buyer)
        XCTAssertNotNil(cart.cart, "the cart is kept")
    }

    @MainActor
    func testTheSampleAccountShowsItsCompanyWithoutABuyer() async {
        let server = StubServer()
        let (buyer, api, _) = make(server)
        token = nil
        sample = true
        contacts = [contact([ottawa, toronto])]
        await buyer.refresh()
        XCTAssertEqual(buyer.company?.companyName, "Analytical Engines Ltd")
        XCTAssertEqual(buyer.company?.locationId, ottawa.id)
        XCTAssertNil(api.buyer, "no token to shop with")
        XCTAssertEqual(server.names, [])

        sample = false
        await buyer.refresh()
        XCTAssertNil(buyer.company, "the preview is over")
    }
}
