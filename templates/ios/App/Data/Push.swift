import Foundation
import Observation
import os
import UIKit
import UserNotifications

// Push notifications (screens v2 spec, "Push notifications"), only in an app built with `PUSH`: the store's own Firebase
// Cloud Messaging, whose campaigns Krypton sends to the topics `all` and `ios` with a `data.link`. The Firebase part
// (topics, the APNs token) is FirebasePush.swift, compiled in with Firebase Messaging; this part is always compiled,
// so it is tested without the SDK. The same on Android (Push.kt).

private let pushLog = Logger(subsystem: "app.storefront", category: "Push")

/// What a device reports to `DEVICES_URL`: an anonymous install id, and whether it takes notifications.
struct DeviceReport: Encodable, Equatable, Sendable {
    let installId: String
    let platform: String
    let optedIn: Bool
}

/// The opt-in to push. `enable` asks the OS (`permission`), subscribes this install to the topics `PushStore.topics`
/// and reports it, `disable` the reverse; through the functions given (`topic`: subscribe or unsubscribe one topic;
/// `report`: send the device's state), and each is remembered in `defaults`. Analytics consent doesn't gate push: the
/// OS permission does.
@MainActor
@Observable
final class PushStore {
    static let platform = "ios"

    /// The FCM topics Krypton sends campaigns to: everyone's, and this platform's.
    static let topics = ["all", platform]

    /// Whether this install takes notifications (as last chosen here).
    private(set) var optedIn: Bool

    /// Whether the one offer after a first purchase was made already.
    private(set) var askedAfterPurchase: Bool

    /// The offer after a first purchase is on show (`offerAfterPurchase`).
    var offering = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let permission: () async -> Bool
    @ObservationIgnored private let topic: (_ name: String, _ subscribe: Bool) async throws -> Void
    @ObservationIgnored private let report: (DeviceReport) async throws -> Void

    private static let idKey = "push.installId"
    private static let optedInKey = "push.optedIn"
    private static let askedKey = "push.askedAfterPurchase"

    init(
        defaults: UserDefaults,
        permission: @escaping () async -> Bool,
        topic: @escaping (_ name: String, _ subscribe: Bool) async throws -> Void,
        report: @escaping (DeviceReport) async throws -> Void
    ) {
        self.defaults = defaults
        self.permission = permission
        self.topic = topic
        self.report = report
        optedIn = defaults.bool(forKey: Self.optedInKey)
        askedAfterPurchase = defaults.bool(forKey: Self.askedKey)
    }

    /// The install's anonymous id: made once, then kept on the device.
    var installId: String {
        if let id = defaults.string(forKey: Self.idKey) { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: Self.idKey)
        return id
    }

    /// Asks the OS, then subscribes to every topic and reports the opt-in. False when the shopper (or an earlier choice in
    /// Settings) refuses; a topic that fails throws. Either way the switch stays off.
    func enable() async throws -> Bool {
        guard await permission() else { return false }
        var done: [String] = []
        do {
            for name in Self.topics {
                try await topic(name, true)
                done.append(name)
            }
        } catch {
            // half subscribed is not on: the topics that took are left again (best effort)
            for name in done { try? await topic(name, false) }
            throw error
        }
        await set(true)
        return true
    }

    /// Reports the opt-out, then unsubscribes from every topic (one that fails is only logged).
    func disable() async {
        await set(false)
        for name in Self.topics {
            do {
                try await topic(name, false)
            } catch {
                pushLog.warning("unsubscribe from \(name, privacy: .public) failed: \(error.localizedDescription)")
            }
        }
    }

    /// After an order: the one offer of notifications, unless they are on or it was made before.
    func offerAfterPurchase() {
        if !optedIn && !askedAfterPurchase { offering = true }
    }

    /// The offer after a first purchase was made (accepted or not): it isn't made again.
    func markAsked() {
        askedAfterPurchase = true
        defaults.set(true, forKey: Self.askedKey)
    }

    private func set(_ on: Bool) async {
        optedIn = on
        defaults.set(on, forKey: Self.optedInKey)
        // fire and forget: a report that fails is only logged
        do {
            try await report(DeviceReport(installId: installId, platform: Self.platform, optedIn: on))
        } catch {
            pushLog.warning("device report failed: \(error.localizedDescription)")
        }
    }

    /// The `link` of a notification (FCM puts its `data` at the top of the payload); nil without one.
    nonisolated static func link(_ userInfo: [AnyHashable: Any]) -> String? {
        guard let link = (userInfo["link"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty else { return nil }
        return link
    }

    /// Sends `report` to `url` (`DEVICES_URL`) as JSON; nothing without a url.
    nonisolated static func post(_ report: DeviceReport, to url: String, session: URLSession = .shared) async throws {
        guard !url.isEmpty, let address = URL(string: url) else { return }
        var request = URLRequest(url: address)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(report)
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            pushLog.warning("device report: HTTP \(http.statusCode)")
        }
    }
}

/// The OS prompt for notifications (once; later the earlier answer), then the registration for remote notifications
/// that gives Firebase the APNs token. True when notifications are allowed.
@MainActor
func askNotificationPermission() async -> Bool {
    let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    if granted { UIApplication.shared.registerForRemoteNotifications() }
    return granted
}

/// Shows a notification that comes while the app is open as a banner, and opens a tapped one's `link` in the app
/// (`Links.resolve`), on the tab on show.
final class PushPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let link = PushStore.link(response.notification.request.content.userInfo)
        Task { @MainActor in
            if let route = Links.resolve(link, hosts: AppGraph.brand.value?.hosts ?? [AppGraph.shopDomain]) {
                AppGraph.tabs.open(route)
            }
            completionHandler()
        }
    }
}
