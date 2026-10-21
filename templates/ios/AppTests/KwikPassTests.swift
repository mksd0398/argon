import XCTest
@testable import ArgonStorefront

final class KwikPassTests: XCTestCase {
    private let suite = UUID().uuidString
    /// The device's Keychain: a new store over it is the app after a restart.
    private var keychain: [String: Data] = [:]
    /// What the store asked GoKwik, in order: method, path after the base, JSON body.
    private var calls: [(method: String, path: String, body: [String: Any])] = []
    private var paths: [String] { calls.map { $0.path } }
    /// GoKwik's answer by path: status and the envelope's `data` (nil answers `{}`).
    private var replies: [String: (Int, Any?)] = [:]

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    @MainActor
    private func store() -> KwikPassStore {
        KwikPassStore(
            environment: .sandbox,
            merchantId: "mid1",
            send: { request in
                let path = String(request.url!.absoluteString.dropFirst(GoKwikEnvironment.sandbox.apiBase.count))
                let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                self.calls.append((request.httpMethod ?? "GET", path, body))
                let (status, data) = self.replies[path] ?? (200, nil)
                let envelope: [String: Any] = data.map { ["success": true, "data": $0] } ?? ["success": true]
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (try JSONSerialization.data(withJSONObject: envelope), response)
            },
            read: { self.keychain[$0] },
            write: { key, value in self.keychain[key] = value },
            defaults: UserDefaults(suiteName: suite)!,
            deviceId: { "device1" }
        )
    }

    /// A store that sent the OTP to 9876543210, with GoKwik's OTP verify answering `verify`.
    @MainActor
    private func verifying(_ verify: [String: Any]) async throws -> KwikPassStore {
        replies["kp/api/v1/auth/browser"] = (200, ["requestId": "req1", "token": "browser1"])
        replies["kp/api/v1/auth/otp/send"] = (200, ["interval": 45])
        var answer: [String: Any] = ["token": "gk1", "coreToken": "core1", "kpToken": "kp1"]
        answer.merge(verify) { $1 }
        replies["kp/api/v2/auth/otp/verify"] = (200, answer)
        let s = store()
        // the app at launch: nothing stored yet
        await s.load()
        let interval = try await s.sendOtp("9876543210")
        XCTAssertEqual(interval, 45)
        return s
    }

    func testBranches() {
        XCTAssertEqual(kwikPassVerifyBranch(["authRequired": true, "email": "a@x.in"]), .emailOtp("a@x.in"))
        XCTAssertEqual(kwikPassVerifyBranch(["email": "a@x.in", "state": "ENABLED"]), .knownEmail("a@x.in"))
        XCTAssertEqual(kwikPassVerifyBranch(["multipleEmail": "a@x.in, b@x.in"]), .chooseEmail(["a@x.in", "b@x.in"]))
        XCTAssertEqual(kwikPassVerifyBranch(["emailRequired": true]), .enterEmail)
        XCTAssertEqual(kwikPassVerifyBranch(["authRequired": true]), .enterEmail, "auth without an email: one is asked for")
    }

    func testIndianMobile() {
        XCTAssertEqual(indianMobile("98765 43210"), "9876543210")
        XCTAssertEqual(indianMobile("+91 98765-43210"), "9876543210")
        XCTAssertEqual(indianMobile("09876543210"), "9876543210")
        XCTAssertNil(indianMobile("1234567890"), "Indian mobiles start with 6 to 9")
        XCTAssertNil(indianMobile("98765"))
    }

    @MainActor
    func testKnownEmailSignsInThroughMultipassAndIsKept() async throws {
        let s = try await verifying(["email": "ada@x.in", "shopifyCustomerId": 42, "state": "ENABLED"])
        replies["kp/api/v2/customer/shopify/multipass"] = (200, ["email": "ada@x.in", "shopifyCustomerId": "42"])
        let step = try await s.verifyOtp("1234")
        XCTAssertEqual(step, .done(newUser: false))
        XCTAssertEqual(paths, ["kp/api/v1/auth/browser", "kp/api/v1/auth/otp/send", "kp/api/v2/auth/otp/verify", "kp/api/v2/customer/shopify/multipass"])
        XCTAssertEqual(calls[2].body["otp"] as? Int, 1234, "the phone OTP goes as a number")
        XCTAssertEqual(calls[2].body["deviceId"] as? String, "device1")
        XCTAssertEqual(calls[3].body["state"] as? String, "ENABLED")
        XCTAssertEqual(calls[3].body["id"] as? String, "42")
        XCTAssertTrue(s.signedIn)
        XCTAssertEqual(s.session?.coreToken, "core1")
        XCTAssertEqual(s.contact?.phone, "+919876543210")

        // the app again: the stored session, still valid
        replies["kp/api/v1/auth/validate-token"] = (200, ["token": ["isValid": true, "isExpired": false]])
        let again = store()
        await again.load()
        XCTAssertTrue(again.signedIn)
        XCTAssertEqual(again.session?.email, "ada@x.in")
    }

