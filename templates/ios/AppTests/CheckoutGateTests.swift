import XCTest
@testable import ArgonStorefront

final class CheckoutGateTests: XCTestCase {
    private let checkout = URL(string: "https://shop.test/cart/c/abc?key=k")!

    /// A fetch that answers `status` with a Location of `location`.
    private func answering(_ status: Int, location: String? = nil) -> (URLRequest) async throws -> (Data, URLResponse) {
        { request in
            let headers = location.map { ["Location": $0] } ?? [:]
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        }
    }

    func testAStorefrontSentToThePasswordPageIsProtected() async {
        var asked: URL?
        let protected = await passwordProtected(checkout, fetch: { request in
            asked = request.url
            return try await self.answering(302, location: "https://shop.test/password")(request)
        })
        XCTAssertTrue(protected)
        XCTAssertEqual(asked?.absoluteString, "https://shop.test/", "the storefront's home page is asked")
    }

    func testAStorefrontWithoutAPasswordIsNot() async {
        let onward = await passwordProtected(checkout, fetch: answering(301, location: "https://www.shop.test/"))
        XCTAssertFalse(onward)
        let ok = await passwordProtected(checkout, fetch: answering(200))
        XCTAssertFalse(ok)
    }

    func testANetworkFailureNeverStopsCheckout() async {
        let offline = await passwordProtected(checkout, fetch: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertFalse(offline)
    }

    private let hosts: Set<String> = ["shop.myshopify.com", "www.shop.com"]

    func testTheStoresOwnPagesAreStorePages() {
        for page in [
            "https://shop.myshopify.com/", "https://www.shop.com", "https://www.shop.com/products/pants?variant=1",
            "https://shop.myshopify.com/cart", "https://shop.myshopify.com/password", "https://WWW.SHOP.COM/collections/all",
        ] { XCTAssertTrue(isStorePage(URL(string: page)!, storeHosts: hosts), page) }
    }

    func testCheckoutAndOtherDomainsAreNot() {
        for page in [
            "https://shop.myshopify.com/checkouts/cn/abc/en-us", "https://shop.myshopify.com/checkouts/cn/abc/thank-you",
            "https://shop.myshopify.com/cart/c/abc?key=k", "https://shop.myshopify.com/123456/checkouts/cn/abc",
            "https://www.shop.com/policies/refund-policy", "https://www.paypal.com/checkoutnow", "https://shop.app/pay",
            "https://help.shopify.com/en/manual", "mailto:help@shop.com",
        ] { XCTAssertFalse(isStorePage(URL(string: page)!, storeHosts: hosts), page) }
    }
}
