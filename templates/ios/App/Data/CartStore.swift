import Foundation
import Observation
import os

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
/// response said. `accessToken` is the signed-in customer's token (nil when signed out), attached to the cart before checkout.
/// A change Shopify refuses throws its `ArgonAPIError.userErrors` (Shopify's message, meant for the shopper).
@MainActor
@Observable
final class CartStore {
    /// Nil while there is no cart (none yet, not loaded yet, expired, or checked out).
    private(set) var cart: Cart? = nil

    private let api: StorefrontAPI
    private let defaults: UserDefaults
    private let accessToken: () async throws -> String?
    // One change at a time: two quick taps must not create two carts or interleave line updates.
    private let lock: AsyncLock
    private static let idKey = "cartId"

    init(api: StorefrontAPI, defaults: UserDefaults, accessToken: @escaping () async throws -> String? = { nil }) {
        self.api = api
        self.defaults = defaults
        self.accessToken = accessToken
        lock = AsyncLock()
    }

    /// Fetches the stored cart. A cart Shopify no longer has (expired, completed) is forgotten without an error.
    func load() async throws {
        await lock.lock()
        defer { lock.unlock() }
        guard let id = currentId() else { return }
        if let found = try await api.cart(id) {
            keep(found)
        } else {
            forget()
        }
    }

    func add(_ variantId: String, quantity: Int) async throws {
        await lock.lock()
        defer { lock.unlock() }
        let lines = [CartLineInput(merchandiseId: variantId, quantity: quantity)]
        // a stored cart that has expired is replaced by a new one holding these lines
        let added = try await change(
            { try await self.api.addLines(cartId: $0, lines: lines) },
            ifGone: { try await self.create(lines) }
        )
        if added == nil { _ = try await create(lines) }
    }

    /// Sets the quantity of a line; 0 (or less) removes it.
    func update(_ lineId: String, quantity: Int) async throws {
        await lock.lock()
        defer { lock.unlock() }
        if quantity <= 0 {
            try await removeLine(lineId)
        } else {
            let lines = [CartLineUpdateInput(id: lineId, quantity: quantity)]
            _ = try await change { try await self.api.updateLines(cartId: $0, lines: lines) }
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
            let identity = CartBuyerIdentityInput(customerAccessToken: token)
            let attached = try await change({ try await self.api.updateBuyerIdentity(cartId: $0, buyerIdentity: identity) })
            return attached?.checkoutUrl
        } catch {
            // the token provider threw, Shopify refused the token (userErrors), or the request failed
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

    private func create(_ lines: [CartLineInput]) async throws -> Cart {
        let created = try await api.cartCreate(CartInput(lines: lines))
        return keep(created.cart)
    }

    private func removeLine(_ lineId: String) async throws {
        _ = try await change { try await self.api.removeLines(cartId: $0, lineIds: [lineId]) }
    }

    private func currentId() -> String? {
        cart?.id ?? defaults.string(forKey: Self.idKey)
    }

    /// Runs `mutation` on the current cart's id and keeps the cart it returns; nil (nothing run) when there is no cart.
    /// When Shopify refuses (userErrors), the cart is looked up: one Shopify no longer has is forgotten (then `ifGone` runs,
    /// if given); one it still has is kept, current, and the refusal is thrown.
    private func change(
        _ mutation: (String) async throws -> CartResult,
        ifGone: (() async throws -> Cart)? = nil
    ) async throws -> Cart? {
        guard let id = currentId() else { return nil }
        do {
            let changed = try await mutation(id)
            return keep(changed.cart)
        } catch ArgonAPIError.userErrors(let errors) {
            if let current = try await api.cart(id) {
                keep(current)
                throw ArgonAPIError.userErrors(errors)
            }
            forget()
            guard let ifGone = ifGone else { throw ArgonAPIError.userErrors(errors) }
            return try await ifGone()
        }
    }

    @discardableResult
    private func keep(_ updated: Cart) -> Cart {
        if updated.id != cart?.id { saveId(updated.id) }
        cart = updated
        return updated
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
