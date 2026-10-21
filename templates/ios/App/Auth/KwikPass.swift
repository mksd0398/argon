import Foundation
import Observation
import os
import UIKit

// KwikPass (`LOGIN=kwikpass`): GoKwik's phone-OTP sign-in, in place of Shopify's customer accounts. GoKwik's backend finds or
// creates the Shopify customer; the app keeps GoKwik's tokens and who the shopper is. There is no Customer Account API token
// in it, so the account pages that need one stay away. The protocol is the one of GoKwik's Flutter SDK 1.0.37.

private let kwikPassLog = Logger(subsystem: "app.storefront", category: "KwikPass")

/// A KwikPass call failed: GoKwik's message, meant for the shopper. `status` is the HTTP status when GoKwik answered.
struct KwikPassError: LocalizedError {
    let message: String
    var status: Int? = nil

    var errorDescription: String? { message }
}

/// The KwikPass session: GoKwik's tokens and the shopper. Signed in once it names the Shopify customer, the phone and
/// the email (`complete`); before that it is a sign-in under way.
struct KwikPassSession: Codable, Equatable {
    /// `gk-access-token`
    var token = ""
    /// `checkout-access-token`, which checkout takes as `gk_token`
    var coreToken = ""
    var kpToken = ""
    var requestId = ""
    /// the browser token, sent as `Authorization`
    var authorization = ""
    /// 10 digits, as typed
    var phone = ""
    var email = ""
    var shopifyCustomerId = ""

    var complete: Bool { !shopifyCustomerId.isEmpty && !phone.isEmpty && !email.isEmpty }
}

/// The 10-digit Indian mobile number in `text` (spaces, a +91 or a leading 0 allowed); nil for anything else.
func indianMobile(_ text: String) -> String? {
    var digits = text.filter { $0.isASCII && $0.isNumber }
    if digits.count == 12, digits.hasPrefix("91") { digits.removeFirst(2) }
    if digits.count == 11, digits.hasPrefix("0") { digits.removeFirst() }
    guard digits.count == 10, let first = digits.first, "6789".contains(first) else { return nil }
    return digits
}

/// Where a verified phone goes next, from OTP verify's `data`.
enum KwikPassVerifyBranch: Equatable {
    /// The phone has an account with this email, not yet proven: an OTP to the email first.
    case emailOtp(String)
    /// The account's email is known: GoKwik signs in to it (multipass).
    case knownEmail(String)
    /// Several accounts share the phone: the shopper picks one.
    case chooseEmail([String])
    /// A new phone: the shopper gives an email.
    case enterEmail
}

