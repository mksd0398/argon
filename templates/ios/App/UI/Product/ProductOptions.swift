import ArgonUI
import SwiftUI

// Block 4 of the product page: the options to choose from.

/// How many variants a product arrives with at most (`variants(first: 250)`, the Storefront API's page ceiling).
private let loadedVariants = 250

/// The options a shopper chooses from: all of them, but for Shopify's lone "Title: Default Title" of a product without
/// options.
func visibleOptions(_ product: Product) -> [ProductOption] {
    product.options.filter { !($0.name == "Title" && $0.optionValues.map { $0.name } == ["Default Title"]) }
}

/// The values of `option` that give a variant that can be bought, keeping the rest of `selection`. The others are shown
/// struck or dimmed, and can still be chosen (to reach "Sold out").
/// ponytail: `variants` holds the product's first 250. Past that, a combination that isn't listed may still exist, so it
/// counts as available and the selected variant's own answer (`variantBySelectedOptions`) tells. Upgrade: decode
/// `encodedVariantAvailability`.
func availableValues(_ variants: [Variant], _ selection: [String: String], _ option: ProductOption) -> Set<String> {
    let values = option.optionValues.map { $0.name }.filter { value in
        var chosen = selection
        chosen[option.name] = value
        return Variants.match(variants, selection: chosen)?.available ?? (variants.count >= loadedVariants)
    }
    return Set(values)
}

// MARK: - Views

/// One group per option: its name with the chosen value ("Colour: Olive"), then its values to pick from, colours
/// (`isColorName`) as swatches and the rest as tags. A value that can't be bought with the rest of the `selection` is
/// struck (a swatch) or dimmed (a tag). `onSelect` gets the option's name and the value tapped.
@MainActor
struct ProductOptions: View {
    let options: [ProductOption]
    let selection: [String: String]
    let variants: [Variant]
    let onSelect: (_ option: String, _ value: String) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.l) {
                ForEach(options, id: \.name) { option in group(option) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.l)
            .padding(.top, theme.spacing.xl)
        }
    }

    private func group(_ option: ProductOption) -> some View {
        let chosen = selection[option.name]
        let available = availableValues(variants, selection, option)
        let isColor = isColorName(option.name)
        let heading = chosen.map { "\(option.name): \($0)" } ?? option.name
        return VStack(alignment: .leading, spacing: theme.spacing.s) {
            Text(heading).font(theme.type.label).foregroundStyle(theme.colors.ink).lineLimit(1)
            // a tag brings its own touch height; swatches need the gap between rows
            FlowLayout(spacing: theme.spacing.s, lineSpacing: isColor ? theme.spacing.s : theme.spacing.xxs) {
                ForEach(option.optionValues, id: \.name) { value in
                    let isAvailable = available.contains(value.name)
                    if isColor {
                        let fill = swatch(for: value)
                        ArgonSwatch(
                            colorHex: fill.colorHex,
                            imageUrl: fill.imageUrl,
                            label: value.name,
                            isSelected: value.name == chosen,
                            isAvailable: isAvailable,
                            onClick: { onSelect(option.name, value.name) }
                        )
                    } else {
                        ArgonTag(text: value.name, isSelected: value.name == chosen, onClick: { onSelect(option.name, value.name) })
                            .opacity(isAvailable ? 1 : 0.45)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(isAvailable ? Text(verbatim: "") : Text("Unavailable"))
                    }
                }
            }
        }
    }
}

/// Its children in rows from the leading edge, starting a new row when the next one doesn't fit (Compose's `FlowRow`).
/// A child wider than a whole row is held to the row's width.
private struct FlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: frames.map { $0.maxX }.max() ?? 0, height: frames.map { $0.maxY }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// Where each child goes in a flow `width` wide, from the flow's own origin.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = CGSize(width: min(ideal.width, width), height: ideal.height)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
