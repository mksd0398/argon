import XCTest
@testable import ArgonStorefront

/// The returns flow's rules (Android's ReturnLogicTest, case for case).
final class ReturnLogicTests: XCTestCase {
    private let tooSmall = "gid://shopify/ReturnReasonDefinition/1"

    /// The contract fixture: what the sample order can send back (a crewneck and a T-shirt, one of each).
    private struct Sample {
        let options: OrderReturnOptions
        let crewneck: ReturnableItem
        let tshirt: ReturnableItem
    }

    @MainActor
    private func sample() async throws -> Sample {
        let found = try await StubServer().customerAccount().returnOptions("gid://shopify/Order/6001004")
        let options = try XCTUnwrap(found)
        XCTAssertEqual(options.returnableItems.count, 2)
        return Sample(options: options, crewneck: options.returnableItems[0], tshirt: options.returnableItems[1])
    }

    // MARK: The exchange note

    func testAnExchangeNoteNamesTheProductTheVariantAndTheSku() {
        XCTAssertEqual(
            exchangeNote(productTitle: "Men's Crewneck", variantTitle: "Large / Olive", sku: "MC-LO", note: ""),
            "Exchange for: Men's Crewneck - Large / Olive (SKU MC-LO)"
        )
    }

    func testTheSkuPartIsLeftOutWhenThereIsNone() {
        XCTAssertEqual(
            exchangeNote(productTitle: "Men's Crewneck", variantTitle: "Large / Olive", sku: nil, note: ""),
            "Exchange for: Men's Crewneck - Large / Olive"
        )
        XCTAssertEqual(
            exchangeNote(productTitle: "Men's Crewneck", variantTitle: "Large / Olive", sku: "  ", note: ""),
            "Exchange for: Men's Crewneck - Large / Olive"
        )
    }

    func testTheShoppersNoteFollowsOnANewLine() {
        XCTAssertEqual(
            exchangeNote(
                productTitle: "Men's Crewneck", variantTitle: "Large / Olive", sku: "MC-LO",
                note: "  The medium was tight at the shoulders.\n"
            ),
            "Exchange for: Men's Crewneck - Large / Olive (SKU MC-LO)\nThe medium was tight at the shoulders."
        )
        XCTAssertEqual(
            exchangeNote(productTitle: "Gift box", variantTitle: nil, sku: "GB-1", note: "   "),
            "Exchange for: Gift box (SKU GB-1)",
            "a blank note adds no line"
        )
    }

    func testAProductWithoutOptionsHasNoVariantPart() {
        XCTAssertEqual(exchangeItem(productTitle: "Gift box", variantTitle: "Default Title", sku: "GB-1"), "Gift box (SKU GB-1)")
        XCTAssertEqual(exchangeItem(productTitle: " Gift box ", variantTitle: nil, sku: nil), "Gift box")
    }

    func testWhatWasTypedInsteadOfPickedIsSentAsItIs() {
        XCTAssertEqual(exchangeNote(wanted: " the same in blue, size L ", note: "Thanks"), "Exchange for: the same in blue, size L\nThanks")
    }

    // MARK: The request's lines

    @MainActor
    func testTheRequestHasOneLinePerChosenItem() async throws {
        let order = try await sample()
        let choices = [
            order.crewneck.lineItemId: ReturnChoice(
                quantity: 1, exchange: true, reasonId: tooSmall, note: "Tight at the shoulders", wanted: "Men's Crewneck - Large / Olive"
            ),
            order.tshirt.lineItemId: ReturnChoice(quantity: 1, reasonId: "gid://shopify/ReturnReasonDefinition/4", note: "  "),
        ]
        XCTAssertEqual(returnLines(order.options.returnableItems, choices), [
            ReturnLineInput(
                lineItemId: "gid://shopify/LineItem/5000001", quantity: 1, returnReasonDefinitionId: tooSmall,
                customerNote: "Exchange for: Men's Crewneck - Large / Olive\nTight at the shoulders"
            ),
            ReturnLineInput(
                lineItemId: "gid://shopify/LineItem/5000003", quantity: 1,
                returnReasonDefinitionId: "gid://shopify/ReturnReasonDefinition/4", customerNote: nil
            ),
        ])
    }

    @MainActor
    func testItemsThatWereNotChosenAreLeftOut() async throws {
        let order = try await sample()
        let choices = [
            order.crewneck.lineItemId: ReturnChoice(quantity: 0, reasonId: tooSmall, note: "changed my mind about returning it"),
            order.tshirt.lineItemId: ReturnChoice(quantity: 1, note: "Faded after one wash"),
            "gid://shopify/LineItem/unknown": ReturnChoice(quantity: 1),
        ]
        XCTAssertEqual(returnLines(order.options.returnableItems, choices), [
            ReturnLineInput(lineItemId: "gid://shopify/LineItem/5000003", quantity: 1, returnReasonDefinitionId: nil, customerNote: "Faded after one wash"),
        ])
        XCTAssertEqual(returnLines(order.options.returnableItems, [:]), [])
    }

