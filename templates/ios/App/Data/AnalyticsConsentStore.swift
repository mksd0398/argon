import Foundation
import Observation

/// Whether the shopper lets the app share what they do in it ("Share usage data" on the Account screen), kept on the
/// device in `defaults`: on until they turn it off. `changed` is called after each change of the choice.
/// ponytail: one switch, on by default. A store selling in the EU needs a prompt before the first event.
@MainActor
@Observable
final class AnalyticsConsentStore {
    private(set) var allowed: Bool

    private let defaults: UserDefaults
    private let changed: () -> Void
    private static let key = "analytics.allowed"

    init(defaults: UserDefaults, changed: @escaping () -> Void = {}) {
        self.defaults = defaults
        self.changed = changed
        // not `bool(forKey:)`: a choice never made would read as off
        allowed = defaults.object(forKey: Self.key) as? Bool ?? true
    }

    func set(_ allowed: Bool) {
        self.allowed = allowed
        defaults.set(allowed, forKey: Self.key)
        changed()
    }
}
