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
            if fail { throw ArgonAPIError.graphql(messages: ["boom"]) }
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

    @MainActor
    func testTheCurrencyIsTheListsOnceAProductHasShownIt() async {
        let l = Listing(sorts: collectionSorts) { after, _, _ in
            after == nil ? self.page(["a"], "c1") : self.page([], nil)
        }
        XCTAssertNil(l.currencyCode)
        await l.reload().value
        XCTAssertEqual(l.currencyCode, "USD")
        _ = await l.loadMore()?.value // an empty page has no price to read: the currency stays
        XCTAssertEqual(l.currencyCode, "USD")
    }

    func testEachListSortsWithTheKeysOfItsOwnQuery() {
        // the values of ProductCollectionSortKeys, ProductSortKeys and SearchSortKeys: a key of another enum is refused by the API
        let collectionKeys: Set<String> = ["COLLECTION_DEFAULT", "BEST_SELLING", "PRICE", "CREATED", "TITLE", "MANUAL", "ID", "RELEVANCE"]
        let catalogKeys: Set<String> = ["BEST_SELLING", "PRICE", "CREATED_AT", "UPDATED_AT", "TITLE", "VENDOR", "PRODUCT_TYPE", "ID", "RELEVANCE"]
        let searchKeys: Set<String> = ["RELEVANCE", "PRICE"]
        XCTAssertTrue(collectionSorts.allSatisfy { collectionKeys.contains($0.key) })
        XCTAssertTrue(catalogSorts.allSatisfy { catalogKeys.contains($0.key) })
        XCTAssertTrue(searchSorts.allSatisfy { searchKeys.contains($0.key) })
        XCTAssertEqual(
            [collectionSorts, catalogSorts, searchSorts].map { $0.first?.label },
            ["Featured", "Best selling", "Relevance"],
            "each list opens in its first sort"
        )
        for sorts in [collectionSorts, catalogSorts, searchSorts] {
            XCTAssertEqual(Set(sorts.map { "\($0.key) \($0.reverse)" }).count, sorts.count, "no two entries sort the same way")
            XCTAssertEqual(Set(sorts.map { $0.label }).count, sorts.count, "or read the same")
        }
    }
}
