import Foundation
import Observation

/// Whether the shopper lets the app share what they do in it ("Share usage data" on the Account screen), kept on the
/// device in `defaults`: on until they turn it off.
/// ponytail: one switch, on by default. A store selling in the EU needs a prompt before the first event.
@MainActor
@Observable
final class AnalyticsConsentStore {
    private(set) var allowed: Bool

    private let defaults: UserDefaults
    private static let key = "analytics.allowed"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // not `bool(forKey:)`: a choice never made would read as off
        allowed = defaults.object(forKey: Self.key) as? Bool ?? true
    }

    func set(_ allowed: Bool) {
        self.allowed = allowed
        defaults.set(allowed, forKey: Self.key)
    }
}
