import SwiftUI

/// Two-column grid of product cards; a card opens its product. While `hasNext`, a footer spinner calls `onLoadMore` as it
/// scrolls into view; if loading failed (`error`) the footer is a Retry button instead. `loadKey` must change whenever a
/// page arrives, even one that adds no items, or the footer would stall (the default, the item count, is enough for a
/// list that only grows).
@MainActor
struct ProductGrid: View {
    let items: [ProductCard]
    let hasNext: Bool
    let onLoadMore: () -> Void
    var error: String? = nil
    var loadKey: Int? = nil
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 16) {
                SwiftUI.Section {
                    ForEach(items, id: \.id) { card in
                        ProductCardView(card: card) { router.open(.product(card.handle)) }
                    }
                } footer: {
                    if hasNext { footer.padding(8) }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder private var footer: some View {
        if let error = error {
            Button(error + ". Retry", action: onLoadMore)
        } else {
            ProgressView().task(id: loadKey ?? items.count) { onLoadMore() }
        }
    }
}
