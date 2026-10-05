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
                let data = try await api.query("Catalog", listingVars(after, sort, []))
                return try parseProductPage(data.connection("products"), filtersKey: "filters")
            }
            let data = try await api.query("Collection", listingVars(after, sort, applied, ["handle": handle]))
            guard let collection = data.obj("collection") else {
                throw StorefrontException(messages: ["Collection not found"], status: nil)
            }
            self?.title = collection.str("title") ?? ""
            return try parseProductPage(collection.connection("products"), filtersKey: "filters")
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
