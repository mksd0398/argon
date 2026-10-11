import Foundation
import os

private let apiLog = Logger(subsystem: "app.storefront", category: "API")

/// Why an API call failed. `network`: no answer (offline, timed out, cancelled). `http`: the server answered with a non-2xx
/// status. `graphql`: the server refused the operation (a 200 carrying an `errors` array). `userErrors`: a mutation refused
/// the change, in Shopify's words, meant for the shopper; a cart mutation also carries the cart that came back beside them
/// (nil when none did: the cart is gone, or the change was refused outright). `decoding`: the response doesn't have the
/// shape the operation's document asks for (`detail` says where; it is logged too).
enum ArgonAPIError: LocalizedError {
    case network(URLError)
    case http(status: Int)
    case graphql(messages: [String])
    case userErrors([UserError], cart: Cart? = nil)
    case decoding(operation: String, detail: String)

    var errorDescription: String? {
        switch self {
        case let .network(error): return error.localizedDescription
        case let .http(status): return "HTTP \(status)"
        case let .graphql(messages): return messages.joined(separator: "\n")
        case let .userErrors(errors, _): return errors.map { $0.message }.joined(separator: "\n")
        case .decoding: return "Invalid response"
        }
    }
}

/// A mutation's `userErrors` entry. `field` is the path to the input it is about; `code` is Shopify's error code (may be null).
struct UserError: Decodable, Equatable, Sendable {
    var field: [String]? = nil
    var code: String? = nil
    let message: String
}

/// Something the app asked for doesn't exist: "Product not found".
struct NotFound: LocalizedError {
    let what: String

    var errorDescription: String? { "\(what) not found" }
}

/// Runs a named GraphQL operation with its variables and returns the response body: `Storefront.query`,
/// `AuthStore.customerQuery`, or a test's canned answers.
typealias GraphQLTransport = (String, [String: Any]) async throws -> Data

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

    /// Runs operation `name` and returns the response body, for `decodeResponse`.
    func query(_ name: String, _ variables: [String: Any] = [:]) async throws -> Data {
        guard let url = url else { throw ArgonAPIError.network(URLError(.badURL)) }
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
        throw EncodingError.invalidValue(variables, EncodingError.Context(codingPath: [], debugDescription: "GraphQL variables must be JSON values"))
    }
    return try JSONSerialization.data(withJSONObject: body)
}

extension URLSession {
    /// Sends a GraphQL `request` and returns the response body. Shared by the Storefront and Customer Account clients.
    func graphQL(_ request: URLRequest) async throws -> Data {
        let result: (Data, URLResponse)
        do {
            result = try await data(for: request)
        } catch let error as URLError {
            throw ArgonAPIError.network(error)
        }
        let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(status) { throw ArgonAPIError.http(status: status) }
        return result.0
    }
}

private struct GraphQLErrors: Decodable {
    struct Entry: Decodable {
        struct Extensions: Decodable {
            let code: String?
        }

        let message: String?
        let extensions: Extensions?
        /// The response field the error is about: the first element of its `path` (the rest may be list indexes).
        let root: String?

        private enum CodingKeys: String, CodingKey {
            case message, extensions, path
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            message = try c.decodeIfPresent(String.self, forKey: .message)
            extensions = try? c.decodeIfPresent(Extensions.self, forKey: .extensions)
            var path = try? c.nestedUnkeyedContainer(forKey: .path)
            root = try? path?.decode(String.self)
        }
    }

    let errors: [Entry]?
}

private struct GraphQLData<T: Decodable>: Decodable {
    let data: T
}

/// Whether a JSON value is null, whatever else it could be.
private struct IsNull: Decodable {
    let value: Bool

    init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decodeNil()
    }
}

/// Each distinct access-denied message is logged once per launch: every product card repeats the same one.
private enum DeniedLog {
    private static let lock = NSLock()
    private static var seen: Set<String> = []

    static func isNew(_ message: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return seen.insert(message).inserted
    }
}

