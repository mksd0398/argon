import XCTest
@testable import App

/// Answers every request with `body` and `status`, so nothing touches the network.
final class StubProtocol: URLProtocol {
    static var body = ""
    static var status = 200

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: StubProtocol.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(StubProtocol.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class StorefrontTests: XCTestCase {
    private func query(_ body: String, status: Int = 200) async throws -> [String: Any] {
        StubProtocol.body = body
        StubProtocol.status = status
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let storefront = Storefront(
            domain: "shop.test",
            token: "",
            apiVersion: "2026-10",
            loadDocument: { _ in "query Q { shop { name } }" },
            session: URLSession(configuration: configuration)
        )
        return try await storefront.query("Q")
    }

    /// The StorefrontException `query` throws, or nil when it succeeds or throws something else.
    private func failure(_ body: String, status: Int = 200) async -> StorefrontException? {
        do {
            _ = try await query(body, status: status)
            return nil
        } catch {
            return error as? StorefrontException
        }
    }

    func testReturnsData() async throws {
        let data = try await query(#"{"data":{"a":1}}"#)
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data["a"] as? Int, 1)
    }

    func testUnparseableBodyIsAStorefrontException() async throws {
        let failed = await failure("<html>")
        let e = try XCTUnwrap(failed)
        XCTAssertEqual(e.messages, ["Invalid response"])
        XCTAssertEqual(e.status, 200)
        XCTAssertFalse(e.isGraphQL)
    }

    func testNonObjectBodyIsAStorefrontException() async throws {
        let failed = await failure("[1,2]")
        let e = try XCTUnwrap(failed)
        XCTAssertEqual(e.messages, ["Invalid response"])
    }

    func testGraphqlErrorsAreAStorefrontException() async throws {
        let failed = await failure(#"{"errors":[{"message":"boom"}]}"#)
        let e = try XCTUnwrap(failed)
        XCTAssertEqual(e.messages, ["boom"])
        XCTAssertTrue(e.isGraphQL, "a 200 carrying errors is a GraphQL failure")
    }

    func testHttpFailureIsNotGraphql() async throws {
        let failed = await failure("service unavailable", status: 503)
        let e = try XCTUnwrap(failed)
        XCTAssertEqual(e.messages, ["HTTP 503"])
        XCTAssertEqual(e.status, 503)
        XCTAssertFalse(e.isGraphQL)
    }
}
