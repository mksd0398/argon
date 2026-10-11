import ArgonUI
import Foundation
import SwiftUI

// MARK: Logic

/// How the filter sheet shows a filter.
enum FilterControl: Equatable {
    case slider, `switch`, swatches, checkboxes
}

/// The control for `filter`: a slider for a price range, a switch for a boolean, and for a list checkboxes, or swatches
/// when it is a colour filter (the store presents it as swatches, a value has a swatch, or it is named colour, color or
/// shade). Nil when it has nothing to choose: no values, or a price range without bounds.
func filterControl(_ filter: Filter) -> FilterControl? {
    if filter.type == "PRICE_RANGE" { return priceSlider(filter) == nil ? nil : .slider }
    if filter.values.isEmpty { return nil }
    if filter.type == "BOOLEAN" { return .switch }
    if filter.presentation == "SWATCH" || filter.values.contains(where: { $0.swatch != nil }) || isColorName(filter.label) {
        return .swatches
    }
    return .checkboxes
}

/// The value a BOOLEAN `filter`'s switch turns on: the one whose input says true, else its first.
func booleanValue(_ filter: Filter) -> FilterValue? {
    filter.values.first { $0.input.lowercased().contains("true") } ?? filter.values.first
}

// Price. A price filter is one entry of the selection, Shopify's `ProductFilter` `{"price":{"min":10.0,"max":50.0}}`.

/// The two ends of a price range; either may be missing.
struct PriceBounds: Decodable, Equatable {
    var min: Double? = nil
    var max: Double? = nil
}

private struct PriceInput: Decodable {
    let price: PriceBounds
}

/// The `min` and `max` of a `{"price":{...}}` filter input (either may be missing); nil for any other input.
func priceRange(_ input: String) -> PriceBounds? {
    (try? JSONDecoder().decode(PriceInput.self, from: Data(input.utf8)))?.price
}

/// The price range selected in `applied`; nil when there is none.
func priceSelection(_ applied: [String]) -> PriceBounds? {
    applied.lazy.compactMap { priceRange($0) }.first
}

/// `{"price":{"min":10.0,"max":50.0}}`: the filter input for the prices from `lower` to `upper`.
func priceInput(_ lower: Double, _ upper: Double) -> String {
    "{\"price\":{\"min\":\(lower),\"max\":\(upper)}}"
}

/// `applied` with `lower`...`upper` as its one price entry; with no price entry when that is the whole of `bounds` (all
/// prices: nothing to filter).
func withPrice(_ applied: [String], _ lower: Double, _ upper: Double, _ bounds: ClosedRange<Double>) -> [String] {
    let others = applied.filter { priceRange($0) == nil }
    return lower <= bounds.lowerBound && upper >= bounds.upperBound ? others : others + [priceInput(lower, upper)]
}

/// A price filter's slider: the `bounds` its two thumbs move in, and the `step` they move by.
struct PriceSlider: Equatable {
    let bounds: ClosedRange<Double>
    let step: Double
}

/// The slider of a PRICE_RANGE `filter`. Its bounds are the `min` and `max` of the filter value's own `input`
/// (`{"price":{"min":0,"max":120}}`: the list's lowest and highest price), widened to whole steps so the highest price
/// stays inside. Nil when there is no range to choose in.
func priceSlider(_ filter: Filter) -> PriceSlider? {
    guard let range = filter.values.lazy.compactMap({ priceRange($0.input) }).first else { return nil }
    let low = range.min ?? 0
    guard let high = range.max, high > low else { return nil }
    let step = priceStep(high - low)
    return PriceSlider(bounds: (low / step).rounded(.down) * step...(high / step).rounded(.up) * step, step: step)
}

/// The smallest of 1, 2, 5, 10, 20, 50, ... that crosses `span` in 100 steps or fewer.
func priceStep(_ span: Double) -> Double {
    // a span that isn't a number would never be crossed
    guard span.isFinite else { return 1 }
    var magnitude = 1.0
    while true {
        for unit in [1.0, 2.0, 5.0] where span / (unit * magnitude) <= 100 { return unit * magnitude }
        magnitude *= 10
    }
}

