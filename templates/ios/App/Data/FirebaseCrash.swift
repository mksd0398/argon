// Crash reports through Crashlytics. Compiled in only when the app has Firebase's `FirebaseCrashlytics` product (the CLI
// adds it with the store's Firebase file); without it `crashBackend` is the one at the bottom, which is nil.
#if canImport(FirebaseCrashlytics)
import FirebaseCore
import FirebaseCrashlytics
import Foundation

/// Crashlytics, once Firebase is started with its own file, `GoogleService-Info.plist`; nil in an app without that file.
@MainActor
func crashBackend() -> CrashBackend? {
    guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return nil }
    if FirebaseApp.app() == nil { FirebaseApp.configure() }
    return CrashlyticsBackend()
}

private struct CrashlyticsBackend: CrashBackend {
    func setKey(_ key: String, _ value: String) { Crashlytics.crashlytics().setCustomValue(value, forKey: key) }

    func log(_ message: String) { Crashlytics.crashlytics().log(message) }

    func record(_ error: Error, where: String) {
        Crashlytics.crashlytics().record(error: error, userInfo: ["where": `where`])
    }
}
#else
@MainActor
func crashBackend() -> CrashBackend? { nil }
#endif
