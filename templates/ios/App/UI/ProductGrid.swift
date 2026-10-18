import ArgonUI
import SwiftUI

/// Two-column grid of product cards, with `header` and `footer` (when given) across both columns above and below them,
/// scrolling with them.
/// While `hasNext`, a footer spinner calls `onLoadMore` as it scrolls into view; if loading failed (`error`) the footer
/// is the message and a Retry button instead. `loadKey` must change whenever a page arrives, even one that adds no items,
/// or the footer would stall (the default, the item count, is enough for a list that only grows). `bottomPadding` is the
/// room under the last row (nil: the same as the sides).
@MainActor
struct ProductGrid: View {
    let items: [ProductCard]
    let hasNext: Bool
    let onLoadMore: () -> Void
    let onOpen: (ProductCard) -> Void
    var error: String? = nil
    var loadKey: Int? = nil
    var bottomPadding: CGFloat? = nil
    var header: AnyView? = nil
    /// Across both columns under the cards.
    var footer: AnyView? = nil
    @Environment(\.argonTheme) private var theme

    var body: some View {
        // cards of a row line up at the top, whatever their heights
        let column = GridItem(.flexible(), spacing: theme.spacing.m, alignment: .top)
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.l) {
                if let header = header { header }
                LazyVGrid(columns: [column, column], spacing: theme.spacing.l) {
                    SwiftUI.Section {
                        ForEach(items, id: \.id) { card in
                            ProductCardView(card: card) { onOpen(card) }
                        }
                    } footer: {
                        if hasNext { loadMore.frame(maxWidth: .infinity).padding(theme.spacing.s) }
                    }
                }
                if let footer = self.footer { footer }
            }
            .padding([.horizontal, .top], theme.spacing.l)
            .padding(.bottom, bottomPadding ?? theme.spacing.l)
        }
    }

    @ViewBuilder private var loadMore: some View {
        if let error = error {
            VStack(spacing: theme.spacing.s) {
                Text(error).font(theme.type.label).foregroundStyle(theme.colors.muted).multilineTextAlignment(.center)
                ArgonButton(title: "Retry", style: .secondary, size: .s, action: onLoadMore)
            }
        } else {
            ArgonSpinner().task(id: loadKey ?? items.count) { onLoadMore() }
        }
    }
}