/// A price at a slider's end or on a tag: in `currencyCode` when the list has shown one, else the bare number.
func priceText(_ value: Double, _ currencyCode: String?) -> String {
    if let currencyCode = currencyCode { return Money(amount: "\(value)", currencyCode: currencyCode).display() }
    return String(format: "%.0f", value.rounded())
}

// MARK: Views

/// The sorts of a product list to choose from, in a bottom sheet; choosing one applies it (`onSelect` closes the sheet).
@MainActor
struct SortSheet: View {
    let sorts: [Sort]
    let selected: Sort
    let onSelect: (Sort) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            SheetTitle(text: "Sort")
            ArgonRadioGroup(options: sorts.map { $0.label }, selectedIndex: sorts.firstIndex(of: selected) ?? -1) { onSelect(sorts[$0]) }
        }
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, theme.spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { theme.colors.surface.ignoresSafeArea() }
    }
}

/// The filters of a product list, in a bottom sheet, one section each (`filterControl` says which control a filter gets).
/// A change applies at once: `onChange` gets the new selection (the selected values' `input` JSON, a price range as one
/// `{"price":{...}}`), the list reloads behind the sheet, and the button that closes it says what is left (`results`,
/// "14 products"; nil while that loads). "Clear" takes every filter off. `scrollTo` is the id of the filter to open at.
@MainActor
struct FilterSheet: View {
    let filters: [Filter]
    let applied: [String]
    let onChange: ([String]) -> Void
    let onDismiss: () -> Void
    var results: String? = nil
    var currencyCode: String? = nil
    var scrollTo: String? = nil
    // A change reloads the filters, and a section above the one just used can come back shorter (fewer values are left).
    // The section that was used (its filter's id, and how far under the list's top edge it sat when the change was made)
    // is put back where it was, so it doesn't jump from under the finger.
    @State private var used: String? = nil
    @State private var usedTop: CGFloat = 0
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(text: "Filters").padding(.horizontal, theme.spacing.l).padding(.top, theme.spacing.xl)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: theme.spacing.l) {
                        ForEach(filters, id: \.id) { filter in
                            FilterSection(
                                filter: filter,
                                applied: applied,
                                onChange: { next in
                                    used = filter.id
                                    onChange(next)
                                },
                                currencyCode: currencyCode
                            )
                            // where the section sits in the list's window, read as a change is made in it (the selection
                            // changes at once, the filters only when the list has reloaded)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.onChange(of: applied) {
                                        if used == filter.id { usedTop = geometry.frame(in: .named(filterList)).minY }
                                    }
                                }
                            }
                            // The section's anchor: a point as far above the section's top as the section sat under the
                            // list's top edge (for the section in use; its own top for any other). Scrolling that point
                            // to the list's top puts the section back where it was.
                            .overlay(alignment: .topLeading) {
                                Color.clear
                                    .frame(width: 0, height: 0)
                                    .id(SectionAnchor(filter: filter.id))
                                    .alignmentGuide(.top) { _ in used == filter.id ? usedTop : 0 }
                            }
                        }
                    }
                    .padding(.horizontal, theme.spacing.l)
                    .padding(.vertical, theme.spacing.m)
                }
                .coordinateSpace(.named(filterList))
                // once the sheet is laid out (a task runs after it appears)
                .task {
                    if let scrollTo = scrollTo, filters.contains(where: { $0.id == scrollTo }) { proxy.scrollTo(scrollTo, anchor: .top) }
                }
                .onChange(of: filters) {
                    if let used = used { proxy.scrollTo(SectionAnchor(filter: used), anchor: .top) }
                }
            }
            HStack(spacing: theme.spacing.m) {
                ArgonButton(title: "Clear", style: .tertiary, isEnabled: !applied.isEmpty) {
                    used = nil
                    onChange([])
                }
                ArgonButton(title: results.map { "Show \($0)" } ?? "Show products", fullWidth: true, action: onDismiss)
            }
            .padding(theme.spacing.l)
        }
        .background { theme.colors.surface.ignoresSafeArea() }
    }
}

