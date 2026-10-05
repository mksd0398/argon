import XCTest
@testable import ArgonStorefront

/// Answers every request through `reply`, so nothing touches the network, and records each one with its body.
final class AuthStub: URLProtocol {
    static var reply: (URLRequest) throws -> (Int, String) = { _ in (404, "") }
    private static var recorded: [URLRequest] = []
    private static let lock = NSLock()

    /// Every request so far, in order (requests arrive on URLSession's threads).
    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        recorded = []
        reply = { _ in (404, "") }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession hands a protocol the body as a stream
        var sent = request
        if sent.httpBody == nil, let stream = request.httpBodyStream { sent.httpBody = AuthStub.read(stream) }
        AuthStub.lock.lock()
        AuthStub.recorded.append(sent)
        let reply = AuthStub.reply
        AuthStub.lock.unlock()
        do {
            let (status, body) = try reply(sent)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        let size = 4096
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: size)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class AuthStoreTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    /// The device's Keychain: a new store over it is the app after a restart.
    private var keychain: [String: Data] = [:]

    /// The app's UserDefaults suite, which (unlike the Keychain) goes when the app is deleted.
    private var suite = UUID().uuidString

    /// The shop's OpenID discovery document.
    private var discovery = #"{"authorization_endpoint":"https://shop.test/authentication/oauth/authorize","token_endpoint":"https://shop.test/authentication/oauth/token","end_session_endpoint":"https://shop.test/authentication/logout"}"#

    /// The token endpoint's answer to a form: status and JSON body.
    private var tokenReply: ([String: String]) throws -> (Int, String) = { _ in (500, "") }

    /// The Customer Account API's answer, by the `Authorization` header it got.
    private var graphqlReply: (String?) -> (Int, String) = { _ in (200, #"{"data":{"customer":{"firstName":"Ada"}}}"#) }

    /// The id_token's nonce; nil means "echo the one the store sent".
    private var idTokenNonce: String? = nil
    private var sentNonce = ""

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStub.self]
        return URLSession(configuration: configuration)
    }()

    override func setUp() {
        super.setUp()
        AuthStub.reset()
        tokenReply = { _ in (200, self.tokens("a1", "r1")) }
        AuthStub.reply = { request in try self.route(request) }
    }

