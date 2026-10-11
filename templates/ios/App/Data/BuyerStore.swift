import Foundation
import Observation
import os

private let buyerLog = Logger(subsystem: "app.storefront", category: "BuyerStore")

/// The company the signed-in customer buys for, and the location chosen among its `locations`.
struct BuyerCompany: Equatable, Sendable {
    let contactId: String
    let companyName: String
    let locations: [CompanyLocation]
    let locationId: String

    /// The chosen location.
    var location: CompanyLocation? { locations.first { $0.id == locationId } }
}

/// The B2B buyer: a signed-in customer who is a company's contact shops in that company's context, with its catalogue,
/// prices and quantity rules. `refresh` finds the company and puts the buyer on the Storefront API (`StorefrontAPI.buyer`)
/// and on the cart; anyone else (signed out, or not a company contact) is a retail shopper. The chosen location is kept in
/// `defaults`. `accessToken` is the customer's Customer Account API token (nil when signed out), which the Storefront API
/// takes as it is (Shopify deprecated exchanging it for a Storefront customer token); `companies` lists the customer's
/// company contacts; `sample` says the sample account is on show, whose company is displayed without a buyer (it has no
/// token to send).
///
/// A failure never reaches the shopper: it is logged, and the app stays in the retail context.
/// ponytail: the buyer's token is as fresh as the last `refresh` (sign-in, app start, back in the foreground, a token
/// change). An app kept in the foreground past the token's life keeps sending the old one. Upgrade: have the Storefront
/// transport ask for a valid token on every call.
@MainActor
@Observable
final class BuyerStore {
    /// Nil for a retail shopper.
    private(set) var company: BuyerCompany? = nil

    private let storefront: StorefrontAPI
    private let cart: CartStore
    private let defaults: UserDefaults
    private let accessToken: () async throws -> String?
    private let companies: () async throws -> [CompanyContact]
    private let sample: () -> Bool
    // One change at a time: a refresh that a newer one overtakes must not apply its company last.
    private let lock = AsyncLock()
    private static let locationKey = "buyer.location"

    init(
        storefront: StorefrontAPI,
        cart: CartStore,
        defaults: UserDefaults,
        accessToken: @escaping () async throws -> String?,
        companies: @escaping () async throws -> [CompanyContact],
        sample: @escaping () -> Bool = { false }
    ) {
        self.storefront = storefront
        self.cart = cart
        self.defaults = defaults
        self.accessToken = accessToken
        self.companies = companies
        self.sample = sample
    }

    /// Finds the customer's company and applies it: after sign-in, at start with a session, and when the token changes
    /// (the Storefront API and the cart hold the token itself). Signed out, or without a company: retail.
    func refresh() async {
        await lock.lock()
        defer { lock.unlock() }
        do {
            let token = try await accessToken()
            guard token != nil || sample() else { return await retail() }
            // ponytail: the first company that has somewhere to buy for. A contact of several companies can't switch
            // between them: add a company picker beside the location one when a store needs it.
            let contact = try await companies().first { !$0.company.locations.isEmpty }
            guard let contact = contact, let first = contact.company.locations.first else { return await retail() }
            let stored = defaults.string(forKey: Self.locationKey)
            // the stored location, if the company still offers it
            let locationId = contact.company.locations.first { $0.id == stored }?.id ?? first.id
            company = BuyerCompany(
                contactId: contact.id,
                companyName: contact.company.name,
                locations: contact.company.locations,
                locationId: locationId
            )
            guard let token = token else { return }
            let buyer = Buyer(customerAccessToken: token, companyLocationId: locationId)
            if storefront.buyer == buyer { return }
            storefront.buyer = buyer
            try await cart.setBuyer(locationId)
        } catch {
            // the error's type only: a message could carry a URL
            buyerLog.warning("company not applied, shopping as a retail customer: \(String(describing: type(of: error)), privacy: .public)")
            await retail()
        }
    }

    /// Buys for another of the company's locations from now on.
    func select(_ locationId: String) async {
        defaults.set(locationId, forKey: Self.locationKey)
        await refresh()
    }

    /// Signed out: back to a retail shopper. The chosen location stays for the next sign-in.
    func clear() async {
        await lock.lock()
        defer { lock.unlock() }
        await retail()
    }

    /// With the lock held.
    private func retail() async {
        company = nil
        storefront.buyer = nil
        // nil only forgets the location: nothing is sent, so nothing can fail
        _ = try? await cart.setBuyer(nil)
    }
}
