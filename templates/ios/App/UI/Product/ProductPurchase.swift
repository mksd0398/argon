import ArgonUI
import SwiftUI

// The buying blocks of the product page: price (unit price, company tag, volume pricing, quantity rule), availability,
// purchase options, quantity with Buy now, and the sticky add-to-cart bar. The rules are the plain functions on top.

/// `quantity` brought onto `rule`: no less than its minimum, no more than its maximum, on its increments (5 in twos is 4).
func clampedQuantity(_ quantity: Int, _ rule: QuantityRule?) -> Int {
    steppedQuantity(quantity, delta: 0, min: rule?.min ?? 1, max: rule?.maximum, step: rule?.step ?? 1)
}

/// A row of the volume pricing table: from `from` items up, each costs `price`.
struct VolumeRow: Equatable {
    let from: Int
    let price: Money

    /// "10+"
    var label: String { "\(from)+" }
}

/// The volume pricing table of `variant`: its own price from the smallest quantity that can be bought, then one row per
/// price break, by quantity. Empty for a variant without price breaks.
func volumeRows(_ variant: Variant) -> [VolumeRow] {
    if variant.quantityPriceBreaks.isEmpty { return [] }
    let first = VolumeRow(from: variant.quantityRule?.min ?? 1, price: variant.price)
    let breaks = variant.quantityPriceBreaks
        .sorted { $0.minimumQuantity < $1.minimumQuantity }
        .filter { $0.minimumQuantity > first.from }
    return [first] + breaks.map { VolumeRow(from: $0.minimumQuantity, price: $0.price) }
}

/// The row `quantity` buys at (the one to highlight): the last one it reaches.
func volumeRow(_ rows: [VolumeRow], _ quantity: Int) -> VolumeRow? {
    rows.last { $0.from <= quantity }
}

private let unitNames = ["ITEM": "item", "FLOZ": "fl oz", "FT2": "ft²", "M2": "m²", "M3": "m³"]

/// "$6.00 / item", "$2.50 / 100 g": `price` per the `measurement`'s reference amount. Nil without a unit price.
/// Shopify's unit names are shown in lower case ("KG" is "kg"), the few that don't read that way by `unitNames`.
func unitPriceLabel(_ price: Money?, _ measurement: UnitPriceMeasurement?, locale: Locale = .current) -> String? {
    guard let price = price, let measurement = measurement, let unit = measurement.referenceUnit,
          !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let name = unitNames[unit] ?? unit.lowercased()
    let per = measurement.referenceValue > 1 ? "\(measurement.referenceValue) \(name)" : name
    return "\(price.display(locale: locale)) / \(per)"
}

