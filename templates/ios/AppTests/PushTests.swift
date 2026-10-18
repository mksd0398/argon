import XCTest
@testable import ArgonStorefront

/// Push (Push.swift) with fakes for the OS prompt, the topics and the device report.
@MainActor
final class PushTests: XCTestCase {
    private var defaults: UserDefaults!
    private var topics: [String] = []
    private var reports: [DeviceReport] = []

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "PushTests")
        defaults.removePersistentDomain(forName: "PushTests")
        topics = []
        reports = []
    }

    private func store(allowed: Bool = true, failing: String? = nil) -> PushStore {
        PushStore(
            defaults: defaults,
            permission: { allowed },
            topic: { [unowned self] name, subscribe in
                if subscribe && name == failing { throw URLError(.notConnectedToInternet) }
                topics.append((subscribe ? "+" : "-") + name)
            },
            report: { [unowned self] in reports.append($0) }
        )
    }

    func testTheInstallIdIsMadeOnceAndKept() {
        let id = store().installId
        XCTAssertFalse(id.isEmpty)
        XCTAssertEqual(store().installId, id, "another launch reads the same id")
        XCTAssertNotNil(UUID(uuidString: id))
    }

    func testEnableAsksSubscribesAndReports() async throws {
        let push = store()
        let enabled = try await push.enable()
        XCTAssertTrue(enabled)
        XCTAssertTrue(push.optedIn)
        XCTAssertEqual(topics, ["+all", "+ios"])
        XCTAssertEqual(reports, [DeviceReport(installId: push.installId, platform: "ios", optedIn: true)])
        XCTAssertTrue(store().optedIn, "remembered")

        await push.disable()
        XCTAssertFalse(push.optedIn)
        XCTAssertEqual(topics, ["+all", "+ios", "-all", "-ios"])
        XCTAssertEqual(reports.last, DeviceReport(installId: push.installId, platform: "ios", optedIn: false))
        XCTAssertFalse(store().optedIn)
    }

    func testARefusalOrAFailedTopicLeavesItOff() async throws {
        let refused = store(allowed: false)
        let enabled = try await refused.enable()
        XCTAssertFalse(enabled)
        XCTAssertFalse(refused.optedIn)
        XCTAssertEqual(topics, [])
        XCTAssertEqual(reports, [])

        // the second topic fails: the first is left again, and nothing is on
        let failing = store(failing: "ios")
        let error = await thrownError { try await failing.enable() }
        XCTAssertNotNil(error)
        XCTAssertFalse(failing.optedIn)
        XCTAssertEqual(topics, ["+all", "-all"])
        XCTAssertEqual(reports, [])
    }

    func testTheOfferAfterAPurchaseIsMadeOnce() async throws {
        let push = store()
        push.offerAfterPurchase()
        XCTAssertTrue(push.offering)
        push.offering = false
        push.markAsked()
        push.offerAfterPurchase()
        XCTAssertFalse(push.offering, "made once")
        XCTAssertTrue(store().askedAfterPurchase)

        // nor to a shopper who has them on
        defaults.removePersistentDomain(forName: "PushTests")
        let on = store()
        _ = try await on.enable()
        on.offerAfterPurchase()
        XCTAssertFalse(on.offering)
    }

    func testANotificationsLinkResolves() {
        let hosts = ["mock.shop"]
        XCTAssertEqual(PushStore.link(["link": " /collections/sale ", "aps": ["alert": "Sale"]]), "/collections/sale")
        XCTAssertEqual(Links.resolve(PushStore.link(["link": "/products/hoodie"]), hosts: hosts), .product("hoodie"))
        XCTAssertEqual(Links.resolve(PushStore.link(["link": "app://screens/about"]), hosts: hosts), .screen("about"))
        XCTAssertNil(PushStore.link(["link": ""]))
        XCTAssertNil(PushStore.link(["aps": ["alert": "Hi"]]))
        XCTAssertNil(PushStore.link(["link": 3]))
    }

    func testTheReportIsTheDevicesJson() throws {
        let data = try JSONEncoder().encode(DeviceReport(installId: "abc", platform: "ios", optedIn: true))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object as NSDictionary, ["installId": "abc", "platform": "ios", "optedIn": true] as NSDictionary)
    }

    func testWithoutPushNothingIsWired() {
        // the demo is built without PUSH (and without Firebase Messaging)
        XCTAssertFalse(AppGraph.pushEnabled)
        XCTAssertNil(AppGraph.push)
    }
}
