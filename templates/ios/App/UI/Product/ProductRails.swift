import ArgonUI
import SwiftUI

/// Blocks 12 to 14 of the product page, each a heading over a row of product cards that scrolls sideways: "Pairs well
/// with" (compact cards with a quick add), "You may also like" and "Recently viewed" (standard cards). Nothing without
/// `cards`. `onOpen` opens a card's product.
/// ponytail: the row is a plain stack, as tall as its tallest card (a lazy one sizes itself on the first cards only):
/// every card is built at once, a dozen at most. Upgrade: a lazy stack with a fixed card height, for longer rails.
@MainActor
struct ProductPageRail: View {
    let title: String
    let cards: [ProductCard]
    let style: ProductCardStyle
    let onOpen: (Route) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                SectionHeader(title: title).padding(.horizontal, theme.spacing.l)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: theme.spacing.m) {
                        ForEach(cards, id: \.id) { card in
                            ProductCardView(card: card, style: style) { onOpen(.product(card.handle)) }
                                .frame(width: style == .compact ? 132 : 160)
                        }
                    }
                    .padding(.horizontal, theme.spacing.l)
                }
            }
            .padding(.top, theme.spacing.xl)
        }
    }
}
