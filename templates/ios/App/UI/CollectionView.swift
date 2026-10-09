import Observation
import SwiftUI

/// One collection's products. Handle "all" is the whole catalogue: Storefront has no `collection(handle: "all")`, so it
/// uses the root `products` query (no filters there).
@MainActor
@Observable
final class CollectionModel {
    private(set) var title: String
    // set at the end of init: its fetch captures self, which needs every other property set first
    @ObservationIgnored private(set) var listing: Listing!

    init(handle: String) {
        let all = handle == "all"
        title = all ? "All products" : ""
        listing = Listing(sorts: all ? catalogSorts : collectionSorts) { [weak self] after, sort, applied in
            let api = AppGraph.storefront
            if all {
                let page = try await api.products(sortKey: sort.key, reverse: sort.reverse, after: after)
                return ProductPage(page, filters: [])
            }
            let found = try await api.collection(handle, filters: applied, sortKey: sort.key, reverse: sort.reverse, after: after)
            guard let collection = found else { throw NotFound(what: "Collection") }
            self?.title = collection.title
            return ProductPage(collection.products, filters: collection.filters)
        }
    }
}

@MainActor
struct CollectionView: View {
    @State private var model: CollectionModel

    init(handle: String) {
        _model = State(initialValue: CollectionModel(handle: handle))
    }

    var body: some View {
        ListingView(listing: model.listing, emptyText: "No products in this collection.")
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { model.listing.start() }
    }
}
