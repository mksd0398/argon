import XCTest
@testable import ArgonStorefront

final class WishlistModelTests: XCTestCase {
    private func card(_ id: String) -> ProductCard {
        ProductCard(id: id, handle: "h-\(id)", title: "T-\(id)", available: true, image: nil, price: Money(amount: "1.00", currencyCode: "USD"), compareAt: nil)
    }

    @MainActor
    func testCardsFollowTheWishlistOrderNotTheOrderTheStoreAnswers() async {
        let m = WishlistModel { ids in ids.reversed().map { self.card($0) } }
        let ids = ["b", "a", "c"]
        await m.sync(ids)
        XCTAssertEqual(m.cards(ids).map { $0.id }, ids)
        XCTAssertFalse(m.pending(ids))
    }

    @MainActor
    func testDeletedProductsAreDroppedAndNotAskedAgain() async {
        var asked: [[String]] = []
        let m = WishlistModel { ids in
            asked.append(ids)
            return ids.filter { $0 != "gone" }.map { self.card($0) }
        }
        await m.sync(["a", "gone"])
        XCTAssertEqual(m.cards(["a", "gone"]).map { $0.id }, ["a"])
        XCTAssertFalse(m.pending(["a", "gone"]))
        await m.sync(["new", "a", "gone"]) // only the unseen id is requested
        XCTAssertEqual(asked, [["a", "gone"], ["new"]])
    }

    @MainActor
    func testAFailureShowsItsMessageUntilARetrySucceeds() async {
        var fail = true
        let m = WishlistModel { ids in
            if fail { throw StorefrontException(messages: ["HTTP 503"], status: 503) }
            return ids.map { self.card($0) }
        }
        await m.sync(["a"])
        XCTAssertEqual(m.error, "HTTP 503")
        XCTAssertTrue(m.pending(["a"]))
        fail = false
        await m.sync(["a"])
        XCTAssertNil(m.error)
        XCTAssertEqual(m.cards(["a"]).map { $0.id }, ["a"])
    }

    @MainActor
    func testALongWishlistIsRequestedInBatchesOfTheApiLimit() async {
        var sizes: [Int] = []
        let m = WishlistModel { ids in
            sizes.append(ids.count)
            return ids.map { self.card($0) }
        }
        await m.sync((1...300).map { "p\($0)" })
        XCTAssertEqual(sizes, [250, 50])
    }
}
