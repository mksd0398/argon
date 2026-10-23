// Google Analytics 4, through Firebase. Compiled in only when the app has Firebase's Swift package (its product
// `FirebaseAnalytics`: README.md, "Analytics"); without it `firebaseSink` is the one at the bottom, which is nil.
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
import FirebaseCore
import Foundation

/// The sink, once Firebase is started with its own file, `GoogleService-Info.plist`; nil in an app without that file.
/// Its SDK collects nothing until the hub says the shopper allows it: `FIREBASE_ANALYTICS_COLLECTION_ENABLED` is off in
/// Info.plist, and `setEnabled` is what turns it on.
@MainActor
func firebaseSink() -> AnalyticsSink? {
    guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return nil }
    // crash reports (FirebaseCrash.swift) may have started it already
    if FirebaseApp.app() == nil { FirebaseApp.configure() }
    return FirebaseSink(serverPurchase: AppGraph.serverPurchase)
}

/// The purchase must reach Google Analytics from one side only: it counts an app's purchase every time it is sent (its
/// `transaction_id` check is for websites). So without the store's server (`serverPurchase` off, `SERVER_PURCHASE`) the
/// app sends the purchase and a cart carries no `_ga_app_instance_id`; with it the app leaves the purchase out and the
/// cart carries the id, which on an order is what tells the server to report it. Whatever versions of the app are in
/// use, no order is counted twice.
///
/// `FirebaseAnalytics.Analytics` is Firebase's: unqualified, `Analytics` is the app's hub.
private struct FirebaseSink: AnalyticsSink {
    let serverPurchase: Bool

    func track(_ event: AnalyticsEvent) {
        guard let params = ga4Params(event, serverPurchase: serverPurchase) else { return }
        FirebaseAnalytics.Analytics.logEvent(event.name, parameters: params)
    }

    func identify(_ user: AnalyticsUser?) {
        FirebaseAnalytics.Analytics.setUserID(user?.id)
    }

    func cartAttributes() async -> [String: String] {
        // no id (the SDK has none yet): an order the server leaves alone
        guard serverPurchase, let id = FirebaseAnalytics.Analytics.appInstanceID() else { return [:] }
        return ["_ga_app_instance_id": id]
    }

    /// The SDK remembers this over the Info.plist default, so after the first launch it starts as the shopper left it.
    func setEnabled(_ allowed: Bool) {
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(allowed)
    }
}
#else
@MainActor
func firebaseSink() -> AnalyticsSink? { nil }
#endif
