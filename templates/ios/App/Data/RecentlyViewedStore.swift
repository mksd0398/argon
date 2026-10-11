import Foundation
import Observation

/// The products the shopper looked at last: their ids, newest first, no duplicates, at most 12, kept on the device in
/// `defaults`. The product page adds itself and shows the others.
@MainActor
@Observable
final class RecentlyViewedStore {
    private(set) var ids: [String] = []

    private let defaults: UserDefaults
    private static let key = "recentlyViewed"
    private static let limit = 12

    init(defaults: UserDefaults) {
        self.defaults = defaults
        ids = defaults.stringArray(forKey: Self.key) ?? []
    }

    /// Puts `productId` first (moving it there when it was already seen); the oldest drops off past the limit.
    func add(_ productId: String) {
        ids = Array(([productId] + ids.filter { $0 != productId }).prefix(Self.limit))
        defaults.set(ids, forKey: Self.key)
    }
}