/// The name of the filter list's own coordinate space: a section's place in the list's window is measured in it.
private let filterList = "filterList"

/// The id of a filter section's anchor in the list (see `FilterSheet`); apart from the section's own id, the filter's.
private struct SectionAnchor: Hashable {
    let filter: String
}

/// A sheet's title; with `section`, the smaller heading of one of its sections.
@MainActor
private struct SheetTitle: View {
    let text: String
    var section = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Text(text)
            .font(section ? theme.type.headline : theme.type.title)
            .foregroundStyle(theme.colors.ink)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
private struct FilterSection: View {
    let filter: Filter
    let applied: [String]
    let onChange: ([String]) -> Void
    let currencyCode: String?
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let control = filterControl(filter)
        if control == .switch {
            // a switch carries the filter's name itself
            if let value = booleanValue(filter) {
                ArgonSwitch(isOn: applied.contains(value.input), label: filter.label) { _ in onChange(toggled(applied, value.input)) }
            }
        } else if let control = control {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                SheetTitle(text: filter.label, section: true)
                switch control {
                case .slider:
                    if let slider = priceSlider(filter) {
                        PriceRangeControl(slider: slider, applied: applied, onChange: onChange, currencyCode: currencyCode)
                    }
                case .swatches:
                    FilterFlow(spacing: theme.spacing.s, rowSpacing: theme.spacing.m) {
                        ForEach(filter.values, id: \.id) { value in
                            let on = applied.contains(value.input)
                            let fill = swatch(for: value)
                            // a colour no product in the list has is struck through (it can still be tapped)
                            ArgonSwatch(
                                colorHex: fill.colorHex, imageUrl: fill.imageUrl, label: value.label,
                                isSelected: on, isAvailable: value.count > 0 || on, size: .l
                            ) { onChange(toggled(applied, value.input)) }
                        }
                    }
                    .padding(.top, theme.spacing.s)
                default:
                    ForEach(filter.values, id: \.id) { value in
                        let on = applied.contains(value.input)
                        // a value no product in the list has can't be ticked (but one that is ticked can be unticked)
                        ArgonCheckbox(isChecked: on, label: "\(value.label) (\(value.count))", isEnabled: value.count > 0 || on) { _ in
                            onChange(toggled(applied, value.input))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// What the price slider waits on before it changes the selection: where the thumbs rest, and the selection they change.
private struct PriceDrag: Equatable {
    let range: PriceBounds?
    let applied: [String]
}

/// The price slider with its two prices under it. The thumbs follow the finger; the selection changes once they have
/// rested for a moment, so a drag is one reload of the list, not one per step.
/// ponytail: a drag in the last moments before the sheet closes is dropped; apply on release if ArgonRangeSlider gets one.
@MainActor
private struct PriceRangeControl: View {
    let slider: PriceSlider
    let applied: [String]
    let onChange: ([String]) -> Void
    let currencyCode: String?
    // where the thumbs are while they move; nil: at the selection
    @State private var dragged: PriceBounds? = nil
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let bounds = slider.bounds
        let selected = priceSelection(applied)
        let lower = dragged?.min ?? selected?.min ?? bounds.lowerBound
        let upper = dragged?.max ?? selected?.max ?? bounds.upperBound
        VStack(spacing: 0) {
            ArgonRangeSlider(lower: lower, upper: upper, bounds: bounds, step: slider.step) { dragged = PriceBounds(min: $0, max: $1) }
            HStack {
                Text(priceText(lower, currencyCode))
                Spacer()
                Text(priceText(upper, currencyCode))
            }
            .font(theme.type.label)
            .foregroundStyle(theme.colors.ink)
        }
        // the thumbs go back to the selection when it changes under them ("Clear", a tag taken off), or the list's prices do
        .onChange(of: selected) { dragged = nil }
        .onChange(of: slider) { dragged = nil }
        // the wait starts over when the selection changes meanwhile: the price is put into the newest one
        .task(id: PriceDrag(range: dragged, applied: applied)) {
            guard let lower = dragged?.min, let upper = dragged?.max else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            let next = withPrice(applied, lower, upper, bounds)
            if next != applied { onChange(next) }
        }
    }
}
