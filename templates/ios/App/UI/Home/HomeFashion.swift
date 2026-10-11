import ArgonUI
import SwiftUI

/// The fashion home (editorial): a full-bleed hero carousel, "Shop by category" as tall image tiles, the first rail as a
/// carousel of cards, the second banner as an inset card, the second rail as a grid of four, the other rails as carousels,
/// then the trust row. Its top bar is the centred logo with search (see HomeView).
@MainActor
struct HomeFashion: View {
    let content: HomeContent
    let onOpen: (Route) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let hero = heroBanners(content.banners)
        let rails = content.rails
        HomeList(top: false) {
            if !hero.isEmpty {
                // edge to edge: no gap between the pages and no neighbour peeking in
                ArgonCarousel(count: hero.count, autoplaySeconds: 5, peekFraction: 0, itemSpacing: 0) { page in
                    if hero.indices.contains(page) {
                        BannerView(banner: hero[page], onOpen: onOpen, ratio: 4.0 / 5.0, headingStyle: \.display, square: true)
                    }
                }
            }
            if !content.categories.isEmpty { CategoryTiles(categories: content.categories, onOpen: onOpen) }
            if let rail = rails.first {
                ProductRail(title: rail.title, cards: rail.items, viewAll: content.routeOf(rail), onOpen: onOpen)
            }
            if content.banners.count > 1 {
                BannerView(banner: content.banners[1], onOpen: onOpen, ratio: 1).padding(.horizontal, theme.spacing.l)
            }
            if rails.count > 1 {
                let rail = rails[1]
                VStack(alignment: .leading, spacing: theme.spacing.m) {
                    SectionHeader(title: rail.title, actionLabel: "View all") { onOpen(content.routeOf(rail)) }
                    ProductPairs(cards: Array(rail.items.prefix(4)), onOpen: onOpen)
                }
                .padding(.horizontal, theme.spacing.l)
            }
            ForEach(Array(rails.dropFirst(2).enumerated()), id: \.offset) { _, rail in
                ProductRail(title: rail.title, cards: rail.items, viewAll: content.routeOf(rail), onOpen: onOpen)
            }
            // nothing to shop yet: the banners above, then the note
            if content.isEmpty { EmptyNote() }
            TrustRow(onOpen: onOpen).padding(.horizontal, theme.spacing.l)
        }
    }
}

/// "Shop by category": 3:4 image tiles that scroll sideways, each with its collection's title under it.
@MainActor
private struct CategoryTiles: View {
    let categories: [CollectionCard]
    let onOpen: (Route) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            SectionHeader(title: "Shop by category").padding(.horizontal, theme.spacing.l)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: theme.spacing.m) {
                    ForEach(categories, id: \.id) { category in
                        Button { onOpen(.collection(category.handle)) } label: {
                            VStack(alignment: .leading, spacing: theme.spacing.s) {
                                CategoryImage(image: category.picture, ratio: 3.0 / 4.0)
                                Text(category.title).font(theme.type.label).foregroundStyle(theme.colors.ink).lineLimit(1)
                            }
                            .frame(width: 132, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, theme.spacing.l)
            }
        }
    }
}
