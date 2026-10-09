import XCTest
@testable import ArgonStorefront

/// Answers every request with `body` and `status` (or fails it with `failure`), so nothing touches the network.
final class StubProtocol: URLProtocol {
    static var body = ""
    static var status = 200
    static var failure: URLError? = nil
    static var lastRequest: URLRequest? = nil

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubProtocol.lastRequest = request
        if let failure = StubProtocol.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: StubProtocol.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(StubProtocol.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The low-level client: what it sends, and how HTTP and transport failures come out.
final class StorefrontTests: XCTestCase {
    override func tearDown() {
        StubProtocol.failure = nil
        StubProtocol.lastRequest = nil
        super.tearDown()
    }

    private func query(_ body: String, status: Int = 200, token: String = "") async throws -> Data {
        StubProtocol.body = body
        StubProtocol.status = status
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let storefront = Storefront(
            domain: "shop.test",
            token: token,
            apiVersion: "2026-10",
            loadDocument: { name in "query \(name) { shop { name } }" },
            session: URLSession(configuration: configuration)
        )
        return try await storefront.query("Q", ["handle": "a"])
    }

    /// The ArgonAPIError the query and its decoding throw, or nil.
    private func failure(_ body: String, status: Int = 200) async -> ArgonAPIError? {
        do {
            let data = try await query(body, status: status)
            _ = try decodeResponse([String: Int].self, from: data, operation: "Q")
            return nil
        } catch {
            return error as? ArgonAPIError
        }
    }

    func testPostsTheDocumentWithItsVariablesAndToken() async throws {
        let data = try await query(#"{"data":{"a":1}}"#, token: "public-token")
        XCTAssertEqual(try decodeResponse([String: Int].self, from: data, operation: "Q"), ["a": 1])
        let request = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://shop.test/api/2026-10/graphql.json")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Shopify-Storefront-Access-Token"), "public-token")
    }

    func testHttpFailureIsItsStatus() async {
        let failed = await failure("service unavailable", status: 503)
        guard case let .http(status)? = failed else { return XCTFail("\(String(describing: failed))") }
        XCTAssertEqual(status, 503)
        XCTAssertEqual(failed?.localizedDescription, "HTTP 503")
    }

    func testNoAnswerIsANetworkError() async {
        StubProtocol.failure = URLError(.notConnectedToInternet)
        let failed = await failure("")
        guard case let .network(error)? = failed else { return XCTFail("\(String(describing: failed))") }
        XCTAssertEqual(error.code, .notConnectedToInternet)
    }

    func testGraphqlErrorsAreAGraphqlError() async {
        let failed = await failure(#"{"errors":[{"message":"boom"}]}"#)
        guard case let .graphql(messages)? = failed else { return XCTFail("\(String(describing: failed))") }
        XCTAssertEqual(messages, ["boom"])
    }

    func testAnUnparseableBodyIsADecodingError() async {
        let failed = await failure("<html>")
        guard case let .decoding(operation, _)? = failed else { return XCTFail("\(String(describing: failed))") }
        XCTAssertEqual(operation, "Q")
        XCTAssertEqual(failed?.localizedDescription, "Invalid response")
    }

    func testVariablesThatArentJsonAreRefusedNotCrashed() {
        XCTAssertThrowsError(try graphQLBody("query Q { shop { name } }", ["bad": Date()]))
    }
}
