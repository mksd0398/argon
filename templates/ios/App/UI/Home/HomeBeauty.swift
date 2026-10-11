import ArgonUI
import SwiftUI

/// The beauty home (soft): an inset, rounded hero carousel, "Shop by category" as circles, the first rail as
/// "Bestsellers", "Shop by routine" (tabs of the first four categories over four of the selected one's products), the
/// second banner as a card, the other rails, then the trust row. Its top bar is the logo at the start with search (see
/// HomeView).
@MainActor
struct HomeBeauty: View {
    let content: HomeContent
    let onOpen: (Route) -> Void
    @State private var routine = 0
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let hero = heroBanners(content.banners)
        let rails = content.rails
        // a routine needs products to show: the store's own category sections come without them
        let routines = Array(content.categories.filter { !$0.products.isEmpty }.prefix(4))
        HomeList {
            if !hero.isEmpty {
                // the carousel's own margins inset the banners and let the next one peek in
                ArgonCarousel(count: hero.count) { page in
                    if hero.indices.contains(page) { BannerView(banner: hero[page], onOpen: onOpen, ratio: 16.0 / 10.0) }
                }
            }
            if !content.categories.isEmpty { CategoryCircles(categories: content.categories, onOpen: onOpen) }
            if let rail = rails.first {
                ProductRail(title: "Bestsellers", cards: rail.items, viewAll: content.routeOf(rail), onOpen: onOpen)
            }
            if !routines.isEmpty {
                Routines(routines: routines, selected: min(max(routine, 0), routines.count - 1), onSelect: { routine = $0 }, onOpen: onOpen)
            }
            if content.banners.count > 1 {
                BannerView(banner: content.banners[1], onOpen: onOpen, ratio: 16.0 / 10.0).padding(.horizontal, theme.spacing.l)
            }
            ForEach(Array(rails.dropFirst().enumerated()), id: \.offset) { _, rail in
                ProductRail(title: rail.title, cards: rail.items, viewAll: content.routeOf(rail), onOpen: onOpen)
            }
            // nothing to shop yet: the banners above, then the note
            if content.isEmpty { EmptyNote() }
            TrustRow(onOpen: onOpen).padding(.horizontal, theme.spacing.l)
        }
    }
}

/// "Shop by category": each collection as a round picture with its title under it, in a row that scrolls sideways.
@MainActor
private struct CategoryCircles: View {
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
                            VStack(spacing: theme.spacing.xs) {
                                ArgonAvatar(imageUrl: category.image.flatMap { URL(string: $0.url) }, initials: category.title, size: .l)
                                    // the title under it names the collection
                                    .accessibilityHidden(true)
                                Text(category.title)
                                    .font(theme.type.caption)
                                    .foregroundStyle(theme.colors.ink)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                            }
                            .frame(width: 72)
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

/// "Shop by routine": a tab per category in `routines`; under them the `selected` one's first four products and "View all".
@MainActor
private struct Routines: View {
    let routines: [CollectionCard]
    let selected: Int
    let onSelect: (Int) -> Void
    let onOpen: (Route) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let current = routines[selected]
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            SectionHeader(title: "Shop by routine")
            // one category has nothing to switch between
            if routines.count > 1 {
                ArgonTabs(titles: routines.map { $0.title }, selectedIndex: selected, onSelect: onSelect)
            }
            ProductPairs(cards: Array(current.products.prefix(4)), onOpen: onOpen)
            ArgonButton(title: "View all", style: .secondary, fullWidth: true) { onOpen(.collection(current.handle)) }
        }
        .padding(.horizontal, theme.spacing.l)
    }
}
