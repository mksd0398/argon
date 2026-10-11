import XCTest
@testable import ArgonStorefront

/// The filter sheet's logic, on the filters of the Collection fixture: availability, price, colour (swatches) and size.
final class FiltersTests: XCTestCase {
    private struct Fixture {
        let filters: [Filter]
        let availability: Filter
        let price: Filter
        let color: Filter
        let size: Filter
        /// The inputs of the first colour and the first size.
        let green: String
        let small: String
    }

    @MainActor
    private func collectionFilters() async throws -> Fixture {
        let collection = try await StubServer().storefront().collection("men")
        let filters = try XCTUnwrap(collection).products.filters
        func filter(_ id: String) throws -> Filter { try XCTUnwrap(filters.first { $0.id == id }, id) }
        let color = try filter("filter.v.option.color")
        let size = try filter("filter.v.option.size")
        return Fixture(
            filters: filters,
            availability: try filter("filter.v.availability"),
            price: try filter("filter.v.price"),
            color: color,
            size: size,
            green: try XCTUnwrap(color.values.first).input,
            small: try XCTUnwrap(size.values.first).input
        )
    }

    private func priceFilter(_ input: String) -> Filter {
        Filter(id: "filter.v.price", label: "Price", type: "PRICE_RANGE", values: [FilterValue(id: "filter.v.price", label: "Price", count: 14, input: input)])
    }

    /// `filter` with some of its parts changed.
    private func changed(_ filter: Filter, label: String? = nil, values: [FilterValue]? = nil, presentation: String? = nil) -> Filter {
        Filter(
            id: filter.id,
            label: label ?? filter.label,
            type: filter.type,
            values: values ?? filter.values,
            presentation: presentation ?? filter.presentation
        )
    }

    @MainActor
    func testEachFilterGetsItsControl() async throws {
        let f = try await collectionFilters()
        XCTAssertEqual(
            [f.availability, f.price, f.color, f.size].map { filterControl($0) },
            [.checkboxes, .slider, .swatches, .checkboxes]
        )
    }

    @MainActor
    func testAColourFilterIsKnownByItsPresentationItsSwatchesOrItsName() async throws {
        let size = try await collectionFilters().size
        XCTAssertEqual(filterControl(size), .checkboxes)
        XCTAssertEqual(filterControl(changed(size, presentation: "SWATCH")), .swatches)
        XCTAssertEqual(filterControl(changed(size, label: "Colour")), .swatches)
        XCTAssertEqual(filterControl(changed(size, label: " shade ")), .swatches)
        let oneSwatch = size.values.enumerated().map { index, value in
            index == 0
                ? FilterValue(id: value.id, label: value.label, count: value.count, input: value.input, swatch: Swatch(color: "#FFFFFF", image: nil))
                : value
        }
        XCTAssertEqual(filterControl(changed(size, values: oneSwatch)), .swatches, "the store set a swatch on a value")
        XCTAssertEqual(filterControl(changed(size, label: "Colour family")), .checkboxes, "a name that only mentions colour is not a colour filter")
    }

