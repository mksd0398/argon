import Foundation

/// Why checkout can't open in the app, as the shopper reads it.
let passwordProtectedCheckout = "This store is password protected, so checkout can't open in the app yet."

/// Checkout can't open: the storefront has a password (`passwordProtected`).
struct CheckoutUnavailable: LocalizedError {
    var errorDescription: String? { passwordProtectedCheckout }
}

/// Stops a request at its first redirect, so the redirect itself can be read.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? { nil }
}

/// Whether the storefront that `checkout` belongs to has a password. Behind one, checkout shows the password page and,
/// once the password is entered, the storefront: a Checkout Kit sheet would show the shop's web pages, not checkout. The
/// storefront's home page is asked, without following its redirect (checkout itself refuses requests that aren't a
/// browser's); any failure is false, so a network problem never stops checkout (Checkout Kit reports its own). `fetch`
/// is for tests.
func passwordProtected(
    _ checkout: URL,
    fetch: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0, delegate: NoRedirect()) }
) async -> Bool {
    guard var home = URLComponents(url: checkout, resolvingAgainstBaseURL: false) else { return false }
    home.path = "/"
    home.query = nil
    guard let url = home.url else { return false }
    var request = URLRequest(url: url)
    request.timeoutInterval = 5
    guard let (_, response) = try? await fetch(request), let http = response as? HTTPURLResponse else { return false }
    return (300..<400).contains(http.statusCode) && (http.value(forHTTPHeaderField: "Location") ?? "").contains("/password")
}
