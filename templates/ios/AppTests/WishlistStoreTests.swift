import XCTest
@testable import ArgonStorefront

final class WishlistStoreTests: XCTestCase {
    private let suite = UUID().uuidString

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// A store on this test's defaults: a new one over the same defaults is the app after a restart.
    @MainActor
    private func store() -> WishlistStore { WishlistStore(defaults: UserDefaults(suiteName: suite)!) }

    @MainActor
    func testToggleAddsThenRemoves() async {
        let s = store()
        XCTAssertEqual(s.ids, [])
        await s.toggle("a")
        XCTAssertEqual(s.ids, ["a"])
        XCTAssertTrue(s.contains("a"))
        await s.toggle("a")
        XCTAssertEqual(s.ids, [])
        XCTAssertFalse(s.contains("a"))
    }

    @MainActor
    func testNewestFirstAndReAddingMovesToFront() async {
        let s = store()
        await s.toggle("a")
        await s.toggle("b")
        XCTAssertEqual(s.ids, ["b", "a"])
        await s.toggle("a") // removed
        XCTAssertEqual(s.ids, ["b"])
        await s.toggle("a") // added again: now the newest
        XCTAssertEqual(s.ids, ["a", "b"])
    }

    @MainActor
    func testSurvivesARestart() async {
        await store().toggle("a")
        XCTAssertEqual(store().ids, ["a"])
    }

    @MainActor
    func testSavingAProductReportsItToAnalyticsAndTakingItOutDoesNot() async {
        var events: [AnalyticsEvent] = []
        let s = WishlistStore(defaults: UserDefaults(suiteName: suite)!, track: { events.append($0) })
        let saved = AnalyticsEvent.addToWishlist(AnalyticsItem(productId: "1", name: "Hoodie", price: 90.0), currency: "CAD")
        await s.toggle("gid://shopify/Product/1", added: saved)
        XCTAssertEqual(events, [saved])
        await s.toggle("gid://shopify/Product/1", added: saved) // taken out again
        await s.toggle("gid://shopify/Product/2") // a caller that doesn't describe the product
        XCTAssertEqual(events, [saved])
    }
}
