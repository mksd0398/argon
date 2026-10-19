import ArgonUI
import Foundation
import Observation
import SwiftUI

// MARK: Logic

/// A sort to choose: `key` is the Storefront sort-key enum value, `reverse` flips it.
struct Sort: Hashable {
    let label: String
    let key: String
    var reverse = false
}

// Each list names its sorts with the keys of its own query's enum: ProductCollectionSortKeys, ProductSortKeys,
// SearchSortKeys. The first of a list is the order the list opens in.
let collectionSorts = [
    Sort(label: "Featured", key: "COLLECTION_DEFAULT"),
    Sort(label: "Best selling", key: "BEST_SELLING"),
    Sort(label: "Price: low to high", key: "PRICE"),
    Sort(label: "Price: high to low", key: "PRICE", reverse: true),
    Sort(label: "Newest", key: "CREATED", reverse: true),
]

// the whole catalogue has no order of the merchant's own ("Featured"): it opens on best selling
let catalogSorts = [
    Sort(label: "Best selling", key: "BEST_SELLING"),
    Sort(label: "Price: low to high", key: "PRICE"),
    Sort(label: "Price: high to low", key: "PRICE", reverse: true),
    Sort(label: "Newest", key: "CREATED_AT", reverse: true),
]
let searchSorts = [
    Sort(label: "Relevance", key: "RELEVANCE"),
    Sort(label: "Price: low to high", key: "PRICE"),
    Sort(label: "Price: high to low", key: "PRICE", reverse: true),
]

/// A page of a product listing (collection, catalog or search results) and the filters it offers.
struct ProductPage: Equatable {
    let items: [ProductCard]
    let filters: [Filter]
    let endCursor: String?
    let hasNext: Bool
}

extension ProductPage {
    init(_ page: Page<ProductCard>) {
        self.init(items: page.items, filters: page.filters, endCursor: page.endCursor, hasNext: page.hasNextPage)
    }
}

/// A cursor-paged product list with a sort and filter selection (collection or search results). `fetch` loads the page
/// after a cursor (nil for the first page); its `applied` are the selected filter values' `input` JSON. `reload` and
/// `loadMore` return the load they start, for tests to await.
@MainActor
@Observable
final class Listing {
    let sorts: [Sort]
    private(set) var sort: Sort
    private(set) var applied: [String] = []
    private(set) var items: [ProductCard] = []
    private(set) var filters: [Filter] = []
    private(set) var hasNext = false
    /// The currency the list's prices are in, once a product has shown it: what a price filter's amounts are written in.
    private(set) var currencyCode: String? = nil
    /// Counts pages that have arrived, even ones that add no new items; a list footer keys its load-more trigger on it.
    private(set) var pagesLoaded = 0
    private(set) var loading = false
    private(set) var error: String? = nil
    @ObservationIgnored private var cursor: String? = nil
    @ObservationIgnored private var task: Task<Void, Never>? = nil
    @ObservationIgnored private var generation = 0
    private let fetch: (String?, Sort, [String]) async throws -> ProductPage

    init(sorts: [Sort], fetch: @escaping (String?, Sort, [String]) async throws -> ProductPage) {
        self.sorts = sorts
        sort = sorts[0]
        self.fetch = fetch
    }

    /// The first load, unless one has already run (a screen calls this each time it appears).
    func start() {
        if generation == 0 { reload() }
    }

    /// Starts over from the first page, with a new `sort` and/or filter selection. `resetFilters` also forgets the filters
    /// the last response offered: pass it when the products behind the list change (a new search query).
    @discardableResult
    func reload(sort: Sort? = nil, applied: [String]? = nil, resetFilters: Bool = false) -> Task<Void, Never> {
        task?.cancel()
        if let sort = sort { self.sort = sort }
        if let applied = applied { self.applied = applied }
        if resetFilters { filters = [] }
        items = []
        hasNext = false
        cursor = nil
        return load()
    }

    @discardableResult
    func loadMore() -> Task<Void, Never>? {
        hasNext && !loading ? load() : nil
    }

