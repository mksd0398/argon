import Foundation

/// `isGraphQL`: the server answered 200 with an `errors` array (a query it refused), as opposed to an HTTP or response-shape failure.
struct StorefrontException: LocalizedError {
    let messages: [String]
    let status: Int?
    var isGraphQL: Bool = false

    var errorDescription: String? { messages.joined(separator: "\n") }
}

/// Storefront API client. `loadDocument(name)` returns the GraphQL document `queries/<name>.graphql`.
final class Storefront {
    private let url: URL?
    private let token: String
    private let loadDocument: (String) throws -> String
    private let session: URLSession
    private var documents: [String: String] = [:]
    private let lock = NSLock()

    init(domain: String, token: String, apiVersion: String, loadDocument: @escaping (String) throws -> String, session: URLSession = .shared) {
        url = URL(string: "https://\(domain)/api/\(apiVersion)/graphql.json")
        self.token = token
        self.loadDocument = loadDocument
        self.session = session
    }

    /// Runs operation `name` and returns its `data`.
    func query(_ name: String, _ variables: [String: Any] = [:]) async throws -> [String: Any] {
        guard let url = url else { throw StorefrontException(messages: ["Invalid shop domain"], status: nil) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "X-Shopify-Storefront-Access-Token") }
        request.httpBody = try graphQLBody(document(name), variables)
        return try await session.graphQL(request)
    }

    private func document(_ name: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cached = documents[name] { return cached }
        let text = try loadDocument(name)
        documents[name] = text
        return text
    }
}

/// The JSON body of a GraphQL request.
func graphQLBody(_ document: String, _ variables: [String: Any]) throws -> Data {
    let body: [String: Any] = ["query": document, "variables": variables]
    // JSONSerialization raises (crashes) instead of throwing on values JSON can't hold
    guard JSONSerialization.isValidJSONObject(body) else {
        throw StorefrontException(messages: ["Invalid variables"], status: nil)
    }
    return try JSONSerialization.data(withJSONObject: body)
}

extension URLSession {
    /// Sends a GraphQL `request` and returns the response's `data`. Shared by the Storefront and Customer Account clients.
    func graphQL(_ request: URLRequest) async throws -> [String: Any] {
        let (body, response) = try await self.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(status) {
            throw StorefrontException(messages: ["HTTP \(status)"], status: status)
        }
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            throw StorefrontException(messages: ["Invalid response"], status: status)
        }
        if let errors = json["errors"] as? [Any] {
            let messages: [String] = errors.map { error in
                ((error as? [String: Any])?["message"] as? String) ?? "\(error)"
            }
            throw StorefrontException(messages: messages, status: status, isGraphQL: true)
        }
        guard let result = json["data"] as? [String: Any] else {
            throw StorefrontException(messages: ["No data in response"], status: status)
        }
        return result
    }
}
