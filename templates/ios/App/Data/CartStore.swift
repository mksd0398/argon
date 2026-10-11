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
///
/// Analytics: `track` gets what each change of the lines put in the cart and took out of it, once Shopify has accepted it,
/// whoever asked for the change; `cartAttributes` are what a new cart carries (`Analytics.cartAttributes`).
@MainActor
@Observable
final class CartStore {
    /// Nil while there is no cart (none yet, not loaded yet, expired, or checked out).
    private(set) var cart: Cart? = nil

    private let api: StorefrontAPI
    private let defaults: UserDefaults
    private let accessToken: () async throws -> String?
    private let track: (AnalyticsEvent) -> Void
    private let cartAttributes: () async -> [String: String]
    // One change at a time: two quick taps must not create two carts or interleave line updates.
    private let lock: AsyncLock
    /// The company location a B2B customer buys for (`setBuyer`); nil for anyone else.
    private var companyLocationId: String? = nil
    /// The buyer Shopify last put on the cart: the cart's id, the customer's token and the company location. Shopify
    /// answers every buyer update with a checkout URL under a new key, so attaching the same buyer again changes the
    /// cart each time: a screen that prepares checkout whenever the cart changes would then reload it without end.
    private var attached: AttachedBuyer? = nil
    private static let idKey = "cartId"

    private struct AttachedBuyer: Equatable {
        let cartId: String
        let token: String
        let companyLocationId: String?
    }

