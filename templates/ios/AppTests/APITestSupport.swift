import XCTest
@testable import ArgonStorefront

private final class FixtureBundle {}

/// The text of AppTests/Fixtures/<name>.json: the response `data` of operation <name>, which the CLI copies there from
/// contract/fixtures (recorded from mock.shop, or hand-written to the schema).
func fixtureText(_ name: String) throws -> String {
    let bundle = Bundle(for: FixtureBundle.self)
    // a synchronized folder may copy Fixtures/ flat into the test bundle
    guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        ?? bundle.url(forResource: name, withExtension: "json") else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(name)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// The names of all the fixtures in the test bundle.
func fixtureNames() -> Set<String> {
    let bundle = Bundle(for: FixtureBundle.self)
    let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures") ?? [])
        + (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
    return Set(urls.map { $0.deletingPathExtension().lastPathComponent })
}

/// Fixture <name>'s `data` as JSONSerialization objects, to build other answers from.
func fixture(_ name: String) throws -> [String: Any] {
    try json(fixtureText(name))
}

func json(_ text: String) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Not a JSON object"])
    }
    return object
}

/// A response body carrying `data`.
func responseBody(_ data: [String: Any]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: ["data": data]), as: UTF8.self)
}

/// Stands in for Shopify behind a facade: answers each operation through `reply` (by default with its fixture) and records
/// what was asked, in order.
@MainActor
final class StubServer {
    private(set) var calls: [(name: String, variables: [String: Any])] = []
    var reply: (String, [String: Any]) async throws -> String

    var names: [String] { calls.map { $0.name } }

    init(reply: @escaping (String, [String: Any]) async throws -> String = { name, _ in try "{\"data\":" + fixtureText(name) + "}" }) {
        self.reply = reply
    }

    func transport(_ name: String, _ variables: [String: Any]) async throws -> Data {
        calls.append((name: name, variables: variables))
        return Data(try await reply(name, variables).utf8)
    }

    /// A facade over this server.
    func storefront() -> StorefrontAPI {
        StorefrontAPI(transport: { name, variables in try await self.transport(name, variables) })
    }

    func customerAccount() -> CustomerAccountAPI {
        CustomerAccountAPI(transport: { name, variables in try await self.transport(name, variables) })
    }
}

/// The error `body` throws; nil when it doesn't throw.
@MainActor
func thrownError<T>(_ body: () async throws -> T) async -> Error? {
    do {
        _ = try await body()
        return nil
    } catch {
        return error
    }
}
