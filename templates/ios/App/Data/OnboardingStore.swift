import Foundation
import Observation

/// Whether the shopper has been through the first-launch welcome (`onboarding.done`, kept on the device in `defaults`):
/// it is shown once, before the tabs, and never again once finished or skipped.
@MainActor
@Observable
final class OnboardingStore {
    private(set) var done: Bool

    private let defaults: UserDefaults
    private static let key = "onboarding.done"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        done = defaults.bool(forKey: Self.key)
    }

    /// The shopper finished or skipped the welcome.
    func finish() { save(true) }

    /// Shows the welcome again (debug builds' "Show onboarding").
    func reset() { save(false) }

    private func save(_ done: Bool) {
        self.done = done
        defaults.set(done, forKey: Self.key)
    }
}
