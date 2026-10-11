// MoEngage. Compiled in only when the app has MoEngage's Swift package (its product `MoEngage-iOS-SDK`: README.md,
// "Analytics"); without it `moEngageSink` is the one at the bottom, which is nil.
#if canImport(MoEngageSDK)
import Foundation
import MoEngageCore
import MoEngageSDK

/// The sink, once the SDK is started in the workspace's data center (`MOENGAGE_DATA_CENTER`, 1 when unset); nil unless
/// `MOENGAGE_WORKSPACE_ID` is set. It is started as the app launches, on the main thread, which is where the SDK asks
/// for it, and switched off from the start when the shopper doesn't share usage data: the SDK has no Info.plist default
/// for that, and the choice is known by now. No push and no in-app messages in this app yet.
@MainActor
func moEngageSink() -> AnalyticsSink? {
    guard !AppGraph.moEngageWorkspaceId.isEmpty else { return nil }
    let dataCenter: MoEngageDataCenter
    switch AppGraph.moEngageDataCenter {
    case "2": dataCenter = .data_center_02
    case "3": dataCenter = .data_center_03
    case "4": dataCenter = .data_center_04
    case "5": dataCenter = .data_center_05
    case "6": dataCenter = .data_center_06
    default: dataCenter = .data_center_01
    }
    let config = MoEngageSDKConfig(appId: AppGraph.moEngageWorkspaceId, dataCenter: dataCenter)
    let state: MoEngageSDKState = AppGraph.analyticsConsent.allowed ? .enabled : .disabled
    // a debug build reports to the workspace's test environment, a release build to the live one: MoEngage's own split
    #if DEBUG
    MoEngage.sharedInstance.initializeDefaultTestInstance(config, sdkState: state)
    #else
    MoEngage.sharedInstance.initializeDefaultLiveInstance(config, sdkState: state)
    #endif
    return MoEngageSink()
}

private struct MoEngageSink: AnalyticsSink {
    private var analytics: MoEngageSDKAnalytics { .sharedInstance }

    func track(_ event: AnalyticsEvent) {
        let (name, attributes) = moEngageEvent(event)
        // an event with nothing to say goes without properties: the SDK takes no empty set of them
        analytics.trackEvent(name, withProperties: attributes.isEmpty ? nil : MoEngageProperties(withAttributes: attributes))
    }

    func identify(_ user: AnalyticsUser?) {
        // a sign-out: what follows on this phone is no longer this customer's
        guard let user else {
            analytics.resetUser()
            return
        }
        analytics.identifyUser(identity: user.id)
        if let email = user.email { analytics.setEmailID(email) }
        if let phone = user.phone { analytics.setMobileNumber(phone) }
        if let firstName = user.firstName { analytics.setFirstName(firstName) }
        if let lastName = user.lastName { analytics.setLastName(lastName) }
    }

    /// The whole SDK on or off, not its data-tracking opt-out: with only that off the SDK goes on collecting analytical
    /// data, and the opt-out itself is a call to MoEngage.
    func setEnabled(_ allowed: Bool) {
        if allowed { MoEngage.sharedInstance.enableSDK() } else { MoEngage.sharedInstance.disableSDK() }
    }
}
#else
@MainActor
func moEngageSink() -> AnalyticsSink? { nil }
#endif
