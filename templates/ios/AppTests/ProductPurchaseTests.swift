import XCTest
@testable import ArgonStorefront

final class ProductPurchaseTests: XCTestCase {
    private let us = Locale(identifier: "en_US")

    private func usd(_ amount: String) -> Money { Money(amount: amount, currencyCode: "USD") }
    private func cad(_ amount: String) -> Money { Money(amount: amount, currencyCode: "CAD") }

    /// A plain variant, as a product's own list has it.
    private func basic(available: Bool = true, compareAt: Money? = nil) -> Variant {
        Variant(id: "v", title: "Small", available: available, options: [:], price: usd("80.0"), compareAt: compareAt, image: nil)
    }

    /// The contract's selected variant in full: $120.00, 4 in stock, sold in twos from 2 to 40, cheaper from 10 and from
    /// 20, a bundle, with a monthly plan at $108.00.
    @MainActor
    private func richVariant() async throws -> Variant {
        let found = try await StubServer().storefront()
            .variantBySelectedOptions(productHandle: "men-crewneck", options: ["Size": "Small", "Color": "Olive"])
        return try XCTUnwrap(found)
    }

    /// The fixture's one selling plan.
    private func monthlyPlan(_ variant: Variant) throws -> SellingPlanAllocation {
        XCTAssertEqual(variant.sellingPlanAllocations.count, 1)
        return try XCTUnwrap(variant.sellingPlanAllocations.first)
    }

    private func rule(_ minimum: Int, _ maximum: Int?, _ increment: Int) -> QuantityRule {
        QuantityRule(minimum: minimum, maximum: maximum, increment: increment)
    }

    private func measurement(_ type: String?, _ unit: String?, _ value: Double, _ referenceUnit: String?, _ referenceValue: Int) -> UnitPriceMeasurement {
        UnitPriceMeasurement(measuredType: type, quantityUnit: unit, quantityValue: value, referenceUnit: referenceUnit, referenceValue: referenceValue)
    }

    private func plan(_ id: String, _ name: String) -> SellingPlanAllocation {
        SellingPlanAllocation(sellingPlan: SellingPlan(id: id, name: name), priceAdjustments: [])
    }

    // MARK: Quantity

    func testTheQuantityIsKeptOnTheRule() {
        let pairs = rule(2, 40, 2)
        XCTAssertEqual(clampedQuantity(1, pairs), 2, "up to the minimum")
        XCTAssertEqual(clampedQuantity(2, pairs), 2)
        XCTAssertEqual(clampedQuantity(5, pairs), 4, "down onto the increments")
        XCTAssertEqual(clampedQuantity(99, pairs), 40, "down to the maximum")
        XCTAssertEqual(clampedQuantity(50, rule(3, 10, 3)), 9, "the top of a range that doesn't end on an increment")
    }

    func testWithoutARuleAnyQuantityFromOneGoes() {
        XCTAssertEqual(clampedQuantity(7, nil), 7)
        XCTAssertEqual(clampedQuantity(0, nil), 1)
        XCTAssertEqual(clampedQuantity(3, rule(0, nil, 0)), 3, "mock.shop sends 0 for no rule")
    }

    // MARK: Volume pricing

    @MainActor
    func testTheVolumeTableStartsAtTheVariantsPriceThenListsEachBreak() async throws {
        let rows = volumeRows(try await richVariant())
        XCTAssertEqual(rows, [
            VolumeRow(from: 2, price: cad("120.0")),
            VolumeRow(from: 10, price: cad("108.0")),
            VolumeRow(from: 20, price: cad("96.0")),
        ])
        XCTAssertEqual(rows.map { $0.label }, ["2+", "10+", "20+"])
        XCTAssertEqual(volumeRows(basic()), [], "no breaks, no table")
    }

    func testTheBreaksAreOrderedAndStartFromOneWithoutARule() {
        var variant = basic()
        variant.quantityPriceBreaks = [
            QuantityPriceBreak(minimumQuantity: 50, price: usd("60.0")),
            QuantityPriceBreak(minimumQuantity: 10, price: usd("70.0")),
        ]
        XCTAssertEqual(volumeRows(variant), [
            VolumeRow(from: 1, price: usd("80.0")),
            VolumeRow(from: 10, price: usd("70.0")),
            VolumeRow(from: 50, price: usd("60.0")),
        ])
    }

