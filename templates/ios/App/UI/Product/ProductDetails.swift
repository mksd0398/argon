import ArgonUI
import SwiftUI

/// The accordion that starts open.
let descriptionTitle = "Description"

/// "care_guide" -> "Care guide": a metafield's key as its label.
func metafieldLabel(_ key: String) -> String {
    let words = key.replacingOccurrences(of: "_", with: " ")
    return words.prefix(1).uppercased() + String(words.dropFirst())
}

// MARK: - Views

/// Block 9 of the product page, one accordion each: "Description", "Details" (the `PDP_METAFIELDS` the product has a
/// value for), "Shipping policy" and "Returns policy" (the shop's own). One with nothing to say is left out. `open` holds
/// the titles of the expanded ones; `onToggle` gets the title tapped.
@MainActor
struct ProductDetails: View {
    let descriptionHtml: String
    let metafields: [Metafield]
    let policies: ShopPolicies?
    let open: Set<String>
    let onToggle: (_ title: String) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let description = text(descriptionHtml)
        let shipping = text(policies?.shippingPolicy?.body)
        let returns = text(policies?.refundPolicy?.body)
        if description != nil || !metafields.isEmpty || shipping != nil || returns != nil {
            VStack(spacing: 0) {
                ArgonDivider()
                if let description = description { section(descriptionTitle) { HtmlText(html: description) } }
                if !metafields.isEmpty {
                    section("Details") {
                        // ponytail: values are shown as the store sends them (a rich-text or JSON metafield shows its raw text)
                        VStack(alignment: .leading, spacing: theme.spacing.s) {
                            ForEach(metafields.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: theme.spacing.l) {
                                    Text(metafieldLabel(metafields[index].key))
                                        .foregroundStyle(theme.colors.muted)
                                        .frame(width: 110, alignment: .leading)
                                    Text(metafields[index].value)
                                        .foregroundStyle(theme.colors.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(theme.type.body)
                            }
                        }
                    }
                }
                if let shipping = shipping { section("Shipping policy") { HtmlText(html: shipping) } }
                if let returns = returns { section("Returns policy") { HtmlText(html: returns) } }
            }
            .padding(.top, theme.spacing.xl)
        }
    }

    /// `html` when it has something to show.
    private func text(_ html: String?) -> String? {
        guard let html = html, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return html
    }

    /// One accordion on the page's gutter, expanded while its `title` is in `open`, with the hairline under it.
    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ArgonAccordion(title: title, isExpanded: open.contains(title), onToggle: { onToggle(title) }, content: content)
            .padding(.horizontal, theme.spacing.l)
        ArgonDivider()
    }
}
