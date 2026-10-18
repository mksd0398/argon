// Push through Firebase Cloud Messaging. Compiled in only when the app has Firebase Messaging (an app built with
// `--push`: the CLI adds the `FirebaseMessaging` product); without it `firebasePush` is the one at the bottom, nil.
// Rich images in notifications need a notification service extension, which the app doesn't have yet.
#if canImport(FirebaseMessaging)
import FirebaseCore
import FirebaseMessaging
import Foundation

/// The push store, once Firebase is started with its own file, `GoogleService-Info.plist`; nil in an app without it.
@MainActor
func firebasePush() -> PushStore? {
    guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return nil }
    if FirebaseApp.app() == nil { FirebaseApp.configure() }
    return PushStore(
        defaults: .standard,
        permission: askNotificationPermission,
        topic: { name, subscribe in
            if subscribe {
                // a topic needs the FCM token, which needs the APNs token: registering for it has just been asked
                // ponytail: polled for up to ten seconds; a delegate callback would be exact
                for _ in 0..<20 where Messaging.messaging().apnsToken == nil {
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
                try await Messaging.messaging().subscribe(toTopic: name)
            } else {
                // leaving needs no wait: without a token there was no subscription to leave
                try await Messaging.messaging().unsubscribe(fromTopic: name)
            }
        },
        report: { try await PushStore.post($0, to: AppGraph.devicesUrl) }
    )
}

/// The APNs token iOS gave the app: Firebase's own app-delegate proxy is off (Info.plist), so it is handed on here.
@MainActor
func pushRegistered(_ token: Data) {
    Messaging.messaging().apnsToken = token
}
#else
import Foundation

@MainActor
func firebasePush() -> PushStore? { nil }

@MainActor
func pushRegistered(_ token: Data) {}
#endif
