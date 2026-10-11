import ArgonUI
import SwiftUI
import UIKit

// The blocks every page is built from, on Argon's components and tokens. The product cards are in ProductCardView.swift.

// MARK: Images

/// Any image the app shows, filling the space it's given (cropped), on a quiet placeholder while it loads or when there
/// is none. A `file:` URL (a bundled stock banner, `StockImages`) is read from disk; any other is loaded from the network.
@MainActor
struct StoreImage: View {
    let url: String?
    let alt: String?
    @Environment(\.argonTheme) private var theme

    init(image: Img?) {
        url = image?.url
        alt = image?.alt
    }

    init(url: String?, alt: String? = nil) {
        self.url = url
        self.alt = alt
    }

    var body: some View {
        theme.colors.border.opacity(0.5)
            .overlay { picture }
            .clipped()
            .accessibilityHidden(alt == nil)
            .accessibilityLabel(alt ?? "")
    }

    @ViewBuilder private var picture: some View {
        if let address = url.flatMap({ URL(string: $0) }) {
            if address.isFileURL {
                // AsyncImage doesn't load file URLs
                if let image = Self.bundled(address.path) { Image(uiImage: image).resizable().scaledToFill() }
            } else {
                AsyncImage(url: address) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
        }
    }

    // A view body runs often (a carousel redraws on every page): each file is read and decoded once.
    private static let cache = NSCache<NSString, UIImage>()

    private static func bundled(_ path: String) -> UIImage? {
        if let kept = cache.object(forKey: path as NSString) { return kept }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

// MARK: Text

/// The merchant's HTML (a product description, a policy) as text: paragraphs, lists, bold, links. Nil when blank or
/// unreadable. The HTML importer runs WebKit, which must be on the main thread.
@MainActor
func htmlText(_ html: String) -> AttributedString? {
    guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    // the system body font instead of the importer's 12 pt Times
    let styled = "<style>body{font:-apple-system-body}</style>" + html
    guard let imported = try? NSAttributedString(
        data: Data(styled.utf8),
        options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
        documentAttributes: nil
    ) else { return nil }
    let text = NSMutableAttributedString(attributedString: imported)
    // the importer's fixed black would vanish in dark mode; links keep their own colour
    text.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: text.length))
    while text.string.hasSuffix("\n") {
        text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1))
    }
    return AttributedString(text)
}

/// `html` shown as text (`htmlText`); nothing while it is blank.
@MainActor
struct HtmlText: View {
    let html: String
    @State private var text: AttributedString? = nil
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading) {
            if let text = text { Text(text).foregroundStyle(theme.colors.ink) }
        }
        .task(id: html) { text = htmlText(html) }
    }
}

/// A small label over an image or beside a price: "Sold out", "Bundle"; `isSale` puts it on the sale colour: "Sale",
/// "Save 20%".
@MainActor
struct LabelTag: View {
    let text: String
    var isSale = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Text(text)
            .font(theme.type.caption)
            .lineLimit(1)
            .foregroundStyle(isSale ? theme.colors.paper : theme.colors.ink)
            .padding(.horizontal, theme.spacing.s)
            .padding(.vertical, theme.spacing.xxs)
            .background(isSale ? theme.colors.sale : theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.s))
    }
}

/// A section's heading, with an optional action on the trailing side ("View all"). It brings no padding of its own: give
/// it the page's gutter.
@MainActor
struct SectionHeader: View {
    let title: String
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil
    @Environment(\.argonTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.s) {
            Text(title)
                .font(theme.type.headline)
                .foregroundStyle(theme.colors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let actionLabel = actionLabel, let onAction = onAction {
                Button(action: onAction) {
                    Text(actionLabel)
                        .font(theme.type.label)
                        .foregroundStyle(theme.colors.muted)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: Price

/// The whole percent `price` is under `compareAt` (80 against 100 is 20); nil without a compare-at price, when it isn't
/// higher, or when the saving rounds to under 1%.
func discountPercent(_ price: Money, _ compareAt: Money?) -> Int? {
    guard let compareAt = compareAt, let now = Double(price.amount), let was = Double(compareAt.amount),
          was > 0, now >= 0, now < was else { return nil }
    let percent = Int(((1 - now / was) * 100).rounded())
    return percent >= 1 ? percent : nil
}

/// A price: `prefix` ("From") before it, the compare-at price struck through after it, and a "Save 20%" tag when it is a
/// discount. The tag drops to a second line where the row is too narrow (a product card).
@MainActor
struct PriceView: View {
    let price: Money
    var compareAt: Money? = nil
    var size: ArgonSize = .m
    var prefix: String? = nil
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let saving = discountPercent(price, compareAt).map { "Save \($0)%" }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s) {
                amounts
                if let saving = saving { LabelTag(text: saving, isSale: true) }
            }
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                amounts
                if let saving = saving { LabelTag(text: saving, isSale: true) }
            }
        }
    }

    private var amounts: some View {
        let small = size == .l ? theme.type.body : size == .m ? theme.type.label : theme.type.caption
        return HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
            if let prefix = prefix {
                Text(prefix).font(small).foregroundStyle(theme.colors.muted)
            }
            Text(price.display())
                .font(size == .l ? theme.type.title : size == .m ? theme.type.headline : theme.type.label)
                .foregroundStyle(theme.colors.ink)
            if let compareAt = compareAt, discountPercent(price, compareAt) != nil {
                Text(compareAt.display())
                    .font(small)
                    .strikethrough()
                    .foregroundStyle(theme.colors.muted)
                    .accessibilityLabel("Was \(compareAt.display())")
            }
        }
        .lineLimit(1)
    }
}

