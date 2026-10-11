import Foundation
import Observation

/// Saved product ids, newest first, no duplicates, kept on the device in `defaults`. `track` gets a product's
/// `add_to_wishlist` once it is saved.
@MainActor
@Observable
final class WishlistStore {
    private(set) var ids: [String] = []

    private let defaults: UserDefaults
    private let track: (AnalyticsEvent) -> Void
    // an array keeps the order (a set would not)
    private static let key = "wishlist"

    init(defaults: UserDefaults, track: @escaping (AnalyticsEvent) -> Void = { _ in }) {
        self.defaults = defaults
        self.track = track
        ids = defaults.stringArray(forKey: Self.key) ?? []
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    /// Adds `productId` as the newest, or removes it when saved. `added` is the event to report when this adds it: the
    /// store holds ids alone, so the caller, which has the product, describes it.
    func toggle(_ productId: String, added: AnalyticsEvent? = nil) async {
        let isNew = !ids.contains(productId)
        ids = isNew ? [productId] + ids : ids.filter { $0 != productId }
        defaults.set(ids, forKey: Self.key)
        if isNew, let added = added { track(added) }
    }
}
