import Foundation
import Observation

/// Saved product ids, newest first, no duplicates, kept on the device in `defaults`.
@MainActor
@Observable
final class WishlistStore {
    private(set) var ids: [String] = []

    private let defaults: UserDefaults
    // an array keeps the order (a set would not)
    private static let key = "wishlist"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        ids = defaults.stringArray(forKey: Self.key) ?? []
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    /// Adds `productId` as the newest, or removes it when saved.
    func toggle(_ productId: String) async {
        ids = ids.contains(productId) ? ids.filter { $0 != productId } : [productId] + ids
        defaults.set(ids, forKey: Self.key)
    }
}
