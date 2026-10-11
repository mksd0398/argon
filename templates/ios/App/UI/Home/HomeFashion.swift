import ArgonUI
import SwiftUI

/// How solid the bar over the hero is (0...1) when the page has scrolled `scrolled` points: clear while more than two
/// bar heights of the hero (`heroHeight` tall) still show, solid once what is left of it is no taller than the bar
/// (`barHeight`, the status bar included), fading in between.
func heroSolid(scrolled: CGFloat, heroHeight: CGFloat, barHeight: CGFloat) -> Double {
    let left = heroHeight - scrolled
    if barHeight <= 0 { return left > 0 ? 0 : 1 }
    return Double(min(max((2 * barHeight - left) / barHeight, 0), 1))
}

/// The fashion home (editorial): a full-bleed hero carousel, "Shop by category" as tall image tiles, the first rail as a
/// carousel of cards, the second banner as an inset card, the second rail as a grid of four, the other rails as carousels,
/// then the trust row. The page fills the screen from its very top: the hero starts under the status bar, and its top
/// bar (the centred logo with search, see HomeView) lies over it, clear at `solid` 0 and turning solid as the hero
/// scrolls out. The page sets `solid`; the bar draws it, and with it the status bar's content (light over the hero).
@MainActor
struct HomeFashion: View {
    let content: HomeContent
    let onOpen: (Route) -> Void
    @Binding var solid: Double
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let hero = heroBanners(content.banners)
        let rails = content.rails
        GeometryReader { proxy in
            // the bar with the status bar: what the page keeps clear of at its top
            let barHeight = proxy.safeAreaInsets.top
            ScrollView {
                VStack(spacing: theme.spacing.xl) {
                    if !hero.isEmpty {
                        // Edge to edge: no gap between the pages and no neighbour peeking in. Not in the lazy list: it
                        // stays laid out when it has scrolled away, so the bar always knows where the hero is.
                        ArgonCarousel(count: hero.count, autoplaySeconds: 5, peekFraction: 0, itemSpacing: 0) { page in
                            if hero.indices.contains(page) {
                                BannerView(banner: hero[page], onOpen: onOpen, ratio: 4.0 / 5.0, headingStyle: \.display, square: true)
                            }
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            // on the screen: the page starts at its top edge
                            let now = heroSolid(scrolled: -frame.minY, heroHeight: frame.height, barHeight: barHeight)
                            if now != solid { solid = now }
                        }
                    }
                    LazyVStack(spacing: theme.spacing.xl) {
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
                .padding(.bottom, theme.spacing.xl)
            }
            // the hero runs up under the bar and the status bar; without one the page starts under the (solid) bar
            .ignoresSafeArea(edges: hero.isEmpty ? [] : .top)
        }
        .onChange(of: hero.isEmpty, initial: true) { _, empty in
            if empty { solid = 1 }
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