    private func load() -> Task<Void, Never> {
        loading = true
        error = nil
        generation += 1
        let mine = generation
        let after = cursor
        let sort = self.sort
        let applied = self.applied
        let started = Task {
            do {
                let page = try await self.fetch(after, sort, applied)
                // a superseded request (a new sort, filter or query) must not touch the list that replaced it
                guard mine == self.generation else { return }
                var seen = Set(self.items.map { $0.id })
                // a catalog that changes between pages can repeat a product
                self.items += page.items.filter { seen.insert($0.id).inserted }
                self.cursor = page.endCursor
                // without a cursor "more" can only repeat the first page
                self.hasNext = page.hasNext && page.endCursor != nil
                self.pagesLoaded += 1
                if let first = page.items.first { self.currencyCode = first.price.currencyCode }
                // a filtered first page that comes back without filters keeps the old ones, so the user can still clear them
                if after == nil && !page.filters.isEmpty { self.filters = keepingPriceBounds(self.filters, page.filters, applied) }
                self.loading = false
            } catch {
                guard mine == self.generation else { return }
                self.error = error.localizedDescription
                self.loading = false
            }
        }
        task = started
        return started
    }
}

/// The filters to show after a reload: the list's new ones (`fresh`), except that while a price range is selected
/// (`applied`) a price filter stays as it was (`current`). Shopify answers a list filtered by price with the range of
/// what is left, which would shrink the slider to the selection and leave no way to widen it again.
/// ponytail: the bounds are those from before the price was chosen, even if other filters change meanwhile.
func keepingPriceBounds(_ current: [Filter], _ fresh: [Filter], _ applied: [String]) -> [Filter] {
    if priceSelection(applied) == nil { return fresh }
    return fresh.map { filter in current.first { $0.type == "PRICE_RANGE" && $0.id == filter.id } ?? filter }
}

