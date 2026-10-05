import AuthenticationServices
import Foundation
import Observation
import os
import UIKit

/// Sign-in failed or was refused. `status` is set when a Shopify endpoint answered with an HTTP error.
struct AuthException: LocalizedError {
    let message: String
    var status: Int? = nil

    var errorDescription: String? { message }
}

private let authLog = Logger(subsystem: "app.storefront", category: "AuthStore")

/// The query of `components` as form fields: `+` is a space, as in application/x-www-form-urlencoded. Undecodable fields are
/// left out.
private func formFields(_ components: URLComponents) -> [String: String] {
    var fields: [String: String] = [:]
    for item in components.percentEncodedQueryItems ?? [] {
        guard let raw = item.value,
              let name = item.name.replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
              let value = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else { continue }
        fields[name] = value
    }
    return fields
}

private let formSafe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

/// An application/x-www-form-urlencoded body.
private func formBody(_ fields: [(String, String)]) -> Data {
    let pairs: [String] = fields.map { field in
        let name = field.0.addingPercentEncoding(withAllowedCharacters: formSafe) ?? ""
        let value = field.1.addingPercentEncoding(withAllowedCharacters: formSafe) ?? ""
        return name + "=" + value
    }
    return Data(pairs.joined(separator: "&").utf8)
}

/// The exception's message, else the error's type: never a value that could hold a token, a code or a URL.
private func logged(_ error: Error) -> String {
    (error as? AuthException)?.message ?? String(describing: type(of: error))
}

/// The customer's Customer Account API session: the OAuth 2.0 authorization code flow for a public client with PKCE (S256),
/// as in shopify.dev/docs/api/customer. Endpoints come from the shop's discovery documents. The session and the sign-in in
/// progress are kept through `read`/`write` (the Keychain); a stored value that can't be read means signed out.
/// `open` shows the authorize URL in a browser and returns the callback URL it was redirected to. `defaults` remembers that
/// this install has run: the Keychain outlives the app, so a reinstall starts by forgetting what the last install stored.
@MainActor
@Observable
final class AuthStore {
    /// False until `load()` (or any other call) has read the stored session.
    private(set) var signedIn = false

    /// Why the last sign-in failed once the browser came back (cancelled, refused); cleared by the next sign-in.
    private(set) var signInError: String? = nil

    private struct Tokens: Codable {
        let access: String
        let refresh: String?
        let idToken: String?
        let expiresAt: Date
    }

    // The sign-in in progress, kept until its callback (or the browser closing) ends it.
    private struct Pending: Codable {
        let verifier: String
        let state: String
        let nonce: String
    }

    private static let tokensKey = "tokens"
    private static let pendingKey = "pending"
    private static let installedKey = "argon.installed"

    private let domain: String
    private let clientId: String
    private let redirectUri: String
    private let loadDocument: (String) throws -> String
    private let open: (URL) async throws -> URL
    private let session: URLSession
    private let read: (String) async -> Data?
    private let write: (String, Data?) async -> Void
    private let defaults: UserDefaults
    private let now: () -> Date

    // One change at a time: two refreshes with the same refresh token would get the second one refused (and sign out).
    private let lock: AsyncLock
    private var loaded = false
    private var tokens: Tokens? = nil
    private var pending: Pending? = nil
    private var openIdConfig: [String: Any]? = nil
    private var graphqlEndpoint: URL? = nil
    private var documents: [String: String] = [:]

    init(
        domain: String,
        clientId: String,
        redirectUri: String,
        loadDocument: @escaping (String) throws -> String,
        open: @escaping (URL) async throws -> URL,
        session: URLSession = .shared,
        read: @escaping (String) async -> Data? = Keychain.load,
        write: @escaping (String, Data?) async -> Void = Keychain.save,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.domain = domain
        self.clientId = clientId
        self.redirectUri = redirectUri
        self.loadDocument = loadDocument
        self.open = open
        self.session = session
        self.read = read
        self.write = write
        self.defaults = defaults
        self.now = now
        lock = AsyncLock()
    }

    /// Reads the stored session, once.
    func load() async {
        await locked { await ensureLoaded() }
    }

