import Observation
import SwiftUI

private let maxNodes = 250 // `nodes(ids:)` takes at most this many ids per request

private func fetchCards(_ ids: [String]) async throws -> [ProductCard] {
    let data = try await AppGraph.storefront.query("Products", ["ids": ids])
    return try cards(data.objects("nodes"))
}

/// The product cards behind the wishlist ids. Cards are fetched once per id and kept, so hearting or un-hearting
/// never reloads the others; the list is always read in wishlist order (newest first), whatever order the store answers in.
/// ponytail: a card is not refreshed until the app restarts (same as the other screens); add pull-to-refresh with them.
@MainActor
@Observable
final class WishlistModel {
    private var found: [String: ProductCard] = [:]
    private var asked: Set<String> = [] // ids fetched already; one missing from `found` is a product that no longer exists
    private(set) var error: String? = nil
    private let fetch: ([String]) async throws -> [ProductCard]

    init(fetch: @escaping ([String]) async throws -> [ProductCard]) {
        self.fetch = fetch
    }

    /// Fetches the cards of `ids` not asked for yet. A failure sets `error`; the next call retries.
    func sync(_ ids: [String]) async {
        error = nil
        let unseen = ids.filter { !asked.contains($0) }
        do {
            for start in stride(from: 0, to: unseen.count, by: maxNodes) {
                let batch = Array(unseen[start..<min(start + maxNodes, unseen.count)])
                let page = try await fetch(batch)
                for card in page { found[card.id] = card }
                asked.formUnion(batch)
            }
        } catch {
            // leaving the screen cancels the fetch; it runs again when the screen is shown
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    /// The cards of `ids`, in that order; products that no longer exist are left out.
    func cards(_ ids: [String]) -> [ProductCard] { ids.compactMap { found[$0] } }

    func pending(_ ids: [String]) -> Bool { ids.contains { !asked.contains($0) } }
}

@MainActor
struct WishlistView: View {
    @State private var model = WishlistModel(fetch: fetchCards)

    var body: some View {
        let ids = AppGraph.wishlist.ids
        let saved = model.cards(ids)
        VStack {
            if !saved.isEmpty {
                // a failed fetch of a newly saved product shows as the grid's Retry footer
                ProductGrid(items: saved, hasNext: model.error != nil, onLoadMore: { retry() }, error: model.error)
            } else if let error = model.error {
                ErrorView(message: error) { retry() }
            } else if model.pending(ids) {
                ProgressView()
            } else {
                Text("Tap ♡ on a product to save it")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Wishlist")
        .task(id: ids) { await model.sync(ids) }
    }

    private func retry() {
        Task { await model.sync(AppGraph.wishlist.ids) }
    }
}
