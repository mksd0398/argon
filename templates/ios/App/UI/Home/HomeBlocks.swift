import ArgonUI
import Foundation
import SwiftUI

// The blocks the four home templates share. Each one is a whole section (its heading included) and takes the page's full
// width: it brings its own side margin (spacing.l), so a row of cards can scroll off the screen's edges.

// MARK: Logic

/// `text`, unless it is nil or blank.
private func shown(_ text: String?) -> String? {
    guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
}

extension HomeContent.Rail {
    /// A rail's heading; a store's product section may have none.
    var title: String { shown(heading) ?? "Featured" }
}

extension HomeContent {
    /// Where a rail's "View all" leads: the collection it shows, else the whole catalogue.
    /// ponytail: a rail doesn't carry its collection, so it is matched to a category by its title (true for a store without a
    /// home screen, whose rails are its collections). Upgrade: keep the collection's handle on `Section.products`.
    func routeOf(_ rail: Rail) -> Route {
        .collection(categories.first { $0.title == rail.heading }?.handle ?? "all")
    }
}

extension CollectionCard {
    /// A category's picture: the collection's own image, else its first product's (many stores never give their
    /// collections one). Nil, and so the quiet placeholder, only when it has neither.
    var picture: Img? { image ?? products.first?.image }
}

/// The banners of a hero carousel: all but the second, which a template shows as a card further down the page.
func heroBanners(_ banners: [HomeContent.Banner]) -> [HomeContent.Banner] {
    banners.enumerated().filter { $0.offset != 1 }.map { $0.element }
}

// MARK: Views

/// A home page: its blocks one under the other in one lazy list, `spacing.xl` apart, with a small margin over the first
/// (the fashion home, whose hero lies under its bar, lays out its own).
@MainActor
struct HomeList<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.argonTheme) private var theme

    var body: some View {
        ScrollView {
            LazyVStack(spacing: theme.spacing.xl) { content }
                .padding(.top, theme.spacing.s)
                .padding(.bottom, theme.spacing.xl)
        }
    }
}

/// A banner: its image in a box of `ratio` (width to height), with the heading, the text and the button over it at the
/// bottom start. The whole banner opens its link. `compact` is for short banners: tighter margins, a small button, no
/// text. `square` leaves the corners unrounded (a banner that spans the screen).
@MainActor
struct BannerView: View {
    let banner: HomeContent.Banner
    let onOpen: (Route) -> Void
    let ratio: CGFloat
    var headingStyle: KeyPath<ArgonTypography, Font> = \.title
    var square = false
    var compact = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let link = banner.link
        let heading = shown(banner.heading)
        let text = compact ? nil : shown(banner.text)
        let button = link == nil ? nil : shown(banner.buttonLabel)
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { StoreImage(image: banner.image) }
            .overlay {
                if heading != nil || text != nil || button != nil {
                    words(heading, text, button)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: square ? 0 : theme.radius.l))
            .contentShape(Rectangle())
            // the button inside is a button of its own and takes its tap before this one
            .onTapGesture { if let link = link { onOpen(link) } }
            .accessibilityAddTraits(link != nil ? .isButton : [])
    }

    /// What sits on a photo uses the dark palette in light and dark mode alike: a dark shade, light text, a light button.
    private func words(_ heading: String?, _ text: String?, _ button: String?) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            // The text and the button are laid out first; the heading has the height they leave, and is cut with an
            // ellipsis to fit it: nothing spills out of the banner, however long the store's words are.
            if let heading = heading {
                Text(heading)
                    .font(theme.type[keyPath: headingStyle])
                    .foregroundStyle(theme.colors.ink)
                    .lineLimit(compact ? 2 : 3)
            }
            if let text = text {
                Text(text).font(theme.type.body).foregroundStyle(theme.colors.ink).lineLimit(2).layoutPriority(1)
            }
            if let button = button, let link = banner.link {
                ArgonButton(title: button, size: compact ? .s : .m) { onOpen(link) }.layoutPriority(1)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(compact ? theme.spacing.m : theme.spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(shade)
        .environment(\.colorScheme, .dark)
    }

    /// The shade grows towards the bottom, where the words are; a banner without a picture is all shade. In a short
    /// banner the heading reaches the top, so the whole picture is shaded a little for it to stay readable.
    private var shade: AnyShapeStyle {
        if banner.image == nil { return AnyShapeStyle(theme.colors.paper) }
        let top: Gradient.Stop = compact
            ? .init(color: theme.colors.paper.opacity(0.3), location: 0)
            : .init(color: .clear, location: 0.35)
        return AnyShapeStyle(LinearGradient(
            stops: [top, .init(color: theme.colors.paper.opacity(0.85), location: 1)],
            startPoint: .top,
            endPoint: .bottom
        ))
    }
}

/// A titled row of product cards that scrolls sideways (`ProductCardRow`), each card `cardWidth` wide, with "View all"
/// (`viewAll`).
@MainActor
struct ProductRail: View {
    let title: String
    let cards: [ProductCard]
    let viewAll: Route
    let onOpen: (Route) -> Void
    var style: ProductCardStyle = .standard
    var cardWidth: CGFloat = 160
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            SectionHeader(title: title, actionLabel: "View all") { onOpen(viewAll) }
                .padding(.horizontal, theme.spacing.l)
            ProductCardRow(cards: cards, style: style, cardWidth: cardWidth) { onOpen(.product($0.handle)) }
        }
    }
}

/// `cards` two to a row (these are a handful of cards: no lazy grid inside the home's list).
@MainActor
struct ProductPairs: View {
    let cards: [ProductCard]
    let onOpen: (Route) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.l) {
            ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { start in
                HStack(alignment: .top, spacing: theme.spacing.m) {
                    ForEach(start..<min(start + 2, cards.count), id: \.self) { index in
                        ProductCardView(card: cards[index]) { onOpen(.product(cards[index].handle)) }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    // a lone card keeps the width of the others
                    if start + 1 == cards.count { Color.clear.frame(maxWidth: .infinity).frame(height: 0) }
                }
            }
        }
    }
}

/// A titled list of `cards` as rows (thumbnail, SKU, price, quick add), with "View all" when `viewAll` is given.
@MainActor
struct ProductRows: View {
    let title: String
    let cards: [ProductCard]
    let onOpen: (Route) -> Void
    var viewAll: Route? = nil
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title, actionLabel: viewAll == nil ? nil : "View all", onAction: viewAll.map { route in { onOpen(route) } })
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                ProductCardView(card: card, style: .row) { onOpen(.product(card.handle)) }
            }
        }
        .padding(.horizontal, theme.spacing.l)
    }
}

/// What a template shows under its banners when the store has no categories and no products to show.
@MainActor
struct EmptyNote: View {
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Text("Nothing to show yet.")
            .font(theme.type.body)
            .foregroundStyle(theme.colors.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(theme.spacing.xl)
    }
}

/// A collection's picture in a box of `ratio` (width to height), as wide as it is given, with rounded corners.
@MainActor
struct CategoryImage: View {
    let image: Img?
    let ratio: CGFloat
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { StoreImage(image: image) }
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.m))
    }
}