/// `text` without the CSS rules a page builder left at its start; the words after them are the description. A
/// collection's description is Shopify's plain text of the merchant's HTML, and that keeps the text of a `<style>` block
/// (page builders put one first): rules like `#html-body [data-pb-style=X]{display:flex}` before the words.
func withoutLeadingCss(_ text: String) -> String {
    text.replacingOccurrences(of: #"^(?:\s*[^{}]{1,200}\{[^{}]*\})+"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// The filter selection is `Listing.applied`: the `input` JSON of every selected filter value, in the order they were
// selected (a price range is one entry, `{"price":{"min":10.0,"max":50.0}}`, see FilterSheet.swift).

/// `applied` with `input` added, or taken out when it is there: a checkbox, a swatch or a switch was tapped.
func toggled(_ applied: [String], _ input: String) -> [String] {
    applied.contains(input) ? applied.filter { $0 != input } : applied + [input]
}

/// Whether `applied` has a value of `filter`: its chip shows as selected.
func isActive(_ filter: Filter, _ applied: [String]) -> Bool {
    filter.type == "PRICE_RANGE" ? priceSelection(applied) != nil : filter.values.contains { applied.contains($0.input) }
}

/// A selected filter value as a removable tag: the `input` to take out of the selection, and the `label` shown.
struct ActiveFilter: Equatable {
    let input: String
    let label: String
}

/// The tags of `applied`, in its order. A value is named by its label among `filters`; a switch by its filter's label
/// ("On sale", not "true"); a price range by its two prices (in `currencyCode` when known); and a value the list no
/// longer offers by the last word of its input (`{"variantOption":{"name":"color","value":"Green"}}` is "Green"), so it can
/// still be removed.
func activeFilters(_ applied: [String], _ filters: [Filter], _ currencyCode: String? = nil) -> [ActiveFilter] {
    applied.map { input in
        let label: String
        if let price = priceRange(input) {
            label = [price.min, price.max].compactMap { $0 }.map { priceText($0, currencyCode) }.joined(separator: " – ")
        } else if let filter = filters.first(where: { filter in filter.values.contains { $0.input == input } }) {
            label = filter.type == "BOOLEAN" ? filter.label : filter.values.first { $0.input == input }?.label ?? ""
        } else {
            label = lastValue(input)
        }
        return ActiveFilter(input: input, label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? input : label)
    }
}

/// The last value written in the JSON `input` (`{"variantOption":{"name":"color","value":"Green"}}` is "Green"); "" when
/// it isn't JSON or doesn't end in a string, a number or a word. JSONSerialization keeps no key order, so the text itself
/// is read: the last string or bare word before the closing braces.
private func lastValue(_ input: String) -> String {
    guard (try? JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed])) != nil,
          let found = input.range(of: #"("(?:[^"\\]|\\.)*"|[^\s\{\}\[\]:,"]+)[\s\}]*$"#, options: .regularExpression) else { return "" }
    let token = input[found].trimmingCharacters(in: CharacterSet(charactersIn: "} \n\r\t"))
    // a string is unescaped by the parser; a number, true or false stays as written
    guard token.hasPrefix("\"") else { return token }
    return (try? JSONSerialization.jsonObject(with: Data(token.utf8), options: [.fragmentsAllowed])) as? String ?? ""
}

/// "14 products", "1 product"; "24+ products" while there are more pages to load.
func resultCount(_ loaded: Int, hasNext: Bool) -> String {
    hasNext ? "\(loaded)+ products" : loaded == 1 ? "1 product" : "\(loaded) products"
}

/// "Filters (2)": `label` with how many are selected; just the label when none is.
func countLabel(_ label: String, _ count: Int) -> String {
    count > 0 ? "\(label) (\(count))" : label
}

// MARK: Views

// room under the grid's last row for the floating pill of the `bottom` template
private let pillClearance: CGFloat = 80

/// A product list in the store's collection `template` (`AppGraph.collectionTemplate`), with the loading, error (Retry)
/// and empty states of `listing`. Over the grid, scrolling with it: the `description` (three lines, "Read more"), the
/// selected filters as removable tags with "Clear all", and in the `bottom` template the result count. The sort and
/// filter controls are a bar pinned over the grid (`top`) or a pill floating over its bottom edge (`bottom`); both open
/// the same sort and filter sheets. Filters show only when the list offers any (the whole catalogue has none).
@MainActor
struct ListingView: View {
    let listing: Listing
    let emptyText: String
    let onOpen: (Route) -> Void
    var description = ""
    var template = AppGraph.collectionTemplate
    /// The screen's sections (screens v2), at the top of what scrolls over the grid.
    var above: AnyView? = nil
    @State private var sortOpen = false
    // the filter sheet: closed (nil), or open at the filter with this id ("": at its top)
    @State private var filtersAt: String? = nil
    @State private var readMore = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let l = listing
        // only the filters the sheet has a control for
        let filters = l.filters.filter { filterControl($0) != nil }
        let applied = l.applied
        let hasFilters = !filters.isEmpty || !applied.isEmpty
        let active = activeFilters(applied, l.filters, l.currencyCode)
        let bottom = template == .bottom
        let count = bottom && !l.items.isEmpty ? resultCount(l.items.count, hasNext: l.hasNext) : nil
        // what scrolls away over the grid; nil when there is nothing to put there
        let header = heading(active, count)
        // read here, not in the sheets' closures: this view follows the list, and hands the sheets what it reads
        let sorts = l.sorts
        let sort = l.sort
        let results = l.loading || l.error != nil ? nil : resultCount(l.items.count, hasNext: l.hasNext)
        let currencyCode = l.currencyCode

        VStack(spacing: 0) {
            if !bottom {
                ListingBar(filters: filters, applied: applied, hasFilters: hasFilters, onSort: { sortOpen = true }, onFilters: { filtersAt = $0 })
            }
            ZStack(alignment: .bottom) {
                if !l.items.isEmpty {
                    ProductGrid(
                        items: l.items,
                        hasNext: l.hasNext,
                        onLoadMore: { l.loadMore() },
                        onOpen: { onOpen(.product($0.handle)) },
                        error: l.error,
                        loadKey: l.pagesLoaded,
                        bottomPadding: bottom ? pillClearance : nil,
                        header: header
                    )
                } else {
                    // no products (yet): the header stays, so a filter that leaves nothing can be taken off again
                    VStack(spacing: 0) {
                        if let header = header { header.padding(theme.spacing.l) }
                        placeholder.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if bottom {
                    ListingPill(selected: applied.count, hasFilters: hasFilters, onSort: { sortOpen = true }, onFilters: { filtersAt = "" })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .argonBottomSheet(isPresented: $sortOpen, detents: [.medium]) {
            SortSheet(sorts: sorts, selected: sort) { picked in
                sortOpen = false
                l.reload(sort: picked)
            }
        }
        .argonBottomSheet(isPresented: Binding(get: { filtersAt != nil }, set: { if !$0 { filtersAt = nil } }), detents: [.large]) {
            FilterSheet(
                filters: filters,
                applied: applied,
                // a change applies at once: the list reloads behind the sheet, and the sheet's button says how many it leaves
                onChange: { l.reload(applied: $0) },
                onDismiss: { filtersAt = nil },
                results: results,
                currencyCode: currencyCode,
                scrollTo: filtersAt
            )
        }
    }

    private func heading(_ active: [ActiveFilter], _ count: String?) -> AnyView? {
        let described = !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if above == nil && !described && active.isEmpty && count == nil { return nil }
        let l = listing
        return AnyView(VStack(alignment: .leading, spacing: theme.spacing.s) {
            if let above = above { above }
            if described { Description(text: description, expanded: readMore) { readMore = true } }
            if !active.isEmpty {
                ActiveFilters(
                    active: active,
                    onRemove: { input in l.reload(applied: l.applied.filter { $0 != input }) },
                    onClear: { l.reload(applied: []) }
                )
            }
            if let count = count { Text(count).font(theme.type.label).foregroundStyle(theme.colors.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading))
    }

    @ViewBuilder private var placeholder: some View {
        if let error = listing.error {
            ErrorView(message: error) { listing.reload() }
        } else if listing.loading || listing.pagesLoaded == 0 {
            // loading, or about to: the screen starts the list as it appears
            ScreenSkeleton(.grid)
        } else {
            Text(listing.applied.isEmpty ? emptyText : "No products match these filters.")
                .font(theme.type.body)
                .foregroundStyle(theme.colors.muted)
                .multilineTextAlignment(.center)
                .padding(theme.spacing.xl)
        }
    }
}

/// A collection's description: three lines, and "Read more" to show the rest when there is more.
@MainActor
private struct Description: View {
    let text: String
    let expanded: Bool
    let onExpand: () -> Void
    @State private var cut = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(theme.type.body)
                .foregroundStyle(theme.colors.muted)
                .lineLimit(expanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    // The whole text, unseen, in the three lines' space: when it doesn't fit there, there is more to read.
                    ViewThatFits(in: .vertical) {
                        Text(text).font(theme.type.body).hidden()
                        Color.clear.onAppear { cut = true }
                    }
                }
            if cut && !expanded {
                Button(action: onExpand) {
                    Text("Read more")
                        .font(theme.type.label)
                        .foregroundStyle(theme.colors.ink)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The selected filters as tags (a tap takes one off), wrapping onto more lines, then "Clear all".
@MainActor
private struct ActiveFilters: View {
    let active: [ActiveFilter]
    let onRemove: (String) -> Void
    let onClear: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        FilterFlow(spacing: theme.spacing.s, rowSpacing: 0) {
            ForEach(active, id: \.input) { filter in
                ArgonTag(text: filter.label, style: .input, onClick: { onRemove(filter.input) }, onRemove: { onRemove(filter.input) })
            }
            ArgonButton(title: "Clear all", style: .tertiary, size: .s, action: onClear)
        }
    }
}

/// The `top` template's controls, pinned over the grid: Sort, "Filters (n)", then a chip per filter that opens the sheet
/// at that filter (`onFilters` gets its id, "" for the sheet's top). The chips scroll sideways; the two buttons stay.
@MainActor
private struct ListingBar: View {
    let filters: [Filter]
    let applied: [String]
    let hasFilters: Bool
    let onSort: () -> Void
    let onFilters: (String) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s) {
                ArgonButton(title: "Sort", style: .secondary, size: .s, icon: .chevronDown, action: onSort)
                if hasFilters {
                    ArgonButton(title: countLabel("Filters", applied.count), style: .secondary, size: .s, icon: .filter) { onFilters("") }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    // not lazy: a lazy row would stretch to the height it is offered, and these are a handful of chips
                    HStack(spacing: theme.spacing.s) {
                        ForEach(filters, id: \.id) { filter in
                            ArgonTag(text: filter.label, isSelected: isActive(filter, applied), onClick: { onFilters(filter.id) })
                        }
                    }
                    .padding(.trailing, theme.spacing.l)
                }
            }
            .padding(.leading, theme.spacing.l)
            .padding(.vertical, theme.spacing.xs)
            ArgonDivider()
        }
    }
}

/// The `bottom` template's controls: a pill floating over the grid's bottom edge, "Sort" | "Filter (n)".
@MainActor
private struct ListingPill: View {
    let selected: Int
    let hasFilters: Bool
    let onSort: () -> Void
    let onFilters: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ArgonButton(title: "Sort", style: .tertiary, size: .s, icon: .sort, action: onSort)
            if hasFilters {
                Rectangle().fill(theme.colors.border).frame(width: 1, height: 24)
                ArgonButton(title: countLabel("Filter", selected), style: .tertiary, size: .s, icon: .filter, action: onFilters)
            }
        }
        .background(theme.colors.surface, in: Capsule())
        // the border keeps its edge in dark mode, where a shadow doesn't show
        .overlay { Capsule().strokeBorder(theme.colors.border, lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .padding(.bottom, theme.spacing.l)
    }
}

/// Its children left to right, wrapping onto more rows when a row is full (the selected filters' tags, a colour filter's
/// swatches).
struct FilterFlow: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews, width: bounds.width).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// Where each child goes in a row `width` wide (one wider than that is cut to it), and the size they take together.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            widest = max(widest, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (frames, CGSize(width: widest, height: y + rowHeight))
    }
}