    init(
        api: StorefrontAPI,
        defaults: UserDefaults,
        accessToken: @escaping () async throws -> String? = { nil },
        track: @escaping (AnalyticsEvent) -> Void = { _ in },
        cartAttributes: @escaping () async -> [String: String] = { [:] }
    ) {
        self.api = api
        self.defaults = defaults
        self.accessToken = accessToken
        self.track = track
        self.cartAttributes = cartAttributes
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

    /// `sellingPlanId`: the subscription the line is bought on; nil for a one-time purchase.
    func add(_ variantId: String, quantity: Int, sellingPlanId: String? = nil) async throws {
        await lock.lock()
        defer { lock.unlock() }
        let lines = [CartLineInput(merchandiseId: variantId, quantity: quantity, sellingPlanId: sellingPlanId)]
        try await reporting {
            // a stored cart that has expired is replaced by a new one holding these lines
            let added = try await self.change(
                { try await self.api.addLines(cartId: $0, lines: lines) },
                ifGone: { try await self.create(lines) }
            )
            if let added = added { return added }
            return try await self.create(lines)
        }
    }

    /// Sets the quantity of a line; 0 (or less) removes it.
    func update(_ lineId: String, quantity: Int) async throws {
        await lock.lock()
        defer { lock.unlock() }
        try await reporting {
            if quantity <= 0 { return try await self.removeLine(lineId) }
            let lines = [CartLineUpdateInput(id: lineId, quantity: quantity)]
            return try await self.change { try await self.api.updateLines(cartId: $0, lines: lines) }
        }
    }

    func remove(_ lineId: String) async throws {
        await lock.lock()
        defer { lock.unlock() }
        try await reporting { try await self.removeLine(lineId) }
    }

    /// Adds the discount `code` to the cart's codes (Shopify takes the whole list each time). False when Shopify says it
    /// can't be used on this cart (unknown, expired, or its conditions aren't met): the code is then taken off again, so
    /// the cart only carries codes that count. False too without a cart or a code.
    func applyDiscount(_ code: String) async throws -> Bool {
        await lock.lock()
        defer { lock.unlock() }
        let entered = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entered.isEmpty, let current = cart else { return false }
        // codes are not case-sensitive: entering one again replaces it instead of listing it twice
        let others = current.discountCodes.map { $0.code }.filter { !Self.sameCode($0, entered) }
        guard let updated = try await change({ try await self.api.updateDiscountCodes(cartId: $0, codes: others + [entered]) }) else {
            return false
        }
        if updated.discountCodes.contains(where: { $0.applicable && Self.sameCode($0.code, entered) }) { return true }
        _ = try await change { try await self.api.updateDiscountCodes(cartId: $0, codes: others) }
        return false
    }

    /// Takes the discount `code` off the cart.
    func removeDiscount(_ code: String) async throws {
        await lock.lock()
        defer { lock.unlock() }
        // without the cart there is no list to send (an empty one would clear every code)
        guard let current = cart else { return }
        let others = current.discountCodes.map { $0.code }.filter { !Self.sameCode($0, code) }
        _ = try await change { try await self.api.updateDiscountCodes(cartId: $0, codes: others) }
    }

    private static func sameCode(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// The URL to hand to Checkout Kit, with the signed-in customer attached to the cart first. Nil without a cart.
    /// Attaching the customer never blocks checkout: if it fails, the shopper checks out as a guest. A buyer the cart
    /// already has is not attached again, so asking twice gives the same URL and leaves the cart as it is.
    func checkoutUrl() async -> String? {
        await lock.lock()
        defer { lock.unlock() }
        guard let current = cart else { return nil }
        do {
            guard let token = try await accessToken() else { return current.checkoutUrl }
            let buyer = AttachedBuyer(cartId: current.id, token: token, companyLocationId: companyLocationId)
            if buyer == attached { return current.checkoutUrl }
            let identity = CartBuyerIdentityInput(customerAccessToken: token, companyLocationId: companyLocationId)
            let updated = try await change({ try await self.api.updateBuyerIdentity(cartId: $0, buyerIdentity: identity) })
            if updated != nil { attached = buyer }
            return updated?.checkoutUrl
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

    /// The company location the signed-in customer buys for (`BuyerStore`), or nil for a retail shopper. It goes on the
    /// cart with the customer's token, so its lines take the company's prices: now when there is a cart, with every new
    /// cart, and before checkout. Nil only forgets the location (signing out drops the cart itself).
    func setBuyer(_ companyLocationId: String?) async throws {
        await lock.lock()
        defer { lock.unlock() }
        self.companyLocationId = companyLocationId
        guard let location = companyLocationId, currentId() != nil, let token = try await accessToken() else { return }
        let identity = CartBuyerIdentityInput(customerAccessToken: token, companyLocationId: location)
        if let updated = try await change({ try await self.api.updateBuyerIdentity(cartId: $0, buyerIdentity: identity) }) {
            attached = AttachedBuyer(cartId: updated.id, token: token, companyLocationId: location)
        }
    }

    private func create(_ lines: [CartLineInput]) async throws -> Cart {
        var input = CartInput(lines: lines)
        // Only a new cart gets the attributes: sending them later would be one more cart mutation, and each one changes
        // the checkout URL (see `attached`). Sorted, so the same attributes are always the same request.
        let attributes = await cartAttributes().sorted { $0.key < $1.key }.map { CartAttribute(key: $0.key, value: $0.value) }
        if !attributes.isEmpty { input.attributes = attributes }
        // a company's cart starts with its buyer, or its first lines would show retail prices; anyone else is attached at checkout
        if let location = companyLocationId, let token = try? await accessToken() {
            input.buyerIdentity = CartBuyerIdentityInput(customerAccessToken: token, companyLocationId: location)
        }
        let created = input
        return try await send { try await self.api.cartCreate(created) }
    }

    private func removeLine(_ lineId: String) async throws -> Cart? {
        try await change { try await self.api.removeLines(cartId: $0, lineIds: [lineId]) }
    }

    /// Runs a change of the cart's lines (with the lock held), then reports what it put in the cart and took out of it:
    /// the quantities Shopify answered with against those from before. So every caller is covered, and a load, a discount
    /// code or a buyer change reports nothing. A new cart had nothing before. A change Shopify refused threw, and reports
    /// nothing; nor does a change of a stored cart that was never loaded (an offline start): what it held isn't known.
    private func reporting(_ mutation: () async throws -> Cart?) async throws {
        let id = currentId()
        let before = cart
        guard let after = try await mutation() else { return }
        let had: [CartLine]
        if after.id != id {
            had = []
        } else if let before = before {
            had = before.lines
        } else {
            return
        }
        cartLineEvents(before: had, after: after.lines).forEach(track)
    }

    private func currentId() -> String? {
        cart?.id ?? defaults.string(forKey: Self.idKey)
    }

    /// Runs `mutation` on the current cart; nil (nothing run) when there is no cart. When it is refused without a cart coming
    /// back, the cart lookup tells a cart Shopify no longer has (forgotten, then `ifGone` runs if given) from a change it
    /// refused (the error is thrown).
    private func change(
        _ mutation: (String) async throws -> Cart,
        ifGone: (() async throws -> Cart)? = nil
    ) async throws -> Cart? {
        guard let id = currentId() else { return nil }
        do {
            return try await send { try await mutation(id) }
        } catch ArgonAPIError.userErrors(let errors, .none) {
            if try await api.cart(id) != nil { throw ArgonAPIError.userErrors(errors, cart: nil) }
            forget()
            guard let ifGone = ifGone else { throw ArgonAPIError.userErrors(errors, cart: nil) }
            return try await ifGone()
        }
    }

    /// Runs `mutation` and keeps the cart it returns, even one that comes back beside user errors (which are rethrown).
    private func send(_ mutation: () async throws -> Cart) async throws -> Cart {
        do {
            let changed = try await mutation()
            return keep(changed)
        } catch ArgonAPIError.userErrors(let errors, let returned?) {
            keep(returned)
            throw ArgonAPIError.userErrors(errors, cart: returned)
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
