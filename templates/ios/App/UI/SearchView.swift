import ArgonUI
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
            return ProductPage(items: results.products, filters: results.filters, endCursor: results.endCursor, hasNext: results.hasNextPage)
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

/// Search (`search?q=`): the field in the top bar, suggestions while typing (queries, collections, products), and the
/// results of a submitted query in the store's collection template (`ListingView`, with search's own sorts).
@MainActor
struct SearchView: View {
    @State private var model: SearchModel
    @State private var suggestions: Suggestions? = nil
    @State private var failure: String? = nil
    @State private var searching = false
    @Environment(Router.self) private var router
    @Environment(\.argonTheme) private var theme

    init(initial: String) {
        _model = State(initialValue: SearchModel(initial: initial))
    }

    var body: some View {
        let typed = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(spacing: 0) {
            if let submitted = model.submitted, typed == submitted {
                ListingView(listing: model.listing, emptyText: "No products match \"\(submitted)\".", onOpen: { router.open($0) })
            } else {
                suggestionList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.paper)
        // the native field brings its own clear button
        .argonTopBar(variant: .search, title: "Search products", searchText: $model.text, isSearching: $searching)
        .onSubmit(of: .search) { model.submit(model.text) }
        .task {
            model.start()
            // opened to type: the field has the keyboard
            if model.submitted == nil { searching = true }
        }
        // 300 ms debounce: typing again cancels this task (and a request in flight) before it queries
        .task(id: model.text) { await suggest() }
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let failure = failure {
                    Text(failure)
                        .font(theme.type.body)
                        .foregroundStyle(theme.colors.sale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(theme.spacing.l)
                }
                if let s = suggestions {
                    ForEach(Array(s.queries.enumerated()), id: \.offset) { _, q in
                        row(ArgonListItem(title: q, leading: .icon(.search), onClick: { submitSuggestion(q) }))
                    }
                    if !s.collections.isEmpty { label("Collections") }
                    ForEach(s.collections.indices, id: \.self) { index in
                        row(ArgonListItem(title: s.collections[index].title, onClick: { router.open(.collection(s.collections[index].handle)) }))
                    }
                    if !s.products.isEmpty { label("Products") }
                    ForEach(Array(s.products.enumerated()), id: \.offset) { _, card in
                        row(ArgonListItem(
                            title: card.title,
                            subtitle: card.price.display(),
                            leading: card.image.map { ArgonListLeading.image(URL(string: $0.url)) },
                            onClick: { router.open(.product(card.handle)) }
                        ))
                    }
                }
            }
        }
    }

    private func row(_ item: ArgonListItem) -> some View {
        item.buttonStyle(.plain).padding(.horizontal, theme.spacing.l)
    }

    private func label(_ text: String) -> some View {
        SectionHeader(title: text)
            .padding(.horizontal, theme.spacing.l)
            .padding(.top, theme.spacing.l)
            .padding(.bottom, theme.spacing.xs)
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
