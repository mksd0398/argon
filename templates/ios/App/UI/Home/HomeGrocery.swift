import ArgonUI
import SwiftUI

/// The grocery home (dense): a short banner carousel, a grid of eight categories with "See all", every rail as small
/// cards with a quick add, and after the second rail the first rail's products again as a list under "Popular". Its top
/// bar is a search field (see HomeView).
@MainActor
struct HomeGrocery: View {
    let content: HomeContent
    let onOpen: (Route) -> Void

    var body: some View {
        let banners = content.banners
        let rails = content.rails
        // "Popular" follows the second rail, or the only one
        let popularAfter = min(1, rails.count - 1)
        HomeList {
            if !banners.isEmpty {
                ArgonCarousel(count: banners.count, showsIndicators: false) { page in
                    if banners.indices.contains(page) {
                        BannerView(banner: banners[page], onOpen: onOpen, ratio: 21.0 / 9.0, compact: true)
                    }
                }
            }
            if content.isEmpty { EmptyNote() }
            if !content.categories.isEmpty { CategoryGrid(categories: Array(content.categories.prefix(8)), onOpen: onOpen) }
            ForEach(Array(rails.enumerated()), id: \.offset) { index, rail in
                ProductRail(title: rail.title, cards: rail.items, viewAll: content.routeOf(rail), onOpen: onOpen, style: .compact, cardWidth: 132)
                if index == popularAfter {
                    ProductRows(title: "Popular", cards: Array(rails[0].items.prefix(5)), onOpen: onOpen)
                }
            }
        }
    }
}

/// "Shop by category": `categories` four to a row as small square pictures with their titles; "See all" opens the Shop tab.
@MainActor
private struct CategoryGrid: View {
    let categories: [CollectionCard]
    let onOpen: (Route) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            SectionHeader(title: "Shop by category", actionLabel: "See all") { AppGraph.tabs.selected = .shop }
            ForEach(Array(stride(from: 0, to: categories.count, by: 4)), id: \.self) { start in
                let row = Array(categories[start..<min(start + 4, categories.count)])
                HStack(alignment: .top, spacing: theme.spacing.s) {
                    ForEach(row, id: \.id) { category in
                        Button { onOpen(.collection(category.handle)) } label: {
                            VStack(spacing: theme.spacing.xs) {
                                CategoryImage(image: category.image, ratio: 1)
                                Text(category.title)
                                    .font(theme.type.caption)
                                    .foregroundStyle(theme.colors.ink)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    // a short last row keeps its tiles the size of the others
                    ForEach(row.count..<4, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity).frame(height: 0) }
                }
            }
        }
        .padding(.horizontal, theme.spacing.l)
    }
}
