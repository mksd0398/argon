import XCTest
@testable import ArgonStorefront

final class CrashReportsTests: XCTestCase {
    private final class Recorded: CrashBackend {
        var logs: [String] = []
        var errors: [String] = []
        func setKey(_ key: String, _ value: String) {}
        func log(_ message: String) { logs.append(message) }
        func record(_ error: Error, where: String) { errors.append(`where`) }
    }

    override func tearDown() {
        CrashReports.backend = nil
    }

    @MainActor
    func testBrokenLiquidIsANonFatalAndStillRenders() {
        let recorded = Recorded()
        CrashReports.backend = recorded
        XCTAssertEqual(Liquid.render("a {% if x %}b", [:]), "a b")
        XCTAssertEqual(recorded.errors, ["liquid: a {% if x %}b"])
    }

    @MainActor
    func testBreadcrumbsComeFromTheAnalyticsEvents() {
        let recorded = Recorded()
        CrashReports.backend = recorded
        CrashSink().track(.screenView("product"))
        XCTAssertEqual(recorded.logs, [breadcrumb(.screenView("product"))])
        XCTAssertTrue(recorded.logs[0].hasPrefix("screen_view"))
    }
}