    @MainActor
    func testALineNeverAsksForMoreThanCanGoBackOrSaysMoreThanShopifyTakes() async throws {
        let tshirt = try await sample().tshirt
        let three = tshirt.with(quantity: 3)
        let wordy = ReturnChoice(quantity: 5, exchange: true, note: String(repeating: "x", count: 400), wanted: "Large")
        let lines = returnLines([three], [three.lineItemId: wordy])
        XCTAssertEqual(lines.count, 1)
        let line = try XCTUnwrap(lines.first)
        let note = try XCTUnwrap(line.customerNote)
        let limit: Int = noteLimit
        XCTAssertEqual(line.quantity, 3)
        XCTAssertEqual(note.count, limit)
        XCTAssertTrue(note.hasPrefix("Exchange for: Large\nxxx"), "the wanted item is what survives the cut")
        XCTAssertEqual(
            returnLines([tshirt.with(quantity: 0)], [tshirt.lineItemId: ReturnChoice(quantity: 1)]), [],
            "nothing can go back: no line"
        )
    }

    func testTheNoteFieldLeavesRoomForTheWantedItem() {
        let limit: Int = noteLimit
        XCTAssertEqual(noteLimit(ReturnChoice(quantity: 1, wanted: "ignored for a refund")), limit)
        // "Exchange for: Large" is 19 characters, and the new line one more
        XCTAssertEqual(noteLimit(ReturnChoice(quantity: 1, exchange: true, wanted: "Large")), limit - 20)
        XCTAssertEqual(noteLimit(ReturnChoice(quantity: 1, exchange: true, wanted: String(repeating: "y", count: 400))), 0)
    }

    // MARK: Step 2

    @MainActor
    func testAChosenItemNeedsAReasonAndAnExchangeNeedsWhatIsWanted() async throws {
        let crewneck = try await sample().crewneck
        XCTAssertEqual(choiceProblem(crewneck, ReturnChoice(quantity: 1)), "Choose a reason")
        XCTAssertNil(choiceProblem(crewneck, ReturnChoice(quantity: 1, reasonId: tooSmall)))
        XCTAssertEqual(
            choiceProblem(crewneck, ReturnChoice(quantity: 1, exchange: true, reasonId: tooSmall, wanted: " ")),
            "Choose what you'd like instead"
        )
        XCTAssertNil(choiceProblem(crewneck, ReturnChoice(quantity: 1, exchange: true, reasonId: tooSmall, wanted: "Large / Olive")))
        let noReasons = ReturnableItem(
            lineItemId: crewneck.lineItemId, title: crewneck.title, image: crewneck.image, quantity: crewneck.quantity, reasons: []
        )
        XCTAssertNil(choiceProblem(noReasons, ReturnChoice(quantity: 1)), "a store that offers no reasons can't be given one")
    }

    @MainActor
    func testAStepIsLeftOnlyWhenItIsComplete() async throws {
        let order = try await sample()
        let done = (order.crewneck, ReturnChoice(quantity: 1, reasonId: tooSmall))
        let noReason = (order.tshirt, ReturnChoice(quantity: 1))
        XCTAssertEqual(stepProblem(0, []), "Choose at least one item")
        XCTAssertNil(stepProblem(0, [noReason]))
        XCTAssertEqual(stepProblem(1, [done, noReason]), "Choose a reason", "the first incomplete item's")
        XCTAssertNil(stepProblem(1, [done]))
        XCTAssertNil(stepProblem(2, [noReason]), "the review has nothing left to ask")
    }

    @MainActor
    func testAnOrderLineIsOfferedOnceWithAllThatCanGoBack() async throws {
        let order = try await sample()
        XCTAssertEqual(returnableItems(order.options), order.options.returnableItems)
        // the crewneck listed twice (2 and 1 of it), and the T-shirt with nothing left to return
        let listed = [order.crewneck.with(quantity: 2), order.tshirt.with(quantity: 0), order.crewneck.with(quantity: 1)]
        let split = OrderReturnOptions(orderId: "o", returnableItems: listed, returns: [])
        XCTAssertEqual(returnableItems(split), [order.crewneck.with(quantity: 3)])
        XCTAssertEqual(returnableItems(OrderReturnOptions(orderId: "o", returnableItems: [], returns: [])), [])
    }

    // MARK: Step 3

