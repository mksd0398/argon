import Observation
import SwiftUI
import UIKit

/// The typed text and, once submitted, the results of that query. State lives here so it survives opening a product.
@MainActor
@Observable
final class SearchModel {
    var text: String
    /// The query whose results `listing` holds; nil before the first search.
    private(set) var submitted: String? = nil
    // set at the end of init: its fetch captures self, which needs every other property set first
    @ObservationIgnored private(set) var listing: Listing!
    @ObservationIgnored private var started = false

    init(initial: String) {
        text = initial
        listing = Listing(sorts: searchSorts) { [weak self] after, sort, applied in
            let query = self?.submitted ?? ""
            let results = try await AppGraph.storefront.search(query, filters: applied, sortKey: sort.key, reverse: sort.reverse, after: after)
            return ProductPage(
                items: results.products,
                filters: results.filters,
                endCursor: results.results.endCursor,
                hasNext: results.results.hasNextPage
            )
        }
    }

    /// Searches for the initial text once (the screen calls this each time it appears).
    func start() {
        if started { return }
        started = true
        submit(text)
    }

    func submit(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return }
        text = q
        submitted = q
        listing.reload(sort: searchSorts[0], applied: [], resetFilters: true)
    }
}

private struct Suggestions {
    let queries: [String]
    let collections: [(handle: String, title: String)]
    let products: [ProductCard]
}

@MainActor
private func loadSuggestions(_ query: String) async throws -> Suggestions {
    let found = try await AppGraph.storefront.predictiveSearch(query)
    return Suggestions(
        queries: found.queries.map { $0.text },
        collections: found.collections.map { (handle: $0.handle, title: $0.title) },
        products: found.products
    )
}

@MainActor
struct SearchView: View {
    @State private var model: SearchModel
    @State private var suggestions: Suggestions? = nil
    @State private var failure: String? = nil
    @State private var searching = false
    @Environment(Router.self) private var router

    init(initial: String) {
        _model = State(initialValue: SearchModel(initial: initial))
    }

    var body: some View {
        let typed = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack {
            if let submitted = model.submitted, typed == submitted {
                ListingView(listing: model.listing, emptyText: "No products match \"\(submitted)\".")
            } else {
                suggestionList
            }
        }
        .searchable(text: $model.text, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search products")
        .onSubmit(of: .search) { model.submit(model.text) }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.start()
            if model.submitted == nil { searching = true }
        }
        // 300 ms debounce: typing again cancels this task (and a request in flight) before it queries
        .task(id: model.text) { await suggest() }
    }

    private var suggestionList: some View {
        List {
            if let failure = failure {
                Text(failure).foregroundStyle(.red)
            }
            if let s = suggestions {
                ForEach(s.queries, id: \.self) { q in
                    Button { submitSuggestion(q) } label: { Label(q, systemImage: "magnifyingglass") }
                }
                if !s.collections.isEmpty {
                    SwiftUI.Section("Collections") {
                        ForEach(s.collections.indices, id: \.self) { index in
                            Button(s.collections[index].title) { router.open(.collection(s.collections[index].handle)) }
                        }
                    }
                }
                if !s.products.isEmpty {
                    SwiftUI.Section("Products") {
                        ForEach(s.products, id: \.id) { card in
                            Button { router.open(.product(card.handle)) } label: { ProductRow(card: card) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .tint(Color.primary)
    }

    /// Searches for a suggested query and ends editing, as the keyboard's Search key does. It resigns the field rather
    /// than setting `searching = false`: dismissing the search clears its text, which would hide the results again.
    private func submitSuggestion(_ query: String) {
        model.submit(query)
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func suggest() async {
        let q = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty || q == model.submitted {
            suggestions = nil
            failure = nil
            return
        }
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
            let found = try await loadSuggestions(q)
            if Task.isCancelled { return }
            suggestions = found
            failure = nil
        } catch {
            if !Task.isCancelled { failure = error.localizedDescription }
        }
    }
}

@MainActor
private struct ProductRow: View {
    let card: ProductCard

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(img: card.image)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title).lineLimit(1)
                Text(card.price.display()).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
