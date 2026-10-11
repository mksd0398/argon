// Meta, through the Facebook SDK's App Events. Compiled in only when the app has the SDK's Swift package (its product
// `FacebookCore`: README.md, "Analytics"); without it `metaSink` is the one at the bottom, which is nil.
#if canImport(FacebookCore)
import FacebookCore
import UIKit

/// The sink, once the SDK is started; nil unless `META_APP_ID` and `META_CLIENT_TOKEN` are set. The SDK reads the two
/// itself, and the app's name, in Info.plist (`FacebookAppID`, `FacebookClientToken`, `FacebookDisplayName`). It collects
/// nothing of its own until the hub says the shopper allows it: Info.plist has `FacebookAutoLogAppEventsEnabled` and
/// `FacebookAdvertiserIDCollectionEnabled` off, and `setEnabled` is what turns them on.
@MainActor
func metaSink() -> AnalyticsSink? {
    guard !AppGraph.metaAppId.isEmpty, !AppGraph.metaClientToken.isEmpty else { return nil }
    ApplicationDelegate.shared.initializeSDK()
    return MetaSink()
}

private struct MetaSink: AnalyticsSink {
    func track(_ event: AnalyticsEvent) {
        guard let mapped = metaEvent(event) else { return }
        let name = AppEvents.Name(mapped.name)
        let parameters = Dictionary(uniqueKeysWithValues: mapped.params.map { (AppEvents.ParameterName($0.key), $0.value) })
        if case let .purchase(_, value, currency, _, _, _, _) = event {
            // the SDK's own call for a purchase: it doesn't wait for its next batch to send it
            AppEvents.shared.logPurchase(amount: value, currency: currency, parameters: parameters)
        } else if let value = mapped.value {
            AppEvents.shared.logEvent(name, valueToSum: value, parameters: parameters)
        } else {
            AppEvents.shared.logEvent(name, parameters: parameters)
        }
    }

    // the SDK hashes the customer's details before they leave the phone
    func identify(_ user: AnalyticsUser?) {
        AppEvents.shared.userID = user?.id
        guard let user else { return AppEvents.shared.clearUserData() }
        AppEvents.shared.setUser(
            email: user.email,
            firstName: user.firstName,
            lastName: user.lastName,
            phone: user.phone,
            dateOfBirth: nil,
            gender: nil,
            city: nil,
            state: nil,
            zip: nil,
            country: nil
        )
    }

    /// What the store's server needs to send Meta the purchase as this app install's: the SDK's id for it, and the device.
    func cartAttributes() async -> [String: String] {
        let info = Bundle.main.infoDictionary ?? [:]
        let screen = UIScreen.main
        let timezone = TimeZone.current
        return [
            "_meta_anon_id": AppEvents.shared.anonymousID,
            "_meta_extinfo": metaExtinfo(
                bundleId: Bundle.main.bundleIdentifier ?? "",
                build: info["CFBundleVersion"] as? String ?? "",
                version: info["CFBundleShortVersionString"] as? String ?? "",
                osVersion: UIDevice.current.systemVersion,
                model: machine(),
                locale: Locale.current.identifier,
                timezoneAbbreviation: timezone.abbreviation() ?? "",
                screenWidth: Int(screen.bounds.width),
                screenHeight: Int(screen.bounds.height),
                screenDensity: Int(screen.scale),
                cores: ProcessInfo.processInfo.activeProcessorCount,
                timezone: timezone.identifier
            ),
            // The phone's answer to iOS's tracking prompt (ATT), as the SDK reads it. The app doesn't show the prompt, so
            // this is 0 until a store adds it.
            "_meta_tracking": Settings.shared.isAdvertiserTrackingEnabled ? "1" : "0",
        ]
    }

    /// The SDK's own collection: the events it logs by itself (installs, sessions) and the advertising id. It remembers
    /// both over the Info.plist defaults. Meta's dashboard has a switch of its own, "Automatic event logging for the
    /// Facebook SDK", which wins over the first: a store must leave that one alone for the shopper's choice to hold.
    func setEnabled(_ allowed: Bool) {
        Settings.shared.isAutoLogAppEventsEnabled = allowed
        Settings.shared.isAdvertiserIDCollectionEnabled = allowed
    }
}

/// The device's model as Apple numbers it ("iPhone15,2").
private func machine() -> String {
    var system = utsname()
    uname(&system)
    return withUnsafeBytes(of: system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
}
#else
@MainActor
func metaSink() -> AnalyticsSink? { nil }
#endif
