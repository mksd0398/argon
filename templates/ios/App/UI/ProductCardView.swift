import ArgonUI
import SwiftUI

extension Money {
    /// "$25.00": the amount in its currency, in `locale`; "5.0 XYZ" when the amount or the currency isn't known.
    func display(locale: Locale = .current) -> String {
        guard let value = Decimal(string: amount), CurrencyFormat.codes.contains(currencyCode),
              let text = CurrencyFormat.string(NSDecimalNumber(decimal: value), currencyCode, locale) else {
            return "\(amount) \(currencyCode)"
        }
        return text
    }
}

/// The ISO currency codes, and one formatter per locale and currency: a grid formats every card, and a NumberFormatter
/// is expensive to build. The lock makes the cache safe from any thread.
private enum CurrencyFormat {
    static let codes = Set(Locale.Currency.isoCurrencies.map { $0.identifier })
    private static let lock = NSLock()
    private static var formatters: [String: NumberFormatter] = [:]

    static func string(_ number: NSDecimalNumber, _ code: String, _ locale: Locale) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let key = locale.identifier + " " + code
        if let formatter = formatters[key] { return formatter.string(from: number) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = code
        formatters[key] = formatter
        return formatter.string(from: number)
    }
}

/// Heart toggle for the product with id `productId`: filled while it is in the wishlist. A 36 pt disc centred in the
/// 44 pt touch target, so the disc sits 4 pt inside whatever corner the button is aligned to.
@MainActor
struct WishlistHeart: View {
    let productId: String
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let saved = AppGraph.wishlist.contains(productId)
        let label: String = saved ? "Remove from wishlist" : "Save to wishlist"
        Button {
            Task { await AppGraph.wishlist.toggle(productId) }
        } label: {
            ArgonIcon(name: saved ? .heartFilled : .heart, size: 17, tint: theme.colors.ink)
                .frame(width: 36, height: 36)
                .background(theme.colors.surface.opacity(0.9), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// How a product card is laid out.
enum ProductCardStyle {
    /// A 4:5 image with the wishlist heart and a "Sold out" or "Sale" tag, then the vendor (when `AppGraph.showVendor`),
    /// title, rating, price and colours.
    case standard
    /// Dense (grocery): a square image, title, price and a quick add.
    case compact
    /// One line of a list (B2B): thumbnail, title, SKU, price, quantity rule and a quick add.
    case row
}

/// A product in a grid, a rail or a list. Tapping it calls `onOpen`; the heart and the quick add take their own taps.
@MainActor
struct ProductCardView: View {
    let card: ProductCard
    var style: ProductCardStyle = .standard
    let onOpen: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Group {
            switch style {
            case .standard: standard
            case .compact: compact
            case .row: row
            }
        }
        .contentShape(Rectangle())
        // the buttons inside are buttons of their own and take their taps before this one
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
    }

    private var standard: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            picture(ratio: 0.8)
                .overlay(alignment: .topLeading) {
                    Group {
                        if !card.available {
                            LabelTag(text: "Sold out")
                        } else if card.compareAt != nil {
                            LabelTag(text: "Sale", isSale: true)
                        }
                    }
                    .padding(theme.spacing.s)
                }
                .overlay(alignment: .topTrailing) { WishlistHeart(productId: card.id) }
            if AppGraph.showVendor && !card.vendor.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(card.vendor).font(theme.type.caption).foregroundStyle(theme.colors.muted).lineLimit(1)
            }
            title()
            if let rating = card.rating, card.ratingCount != 0 {
                ArgonRating(value: rating, count: card.ratingCount)
            }
            price
            colours
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            picture(ratio: 1)
            // two lines always, so the quick adds of a row of cards line up
            title(reservesSpace: true)
            price
            QuickAdd(card: card, onOpen: onOpen)
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: theme.spacing.m) {
            StoreImage(image: card.image)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.s))
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                title()
                if let sku = card.firstVariant?.sku, !sku.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("SKU \(sku)").font(theme.type.caption).foregroundStyle(theme.colors.muted).lineLimit(1)
                }
                price
                if let rule = quantityRuleLabel(card.firstVariant?.quantityRule) {
                    Text(rule).font(theme.type.caption).foregroundStyle(theme.colors.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            QuickAdd(card: card, onOpen: onOpen)
        }
        .padding(.vertical, theme.spacing.s)
    }

    private func picture(ratio: CGFloat) -> some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { StoreImage(image: card.image) }
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.m))
    }

    private func title(reservesSpace: Bool = false) -> some View {
        Text(card.title)
            .font(theme.type.label)
            .foregroundStyle(theme.colors.ink)
            .lineLimit(2, reservesSpace: reservesSpace)
            .multilineTextAlignment(.leading)
    }

    private var price: some View {
        PriceView(price: card.price, compareAt: card.compareAt, size: .s, prefix: card.hasPriceRange ? "From" : nil)
    }

    /// Up to four of the product's colours as dots, then "+N" for the rest.
    @ViewBuilder private var colours: some View {
        let colors = card.colors
        if !colors.isEmpty {
            HStack(spacing: theme.spacing.xxs) {
                ForEach(Array(colors.prefix(4).enumerated()), id: \.offset) { _, value in
                    let fill = swatch(for: value)
                    ArgonSwatch(colorHex: fill.colorHex, imageUrl: fill.imageUrl, label: value.name, size: .s)
                }
                if colors.count > 4 {
                    Text(verbatim: "+\(colors.count - 4)").font(theme.type.caption).foregroundStyle(theme.colors.muted)
                }
            }
        }
    }
}