    override func tearDown() {
        AuthStub.reset()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private var requests: [URLRequest] { AuthStub.requests }
    private var paths: [String] { requests.map { $0.url?.path ?? "" } }

    private func route(_ request: URLRequest) throws -> (Int, String) {
        switch request.url?.path ?? "" {
        case "/.well-known/openid-configuration":
            return (200, discovery)
        case "/.well-known/customer-account-api":
            return (200, #"{"graphql_api":"https://shop.test/customer/api/2026-10/graphql"}"#)
        case "/authentication/oauth/token":
            return try tokenReply(form(request))
        case "/customer/api/2026-10/graphql":
            return graphqlReply(request.value(forHTTPHeaderField: "Authorization"))
        case "/authentication/logout":
            return (200, "")
        default:
            return (404, "")
        }
    }

    private func tokens(_ access: String, _ refresh: String?, expiresIn: Int = 3600) -> String {
        var json: [String: Any] = ["access_token": access, "id_token": idToken(idTokenNonce ?? sentNonce), "expires_in": expiresIn]
        if let refresh = refresh { json["refresh_token"] = refresh }
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func idToken(_ nonce: String) -> String {
        base64Url(Data(#"{"alg":"RS256"}"#.utf8)) + "." + base64Url(Data(#"{"nonce":"\#(nonce)","sub":"1"}"#.utf8)) + ".sig"
    }

    /// The form fields of a token request.
    private func form(_ request: URLRequest) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in String(decoding: request.httpBody ?? Data(), as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let name = String(parts[0]).removingPercentEncoding else { continue }
            fields[name] = String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        }
        return fields
    }

    private func query(_ url: URL) -> [String: String] {
        var fields: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { fields[item.name] = item.value }
        return fields
    }

    /// The error `body` throws; nil when it doesn't throw.
    @MainActor
    private func thrown<T>(_ body: () async throws -> T) async -> Error? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error
        }
    }

    /// A store over this test's Keychain. `open` is the browser: by default the shopper closes it.
    @MainActor
    private func store(
        read: ((String) async -> Data?)? = nil,
        open: @escaping (URL) async throws -> URL = { _ in throw CancellationError() }
    ) -> AuthStore {
        AuthStore(
            domain: "shop.test",
            clientId: "client-1",
            redirectUri: "shop.1.app://callback",
            loadDocument: { name in "query \(name) { customer { firstName } }" },
            open: open,
            session: session,
            read: read ?? { account in self.keychain[account] },
            write: { account, data in self.keychain[account] = data },
            defaults: UserDefaults(suiteName: suite)!,
            now: { self.clock }
        )
    }

    /// Starts a sign-in and returns the authorize URL's query.
    @MainActor
    private func start(_ s: AuthStore) async throws -> [String: String] {
        let url = try await s.start()
        let fields = query(url)
        sentNonce = fields["nonce"] ?? ""
        return fields
    }

    @MainActor
    private func signedIn(_ s: AuthStore) async throws -> AuthStore {
        let state = try await start(s)["state"] ?? ""
        try await s.handleCallback("shop.1.app://callback?code=c1&state=\(state)")
        return s
    }

    @MainActor
    func testSignInSurvivesProcessDeathAndExchangesTheCode() async throws {
        let url = try await store().start()
        XCTAssertEqual(url.path, "/authentication/oauth/authorize")
        let authorize = query(url)
        sentNonce = authorize["nonce"] ?? ""
        XCTAssertEqual(authorize["scope"], "openid email customer-account-api:full")
        XCTAssertEqual(authorize["client_id"], "client-1")
        XCTAssertEqual(authorize["response_type"], "code")
        XCTAssertEqual(authorize["redirect_uri"], "shop.1.app://callback")
        XCTAssertEqual(authorize["code_challenge_method"], "S256")
        let state = try XCTUnwrap(authorize["state"])

        // the app is killed while the browser is open; the callback reaches a new process
        let s = store()
        XCTAssertFalse(s.signedIn)
        try await s.handleCallback("shop.1.app://callback?code=c1&state=\(state)")
        XCTAssertTrue(s.signedIn)
        let token = try await s.validAccessToken()
        XCTAssertEqual(token, "a1")

        let exchange = try XCTUnwrap(requests.last(where: { $0.url?.path == "/authentication/oauth/token" }))
        let form = self.form(exchange)
        XCTAssertEqual(form["grant_type"], "authorization_code")
        XCTAssertEqual(form["client_id"], "client-1")
        XCTAssertEqual(form["redirect_uri"], "shop.1.app://callback")
        XCTAssertEqual(form["code"], "c1")
        XCTAssertEqual(Pkce.challenge(form["code_verifier"] ?? ""), authorize["code_challenge"])

        // the tokens outlive the process, in the Keychain; the pending sign-in is gone
        XCTAssertEqual(Array(keychain.keys), ["tokens"])
        let restarted = try await store().validAccessToken()
        XCTAssertEqual(restarted, "a1")
    }

    @MainActor
    func testAStateMismatchThrowsAndTheRealCallbackStillWorks() async throws {
        let s = store()
        let state = try await start(s)["state"] ?? ""
        let forged = await thrown { try await s.handleCallback("shop.1.app://callback?code=c1&state=forged") }
        XCTAssertTrue(forged is AuthException)
        XCTAssertFalse(s.signedIn)
        XCTAssertFalse(paths.contains("/authentication/oauth/token"), "no code is exchanged")
        let otherApp = await thrown { try await s.handleCallback("other.app://callback?code=c1&state=\(state)") }
        XCTAssertTrue(otherApp is AuthException, "the right state on another scheme is still rejected")
        let otherHost = await thrown { try await s.handleCallback("shop.1.app://evil?code=c1&state=\(state)") }
        XCTAssertTrue(otherHost is AuthException, "the right state on another host is still rejected")
        XCTAssertFalse(paths.contains("/authentication/oauth/token"))

        // the forgeries didn't end the sign-in in progress
        try await s.handleCallback("shop.1.app://callback?code=c1&state=\(state)")
        XCTAssertTrue(s.signedIn)
    }

    @MainActor
    func testACallbackWithNoSignInInProgressIsRejected() async throws {
        let s = store()
        let rejected = await thrown { try await s.handleCallback("shop.1.app://callback?code=c1&state=") }
        XCTAssertTrue(rejected is AuthException)
        XCTAssertEqual(paths, [])
    }

    @MainActor
    func testAUsedCallbackCantBeReplayed() async throws {
        let s = store()
        let state = try await start(s)["state"] ?? ""
        let callback = "shop.1.app://callback?code=c1&state=\(state)"
        try await s.handleCallback(callback)
        let replayed = await thrown { try await s.handleCallback(callback) }
        XCTAssertTrue(replayed is AuthException)
        XCTAssertEqual(paths.filter { $0 == "/authentication/oauth/token" }.count, 1)
        XCTAssertTrue(s.signedIn, "the replay doesn't end the session")
    }

    @MainActor
    func testAnInsecureTokenEndpointStopsSignInBeforeTheBrowser() async throws {
        discovery = discovery.replacingOccurrences(of: "https://shop.test/authentication/oauth/token", with: "http://shop.test/authentication/oauth/token")
        let s = store()
        let failed = await thrown { try await s.start() }
        XCTAssertTrue(failed is AuthException)
        XCTAssertNil(keychain["pending"], "no sign-in in progress")
        XCTAssertFalse(paths.contains("/authentication/oauth/token"), "nothing is sent to it")
    }

    @MainActor
    func testAReinstallStartsSignedOut() async throws {
        _ = try await signedIn(store())
        XCTAssertEqual(Array(keychain.keys), ["tokens"])

        // the app is deleted and installed again: its UserDefaults go, the Keychain stays
        let firstInstall = suite
        defer { UserDefaults.standard.removePersistentDomain(forName: firstInstall) }
        suite = UUID().uuidString
        let reinstalled = store()
        await reinstalled.load()
        XCTAssertFalse(reinstalled.signedIn)
        XCTAssertEqual(keychain, [:], "the last install's session is gone from the Keychain")

        // only the first launch forgets: this install's session outlives a restart
        _ = try await signedIn(reinstalled)
        let restarted = store()
        await restarted.load()
        XCTAssertTrue(restarted.signedIn)
    }

    @MainActor
    func testANonceMismatchIsRejected() async throws {
        idTokenNonce = "replayed"
        let s = store()
        let state = try await start(s)["state"] ?? ""
        let rejected = await thrown { try await s.handleCallback("shop.1.app://callback?code=c1&state=\(state)") }
        XCTAssertTrue(rejected is AuthException)
        XCTAssertFalse(s.signedIn)
        let token = try await s.validAccessToken()
        XCTAssertNil(token)
    }

    @MainActor
    func testAnErrorCallbackEndsTheAttemptWithoutACrash() async throws {
        let s = store()
        let state = try await start(s)["state"] ?? ""
        let failed = await thrown {
            try await s.handleCallback("shop.1.app://callback?error=access_denied&error_description=Cancelled+by+user&state=\(state)")
        }
        XCTAssertTrue(failed is AuthException)
        XCTAssertEqual(s.signInError, "Cancelled by user")
        XCTAssertFalse(s.signedIn)
        XCTAssertFalse(paths.contains("/authentication/oauth/token"))
    }

    @MainActor
    func testAnExpiringTokenIsRefreshed() async throws {
        let s = try await signedIn(store())
        tokenReply = { _ in (200, self.tokens("a2", "r2")) }
        clock = clock.addingTimeInterval(3600 - 30) // 30 s left: inside the 60 s margin
        let token = try await s.validAccessToken()
        XCTAssertEqual(token, "a2")
        let refresh = try XCTUnwrap(requests.last)
        XCTAssertEqual(form(refresh), ["grant_type": "refresh_token", "client_id": "client-1", "refresh_token": "r1"])
        XCTAssertTrue(s.signedIn)
    }

    @MainActor
    func testARefusedRefreshSignsOut() async throws {
        let s = try await signedIn(store())
        tokenReply = { _ in (400, #"{"error":"invalid_grant"}"#) }
        clock = clock.addingTimeInterval(3600)
        let token = try await s.validAccessToken()
        XCTAssertNil(token)
        XCTAssertFalse(s.signedIn)
        let restarted = try await store().validAccessToken()
        XCTAssertNil(restarted, "signed out in the Keychain too")
    }

    @MainActor
    func testAnUnreachableOrFailingTokenEndpointKeepsTheSession() async throws {
        let s = try await signedIn(store())
        clock = clock.addingTimeInterval(3600)
        tokenReply = { _ in throw URLError(.notConnectedToInternet) }
        let offline = await thrown { try await s.validAccessToken() }
        XCTAssertTrue(offline is URLError, String(describing: offline))
        XCTAssertTrue(s.signedIn)
        // only 400 and 401 are refusals: rate limits and server errors aren't
        for status in [429, 503] {
            tokenReply = { _ in (status, #"{"error":"slow_down"}"#) }
            let failed = await thrown { try await s.validAccessToken() }
            XCTAssertEqual((failed as? AuthException)?.status, status)
            XCTAssertTrue(s.signedIn, "\(status) keeps the session")
        }
    }

    @MainActor
    func testConcurrentCallersShareOneRefresh() async throws {
        let s = try await signedIn(store())
        // the token endpoint answers only after a while: both callers are in flight by then
        tokenReply = { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return (200, self.tokens("a2", "r2"))
        }
        clock = clock.addingTimeInterval(3600)
        async let first = s.validAccessToken()
        async let second = s.validAccessToken()
        let a = try await first
        let b = try await second
        XCTAssertEqual([a, b], ["a2", "a2"])
        let refreshes = requests.filter { $0.url?.path == "/authentication/oauth/token" && form($0)["grant_type"] == "refresh_token" }
        XCTAssertEqual(refreshes.count, 1)
    }

    @MainActor
    func testACallerCancelledMidRefreshKeepsTheRotatedToken() async throws {
        let s = try await signedIn(store())
        let gate = DispatchSemaphore(value: 0)
        tokenReply = { _ in
            _ = gate.wait(timeout: .now() + 5)
            return (200, self.tokens("a2", "r2"))
        }
        clock = clock.addingTimeInterval(3600)
        let caller = Task { try await s.validAccessToken() }
        let isRefresh: (URLRequest) -> Bool = { $0.url?.path == "/authentication/oauth/token" && self.form($0)["grant_type"] == "refresh_token" }
        var waited = 0
        while !requests.contains(where: isRefresh), waited < 500 {
            try await Task.sleep(nanoseconds: 10_000_000)
            waited += 1
        }
        // the screen goes away while Shopify is rotating r1 into r2
        caller.cancel()
        gate.signal()
        _ = try? await caller.value
        XCTAssertTrue(s.signedIn)

        // r1 is spent: the next refresh, after a restart too, must send r2
        let restarted = store()
        tokenReply = { _ in (200, self.tokens("a3", "r3")) }
        clock = clock.addingTimeInterval(3600)
        let token = try await restarted.validAccessToken()
        XCTAssertEqual(token, "a3")
        let refresh = try XCTUnwrap(requests.last)
        XCTAssertEqual(form(refresh)["refresh_token"], "r2")
    }

    @MainActor
    func testUnreadableStoredTokensMeanSignedOut() async throws {
        _ = try await signedIn(store())
        // what the Keychain hands back can't be read as a session
        let s = store(read: { _ in Data("not a session".utf8) })
        await s.load()
        XCTAssertFalse(s.signedIn)
        let token = try await s.validAccessToken()
        XCTAssertNil(token)
    }

    @MainActor
    func testCustomerQuerySendsTheRawTokenAndRetriesOnceAfter401() async throws {
        let s = try await signedIn(store())
        graphqlReply = { auth in auth == "a1" ? (401, "") : (200, #"{"data":{"customer":{"firstName":"Ada"}}}"#) }
        tokenReply = { _ in (200, self.tokens("a2", "r2")) }
        let data = try await s.customerQuery("Customer")
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data.obj("customer")?.str("firstName"), "Ada")
        let graphql = requests.filter { $0.url?.path == "/customer/api/2026-10/graphql" }
        XCTAssertEqual(graphql.map { $0.value(forHTTPHeaderField: "Authorization") }, ["a1", "a2"])
    }

    @MainActor
    func testA401AfterRefreshSignsOut() async throws {
        let s = try await signedIn(store())
        graphqlReply = { _ in (401, "") }
        tokenReply = { _ in (200, self.tokens("a2", "r2")) }
        let failed = await thrown { try await s.customerQuery("Customer") }
        XCTAssertTrue(failed is StorefrontException)
        XCTAssertFalse(s.signedIn)
    }

    @MainActor
    func testSignOutCallsLogoutWithTheIdTokenAndForgetsTheTokens() async throws {
        let s = try await signedIn(store())
        await s.signOut()
        XCTAssertFalse(s.signedIn)
        let logout = try XCTUnwrap(requests.last?.url)
        XCTAssertEqual(logout.path, "/authentication/logout")
        XCTAssertEqual(query(logout)["id_token_hint"], idToken(sentNonce))
        let restarted = try await store().validAccessToken()
        XCTAssertNil(restarted)
    }

    // iOS: the browser session hands the callback straight back to signIn().

    @MainActor
    func testSignInRunsTheBrowserAndExchangesItsCallback() async throws {
        let s = store(open: { url in
            let authorize = self.query(url)
            self.sentNonce = authorize["nonce"] ?? ""
            return URL(string: "shop.1.app://callback?code=c1&state=\(authorize["state"] ?? "")")!
        })
        try await s.signIn()
        XCTAssertTrue(s.signedIn)
        XCTAssertNil(s.signInError)
        XCTAssertEqual(Array(keychain.keys), ["tokens"])
    }

    @MainActor
    func testClosingTheBrowserOrARefusalEndsTheAttemptQuietly() async throws {
        // the shopper closes the sheet: no error, nothing pending, no code exchanged
        try await store().signIn()
        XCTAssertNil(keychain["pending"])
        XCTAssertFalse(paths.contains("/authentication/oauth/token"))

        // Shopify answers with an error: shown above Sign in, not thrown
        let s = store(open: { url in
            URL(string: "shop.1.app://callback?error=access_denied&state=\(self.query(url)["state"] ?? "")")!
        })
        try await s.signIn()
        XCTAssertEqual(s.signInError, "Sign-in was cancelled")
        XCTAssertFalse(s.signedIn)
        XCTAssertNil(keychain["pending"])
    }
}
