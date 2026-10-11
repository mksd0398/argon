import XCTest
@testable import ArgonStorefront

final class RecentlyViewedStoreTests: XCTestCase {
    private let suite = UUID().uuidString

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// A store on this test's defaults: a new one over the same defaults is the app after a restart.
    @MainActor
    private func store() -> RecentlyViewedStore { RecentlyViewedStore(defaults: UserDefaults(suiteName: suite)!) }

    @MainActor
    func testNewestFirstAndSeeingOneAgainMovesItToTheFront() {
        let s = store()
        XCTAssertEqual(s.ids, [])
        s.add("a")
        s.add("b")
        s.add("c")
        XCTAssertEqual(s.ids, ["c", "b", "a"])
        s.add("a")
        XCTAssertEqual(s.ids, ["a", "c", "b"], "no duplicates")
        s.add("a")
        XCTAssertEqual(s.ids, ["a", "c", "b"])
    }

    @MainActor
    func testKeepsTheLastTwelve() {
        let s = store()
        for number in 1...15 { s.add("p\(number)") }
        XCTAssertEqual(s.ids.count, 12)
        XCTAssertEqual(s.ids.first, "p15")
        XCTAssertEqual(s.ids.last, "p4", "the oldest three dropped off")
    }

    @MainActor
    func testSurvivesARestart() {
        let s = store()
        s.add("a")
        s.add("b")
        XCTAssertEqual(store().ids, ["b", "a"])
    }
}
