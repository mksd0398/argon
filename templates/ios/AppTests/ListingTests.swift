import XCTest
@testable import ArgonStorefront

final class ListingTests: XCTestCase {
    private func card(_ id: String) -> ProductCard {
        ProductCard(id: id, handle: "h-\(id)", title: "T-\(id)", available: true, image: nil, price: Money(amount: "1.00", currencyCode: "USD"), compareAt: nil)
    }

    private func page(_ ids: [String], _ next: String?, _ filters: [Filter] = []) -> ProductPage {
        ProductPage(items: ids.map { card($0) }, filters: filters, endCursor: next, hasNext: next != nil)
    }

    private let color = Filter(
        id: "f",
        label: "Color",
        type: "LIST",
        values: [FilterValue(id: "v", label: "Red", count: 2, input: #"{"variantOption":{"name":"Color","value":"Red"}}"#)]
    )

    @MainActor
    func testPagesAppendFromTheCursorUntilTheLast() async {
        var cursors: [String?] = []
        let l = Listing(sorts: collectionSorts) { after, _, _ in
            cursors.append(after)
            return after == nil ? self.page(["a", "b"], "c1") : self.page(["c"], nil)
        }
        await l.reload().value
        XCTAssertEqual(l.items.map { $0.id }, ["a", "b"])
        XCTAssertTrue(l.hasNext)
        _ = await l.loadMore()?.value
        XCTAssertEqual(l.items.map { $0.id }, ["a", "b", "c"])
        XCTAssertFalse(l.hasNext)
        XCTAssertNil(l.loadMore(), "nothing left: no request")
        XCTAssertEqual(cursors, [nil, "c1"])
    }

    @MainActor
    func testARepeatedProductIsKeptOnce() async {
        let l = Listing(sorts: collectionSorts) { after, _, _ in
            after == nil ? self.page(["a", "b"], "c1") : self.page(["b", "c"], nil)
        }
        await l.reload().value
        _ = await l.loadMore()?.value
        XCTAssertEqual(l.items.map { $0.id }, ["a", "b", "c"])
    }

    @MainActor
    func testReloadStartsOverWithTheNewSortAndFilters() async {
        var seen: [(after: String?, sort: Sort, applied: [String])] = []
        let l = Listing(sorts: collectionSorts) { after, sort, applied in
            seen.append((after: after, sort: sort, applied: applied))
            return self.page(["x\(seen.count)"], "next")
        }
        await l.reload().value
        _ = await l.loadMore()?.value
        await l.reload(sort: collectionSorts[3]).value
        await l.reload(applied: [#"{"available":true}"#]).value
        XCTAssertEqual(l.items.map { $0.id }, ["x4"])
        XCTAssertEqual(seen.map { $0.after }, [nil, "next", nil, nil])
        XCTAssertEqual(seen.map { $0.sort }, [collectionSorts[0], collectionSorts[0], collectionSorts[3], collectionSorts[3]])
        XCTAssertEqual(seen.map { $0.applied }, [[], [], [], [#"{"available":true}"#]])
    }

    @MainActor
    func testFailureShowsTheMessageAndReloadRecovers() async {
        var fail = true
        let l = Listing(sorts: collectionSorts) { _, _, _ in
            if fail { throw StorefrontException(messages: ["boom"], status: 200) }
            return self.page(["a"], nil)
        }
        await l.reload().value
        XCTAssertEqual(l.error, "boom")
        XCTAssertFalse(l.loading)
        XCTAssertTrue(l.items.isEmpty)
        fail = false
        await l.reload().value
        XCTAssertNil(l.error)
        XCTAssertEqual(l.items.map { $0.id }, ["a"])
    }

    @MainActor
    func testFiltersComeFromTheFirstPageAndSurviveAnEmptyOne() async {
        let color = self.color
        var withFilters = true
        let l = Listing(sorts: collectionSorts) { after, _, _ in
            after == nil ? self.page(["a"], "n", withFilters ? [color] : []) : self.page(["b"], nil)
        }
        await l.reload().value
        XCTAssertEqual(l.filters, [color])
        _ = await l.loadMore()?.value // later pages carry no filters of their own
        XCTAssertEqual(l.filters, [color])
        withFilters = false
        await l.reload(applied: [#"{"available":true}"#]).value
        XCTAssertEqual(l.filters, [color])
    }

    @MainActor
    func testANewQueryDropsTheFiltersOfTheOldOne() async {
        let color = self.color
        var query = "shirt"
        let l = Listing(sorts: searchSorts) { _, _, _ in self.page(["a"], nil, query == "shirt" ? [color] : []) }
        await l.reload().value
        XCTAssertEqual(l.filters, [color])
        query = "hat" // a different search: no facets of its own, and none of the old query's either
        await l.reload(sort: searchSorts[0], applied: [], resetFilters: true).value
        XCTAssertTrue(l.filters.isEmpty)
        XCTAssertTrue(l.applied.isEmpty)
    }

    @MainActor
    func testFiltersAreClearedAtOnceNotWhenTheNewPageArrives() async {
        let color = Filter(id: "f", label: "Color", type: "LIST", values: [])
        var slow = false
        let l = Listing(sorts: searchSorts) { _, _, _ in
            if slow { try await Task.sleep(nanoseconds: 10_000_000_000) }
            return self.page(["a"], nil, [color])
        }
        await l.reload().value
        slow = true
        let pending = l.reload(resetFilters: true)
        XCTAssertTrue(l.filters.isEmpty, "the old query's facets must not show while the new one loads")
        XCTAssertTrue(l.loading)
        pending.cancel()
    }

    @MainActor
    func testPageCounterAdvancesEvenWhenAPageAddsNothing() async {
        let l = Listing(sorts: collectionSorts) { after, _, _ in
            switch after {
            case nil: return self.page(["a", "b"], "c1")
            case "c1"?: return self.page(["a"], "c2") // only a repeat
            default: return self.page([], "c3") // an empty page that still has a next
            }
        }
        await l.reload().value
        XCTAssertEqual(l.pagesLoaded, 1)
        _ = await l.loadMore()?.value
        XCTAssertEqual(l.pagesLoaded, 2)
        XCTAssertEqual(l.items.count, 2)
        _ = await l.loadMore()?.value
        XCTAssertEqual(l.pagesLoaded, 3, "a footer keyed on this restarts although items.count didn't change")
        XCTAssertEqual(l.items.count, 2)
        XCTAssertTrue(l.hasNext)
    }

    @MainActor
    func testMoreWithoutACursorIsNotMore() async {
        let l = Listing(sorts: collectionSorts) { _, _, _ in
            ProductPage(items: [self.card("a")], filters: [], endCursor: nil, hasNext: true)
        }
        await l.reload().value
        XCTAssertFalse(l.hasNext)
    }

    func testVariablesCarrySortFiltersAndCursor() throws {
        let vars = listingVars(nil, collectionSorts[3], [#"{"available":true}"#], ["handle": "men"])
        XCTAssertEqual(vars["handle"] as? String, "men")
        XCTAssertEqual(vars["first"] as? Int, 24)
        XCTAssertTrue(vars["after"] is NSNull)
        XCTAssertEqual(vars["sortKey"] as? String, "PRICE")
        XCTAssertEqual(vars["reverse"] as? Bool, true)
        let filters = try XCTUnwrap(vars["filters"] as? [[String: Any]])
        XCTAssertEqual(filters.first?["available"] as? Bool, true)

        let next = listingVars("c1", searchSorts[0], [])
        XCTAssertEqual(next["after"] as? String, "c1")
        XCTAssertEqual(next["sortKey"] as? String, "RELEVANCE")
        XCTAssertNil(next["filters"], "no filters key when none are applied")
    }

    private func price(_ filter: String?) throws -> [String: Double] {
        let text = try XCTUnwrap(filter)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        return try XCTUnwrap(object["price"] as? [String: Double])
    }

    func testPriceFilterGivesMinAndOrMax() throws {
        XCTAssertEqual(try price(priceFilter("10", " 50.5 ")), ["min": 10, "max": 50.5])
        XCTAssertEqual(try price(priceFilter("", "20")), ["max": 20])
        XCTAssertEqual(try price(priceFilter("12,5", "")), ["min": 12.5], "a comma-decimal keyboard's comma")
        XCTAssertNil(priceFilter("", "abc"))
    }
}
