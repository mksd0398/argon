import Foundation
import Observation
import SwiftUI

/// A sort menu entry: `key` is the Storefront sort-key enum value, `reverse` flips it.
struct Sort: Hashable {
    let label: String
    let key: String
    var reverse = false
}

// The same five entries, with the sort-key name each query's enum uses (ProductCollectionSortKeys vs ProductSortKeys).
let collectionSorts = [
    Sort(label: "Featured", key: "COLLECTION_DEFAULT"),
    Sort(label: "Best selling", key: "BEST_SELLING"),
    Sort(label: "Price: low to high", key: "PRICE"),
    Sort(label: "Price: high to low", key: "PRICE", reverse: true),
    Sort(label: "Newest", key: "CREATED", reverse: true),
]
let catalogSorts = [
    Sort(label: "Featured", key: "BEST_SELLING"),
    Sort(label: "Best selling", key: "BEST_SELLING"),
    Sort(label: "Price: low to high", key: "PRICE"),
    Sort(label: "Price: high to low", key: "PRICE", reverse: true),
    Sort(label: "Newest", key: "CREATED_AT", reverse: true),
]
let searchSorts = [
    Sort(label: "Relevance", key: "RELEVANCE"),
    Sort(label: "Price: low to high", key: "PRICE"),
    Sort(label: "Price: high to low", key: "PRICE", reverse: true),
]

/// A page of a product listing (collection, catalog or search results) and the filters it offers.
struct ProductPage: Equatable {
    let items: [ProductCard]
    let filters: [Filter]
    let endCursor: String?
    let hasNext: Bool
}

extension ProductPage {
    init(_ page: Page<ProductCard>, filters: [Filter]) {
        self.init(items: page.items, filters: filters, endCursor: page.endCursor, hasNext: page.hasNextPage)
    }
}

/// A cursor-paged product list with a sort and filter selection (collection or search results). `fetch` loads the page
/// after a cursor (nil for the first page). `reload` and `loadMore` return the load they start, for tests to await.
@MainActor
@Observable
final class Listing {
    let sorts: [Sort]
    private(set) var sort: Sort
    private(set) var applied: [String] = []
    private(set) var items: [ProductCard] = []
    private(set) var filters: [Filter] = []
    private(set) var hasNext = false
    /// Counts pages that have arrived, even ones that add no new items; a list footer keys its load-more trigger on it.
    private(set) var pagesLoaded = 0
    private(set) var loading = false
    private(set) var error: String? = nil
    @ObservationIgnored private var cursor: String? = nil
    @ObservationIgnored private var task: Task<Void, Never>? = nil
    @ObservationIgnored private var generation = 0
    private let fetch: (String?, Sort, [String]) async throws -> ProductPage

    init(sorts: [Sort], fetch: @escaping (String?, Sort, [String]) async throws -> ProductPage) {
        self.sorts = sorts
        sort = sorts[0]
        self.fetch = fetch
    }

    /// The first load, unless one has already run (a screen calls this each time it appears).
    func start() {
        if generation == 0 { reload() }
    }

    /// Starts over from the first page, with a new `sort` and/or filter selection. `resetFilters` also forgets the filters
    /// the last response offered: pass it when the products behind the list change (a new search query).
    @discardableResult
    func reload(sort: Sort? = nil, applied: [String]? = nil, resetFilters: Bool = false) -> Task<Void, Never> {
        task?.cancel()
        if let sort = sort { self.sort = sort }
        if let applied = applied { self.applied = applied }
        if resetFilters { filters = [] }
        items = []
        hasNext = false
        cursor = nil
        return load()
    }

    @discardableResult
    func loadMore() -> Task<Void, Never>? {
        hasNext && !loading ? load() : nil
    }

    private func load() -> Task<Void, Never> {
        loading = true
        error = nil
        generation += 1
        let mine = generation
        let after = cursor
        let sort = self.sort
        let applied = self.applied
        let started = Task {
            do {
                let page = try await self.fetch(after, sort, applied)
                // a superseded request (a new sort, filter or query) must not touch the list that replaced it
                guard mine == self.generation else { return }
                var seen = Set(self.items.map { $0.id })
                // a catalog that changes between pages can repeat a product
                self.items += page.items.filter { seen.insert($0.id).inserted }
                self.cursor = page.endCursor
                // without a cursor "more" can only repeat the first page
                self.hasNext = page.hasNext && page.endCursor != nil
                self.pagesLoaded += 1
                // a filtered first page that comes back without filters keeps the old ones, so the user can still clear them
                if after == nil && !page.filters.isEmpty { self.filters = page.filters }
                self.loading = false
            } catch {
                guard mine == self.generation else { return }
                self.error = error.localizedDescription
                self.loading = false
            }
        }
        task = started
        return started
    }
}

/// Sort and filter bar over a `ProductGrid`, with the loading, error (Retry) and empty states of `listing`.
@MainActor
struct ListingView: View {
    let listing: Listing
    let emptyText: String

    var body: some View {
        VStack(spacing: 0) {
            ListingBar(listing: listing)
            VStack {
                if !listing.items.isEmpty {
                    ProductGrid(
                        items: listing.items,
                        hasNext: listing.hasNext,
                        onLoadMore: { listing.loadMore() },
                        error: listing.error,
                        loadKey: listing.pagesLoaded
                    )
                } else if let error = listing.error {
                    ErrorView(message: error) { listing.reload() }
                } else if listing.loading {
                    ProgressView()
                } else {
                    Text(emptyText).multilineTextAlignment(.center).padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
