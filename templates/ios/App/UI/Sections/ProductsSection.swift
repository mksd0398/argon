import ArgonUI
import SwiftUI

// `products` and `collections`: the store's own cards, from the screen's one SectionNodes call.

/// The cards a `products` section shows: its `products` when it lists any (those that loaded, in its order), else the
/// first `limit` of its collection's.
func sectionProducts(_ settings: SectionSettings, nodes: [String: Node]) -> [ProductCard] {
    let listed = settings.gids("products", "Product").compactMap { nodes[$0]?.productCard }
    if !settings.gids("products", "Product").isEmpty { return listed }
    let limit = Int(settings.number("limit", 8, 1...24))
    let collection = settings.gid("collection", "Collection").flatMap { nodes[$0]?.collectionCard }
    return Array((collection?.products ?? []).prefix(limit))
}

/// `products`: a heading, then the cards in a row that scrolls sideways (`carousel`) or two to a row (`grid`). "See all"
/// opens the collection, when there is one and `show_all`.
@MainActor
struct ProductsSection: View {
    let settings: SectionSettings
    let scope: SectionScope
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let cards = sectionProducts(settings, nodes: scope.nodes)
        let collection = settings.gid("collection", "Collection").flatMap { scope.collection($0) }
        let seeAll = settings.boolean("show_all", true) ? collection : nil
        let title = scope.text(settings, "heading") ?? seeAll?.title
        let open: (ProductCard) -> Void = { scope.open(.product($0.handle), nil) }
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                if let title = title {
                    SectionHeader(
                        title: title,
                        actionLabel: seeAll == nil ? nil : "See all",
                        onAction: seeAll.map { collection in { scope.open(.collection(collection.handle), nil) } }
                    )
                    .padding(.horizontal, theme.spacing.l)
                }
                if settings.choice("style", ["carousel", "grid"], "carousel") == "grid" {
                    ProductPairs(cards: cards) { route in scope.open(route, nil) }.padding(.horizontal, theme.spacing.l)
                } else {
                    ProductCardRow(cards: cards, onOpen: open)
                }
            }
        }
    }
}

/// `collections`: pictures in circles with the title under them in a row that scrolls sideways (`circles`), two to a
/// row (`grid`), or rows of a list (`list`).
@MainActor
struct CollectionsSection: View {
    let settings: SectionSettings
    let scope: SectionScope
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let cards = settings.gids("collections", "Collection").compactMap { scope.collection($0) }
        let open: (CollectionCard) -> Void = { scope.open(.collection($0.handle), nil) }
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                if let title = scope.text(settings, "heading") {
                    SectionHeader(title: title).padding(.horizontal, theme.spacing.l)
                }
                switch settings.choice("style", ["circles", "grid", "list"], "circles") {
                case "grid": grid(cards, open)
                case "list": list(cards, open)
                default: circles(cards, open)
                }
            }
        }
    }

    private func circles(_ cards: [CollectionCard], _ open: @escaping (CollectionCard) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: theme.spacing.m) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    Button { open(card) } label: {
                        VStack(spacing: theme.spacing.xs) {
                            StoreImage(image: card.picture).frame(width: 72, height: 72).clipShape(Circle())
                            Text(card.title)
                                .font(theme.type.caption)
                                .foregroundStyle(theme.colors.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 84)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, theme.spacing.l)
        }
    }

    private func grid(_ cards: [CollectionCard], _ open: @escaping (CollectionCard) -> Void) -> some View {
        VStack(spacing: theme.spacing.l) {
            ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { start in
                HStack(alignment: .top, spacing: theme.spacing.m) {
                    ForEach(start..<min(start + 2, cards.count), id: \.self) { index in
                        Button { open(cards[index]) } label: {
                            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                                CategoryImage(image: cards[index].picture, ratio: 1)
                                Text(cards[index].title).font(theme.type.label).foregroundStyle(theme.colors.ink).lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    // a lone card keeps the width of the others
                    if start + 1 == cards.count { Color.clear.frame(maxWidth: .infinity).frame(height: 0) }
                }
            }
        }
        .padding(.horizontal, theme.spacing.l)
    }

    private func list(_ cards: [CollectionCard], _ open: @escaping (CollectionCard) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                ArgonListItem(
                    title: card.title,
                    leading: .image(card.picture.flatMap { URL(string: $0.url) }),
                    trailing: .chevron
                ) { open(card) }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, theme.spacing.l)
    }
}