/// Whether `errors` only say that the token may not read some fields (code ACCESS_DENIED), and each of those fields sits
/// under a root field of `body`'s `data` that still came back: the denied fields are null there, the rest is usable.
/// A denied root field (null in `data`) is not: the operation has nothing to show.
private func onlyDeniedFields(_ errors: [GraphQLErrors.Entry], in body: Data) -> Bool {
    guard errors.allSatisfy({ $0.extensions?.code == "ACCESS_DENIED" }),
          let roots = try? JSONDecoder().decode(GraphQLData<[String: IsNull]>.self, from: body).data else { return false }
    return errors.allSatisfy { error in error.root.flatMap { roots[$0] }?.value == false }
}

/// The `data` of response `body` as `T`. An `errors` array is ArgonAPIError.graphql, checked first (data that comes with errors
/// may be partial), unless all it reports is fields the token may not read (`onlyDeniedFields`: a Headless token without
/// `unauthenticated_read_product_inventory`, say): then `data` is returned with those fields null, so a page loses its stock
/// count instead of failing. Anything else that doesn't fit `T` is .decoding.
func decodeResponse<T: Decodable>(_ type: T.Type, from body: Data, operation: String) throws -> T {
    let decoder = JSONDecoder()
    do {
        let errors = try decoder.decode(GraphQLErrors.self, from: body).errors ?? []
        if !errors.isEmpty {
            let messages = errors.map { $0.message ?? "Unknown error" }
            guard onlyDeniedFields(errors, in: body) else { throw ArgonAPIError.graphql(messages: messages) }
            // GraphQL messages name fields and permissions, never a token
            for message in Set(messages) where DeniedLog.isNew(message) {
                apiLog.warning("\(operation, privacy: .public): \(message, privacy: .public)")
            }
        }
        return try decoder.decode(GraphQLData<T>.self, from: body).data
    } catch let error as DecodingError {
        let detail = describe(error)
        // field paths and types only, never values
        apiLog.error("\(operation, privacy: .public) response not decoded: \(detail, privacy: .public)")
        throw ArgonAPIError.decoding(operation: operation, detail: detail)
    }
}

/// Root field `root` of operation `name`'s `data`. `T` is optional for a root the schema allows to be null.
func fetchField<T: Decodable>(_ transport: GraphQLTransport, _ name: String, _ variables: [String: Any], root: String) async throws -> T {
    let body = try await transport(name, variables)
    let data = try decodeResponse([String: T].self, from: body, operation: name)
    guard let value = data[root] else { throw ArgonAPIError.decoding(operation: name, detail: "\(root) missing") }
    return value
}

/// A mutation's payload field: the operation name with a lowercase first letter (`CartLinesAdd` -> `cartLinesAdd`).
func payloadField(_ operation: String) -> String {
    operation.prefix(1).lowercased() + String(operation.dropFirst())
}

/// `value` as JSONSerialization objects, to sit in a variables dictionary.
func jsonValue<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
}

/// A decoding failure as "<what> at <path>".
private func describe(_ error: DecodingError) -> String {
    func at(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map { key in key.intValue.map { "\($0)" } ?? key.stringValue }.joined(separator: ".")
        return path.isEmpty ? "the root" : path
    }
    switch error {
    case let .keyNotFound(key, context): return "\(key.stringValue) missing at \(at(context))"
    case let .valueNotFound(_, context): return "null at \(at(context))"
    case let .typeMismatch(type, context): return "\(type) expected at \(at(context))"
    case let .dataCorrupted(context): return "\(context.debugDescription) at \(at(context))"
    @unknown default: return String(describing: error)
    }
}

extension KeyedDecodingContainer {
    /// The `nodes` of the connection under `key`; empty when the connection is null or not selected.
    func nodes<T: Decodable>(_ key: Key) throws -> [T] {
        try decodeIfPresent(Nodes<T>.self, forKey: key)?.nodes ?? []
    }
}

/// A connection read for its `nodes` only.
struct Nodes<T: Decodable>: Decodable {
    let nodes: [T]
}