/// "Minimum 2 · Maximum 40 · Sold in multiples of 2": the parts of `rule` that limit an order; nil when none does.
func quantityRuleSentence(_ rule: QuantityRule?) -> String? {
    guard let rule = rule else { return nil }
    var parts: [String] = []
    if rule.min > 1 { parts.append("Minimum \(rule.min)") }
    if let maximum = rule.maximum { parts.append("Maximum \(maximum)") }
    if rule.step > 1 { parts.append("Sold in multiples of \(rule.step)") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// Good: in stock. Low: nearly gone (the warning colour). Later: sold now, shipped when it is back.
enum AvailabilityTone {
    case good, low, later
}

struct AvailabilityLine: Equatable {
    let text: String
    let tone: AvailabilityTone
}

/// What the page says about `variant`'s stock: "Only 3 left" for 1 to 5, "Ships when back in stock" for one sold while
/// out of stock, else "In stock". Nil for a variant that can't be bought (the button says "Sold out") or isn't there.
func availabilityLine(_ variant: Variant?) -> AvailabilityLine? {
    guard let variant = variant, variant.available else { return nil }
    if let left = variant.quantityAvailable, (1...5).contains(left) {
        return AvailabilityLine(text: "Only \(left) left", tone: .low)
    }
    if variant.currentlyNotInStock { return AvailabilityLine(text: "Ships when back in stock", tone: .later) }
    return AvailabilityLine(text: "In stock", tone: .good)
}

/// "Sale −20%": the gallery's tag for a price below its compare-at price; nil when it is no discount.
func saleTag(_ price: Money, _ compareAt: Money?) -> String? {
    discountPercent(price, compareAt).map { "Sale −\($0)%" }
}

/// What the variant costs on the plan of `allocation`; nil when the store sends no price for it.
func planPrice(_ allocation: SellingPlanAllocation) -> Money? {
    allocation.priceAdjustments.first?.price
}

/// "Deliver every month · $108.00": a plan's row among the purchase options.
func planLabel(_ allocation: SellingPlanAllocation) -> String {
    [allocation.sellingPlan.name, planPrice(allocation)?.display()].compactMap { $0 }.joined(separator: " · ")
}

/// The plan `variant` is bought on: the one with `planId`; without one, a one-time purchase (nil), or the variant's
/// first plan when the product is sold by plan only (`requiresSellingPlan`).
func chosenPlan(_ variant: Variant?, requiresSellingPlan: Bool, planId: String?) -> SellingPlanAllocation? {
    let plans = variant?.sellingPlanAllocations ?? []
    return plans.first { $0.sellingPlan.id == planId } ?? (requiresSellingPlan ? plans.first : nil)
}

/// What one item costs as chosen, and the higher price to strike beside it (nil: none).
struct ChosenPrice: Equatable {
    let price: Money
    let compareAt: Money?
}

/// The price of one `variant` as the shopper has set it up: on `plan`, the plan's price; else the volume price
/// `quantity` reaches (`volumeRow`); else the variant's own. The struck price is the plan's or the variant's compare-at,
/// else the variant's own price when the chosen one is lower.
func chosenPrice(_ variant: Variant, quantity: Int, plan: SellingPlanAllocation?) -> ChosenPrice {
    let price = plan.flatMap { planPrice($0) } ?? volumeRow(volumeRows(variant), quantity)?.price ?? variant.price
    let compareAt = plan?.priceAdjustments.first?.compareAtPrice ?? variant.compareAt ?? (variant.price != price ? variant.price : nil)
    return ChosenPrice(price: price, compareAt: compareAt)
}

/// Where an add to the cart stands: nothing running, running, or just done (shown for two seconds).
enum AddPhase {
    case idle, adding, added
}

/// The main button's words: "Unavailable" without a variant, "Sold out" for one that can't be bought, else by `phase`.
func addButtonLabel(_ variant: Variant?, _ phase: AddPhase) -> String {
    guard let variant = variant else { return "Unavailable" }
    if !variant.available { return "Sold out" }
    switch phase {
    case .adding: return "Adding…"
    case .added: return "Added"
    case .idle: return "Add to cart"
    }
}

// MARK: - Views

/// Block 3. The price as chosen (`price`), the unit price, "Your price for <company>" in a company context
/// (`companyName`), the volume pricing table with the row `quantity` reaches highlighted, and the quantity rule.
@MainActor
struct ProductPrice: View {
    let variant: Variant?
    let price: ChosenPrice?
    let quantity: Int
    let companyName: String?
    @Environment(\.argonTheme) private var theme

    var body: some View {
        if let variant = variant, let price = price {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                PriceView(price: price.price, compareAt: price.compareAt, size: .l)
                if let unit = unitPriceLabel(variant.unitPrice, variant.unitPriceMeasurement) {
                    Text(unit).font(theme.type.caption).foregroundStyle(theme.colors.muted)
                }
                if let companyName = companyName { LabelTag(text: "Your price for \(companyName)") }
                VolumePricing(rows: volumeRows(variant), quantity: quantity)
                if let rule = quantityRuleSentence(variant.quantityRule) {
                    Text(rule).font(theme.type.caption).foregroundStyle(theme.colors.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.l)
            .padding(.top, theme.spacing.m)
        }
    }
}

/// "Volume pricing", then a row per step ("10+", "$108.00 each"); the row `quantity` reaches is on the surface colour.
@MainActor
private struct VolumePricing: View {
    let rows: [VolumeRow]
    let quantity: Int
    @Environment(\.argonTheme) private var theme

    var body: some View {
        if !rows.isEmpty {
            let current = volumeRow(rows, quantity)
            let shape = RoundedRectangle(cornerRadius: theme.radius.m)
            VStack(alignment: .leading, spacing: 0) {
                Text("Volume pricing")
                    .font(theme.type.label)
                    .foregroundStyle(theme.colors.muted)
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.vertical, theme.spacing.s)
                ForEach(rows, id: \.from) { row in
                    let isCurrent = row == current
                    HStack(spacing: theme.spacing.s) {
                        Text(row.label).frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: "\(row.price.display()) each")
                    }
                    .font(theme.type.label)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? theme.colors.ink : theme.colors.muted)
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.vertical, theme.spacing.s)
                    .background(isCurrent ? theme.colors.surface : Color.clear)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(theme.colors.border, lineWidth: 1) }
        }
    }
}