/// Product cards in a row that scrolls sideways (a rail), each `cardWidth` wide, inset by the page's gutter. `onOpen`
/// gets the card tapped. Not lazy: a rail is a handful of cards, and a lazy row sizes itself on its first cards only, so
/// the page under it would jump when a taller card (a second title line, colour dots) scrolled in. This row is as tall
/// as its tallest card, and every card is stretched to that height.
@MainActor
struct ProductCardRow: View {
    let cards: [ProductCard]
    var style: ProductCardStyle = .standard
    var cardWidth: CGFloat = 160
    let onOpen: (ProductCard) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: theme.spacing.m) {
                // by position: a store's section may list a product twice
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    ProductCardView(card: card, style: style) { onOpen(card) }
                        .frame(width: cardWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            // the row measures itself on its tallest card, then hands that height to every card
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, theme.spacing.l)
        }
    }
}

/// "Min. 2 · Multiples of 2": the parts of `rule` a buyer has to know; nil when any quantity can be bought.
func quantityRuleLabel(_ rule: QuantityRule?) -> String? {
    guard let rule = rule else { return nil }
    var parts: [String] = []
    if rule.min > 1 { parts.append("Min. \(rule.min)") }
    if rule.step > 1 { parts.append("Multiples of \(rule.step)") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// A card's shortcut to the cart. A product with a choice to make (`quickAddVariantId` is nil) gets "Options", which
/// opens it (`onOpen`). Any other gets "Add"; once its variant is in the cart that becomes a stepper on the cart line's
/// quantity, moving by the variant's quantity rule (under the rule's minimum the line is removed). A change Shopify
/// refuses shows its message for a moment (`AppGraph.toast`) and leaves the quantity as it was.
@MainActor
struct QuickAdd: View {
    let card: ProductCard
    let onOpen: () -> Void
    @State private var busy = false

    var body: some View {
        Group {
            if let variantId = card.quickAddVariantId {
                let rule = card.firstVariant?.quantityRule
                let least = rule?.min ?? 1
                if let line = AppGraph.cart.cart?.lines.first(where: { $0.variantId == variantId }) {
                    ArgonQuantityStepper(
                        value: line.quantity,
                        onChange: { quantity in write { try await AppGraph.cart.update(line.id, quantity: quantity < least ? 0 : quantity) } },
                        min: 0,
                        max: rule?.maximum,
                        step: rule?.step ?? 1,
                        size: .s,
                        isEnabled: !busy
                    )
                } else {
                    ArgonButton(title: "Add", style: .secondary, size: .s, isLoading: busy) {
                        write { try await AppGraph.cart.add(variantId, quantity: least) }
                    }
                }
            } else {
                ArgonButton(title: "Options", style: .secondary, size: .s, action: onOpen)
            }
        }
        // as tall as the button in all three states, so a card doesn't jump when "Add" becomes the stepper
        .frame(minHeight: 44, alignment: .leading)
    }

    private func write(_ change: @escaping () async throws -> Void) {
        busy = true
        // on the app's scope, not the card's: scrolling the card away must not drop the change
        Task {
            do {
                try await change()
            } catch {
                AppGraph.toast.show(error.localizedDescription)
            }
            busy = false
        }
    }
}