    @MainActor
    func testAuthRequiredSendsAnEmailOtpFirst() async throws {
        let s = try await verifying(["authRequired": true, "email": "ada@x.in"])
        let step = try await s.verifyOtp("123456")
        XCTAssertEqual(step, .emailOtp("ada@x.in"))
        XCTAssertEqual(paths.last, "kp/api/v1/auth/email-otp/send")
        XCTAssertFalse(s.signedIn)

        replies["kp/api/v1/auth/email-otp/verify"] = (200, ["email": "ada@x.in", "shopifyCustomerId": "7"])
        let done = try await s.verifyEmailOtp("ada@x.in", code: "0042")
        XCTAssertEqual(done, .done(newUser: false))
        XCTAssertEqual(calls.last?.body["otp"] as? String, "0042", "the email OTP goes as text")
        XCTAssertTrue(s.signedIn)
    }

    @MainActor
    func testNewPhoneNewEmailIsCreatedBySession() async throws {
        let s = try await verifying(["emailRequired": true])
        let next = try await s.verifyOtp("1234")
        XCTAssertEqual(next, .enterEmail)
        replies["kp/api/v1/disposable-email/validate/new@x.in"] = (200, ["valid": true])
        replies["kp/api/v1/customer/shopify-session"] = (200, ["isNewUser": true, "shopifyCustomerId": "99"])
        let created = try await s.submitEmail("new@x.in")
        XCTAssertEqual(created, .done(newUser: true))
        XCTAssertEqual(s.session?.shopifyCustomerId, "99")
        XCTAssertNotNil(keychain["kwikpass"], "kept, unlike GoKwik's SDK")
    }

    @MainActor
    func testNewPhoneExistingEmailHasToProveIt() async throws {
        let s = try await verifying(["emailRequired": true])
        _ = try await s.verifyOtp("1234")
        replies["kp/api/v1/disposable-email/validate/old@x.in"] = (200, ["valid": true])
        replies["kp/api/v1/customer/shopify-session"] = (200, ["isNewUser": false])
        let known = try await s.submitEmail("old@x.in")
        XCTAssertEqual(known, .emailOtp("old@x.in"))
        XCTAssertEqual(paths.last, "kp/api/v1/auth/email-otp/send")
        XCTAssertFalse(s.signedIn)
    }

    @MainActor
    func testADisposableEmailIsRefused() async throws {
        let s = try await verifying(["emailRequired": true])
        _ = try await s.verifyOtp("1234")
        let error = await thrownError { try await s.submitEmail("x@mailinator.com") }
        XCTAssertEqual((error as? KwikPassError)?.message, "Entered email is not valid")
    }

    @MainActor
    func testAnExpiredTokenSignsOutAtLaunchButNoNetworkKeepsTheSession() async throws {
        let s = try await verifying(["email": "ada@x.in", "shopifyCustomerId": "42"])
        _ = try await s.verifyOtp("1234")
        XCTAssertTrue(s.signedIn)

        replies["kp/api/v1/auth/validate-token"] = (500, nil)
        let offline = store()
        await offline.load()
        XCTAssertTrue(offline.signedIn, "GoKwik not reached: the session stays")

        replies["kp/api/v1/auth/validate-token"] = (200, ["token": ["isValid": true, "isExpired": true]])
        let expired = store()
        await expired.load()
        XCTAssertFalse(expired.signedIn)
        XCTAssertNil(keychain["kwikpass"])
    }

    func testHeadersCarryTheSession() {
        var session = KwikPassSession()
        XCTAssertNil(kwikPassHeaders(merchantId: "m", session: session)["gk-access-token"])
        session.token = "gk1"
        session.coreToken = "core1"
        session.requestId = "req1"
        session.authorization = "browser1"
        let headers = kwikPassHeaders(merchantId: "m", session: session)
        XCTAssertEqual(headers["gk-merchant-id"], "m")
        XCTAssertEqual(headers["kp-integration-type"], "APP_MAKER")
        XCTAssertEqual(headers["sdk-platform"], "argon-ios")
        XCTAssertEqual(headers["gk-access-token"], "gk1")
        XCTAssertEqual(headers["checkout-access-token"], "core1")
        XCTAssertEqual(headers["kp-request-id"], "req1")
        XCTAssertEqual(headers["Authorization"], "browser1", "no Bearer")
    }
}