/// Block 5. The stock line (`availabilityLine`) and "Pickup available at <location>" (`pickup`, the location's name).
@MainActor
struct ProductAvailability: View {
    let variant: Variant?
    let pickup: String?
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let line = availabilityLine(variant)
        if line != nil || pickup != nil {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                if let line = line {
                    iconLine(line.tone == .good ? .check : .clock, line.text, color(line.tone))
                }
                if let pickup = pickup {
                    iconLine(.location, "Pickup available at \(pickup)", theme.colors.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.l)
            .padding(.top, theme.spacing.l)
        }
    }

    private func color(_ tone: AvailabilityTone) -> Color {
        switch tone {
        case .good: return theme.colors.success
        case .low: return theme.colors.sale
        case .later: return theme.colors.muted
        }
    }

    private func iconLine(_ icon: ArgonIconName, _ text: String, _ color: Color) -> some View {
        HStack(spacing: theme.spacing.xs) {
            ArgonIcon(name: icon, size: 16, tint: color)
            Text(text).font(theme.type.label).foregroundStyle(color).lineLimit(2)
        }
    }
}

/// Block 6, for a variant with selling plans. "One-time purchase" (left out when the product is sold by plan only,
/// `requiresSellingPlan`) and each plan with its price; `plan` is the chosen one, `onSelect` gets a plan's id, or nil
/// for the one-time purchase.
@MainActor
struct ProductPurchaseOptions: View {
    let variant: Variant?
    let requiresSellingPlan: Bool
    let plan: SellingPlanAllocation?
    let onSelect: (_ planId: String?) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let plans = variant?.sellingPlanAllocations ?? []
        if !plans.isEmpty {
            // the rows are the one-time purchase (when there is one), then the plans
            let oneTime = requiresSellingPlan ? [] : ["One-time purchase"]
            let chosen = plans.firstIndex { $0.sellingPlan.id == plan?.sellingPlan.id }
            // -1 is no row: the radio group has no "none chosen" of its own
            let selected = chosen.map { $0 + oneTime.count } ?? (requiresSellingPlan ? -1 : 0)
            VStack(alignment: .leading, spacing: 0) {
                Text("Purchase options").font(theme.type.label).foregroundStyle(theme.colors.muted)
                ArgonRadioGroup(options: oneTime + plans.map { planLabel($0) }, selectedIndex: selected) { row in
                    let index = row - oneTime.count
                    onSelect(plans.indices.contains(index) ? plans[index].sellingPlan.id : nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.l)
            .padding(.top, theme.spacing.xl)
        }
    }
}

/// Block 7. The quantity on the variant's `rule`, and "Buy now" (adds, then opens checkout; `isBuying` while it does).
/// `canBuyNow` is off while another add is running.
@MainActor
struct ProductQuantity: View {
    let quantity: Int
    let rule: QuantityRule?
    let canBuyNow: Bool
    let isBuying: Bool
    let onQuantity: (Int) -> Void
    let onBuyNow: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.l) {
            HStack {
                Text("Quantity")
                    .font(theme.type.label)
                    .foregroundStyle(theme.colors.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ArgonQuantityStepper(value: quantity, onChange: onQuantity, min: rule?.min ?? 1, max: rule?.maximum, step: rule?.step ?? 1)
            }
            ArgonButton(title: "Buy now", style: .secondary, isLoading: isBuying, isEnabled: canBuyNow, fullWidth: true, action: onBuyNow)
        }
        .padding(.horizontal, theme.spacing.l)
        .padding(.top, theme.spacing.xl)
    }
}

/// The bar pinned under the page, above the tab bar: the price as chosen on the left, the main button on the right
/// (`label`, see `addButtonLabel`). It goes in the page's bottom safe-area inset.
@MainActor
struct StickyAddBar: View {
    let price: ChosenPrice?
    let label: String
    let isEnabled: Bool
    let isLoading: Bool
    let onAdd: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ArgonDivider()
            HStack(spacing: theme.spacing.m) {
                Group {
                    if let price = price { PriceView(price: price.price, compareAt: price.compareAt) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // as wide for "Added" as for "Add to cart": the price beside it doesn't jump
                ArgonButton(title: label, isLoading: isLoading, isEnabled: isEnabled, fullWidth: true, action: onAdd)
                    .frame(minWidth: 160)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, theme.spacing.l)
            .padding(.vertical, theme.spacing.m)
        }
        .background(theme.colors.surface)
    }
}
