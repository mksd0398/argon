import SwiftUI

/// `{"price":{"min":x,"max":y}}` for the min/max fields (either may be empty); nil when neither is a number.
func priceFilter(_ low: String, _ high: String) -> String? {
    func number(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
        return value
    }
    var price: [String: Double] = [:]
    if let min = number(low) { price["min"] = min }
    if let max = number(high) { price["max"] = max }
    if price.isEmpty { return nil }
    guard let data = try? JSONSerialization.data(withJSONObject: ["price": price], options: [.sortedKeys]) else { return nil }
    return String(decoding: data, as: UTF8.self)
}

/// The `price` bounds of an applied filter, or nil when it isn't a price filter.
private func priceBounds(_ input: String) -> [String: Any]? {
    let object = try? JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any]
    return object?["price"] as? [String: Any]
}

/// The Sort menu and, when the response has filters (or some are applied), the Filter button with its sheet.
@MainActor
struct ListingBar: View {
    let listing: Listing
    @State private var filtering = false

    var body: some View {
        let filterTitle = listing.applied.isEmpty ? "Filter" : "Filter (\(listing.applied.count))"
        HStack {
            Menu {
                ForEach(listing.sorts, id: \.self) { sort in
                    Button(sort.label) { listing.reload(sort: sort) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: "Sort: \(listing.sort.label)")
                    Image(systemName: "chevron.down").font(.caption)
                }
            }
            Spacer()
            if !listing.filters.isEmpty || !listing.applied.isEmpty {
                Button(filterTitle) { filtering = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .sheet(isPresented: $filtering) {
            FilterSheet(filters: listing.filters, applied: listing.applied) { picked in
                filtering = false
                listing.reload(applied: picked)
            }
        }
    }
}

/// One section per `Filter`: switches for a list, min/max fields for a price range. `applied` and `onApply` are the
/// selected values' `input` JSON strings (the price range as `{"price":{...}}`).
@MainActor
struct FilterSheet: View {
    let filters: [Filter]
    let onApply: ([String]) -> Void
    @State private var picked: Set<String>
    @State private var low: String
    @State private var high: String

    init(filters: [Filter], applied: [String], onApply: @escaping ([String]) -> Void) {
        self.filters = filters
        self.onApply = onApply
        _picked = State(initialValue: Set(applied.filter { priceBounds($0) == nil }))
        _low = State(initialValue: Self.bound("min", applied))
        _high = State(initialValue: Self.bound("max", applied))
    }

    private static func bound(_ key: String, _ applied: [String]) -> String {
        for input in applied {
            if let value = priceBounds(input)?[key] { return "\(value)" }
        }
        return ""
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(filters, id: \.id) { filter in
                    SwiftUI.Section(filter.label) {
                        if filter.type == "PRICE_RANGE" {
                            HStack(spacing: 12) {
                                TextField("Min", text: $low).keyboardType(.decimalPad)
                                TextField("Max", text: $high).keyboardType(.decimalPad)
                            }
                        } else {
                            ForEach(filter.values, id: \.id) { value in
                                Toggle(isOn: selected(value.input)) { Text(verbatim: "\(value.label) (\(value.count))") }
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { onApply([]) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply(Array(picked) + [priceFilter(low, high)].compactMap { $0 }) }
                }
            }
        }
    }

    private func selected(_ input: String) -> Binding<Bool> {
        Binding(
            get: { picked.contains(input) },
            set: { on in
                if on { picked.insert(input) } else { picked.remove(input) }
            }
        )
    }
}
