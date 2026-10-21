import XCTest
@testable import ArgonStorefront

final class GoKwikTests: XCTestCase {
    private let cartId = "gid://shopify/Cart/hWN20nvTkiET80LEjquVKpxU?key=7a1e23034ec76ce3d121035b4510b818"

    /// The query parameters of `url`, as GoKwik sends them: base64 left as it is.
    private func params(_ url: URL) -> [String: String] {
        let query = url.absoluteString.split(separator: "?", maxSplits: 1).last ?? ""
        var values: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            values[String(parts[0])] = parts.count > 1 ? String(parts[1]) : ""
        }
        return values
    }

    private func decoded(_ base64: String?) throws -> Any {
        let data = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(base64)))
        return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }

    private func url(coreToken: String? = nil, email: String? = nil, upiApps: [String] = []) throws -> URL {
        try XCTUnwrap(goKwikCheckoutUrl(
            cartId: cartId, storefrontToken: "sf-token", shopDomain: "shop.myshopify.com", merchantId: "mid1",
            environment: .sandbox, coreToken: coreToken, email: email, upiApps: upiApps
        ))
    }

    func testStoreInfoCarriesTheCartWithoutItsPrefix() throws {
        let link = try url()
        XCTAssertTrue(link.absoluteString.hasPrefix("https://sandbox.pdp.gokwik.co/app/kwik-checkout.html?storeInfo="))
        let info = try XCTUnwrap(try decoded(params(link)["storeInfo"]) as? [String: Any])
        XCTAssertEqual(info["mid"] as? String, "mid1")
        XCTAssertEqual(info["environment"] as? String, "sandbox")
        XCTAssertEqual(info["platform"] as? String, "ios")
        XCTAssertEqual(info["tag"] as? String, "mobile_app_ios")
        XCTAssertEqual(info["type"] as? String, "merchantInfo")
        let store = try XCTUnwrap(info["storeData"] as? [String: Any])
        XCTAssertEqual(store["cartId"] as? String, "hWN20nvTkiET80LEjquVKpxU?key=7a1e23034ec76ce3d121035b4510b818")
        XCTAssertEqual(store["storefrontAccessToken"] as? String, "sf-token")
        XCTAssertEqual(store["shopDomain"] as? String, "shop.myshopify.com")
    }

    func testSignedOutSendsNoSession() throws {
        let values = params(try url())
        XCTAssertNil(values["gk_token"])
        XCTAssertNil(values["kp_email"])
        XCTAssertNil(values["upi_apps"])
    }

    func testSignedInSendsTheCoreTokenAndEmail() throws {
        let values = params(try url(coreToken: "core1", email: "ada@example.com", upiApps: ["googlepay", "phonepe"]))
        // base64 of {"coreToken":"core1"}
        XCTAssertEqual(values["gk_token"], "eyJjb3JlVG9rZW4iOiJjb3JlMSJ9")
        XCTAssertEqual(try decoded(values["kp_email"]) as? String, "ada@example.com")
        XCTAssertEqual(try decoded(values["upi_apps"]) as? [String], ["googlepay", "phonepe"])
    }

    func testProductionBase() throws {
        let link = goKwikCheckoutUrl(cartId: "c", storefrontToken: "", shopDomain: "s", merchantId: "m", environment: .production)
        XCTAssertTrue(link?.absoluteString.hasPrefix("https://pdp.gokwik.co/app/kwik-checkout.html?storeInfo=") == true)
    }

    func testEnvironmentIsSandboxOnlyWhenSaidSo() {
        XCTAssertEqual(GoKwikEnvironment(config: " Sandbox "), .sandbox)
        XCTAssertEqual(GoKwikEnvironment(config: "production"), .production)
        XCTAssertEqual(GoKwikEnvironment(config: ""), .production)
    }

    func testOnlyGoKwikHostsAreHeard() {
        XCTAssertTrue(isGoKwikHost("pdp.gokwik.co"))
        XCTAssertTrue(isGoKwikHost("gokwik.co"))
        XCTAssertFalse(isGoKwikHost("evilgokwik.co"))
        XCTAssertFalse(isGoKwikHost("gokwik.co.evil.com"))
        XCTAssertFalse(isGoKwikHost(nil))
    }

    func testEvents() throws {
        guard case .loaded? = goKwikEvent(#"{"type":"gokwikLoaded","data":{"isTrusted":true}}"#) else { return XCTFail() }
        guard case .closed? = goKwikEvent(#"{"type":"modal_closed"}"#) else { return XCTFail() }
        guard case .disabled? = goKwikEvent(#"{"type":"gk-checkout-disable","data":{}}"#) else { return XCTFail() }
        guard case .orderSuccess(let data)? = goKwikEvent(#"{"type":"orderSuccess","data":{"order_id":"123"}}"#) else { return XCTFail() }
        XCTAssertEqual(data["order_id"] as? String, "123")
        guard case .openInBrowser(let a)? = goKwikEvent(#"{"type":"openInBrowserTab","data":{"url":"https://a.test/x"}}"#),
              case .openInBrowser(let b)? = goKwikEvent(#"{"type":"openInBrowserTab","data":"https://b.test/y"}"#) else { return XCTFail() }
        XCTAssertEqual(a.absoluteString, "https://a.test/x")
        XCTAssertEqual(b.absoluteString, "https://b.test/y")
        XCTAssertNil(goKwikEvent(#"{"type":"gokwik_events","data":{}}"#))
        XCTAssertNil(goKwikEvent("not json"))
    }

    func testPurchaseNeedsAnOrderId() {
        XCTAssertNil(goKwikPurchase(["amount": "10"], cart: nil))
        guard case let .purchase(orderId, value, currency, _, _, _, items)? =
            goKwikPurchase(["order_id": 5_551_234, "total_price": "499.00", "currency": "INR"], cart: nil) else { return XCTFail() }
        XCTAssertEqual(orderId, "5551234")
        XCTAssertEqual(value, 499)
        XCTAssertEqual(currency, "INR")
        XCTAssertTrue(items.isEmpty)
    }
}