    /// Signs in through `open`: a new verifier, state and nonce, Shopify's page in the browser, then the callback it returns.
    /// Throws when the browser can't be shown (discovery failed: no Customer Account API), before it opens. The shopper closing
    /// the browser returns quietly; a callback that fails or is refused is reported through `signInError`.
    func signIn() async throws {
        let url = try await start()
        let callback: URL
        do {
            callback = try await open(url)
        } catch {
            // that attempt is over: nothing will come back for it
            await locked { await setPending(nil) }
            if error is CancellationError { return }
            throw error
        }
        do {
            try await handleCallback(callback.absoluteString)
        } catch {
            if signInError == nil { signInError = error.localizedDescription }
            authLog.warning("sign-in callback not accepted: \(logged(error), privacy: .public)")
        }
    }

    /// Starts a sign-in: remembers a new verifier, state and nonce, and returns Shopify's authorize URL.
    func start() async throws -> URL {
        return try await locked {
            await ensureLoaded()
            signInError = nil
            let config = try await openId()
            // the code goes back to the token endpoint: one that isn't https stops the sign-in before the browser opens
            _ = try endpoint(config, "token_endpoint")
            let authorize = try endpoint(config, "authorization_endpoint")
            let verifier = Pkce.verifier()
            let state = Pkce.verifier()
            let nonce = Pkce.verifier()
            let url = authorize.appending(queryItems: [
                URLQueryItem(name: "scope", value: "openid email customer-account-api:full"),
                URLQueryItem(name: "client_id", value: clientId),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: redirectUri),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "nonce", value: nonce),
                URLQueryItem(name: "code_challenge", value: Pkce.challenge(verifier)),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
            ])
            await setPending(Pending(verifier: verifier, state: state, nonce: nonce))
            return url
        }
    }

    /// The browser came back to `redirectUri` with `uri`. A callback that isn't for the sign-in in progress (none, or another
    /// `state`) throws and changes nothing. Otherwise that attempt ends here: an `error` answer or a failed exchange throws and
    /// sets `signInError`; a `code` is exchanged for tokens once the id_token's nonce matches.
    func handleCallback(_ uri: String) async throws {
        try await locked {
            await ensureLoaded()
            let components = URLComponents(string: uri)
            let expected = URLComponents(string: redirectUri)
            let fields = components.map(formFields) ?? [:]
            guard let attempt = pending, let callback = components,
                  callback.scheme == expected?.scheme, callback.host == expected?.host,
                  fields["state"] == attempt.state else {
                throw AuthException(message: "This sign-in link isn't for this app")
            }
            await setPending(nil)
            do {
                if fields["error"] != nil {
                    throw AuthException(message: fields["error_description"] ?? "Sign-in was cancelled")
                }
                guard let code = fields["code"] else { throw AuthException(message: "Sign-in failed") }
                let request = try await tokenRequest([
                    ("grant_type", "authorization_code"),
                    ("client_id", clientId),
                    ("redirect_uri", redirectUri),
                    ("code", code),
                    ("code_verifier", attempt.verifier),
                ])
                let json = try await fetch(request)
                guard idTokenNonce(json.str("id_token")) == attempt.nonce else {
                    throw AuthException(message: "Sign-in couldn't be verified")
                }
                let signedInTokens = try parseTokens(json, previous: nil)
                await setTokens(signedInTokens)
            } catch {
                if !(error is CancellationError) { signInError = error.localizedDescription }
                throw error
            }
        }
    }

    /// The access token, refreshed first when it expires within 60 s. Nil when signed out, or when Shopify refuses the
    /// refresh (400/401: that signs out). Any other refresh failure throws and keeps the session.
    func validAccessToken() async throws -> String? {
        return try await locked {
            await ensureLoaded()
            guard let current = tokens else { return nil }
            if current.expiresAt.timeIntervalSince(now()) > 60 { return current.access }
            return try await refresh(current)
        }
    }

    /// Runs Customer Account API operation `name` and returns its `data`. A 401 refreshes and retries once; a second signs out.
    func customerQuery(_ name: String, _ variables: [String: Any] = [:]) async throws -> [String: Any] {
        let url = try await graphqlUrl()
        let body = try graphQLBody(document(name), variables)
        let first = try await validAccessToken()
        guard let token = first else { throw AuthException(message: "You're signed out") }
        do {
            return try await session.graphQL(customerRequest(url, body, token))
        } catch let error as StorefrontException where error.status == 401 {
            // revoked or expired early: refreshed and retried below
        }
        // a concurrent caller may already have refreshed it
        let second: String? = try await locked {
            guard let current = tokens else { return nil }
            if current.access != token { return current.access }
            return try await refresh(current)
        }
        guard let retry = second else { throw AuthException(message: "You're signed out") }
        do {
            return try await session.graphQL(customerRequest(url, body, retry))
        } catch let error as StorefrontException where error.status == 401 {
            await locked { await setTokens(nil) }
            throw error
        }
    }

    /// Forgets the session on the device, then ends it at Shopify: a mobile client calls the logout endpoint as an API with
    /// `id_token_hint` (it answers 200 instead of redirecting). That call is best-effort.
    func signOut() async {
        let idToken: String? = await locked {
            await ensureLoaded()
            let hint = tokens?.idToken
            await setTokens(nil)
            return hint
        }
        guard let hint = idToken else { return }
        do {
            let config = try await openId()
            let logout = try endpoint(config, "end_session_endpoint")
            let url = logout.appending(queryItems: [URLQueryItem(name: "id_token_hint", value: hint)])
            _ = try await session.data(for: URLRequest(url: url))
        } catch {
            // signed out on the device already; Shopify's session then simply runs out
            authLog.warning("logout call failed (\(logged(error), privacy: .public))")
        }
    }

    /// Runs `body` holding the lock.
    private func locked<T>(_ body: () async throws -> T) async rethrows -> T {
        await lock.lock()
        defer { lock.unlock() }
        return try await body()
    }

    /// With the lock held. Shopify refusing the refresh (400 or 401, RFC 6749 §5.2) signs out and returns nil; anything else
    /// (offline, 408, 429, 5xx) throws and keeps the session.
    private func refresh(_ current: Tokens) async throws -> String? {
        guard let refreshToken = current.refresh else {
            await setTokens(nil)
            return nil
        }
        let request = try await tokenRequest([("grant_type", "refresh_token"), ("client_id", clientId), ("refresh_token", refreshToken)])
        // An unstructured task, which the caller's cancellation doesn't reach: once Shopify has rotated the refresh token,
        // the caller going away mustn't lose the new one.
        return try await Task { () async throws -> String? in
            let json: [String: Any]
            do {
                json = try await self.fetch(request)
            } catch let error as AuthException where error.status == 400 || error.status == 401 {
                await self.setTokens(nil)
                return nil
            }
            let refreshed = try self.parseTokens(json, previous: current)
            await self.setTokens(refreshed)
            return refreshed.access
        }.value
    }

    /// With the lock held.
    private func ensureLoaded() async {
        if loaded { return }
        // UserDefaults goes with the app; the Keychain doesn't. Without this a reinstall comes back signed in as the last customer.
        if !defaults.bool(forKey: Self.installedKey) {
            await write(Self.tokensKey, nil)
            await write(Self.pendingKey, nil)
            defaults.set(true, forKey: Self.installedKey)
        }
        tokens = await stored(Tokens.self, Self.tokensKey)
        pending = await stored(Pending.self, Self.pendingKey)
        signedIn = tokens != nil
        loaded = true
    }

    /// A stored value; nil when there is none, the Keychain refused (logged there), or it can't be parsed.
    private func stored<T: Decodable>(_ type: T.Type, _ key: String) async -> T? {
        guard let data = await read(key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            authLog.warning("stored session unreadable (\(logged(error), privacy: .public))")
            return nil
        }
    }

    private func setTokens(_ value: Tokens?) async {
        tokens = value
        signedIn = value != nil
        await write(Self.tokensKey, value.flatMap { try? JSONEncoder().encode($0) })
    }

    private func setPending(_ value: Pending?) async {
        pending = value
        await write(Self.pendingKey, value.flatMap { try? JSONEncoder().encode($0) })
    }

    /// A token response. A refresh answer may leave out the refresh and id tokens; the previous ones then carry on.
    private func parseTokens(_ json: [String: Any], previous: Tokens?) throws -> Tokens {
        guard let access = json.str("access_token") else { throw AuthException(message: "Sign-in failed") }
        return Tokens(
            access: access,
            refresh: json.str("refresh_token") ?? previous?.refresh,
            idToken: json.str("id_token") ?? previous?.idToken,
            expiresAt: now().addingTimeInterval(TimeInterval(json.int("expires_in") ?? 0))
        )
    }

    private func tokenRequest(_ form: [(String, String)]) async throws -> URLRequest {
        let config = try await openId()
        let url = try endpoint(config, "token_endpoint")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(form)
        return request
    }

    private func customerRequest(_ url: URL, _ body: Data, _ token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // the bare access token, with no "Bearer" (shopify.dev/docs/api/customer, "Endpoints and queries")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    private func openId() async throws -> [String: Any] {
        if let cached = openIdConfig { return cached }
        let config = try await get("https://\(domain)/.well-known/openid-configuration")
        openIdConfig = config
        return config
    }

    private func graphqlUrl() async throws -> URL {
        if let cached = graphqlEndpoint { return cached }
        let config = try await get("https://\(domain)/.well-known/customer-account-api")
        let url = try endpoint(config, "graphql_api")
        graphqlEndpoint = url
        return url
    }

    private func document(_ name: String) throws -> String {
        if let cached = documents[name] { return cached }
        let text = try loadDocument(name)
        documents[name] = text
        return text
    }

    private func get(_ link: String) async throws -> [String: Any] {
        guard let url = URL(string: link) else { throw AuthException(message: "Sign-in isn't set up for this store") }
        return try await fetch(URLRequest(url: url))
    }

    /// The JSON a Shopify auth endpoint answered; an HTTP error is an AuthException with its status.
    private func fetch(_ request: URLRequest) async throws -> [String: Any] {
        let (body, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        guard (200...299).contains(status), let result = json else {
            let message = json?.str("error_description") ?? "Sign-in isn't available right now (HTTP \(status))"
            throw AuthException(message: message, status: status)
        }
        return result
    }

    /// A discovered endpoint. Tokens only ever go to https.
    private func endpoint(_ config: [String: Any], _ key: String) throws -> URL {
        guard let link = config.str(key), let url = URL(string: link), url.scheme?.lowercased() == "https", url.host != nil else {
            throw AuthException(message: "Sign-in isn't set up for this store")
        }
        return url
    }

    // ponytail: reads the id_token's nonce without verifying the token's signature (it came straight from the token endpoint
    // over TLS). To verify it, check the RS256 signature against the keys at the discovery document's `jwks_uri`, then iss/aud/exp.
    private func idTokenNonce(_ idToken: String?) -> String? {
        guard let parts = idToken?.split(separator: "."), parts.count > 1,
              let payload = base64UrlDecoded(String(parts[1])),
              let claims = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return nil }
        return claims.str("nonce")
    }
}

/// The browser step of sign-in: Shopify's page in an ASWebAuthenticationSession, which hands the callback URL straight back
/// (no URL scheme to register, no other app can answer). Not ephemeral: it shares Safari's cookies, so a shopper already
/// signed in to the shop isn't asked again.
final class BrowserSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    // the session must stay alive while it is shown
    private var session: ASWebAuthenticationSession? = nil

    /// The URL the page redirected to (`scheme://…`). The shopper closing the sheet throws CancellationError.
    @MainActor
    func open(_ url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            // start() can fail with or without calling the handler: resume once either way
            var finished = false
            let finish: (Result<URL, Error>) -> Void = { result in
                guard !finished else { return }
                finished = true
                self.session = nil
                continuation.resume(with: result)
            }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback = callback {
                    finish(.success(callback))
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    finish(.failure(CancellationError()))
                } else {
                    finish(.failure(error ?? CancellationError()))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                finish(.failure(AuthException(message: "Sign-in couldn't open the browser")))
            }
        }
    }

    // The system asks on the main thread, while the session starts.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return MainActor.assumeIsolated {
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
            return windows.first(where: { $0.isKeyWindow }) ?? windows.first ?? ASPresentationAnchor()
        }
    }
}