    @MainActor
    func testAFilterWithNothingToChooseHasNoControl() async throws {
        let size = try await collectionFilters().size
        XCTAssertNil(filterControl(changed(size, values: [])))
        XCTAssertNil(filterControl(Filter(id: "filter.v.price", label: "Price", type: "PRICE_RANGE", values: [])), "a price filter without a value has no bounds")
        XCTAssertNil(filterControl(priceFilter(#"{"price":{"min":40,"max":40}}"#)), "every product costs the same")
    }

    func testABooleanFilterIsASwitchOnItsTrueValue() {
        func value(_ id: String, _ flag: String) -> FilterValue {
            FilterValue(id: id, label: flag, count: 2, input: "{\"productMetafield\":{\"namespace\":\"custom\",\"key\":\"vegan\",\"value\":\"\(flag)\"}}")
        }
        let vegan = Filter(id: "filter.p.m.custom.vegan", label: "Vegan", type: "BOOLEAN", values: [value("no", "false"), value("yes", "true")])
        XCTAssertEqual(filterControl(vegan), .switch)
        XCTAssertEqual(booleanValue(vegan)?.id, "yes")
        XCTAssertEqual(booleanValue(changed(vegan, values: Array(vegan.values.prefix(1))))?.id, "no", "without a true value: the first")
    }

    @MainActor
    func testATapAddsAValueAndASecondTapTakesItOut() async throws {
        let f = try await collectionFilters()
        let one = toggled([], f.green)
        XCTAssertEqual(one, [f.green])
        let two = toggled(one, f.small)
        XCTAssertEqual(two, [f.green, f.small], "in the order selected")
        XCTAssertEqual(toggled(two, f.green), [f.small])
    }

    @MainActor
    func testThePriceSliderTakesItsBoundsFromTheFilterValuesOwnInput() async throws {
        let f = try await collectionFilters()
        XCTAssertEqual(f.price.values.map { $0.input }, [#"{"price":{"min":0,"max":120}}"#])
        XCTAssertEqual(priceSlider(f.price), PriceSlider(bounds: 0...120, step: 2))
        XCTAssertEqual(
            priceSlider(priceFilter(#"{"price":{"min":12.5,"max":119.99}}"#)),
            PriceSlider(bounds: 12...120, step: 2),
            "widened to whole steps, so 119.99 stays inside"
        )
        XCTAssertEqual(priceSlider(priceFilter(#"{"price":{"min":0,"max":48000}}"#)), PriceSlider(bounds: 0...48000, step: 500), "a currency with large amounts")
        XCTAssertEqual(priceSlider(priceFilter(#"{"price":{"max":80}}"#)), PriceSlider(bounds: 0...80, step: 1), "no min: from 0")
        XCTAssertNil(priceSlider(f.size))
    }

    func testTheStepKeepsTheSliderAtAHundredStopsOrFewer() {
        XCTAssertEqual([0.5, 100, 101, 250, 1000, 2000, 4999].map { priceStep($0) }, [1, 1, 2, 5, 10, 20, 50])
    }

    @MainActor
    func testThePriceInputIsShopifysProductFilter() async throws {
        let green = try await collectionFilters().green
        XCTAssertEqual(priceInput(10, 50), #"{"price":{"min":10.0,"max":50.0}}"#)
        XCTAssertEqual(priceRange(priceInput(10, 50)), PriceBounds(min: 10, max: 50))
        XCTAssertEqual(priceRange(#"{"price":{"min":0,"max":120}}"#), PriceBounds(min: 0, max: 120))
        XCTAssertEqual(priceRange(#"{"price":{"max":20}}"#), PriceBounds(min: nil, max: 20))
        XCTAssertNil(priceRange(green), "another filter")
        XCTAssertNil(priceRange("not json"))
    }

    @MainActor
    func testThePriceRangeIsOneEntryOfTheSelection() async throws {
        let green = try await collectionFilters().green
        let bounds = 0.0...120.0
        let one = withPrice([green], 20, 60, bounds)
        XCTAssertEqual(one, [green, #"{"price":{"min":20.0,"max":60.0}}"#])
        XCTAssertEqual(priceSelection(one), PriceBounds(min: 20, max: 60))
        XCTAssertEqual(withPrice(one, 20, 80, bounds), [green, #"{"price":{"min":20.0,"max":80.0}}"#], "moved: replaced, not added")
        XCTAssertEqual(withPrice(one, 0, 120, bounds), [green], "the whole range is no filter")
        XCTAssertNil(priceSelection([green]))
    }

    @MainActor
    func testAFilterIsActiveWhenTheSelectionHasOneOfItsValues() async throws {
        let f = try await collectionFilters()
        XCTAssertTrue(isActive(f.color, [f.green]))
        XCTAssertFalse(isActive(f.size, [f.green]))
        XCTAssertFalse(isActive(f.price, [f.green]), "the price filter's own input is its bounds, not a selection")
        XCTAssertTrue(isActive(f.price, [priceInput(20, 60)]))
    }

    @MainActor
    func testSelectedFiltersAreNamedForTheirTags() async throws {
        let f = try await collectionFilters()
        let inStock = try XCTUnwrap(f.availability.values.first).input
        let gone = #"{"variantOption":{"name":"color","value":"Teal"}}"#
        let applied = [f.green, inStock, priceInput(20, 60), gone]
        let active = activeFilters(applied, f.filters)
        XCTAssertEqual(active.map { $0.input }, applied)
        XCTAssertEqual(active.map { $0.label }, ["Green", "In stock", "20 – 60", "Teal"])
        let twenty = Money(amount: "20.0", currencyCode: "USD").display()
        let sixty = Money(amount: "60.0", currencyCode: "USD").display()
        XCTAssertEqual(
            activeFilters([priceInput(20, 60)], f.filters, "USD").map { $0.label },
            ["\(twenty) – \(sixty)"],
            "in the list's currency once it is known"
        )
        let vegan = Filter(
            id: "b",
            label: "Vegan",
            type: "BOOLEAN",
            values: [FilterValue(id: "yes", label: "true", count: 2, input: #"{"productMetafield":{"key":"vegan","value":"true"}}"#)]
        )
        XCTAssertEqual(activeFilters([vegan.values[0].input], [vegan]).map { $0.label }, ["Vegan"], "a switch is named by its filter")
        XCTAssertEqual(activeFilters(["?"], f.filters).map { $0.label }, ["?"], "unreadable: itself, so it can still be removed")
    }

    func testCountsReadNaturally() {
        XCTAssertEqual(resultCount(14, hasNext: false), "14 products")
        XCTAssertEqual(resultCount(1, hasNext: false), "1 product")
        XCTAssertEqual(resultCount(0, hasNext: false), "0 products")
        XCTAssertEqual(resultCount(24, hasNext: true), "24+ products", "more pages to come")
        XCTAssertEqual(countLabel("Filters", 0), "Filters")
        XCTAssertEqual(countLabel("Filter", 2), "Filter (2)")
    }

    @MainActor
    func testThePriceSliderKeepsItsBoundsWhileAPriceIsSelected() async throws {
        let f = try await collectionFilters()
        // Shopify answers a list filtered to 0...80 with a price filter of 0...80: the slider must not shrink to it
        let narrowed = priceFilter(#"{"price":{"min":0,"max":80}}"#)
        let fresh = [f.availability, narrowed, changed(f.color, values: Array(f.color.values.prefix(1)))]
        let kept = keepingPriceBounds(f.filters, fresh, [priceInput(0, 80), f.green])
        XCTAssertEqual(kept[1], f.price, "the price filter is the one from before")
        XCTAssertEqual([kept[0], kept[2]], [fresh[0], fresh[2]], "every other filter is the new one")
        XCTAssertEqual(keepingPriceBounds(f.filters, fresh, [f.green]), fresh, "no price selected: all new")
        XCTAssertEqual(keepingPriceBounds([], fresh, [priceInput(0, 80)]), fresh, "nothing to keep yet")
    }

    func testADescriptionLosesTheCssAPageBuilderLeftBeforeIt() {
        let css = "#html-body [data-pb-style=SMHWSI9]{justify-content:flex-start;display:flex}#html-body [data-pb-style=A1]{border-style:none}"
        XCTAssertEqual(withoutLeadingCss("\(css) Silk sarees for every day."), "Silk sarees for every day.")
        XCTAssertEqual(withoutLeadingCss(css), "", "only CSS: nothing to show")
        XCTAssertEqual(withoutLeadingCss("Cotton Silk Saree- Drape every occasion"), "Cotton Silk Saree- Drape every occasion", "plain words stay as they are")
        XCTAssertEqual(withoutLeadingCss(""), "")
    }
}