    @MainActor
    func testTheRowForAQuantityIsTheLastOneItReaches() async throws {
        let rows = volumeRows(try await richVariant())
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(volumeRow(rows, 2), rows[0])
        XCTAssertEqual(volumeRow(rows, 9), rows[0])
        XCTAssertEqual(volumeRow(rows, 10), rows[1])
        XCTAssertEqual(volumeRow(rows, 19), rows[1])
        XCTAssertEqual(volumeRow(rows, 20), rows[2])
        XCTAssertEqual(volumeRow(rows, 40), rows[2])
        XCTAssertNil(volumeRow(rows, 1), "under the first row")
        XCTAssertNil(volumeRow([], 5))
    }

    @MainActor
    func testThePriceOfOneFollowsTheQuantityAndThePlan() async throws {
        let rich = try await richVariant()
        let monthly = try monthlyPlan(rich)
        XCTAssertEqual(chosenPrice(rich, quantity: 2, plan: nil), ChosenPrice(price: cad("120.0"), compareAt: nil))
        XCTAssertEqual(
            chosenPrice(rich, quantity: 10, plan: nil),
            ChosenPrice(price: cad("108.0"), compareAt: cad("120.0")),
            "ten or more cost less each, with the full price struck"
        )
        XCTAssertEqual(chosenPrice(rich, quantity: 20, plan: nil), ChosenPrice(price: cad("96.0"), compareAt: cad("120.0")))
        XCTAssertEqual(
            chosenPrice(rich, quantity: 20, plan: monthly),
            ChosenPrice(price: cad("108.0"), compareAt: cad("120.0")),
            "the plan's price, whatever the quantity"
        )
    }

    func testAVariantOnSaleKeepsItsCompareAtPrice() {
        let onSale = basic(compareAt: usd("100.0"))
        XCTAssertEqual(chosenPrice(onSale, quantity: 1, plan: nil), ChosenPrice(price: usd("80.0"), compareAt: usd("100.0")))
        XCTAssertEqual(chosenPrice(basic(), quantity: 3, plan: nil), ChosenPrice(price: usd("80.0"), compareAt: nil))
        XCTAssertEqual(
            chosenPrice(basic(), quantity: 1, plan: plan("p", "Monthly")),
            ChosenPrice(price: usd("80.0"), compareAt: nil),
            "a plan that sends no price costs the variant's"
        )
    }

    // MARK: Unit price

    @MainActor
    func testTheUnitPriceReadsPerItsReferenceAmount() async throws {
        XCTAssertEqual(unitPriceLabel(usd("6.0"), measurement("COUNT", "ITEM", 2.0, "ITEM", 1), locale: us), "$6.00 / item")
        XCTAssertEqual(unitPriceLabel(usd("2.5"), measurement("WEIGHT", "G", 250.0, "G", 100), locale: us), "$2.50 / 100 g")
        XCTAssertEqual(unitPriceLabel(usd("4.0"), measurement("WEIGHT", "G", 500.0, "KG", 1), locale: us), "$4.00 / kg")
        XCTAssertEqual(unitPriceLabel(usd("1.2"), measurement("VOLUME", "FLOZ", 12.0, "FLOZ", 1), locale: us), "$1.20 / fl oz")
        XCTAssertEqual(unitPriceLabel(usd("9.0"), measurement("AREA", "M2", 3.0, "M2", 1), locale: us), "$9.00 / m²")
        let rich = try await richVariant()
        XCTAssertEqual(unitPriceLabel(rich.unitPrice, rich.unitPriceMeasurement), "\(cad("60.0").display()) / item")
    }

    func testNoUnitPriceWithoutAPriceAndAUnit() {
        XCTAssertNil(unitPriceLabel(nil, measurement("COUNT", "ITEM", 2.0, "ITEM", 1)))
        XCTAssertNil(unitPriceLabel(usd("6.0"), nil))
        XCTAssertNil(unitPriceLabel(usd("6.0"), measurement(nil, nil, 0, nil, 0)))
        XCTAssertNil(unitPriceLabel(basic().unitPrice, basic().unitPriceMeasurement))
    }

    // MARK: Quantity rule

