import Foundation
import Observation
import os

/// Shopify refused a cart change (a `userErrors` entry); the message is Shopify's, meant for the shopper.
struct CartException: LocalizedError {
    let message: String
    /// The mutation answered without a cart: the cart is gone, or the change was refused (a bad variant id).
    var noCart = false

    var errorDescription: String? { message }
}

/// One holder at a time, in arrival order (a coroutine mutex): an `await` inside the locked section lets no one else in.
@MainActor
final class AsyncLock {
    private var locked = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiting.append(continuation)
        }
    }

    /// Hands the lock to the next waiter, if any.
    func unlock() {
        if waiting.isEmpty {
            locked = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

private let cartLog = Logger(subsystem: "app.storefront", category: "CartStore")

/// The shopper's cart through the Storefront Cart API. Only the cart id is kept on the device; `cart` is whatever the last
/// response said. `query` runs a named GraphQL operation and returns its `data`; `accessToken` is the signed-in
/// customer's token (nil when signed out), attached to the cart before checkout.
@MainActor
@Observable
final class CartStore {
    /// Nil while there is no cart (none yet, not loaded yet, expired, or checked out).
    private(set) var cart: Cart? = nil

    private let query: (String, [String: Any]) async throws -> [String: Any]
    private let defaults: UserDefaults
    private let accessToken: () async throws -> String?
    // One change at a time: two quick taps must not create two carts or interleave line updates.
    private let lock: AsyncLock
    private static let idKey = "cartId"

    init(
        query: @escaping (String, [String: Any]) async throws -> [String: Any],
        defaults: UserDefaults,
        accessToken: @escaping () async throws -> String? = { nil }
    ) {
        self.query = query
        self.defaults = defaults
        self.accessToken = accessToken
        lock = AsyncLock()
    }

    /// Fetches the stored cart. A cart Shopify no longer has (expired, completed) is forgotten without an error.
    func load() async throws {
        await lock.lock()
        defer { lock.unlock() }
        guard let id = currentId() else { return }
        if let found = try await query("Cart", ["id": id]).obj("cart") {
            cart = try parseCart(found)
        } else {
            forget()
        }
    }

    func add(_ variantId: String, quantity: Int) async throws {
        await lock.lock()
        defer { lock.unlock() }
        let lines: [[String: Any]] = [["merchandiseId": variantId, "quantity": quantity]]
        // a stored cart that has expired is replaced by a new one holding these lines
        let added = try await change("CartLinesAdd", "lines", lines, ifGone: { try await self.create(lines) })
        if added == nil { _ = try await create(lines) }
    }

    /// Sets the quantity of a line; 0 (or less) removes it.
    func update(_ lineId: String, quantity: Int) async throws {
        await lock.lock()
        defer { lock.unlock() }
        if quantity <= 0 {
            try await removeLine(lineId)
        } else {
            let lines: [[String: Any]] = [["id": lineId, "quantity": quantity]]
            _ = try await change("CartLinesUpdate", "lines", lines)
        }
    }

    func remove(_ lineId: String) async throws {
        await lock.lock()
        defer { lock.unlock() }
        try await removeLine(lineId)
    }

    /// The URL to hand to Checkout Kit, with the signed-in customer attached to the cart first. Nil without a cart.
    /// Attaching the customer never blocks checkout: if it fails, the shopper checks out as a guest.
    func checkoutUrl() async -> String? {
        await lock.lock()
        defer { lock.unlock() }
        guard let current = cart else { return nil }
        do {
            guard let token = try await accessToken() else { return current.checkoutUrl }
            let identity: [String: Any] = ["customerAccessToken": token]
            return try await change("CartBuyerIdentityUpdate", "buyerIdentity", identity)?.checkoutUrl
        } catch {
            // the token provider threw, Shopify refused the token (CartException), or the request failed
            cartLog.warning("customer not attached to the cart; checking out as a guest: \(error.localizedDescription)")
            return cart?.checkoutUrl // nil if the cart turned out to be gone
        }
    }

    /// The order was placed: the cart is spent, so the next add starts a new one.
    func completed() async {
        await lock.lock()
        defer { lock.unlock() }
        forget()
    }

    private func create(_ lines: [[String: Any]]) async throws -> Cart {
        try await send("CartCreate", ["input": ["lines": lines]])
    }

    private func removeLine(_ lineId: String) async throws {
        _ = try await change("CartLinesRemove", "lineIds", [lineId])
    }

    private func currentId() -> String? {
        cart?.id ?? defaults.string(forKey: Self.idKey)
    }

    /// Runs a mutation on the current cart; nil (nothing run) when there is no cart. When no cart comes back, the cart lookup
    /// tells a cart Shopify no longer has (forgotten, then `ifGone` runs if given) from a change it refused (the error is thrown).
    private func change(
        _ name: String,
        _ key: String,
        _ value: Any,
        ifGone: (() async throws -> Cart)? = nil
    ) async throws -> Cart? {
        guard let id = currentId() else { return nil }
        do {
            return try await send(name, ["cartId": id, key: value])
        } catch let error as CartException where error.noCart {
            if try await query("Cart", ["id": id]).obj("cart") != nil { throw error }
            forget()
            guard let ifGone = ifGone else { throw error }
            return try await ifGone()
        }
    }

    /// Runs mutation `name`, keeps the cart it returns (even beside userErrors), and throws the first user error.
    private func send(_ name: String, _ variables: [String: Any]) async throws -> Cart {
        let field = name.prefix(1).lowercased() + String(name.dropFirst())
        guard let payload = try await query(name, variables).obj(field) else {
            throw StorefrontException(messages: ["Invalid response"], status: nil)
        }
        let parsed = try payload.obj("cart").map { try parseCart($0) }
        if let parsed = parsed {
            if parsed.id != cart?.id { saveId(parsed.id) }
            cart = parsed
        }
        let error = payload.objects("userErrors").first.map { $0.str("message") ?? "The cart could not be updated" }
        guard let returned = parsed else { throw CartException(message: error ?? "The cart is unavailable", noCart: true) }
        if let error = error { throw CartException(message: error) }
        return returned
    }

    private func forget() {
        cart = nil
        saveId(nil)
    }

    private func saveId(_ id: String?) {
        if let id = id {
            defaults.set(id, forKey: Self.idKey)
        } else {
            defaults.removeObject(forKey: Self.idKey)
        }
    }
}