// MARK: Swatches

/// Colours for option values named after one, for stores that haven't set swatches.
enum SwatchColors {
    /// The `#RRGGBB` of the colour `name` names: the whole name when it is a known colour, else its last word ("Peacock
    /// Blue" is blue, "Off White" white), else any of its words. Nil for a name with none, and for "multi" (several
    /// colours have no one swatch).
    static func hex(_ name: String) -> String? {
        let whole = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = whole.split(whereSeparator: { !$0.isLetter }).map { String($0) }
        let candidates = [whole] + [words.last].compactMap { $0 } + words
        guard let known = candidates.first(where: { table[$0] != nil || $0 == "multi" }) else { return nil }
        return table[known]
    }

    // the same table on Android
    private static let table: [String: String] = [
        "black": "#000000", "white": "#FFFFFF", "grey": "#808080", "gray": "#808080", "silver": "#C0C0C0",
        "red": "#D0312D", "maroon": "#800000", "pink": "#F4A6C0", "rose": "#E8909C", "orange": "#F28C28",
        "peach": "#FFCBA4", "yellow": "#F7D13D", "gold": "#D4AF37", "mustard": "#D9A404", "green": "#3F8F4F",
        "olive": "#808000", "teal": "#008080", "turquoise": "#40E0D0", "blue": "#2F6FCF", "navy": "#1F2A5C",
        "sky": "#87CEEB", "purple": "#7B3FA0", "violet": "#8F5FD7", "lavender": "#B9A5E0", "magenta": "#C2188B",
        "brown": "#7B4B2A", "tan": "#D2B48C", "beige": "#E8DCC4", "cream": "#FFFDD0", "ivory": "#FFFFF0",
        "khaki": "#C3B091", "coral": "#FF7F50", "mint": "#98E0B8", "lime": "#A4D431", "burgundy": "#800020",
        "wine": "#722F37", "charcoal": "#36454F", "copper": "#B87333", "bronze": "#CD7F32",
    ]
}

/// What an `ArgonSwatch` is drawn with: a colour (`#RRGGBB`) and/or an image.
struct SwatchFill: Equatable {
    var colorHex: String? = nil
    var imageUrl: URL? = nil
}

/// The swatch of a value named `name`: the store's own (`swatch`, a colour or an image) when it has one, else the colour
/// its name says (`SwatchColors`).
func swatch(_ swatch: Swatch?, name: String) -> SwatchFill {
    let image = swatch?.image.flatMap { URL(string: $0.url) }
    if swatch?.color != nil || image != nil { return SwatchFill(colorHex: swatch?.color, imageUrl: image) }
    return SwatchFill(colorHex: SwatchColors.hex(name))
}

/// The swatch of a product option's value.
func swatch(for value: ProductOptionValue) -> SwatchFill {
    swatch(value.swatch, name: value.name)
}

/// The swatch of a filter's value.
func swatch(for value: FilterValue) -> SwatchFill {
    swatch(value.swatch, name: value.label)
}

// MARK: Trust

/// The reassurances under a page: "Secure checkout", and "Shipping policy" and "Returns policy" for the policies the shop
/// has, each opening it (`onOpen` is given its `Route.policy`). The policies are the session's (`StorefrontAPI.policies`);
/// when they can't be loaded only the first item shows.
@MainActor
struct TrustRow: View {
    let onOpen: (Route) -> Void
    @State private var policies: ShopPolicies? = nil
    @Environment(\.argonTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s) {
            item(.lock, "Secure checkout", policy: nil)
            if let policy = policies?.shippingPolicy { item(.truck, "Shipping policy", policy: policy) }
            if let policy = policies?.refundPolicy { item(.returns, "Returns policy", policy: policy) }
        }
        .task { policies = try? await AppGraph.storefront.policies() }
    }

    @ViewBuilder
    private func item(_ icon: ArgonIconName, _ label: String, policy: ShopPolicy?) -> some View {
        let content = VStack(spacing: theme.spacing.xs) {
            ArgonIcon(name: icon, tint: theme.colors.ink)
            Text(label).font(theme.type.caption).foregroundStyle(theme.colors.muted).multilineTextAlignment(.center)
        }
        .padding(.vertical, theme.spacing.s)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        if let policy = policy {
            Button { onOpen(.policy(policy.handle)) } label: { content }.buttonStyle(.plain)
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}