func kwikPassVerifyBranch(_ data: [String: Any]) -> KwikPassVerifyBranch {
    let email = (data["email"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    if data["authRequired"] as? Bool == true, !email.isEmpty { return .emailOtp(email) }
    if !email.isEmpty { return .knownEmail(email) }
    let several = ((data["multipleEmail"] as? String) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    return several.isEmpty ? .enterEmail : .chooseEmail(several)
}

/// What the sign-in screens show next.
enum KwikPassStep: Equatable {
    /// An OTP went to this email: verify it (`verifyEmailOtp`).
    case emailOtp(String)
    case chooseEmail([String])
    case enterEmail
    /// Signed in; `newUser` when GoKwik created the customer just now.
    case done(newUser: Bool)
}

/// A JSON id GoKwik may send as a number or a string.
private func idText(_ value: Any?) -> String {
    if let text = value as? String { return text }
    if let number = value as? NSNumber { return number.stringValue }
    return ""
}

/// The KwikPass session and its sign-in. The session is kept through `read`/`write` (the Keychain), only once complete;
/// `send` is the network. `defaults` remembers that this install has run: the Keychain outlives the app.
@MainActor
@Observable
final class KwikPassStore {
    /// The signed-in session; nil when signed out.
    private(set) var session: KwikPassSession? = nil

    var signedIn: Bool { session?.complete == true }

    /// The shopper on the cart, so Shopify's checkout is prefilled: their email and phone (E.164).
    var contact: (email: String, phone: String)? {
        guard let session = session, session.complete else { return nil }
        return (session.email, "+91" + session.phone)
    }

    private static let sessionKey = "kwikpass"
    private static let installedKey = "argon.kwikpass.installed"

    private let base: String
    private let merchantId: String
    private let send: (URLRequest) async throws -> (Data, URLResponse)
    private let read: (String) async -> Data?
    private let write: (String, Data?) async -> Void
    private let defaults: UserDefaults
    private let deviceId: @MainActor () -> String
    private var loaded = false
    /// The sign-in under way: its tokens, then the phone, until the shopper is known.
    private var pending = KwikPassSession()

    init(
        environment: GoKwikEnvironment,
        merchantId: String,
        send: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) },
        read: @escaping (String) async -> Data? = Keychain.load,
        write: @escaping (String, Data?) async -> Void = Keychain.save,
        defaults: UserDefaults = .standard,
        deviceId: @escaping @MainActor () -> String = { UIDevice.current.identifierForVendor?.uuidString ?? "" }
    ) {
        base = environment.apiBase
        self.merchantId = merchantId
        self.send = send
        self.read = read
        self.write = write
        self.defaults = defaults
        self.deviceId = deviceId
    }

    /// Reads the stored session, once, then asks GoKwik whether its token still holds: an invalid or expired one signs out;
    /// not reaching GoKwik keeps the session.
    func load() async {
        guard !loaded else { return }
        loaded = true
        if !defaults.bool(forKey: Self.installedKey) {
            await write(Self.sessionKey, nil)
            defaults.set(true, forKey: Self.installedKey)
        }
        guard let data = await read(Self.sessionKey),
              let stored = try? JSONDecoder().decode(KwikPassSession.self, from: data), stored.complete else { return }
        session = stored
        do {
            let answer = try await call("GET", "kp/api/v1/auth/validate-token", with: stored) as? [String: Any]
            let token = answer?["token"] as? [String: Any]
            if token?["isValid"] as? Bool == false || token?["isExpired"] as? Bool == true { await signOut() }
        } catch let error as KwikPassError where (400...499).contains(error.status ?? 0) {
            await signOut()
        } catch {
            kwikPassLog.warning("session not checked (\(String(describing: type(of: error)), privacy: .public))")
        }
    }

    /// Sends the sign-in OTP to `phone` (10 digits); returns the seconds before it may be sent again.
    func sendOtp(_ phone: String) async throws -> Int {
        // a fresh browser token for each sign-in: the request id and `Authorization` the OTP calls carry
        pending = KwikPassSession()
        let browser = try await call("GET", "kp/api/v1/auth/browser") as? [String: Any]
        pending.requestId = idText(browser?["requestId"])
        pending.authorization = browser?["token"] as? String ?? ""
        let sent = try await call("POST", "kp/api/v1/auth/otp/send", ["phone": phone]) as? [String: Any]
        pending.phone = phone
        return (sent?["interval"] as? Int) ?? 30
    }

    /// Verifies the phone's OTP; then signs in when the account's email is known, or says what the shopper does next.
    func verifyOtp(_ code: String) async throws -> KwikPassStep {
        guard let otp = Int(code) else { throw KwikPassError(message: "Enter the code we sent you") }
        let body: [String: Any] = ["phone": pending.phone, "otp": otp, "deviceId": deviceId()]
        let data = try await call("POST", "kp/api/v2/auth/otp/verify", body) as? [String: Any] ?? [:]
        pending.token = data["token"] as? String ?? ""
        pending.coreToken = data["coreToken"] as? String ?? ""
        pending.kpToken = data["kpToken"] as? String ?? ""
        pending.shopifyCustomerId = idText(data["shopifyCustomerId"])
        switch kwikPassVerifyBranch(data) {
        case .emailOtp(let email):
            try await sendEmailOtp(email)
            return .emailOtp(email)
        case .knownEmail(let email):
            // `/account/activate` (classic accounts only) is left out: the app's customers are on new customer accounts
            let state = data["state"] as? String ?? ""
            let answer = try await call("POST", "kp/api/v2/customer/shopify/multipass", [
                "id": pending.shopifyCustomerId, "email": email, "redirectUrl": "/", "isMarketingEventSubscribed": true, "state": state,
            ]) as? [String: Any] ?? [:]
            try await finish(answer, email: email)
            return .done(newUser: false)
        case .chooseEmail(let emails):
            return .chooseEmail(emails)
        case .enterEmail:
            return .enterEmail
        }
    }

    /// A new phone's email (or the one picked of several): GoKwik creates the customer for a new one and that signs in;
    /// an existing customer's email has to be proven first, by an OTP to it.
    func submitEmail(_ entered: String) async throws -> KwikPassStep {
        let email = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = "kp/api/v1/disposable-email/validate/" + (email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email)
        let check = try await envelope("GET", path)
        guard check["success"] as? Bool == true, let found = check["data"], !(found is NSNull) else {
            throw KwikPassError(message: "Entered email is not valid")
        }
        var body: [String: Any] = ["email": email, "redirectUrl": "/", "isMarketingEventSubscribed": true]
        if !pending.shopifyCustomerId.isEmpty { body["id"] = pending.shopifyCustomerId }
        let answer = try await call("POST", "kp/api/v1/customer/shopify-session", body) as? [String: Any] ?? [:]
        if answer["isNewUser"] as? Bool == true {
            try await finish(answer, email: email)
            return .done(newUser: true)
        }
        try await sendEmailOtp(email)
        return .emailOtp(email)
    }

    func sendEmailOtp(_ email: String) async throws {
        _ = try await call("POST", "kp/api/v1/auth/email-otp/send", ["email": email])
    }

    /// Verifies the OTP sent to `email`, which signs in.
    func verifyEmailOtp(_ email: String, code: String) async throws -> KwikPassStep {
        let answer = try await call("POST", "kp/api/v1/auth/email-otp/verify", [
            "email": email, "otp": code, "redirectUrl": "/", "isMarketingEventSubscribed": true,
        ]) as? [String: Any] ?? [:]
        try await finish(answer, email: email)
        return .done(newUser: false)
    }

    /// Forgets the session on the device; KwikPass has no server sign-out.
    func signOut() async {
        session = nil
        pending = KwikPassSession()
        await write(Self.sessionKey, nil)
    }

    /// The shopper is known: the session is complete, stored, and signed in.
    private func finish(_ answer: [String: Any], email: String) async throws {
        var complete = pending
        complete.email = (answer["email"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? email
        let id = idText(answer["shopifyCustomerId"])
        if !id.isEmpty { complete.shopifyCustomerId = id }
        guard complete.complete else { throw KwikPassError(message: "Sign-in couldn't be completed") }
        session = complete
        pending = KwikPassSession()
        await write(Self.sessionKey, try? JSONEncoder().encode(complete))
    }

    /// GoKwik's answer's `data`; a refusal throws GoKwik's message.
    private func call(_ method: String, _ path: String, _ body: [String: Any]? = nil, with tokens: KwikPassSession? = nil) async throws -> Any? {
        let json = try await envelope(method, path, body, with: tokens)
        if json["success"] as? Bool == false || json["isSuccess"] as? Bool == false { throw KwikPassError(message: message(json)) }
        return json["data"]
    }

    /// GoKwik's whole answer `{ data, success, isSuccess, … }`; an HTTP error throws its message and status.
    private func envelope(_ method: String, _ path: String, _ body: [String: Any]? = nil, with tokens: KwikPassSession? = nil) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw KwikPassError(message: "Sign-in isn't set up for this store") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        for (name, value) in kwikPassHeaders(merchantId: merchantId, session: tokens ?? pending) { request.setValue(value, forHTTPHeaderField: name) }
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200...299).contains(status) else { throw KwikPassError(message: message(json), status: status) }
        return json
    }

    private func message(_ json: [String: Any]) -> String {
        let error = json["error"]
        return (error as? [String: Any])?["message"] as? String
            ?? error as? String
            ?? json["error_msg"] as? String
            ?? json["message"] as? String
            ?? "Something went wrong. Please try again."
    }
}

/// The headers every KwikPass call carries, with the session's tokens once it has them.
func kwikPassHeaders(merchantId: String, session: KwikPassSession) -> [String: String] {
    var headers = [
        "accept": "*/*",
        "gk-source": "kp",
        "appplatform": "ios",
        "appversion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        "source": "ios-app",
        "gk-platform": "shopify",
        "gk-merchant-id": merchantId,
        "sdk-platform": "argon-ios",
        "sdk-version": "1.0.37",
        "kp-integration-type": "APP_MAKER",
    ]
    if !session.token.isEmpty { headers["gk-access-token"] = session.token }
    if !session.coreToken.isEmpty { headers["checkout-access-token"] = session.coreToken }
    if !session.requestId.isEmpty {
        headers["gk-request-id"] = session.requestId
        headers["kp-request-id"] = session.requestId
    }
    // the raw token, with no "Bearer"
    if !session.authorization.isEmpty { headers["Authorization"] = session.authorization }
    return headers
}
