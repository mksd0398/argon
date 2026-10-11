import ArgonUI
import SwiftUI

/// Blocks 12 to 14 of the product page, each a heading over a row of product cards that scrolls sideways
/// (`ProductCardRow`, as tall as its tallest card): "Pairs well with" (compact cards with a quick add), "You may also
/// like" and "Recently viewed" (standard cards). Nothing without `cards`. `onOpen` opens a card's product.
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
                ProductCardRow(cards: cards, style: style, cardWidth: style == .compact ? 132 : 160) { onOpen(.product($0.handle)) }
            }
            .padding(.top, theme.spacing.xl)
        }
    }
}
