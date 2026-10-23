import Foundation

/// What `CrashReports` hands its reports to: Crashlytics (`FirebaseCrash.swift`), in an app built with the store's
/// Firebase file and Firebase's Crashlytics product.
protocol CrashBackend {
    func setKey(_ key: String, _ value: String)
    func log(_ message: String)
    func record(_ error: Error, where: String)
}

/// Crash reporting: the keys a crash is reported with, the breadcrumbs before it, and the caught failures worth fixing
/// (non-fatal reports). Always compiled, so every call site is unconditional: without Firebase, and in tests, `backend`
/// is nil and every call does nothing.
///
/// Crash reports are not behind the analytics switch: they carry no personal data (the keys, no user id). The
/// breadcrumbs are, as a sink of the analytics hub (`CrashSink`).
enum CrashReports {
    nonisolated(unsafe) static var backend: CrashBackend?

    static func setKey(_ key: String, _ value: String) { backend?.setKey(key, value) }

    static func log(_ message: String) { backend?.log(message) }

    /// A caught failure that is a bug somewhere (the app's, or the store's content): reported, the app carries on.
    static func record(_ error: Error, _ where: String) {
        backend?.log("non-fatal: \(`where`)")
        backend?.record(error, where: `where`)
    }

    /// Starts crash reporting as the app launches, before anything that could crash: the backend, and what the app is.
    @MainActor static func start() {
        backend = crashBackend()
        setKey("shop", AppGraph.shopDomain)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        setKey("app_version", "\(version) (\(build))")
        setKey("argon", AppGraph.argonRevision)
        #if DEBUG
        // Debug builds only: launched with `-ArgonTestCrash YES` (Xcode's launch arguments, or `xcrun simctl launch`),
        // the app crashes a second after launch, to prove crash reports reach the store's Firebase (they are sent at
        // the next launch).
        if UserDefaults.standard.bool(forKey: "ArgonTestCrash") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { fatalError("Argon test crash (debug builds only)") }
        }
        #endif
    }
}

/// The breadcrumbs: every analytics event the shopper allows, as one line before a crash.
struct CrashSink: AnalyticsSink {
    func track(_ event: AnalyticsEvent) { CrashReports.log(breadcrumb(event)) }
}

/// One event as a breadcrumb, as the debug log prints it: `add_to_cart {value=499.0, currency=INR, …}`, at most 300 characters.
func breadcrumb(_ event: AnalyticsEvent) -> String { String("\(event.name) \(event.paramsText)".prefix(300)) }
