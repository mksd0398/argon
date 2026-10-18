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
}