    @MainActor
    func testTheRuleSentenceNamesOnlyThePartsThatLimitAnOrder() async throws {
        let rich = try await richVariant()
        XCTAssertEqual(quantityRuleSentence(rich.quantityRule), "Minimum 2 · Maximum 40 · Sold in multiples of 2")
        XCTAssertEqual(quantityRuleSentence(rule(1, 10, 1)), "Maximum 10")
        XCTAssertEqual(quantityRuleSentence(rule(6, nil, 6)), "Minimum 6 · Sold in multiples of 6")
        XCTAssertNil(quantityRuleSentence(rule(1, nil, 1)))
        XCTAssertNil(quantityRuleSentence(rule(0, nil, 0)), "mock.shop's zeros are no rule")
        XCTAssertNil(quantityRuleSentence(nil))
    }

    // MARK: Availability

    @MainActor
    func testTheAvailabilityLineGoesByStock() async throws {
        var rich = try await richVariant()
        XCTAssertEqual(availabilityLine(rich), AvailabilityLine(text: "Only 4 left", tone: .low))
        rich.quantityAvailable = 1
        XCTAssertEqual(availabilityLine(rich), AvailabilityLine(text: "Only 1 left", tone: .low))
        rich.quantityAvailable = 6
        XCTAssertEqual(availabilityLine(rich), AvailabilityLine(text: "In stock", tone: .good))
        XCTAssertEqual(availabilityLine(basic()), AvailabilityLine(text: "In stock", tone: .good), "a token that may not read stock")
        rich.quantityAvailable = 0
        rich.currentlyNotInStock = true
        XCTAssertEqual(availabilityLine(rich), AvailabilityLine(text: "Ships when back in stock", tone: .later))
    }

    func testAVariantThatCantBeBoughtHasNoAvailabilityLine() {
        XCTAssertNil(availabilityLine(nil))
        XCTAssertNil(availabilityLine(basic(available: false)))
        var stale = basic(available: false)
        stale.quantityAvailable = 4
        XCTAssertNil(availabilityLine(stale), "sold out with a stale count")
    }

    // MARK: Sale tag

    func testTheSaleTagIsThePercentOffTheCompareAtPrice() {
        XCTAssertEqual(saleTag(usd("80.0"), usd("100.0")), "Sale −20%")
        XCTAssertEqual(saleTag(usd("20.0"), usd("30.0")), "Sale −33%")
        XCTAssertNil(saleTag(usd("80.0"), nil))
        XCTAssertNil(saleTag(usd("80.0"), usd("80.0")))
        XCTAssertNil(saleTag(usd("80.0"), usd("0.0")), "Shopify's 0.0 is no compare-at")
    }

    // MARK: Selling plans

    @MainActor
    func testAPlanCostsItsFirstPriceAdjustment() async throws {
        let monthly = try monthlyPlan(try await richVariant())
        XCTAssertEqual(planPrice(monthly), cad("108.0"))
        XCTAssertNil(planPrice(plan("p", "Monthly")))
        XCTAssertEqual(planLabel(monthly), "Deliver every month · \(cad("108.0").display())")
        XCTAssertEqual(planLabel(plan("p", "Monthly")), "Monthly")
    }

    @MainActor
    func testThePlanIsTheChosenOneElseOneTimeElseTheFirstWhenAPlanIsRequired() async throws {
        let rich = try await richVariant()
        let monthly = try monthlyPlan(rich)
        XCTAssertNil(chosenPlan(rich, requiresSellingPlan: false, planId: nil), "nothing chosen: a one-time purchase")
        XCTAssertEqual(chosenPlan(rich, requiresSellingPlan: false, planId: monthly.sellingPlan.id), monthly)
        XCTAssertNil(chosenPlan(rich, requiresSellingPlan: false, planId: "gid://shopify/SellingPlan/1"), "a plan this variant doesn't have")
        XCTAssertEqual(chosenPlan(rich, requiresSellingPlan: true, planId: nil), monthly, "sold by plan only")
        XCTAssertNil(chosenPlan(basic(), requiresSellingPlan: true, planId: nil))
        XCTAssertNil(chosenPlan(nil, requiresSellingPlan: true, planId: monthly.sellingPlan.id))
    }

    // MARK: The main button

    func testTheMainButtonSaysWhatATapWouldDo() {
        XCTAssertEqual(addButtonLabel(basic(), .idle), "Add to cart")
        XCTAssertEqual(addButtonLabel(basic(), .adding), "Adding…")
        XCTAssertEqual(addButtonLabel(basic(), .added), "Added")
        XCTAssertEqual(addButtonLabel(basic(available: false), .idle), "Sold out")
        XCTAssertEqual(addButtonLabel(nil, .idle), "Unavailable")
    }
}