    @MainActor
    func testTheReviewSaysWhatWasAskedForEachItem() async throws {
        let order = try await sample()
        let exchange = ReturnChoice(quantity: 1, exchange: true, reasonId: tooSmall, note: " Tight ", wanted: "Men's Crewneck - Large / Olive")
        XCTAssertEqual(
            reviewDetails(order.crewneck, exchange),
            ["Medium / Olive", "Qty 1", "Exchange for: Men's Crewneck - Large / Olive", "Size was too small", "Tight"]
        )
        XCTAssertEqual(reviewDetails(order.tshirt, ReturnChoice(quantity: 4)), ["Large / Ocean", "Qty 1", "Refund"])
    }

    @MainActor
    func testFeesShowWithTheirAmounts() async throws {
        let options = try await sample().options
        let rows = feeRows(options, money: { "\($0.amount) \($0.currencyCode)" })
        XCTAssertEqual(rows.map { [$0.label, $0.amount] }, [["Return shipping", "8.0 CAD"]])
        XCTAssertEqual(feeLabel(ReturnFee(kind: "RestockingFee", title: nil, amount: nil)), "Restocking fee")
        XCTAssertEqual(feeLabel(ReturnFee(kind: "ReturnShippingFee", title: " ", amount: nil)), "Return shipping")
        XCTAssertEqual(feeLabel(ReturnFee(kind: "RestockingFee", title: "Handling", amount: nil)), "Handling")
        XCTAssertEqual(feeLabel(ReturnFee(kind: "", title: nil, amount: nil)), "Fee")
    }

    // MARK: The replacement picker

    private func variant(_ id: String, _ size: String, _ color: String, available: Bool = true, sku: String? = nil) -> Variant {
        Variant(
            id: id, title: "\(size) / \(color)", available: available, options: ["Size": size, "Color": color],
            price: Money(amount: "120.0", currencyCode: "CAD"), compareAt: nil, image: nil, sku: sku
        )
    }

    private func option(_ name: String, _ values: String...) -> ProductOption {
        ProductOption(name: name, optionValues: values.map { ProductOptionValue(name: $0) })
    }

    private func product(_ handle: String, _ title: String, options: [ProductOption] = [], variants: [Variant] = []) -> Product {
        let price = Money(amount: "120.0", currencyCode: "CAD")
        return Product(
            id: "p", handle: handle, title: title, vendor: "", productType: "", descriptionHtml: "", available: true,
            isGiftCard: false, requiresSellingPlan: false, encodedVariantExistence: nil, encodedVariantAvailability: nil, seo: nil,
            priceRange: PriceRange(minVariantPrice: price, maxVariantPrice: price), media: [], options: options,
            selectedOrFirstAvailableVariant: nil, adjacentVariants: [], variants: variants
        )
    }

    private var crewneckProduct: Product {
        product(
            "men-crewneck", "Men's Crewneck",
            options: [option("Size", "Medium", "Large"), option("Color", "Olive", "Ocean")],
            variants: [
                variant("m-olive", "Medium", "Olive", sku: "MC-MO"),
                variant("l-olive", "Large", "Olive", sku: "MC-LO"),
                variant("m-ocean", "Medium", "Ocean", available: false),
            ]
        )
    }

    func testThePickerStartsAtTheVariantBeingReturned() {
        XCTAssertEqual(startSelection(crewneckProduct, "l-olive"), ["Size": "Large", "Color": "Olive"])
        XCTAssertEqual(
            startSelection(crewneckProduct, "gone"), ["Size": "Medium", "Color": "Olive"],
            "a variant that is gone: the first available one"
        )
        XCTAssertEqual(startSelection(product("h", "T"), nil), [:])
    }

    func testASelectionIsWantedOnlyWhenItsVariantCanBeHad() {
        XCTAssertEqual(wantedVariant(crewneckProduct, ["Size": "Large", "Color": "Olive"]), "Men's Crewneck - Large / Olive (SKU MC-LO)")
        XCTAssertEqual(wantedVariant(crewneckProduct, ["Size": "Medium", "Color": "Ocean"]), "", "sold out")
        XCTAssertEqual(wantedVariant(crewneckProduct, ["Size": "Large", "Color": "Ocean"]), "", "no such variant")
    }

    func testAProductWithoutOptionsHasNothingToChoose() {
        XCTAssertEqual(choosableOptions(crewneckProduct).map { $0.name }, ["Size", "Color"])
        let only = Variant(
            id: "v", title: "Default Title", available: true, options: [:], price: Money(amount: "9.0", currencyCode: "CAD"),
            compareAt: nil, image: nil, sku: "GB-1"
        )
        let plain = product("gift-box", "Gift box", options: [option("Title", "Default Title")], variants: [only])
        XCTAssertEqual(choosableOptions(plain), [])
        XCTAssertEqual(wantedVariant(plain, startSelection(plain, nil)), "Gift box (SKU GB-1)", "its one variant is the replacement")
    }
}
