import ArgonUI
import Observation
import SwiftUI

/// One collection's products. Handle "all" is the whole catalogue: Storefront has no `collection(handle: "all")`, so it
/// uses the root `products` query (no filters or description there, and its own sorts).
@MainActor
@Observable
final class CollectionModel {
    private(set) var title: String
    /// The collection's description, once the first page is here; empty when it has none.
    private(set) var description = ""
    // set at the end of init: its fetch captures self, which needs every other property set first
    @ObservationIgnored private(set) var listing: Listing!

    init(handle: String) {
        let all = handle == "all"
        title = all ? "All products" : ""
        listing = Listing(sorts: all ? catalogSorts : collectionSorts) { [weak self] after, sort, applied in
            let api = AppGraph.storefront
            if all {
                let page = try await api.products(sortKey: sort.key, reverse: sort.reverse, after: after)
                return ProductPage(page)
            }
            let found = try await api.collection(handle, filters: applied, sortKey: sort.key, reverse: sort.reverse, after: after)
            guard let collection = found else { throw NotFound(what: "Collection") }
            self?.title = collection.title
            self?.description = withoutLeadingCss(collection.description)
            return ProductPage(collection.products)
        }
    }
}

/// A collection (`collection/{handle}`): its title in the top bar with search and the cart, and its products in the
/// store's collection template (`ListingView`).
@MainActor
struct CollectionView: View {
    @State private var model: CollectionModel
    @Environment(Router.self) private var router
    @Environment(\.argonTheme) private var theme

    init(handle: String) {
        _model = State(initialValue: CollectionModel(handle: handle))
    }

    var body: some View {
        // the cart is a tab: its count as the badge, none on an empty cart
        let inCart = AppGraph.cart.cart?.totalQuantity ?? 0
        ListingView(listing: model.listing, emptyText: "No products in this collection.", onOpen: { router.open($0) }, description: model.description)
            .background(theme.colors.paper)
            .argonTopBar(
                title: model.title,
                trailing: [
                    ArgonTopBarAction(icon: .search, accessibilityLabel: "Search") { router.open(.search("")) },
                    ArgonTopBarAction(icon: .bag, accessibilityLabel: "Cart", badge: inCart > 0 ? inCart : nil) { AppGraph.tabs.selected = .cart },
                ]
            )
            .task { model.listing.start() }
    }
}
