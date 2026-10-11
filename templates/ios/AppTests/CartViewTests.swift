import XCTest
@testable import ArgonStorefront

final class CartViewTests: XCTestCase {
    private func part(_ product: String, _ variant: String, _ quantity: Int) -> CartLineComponent {
        CartLineComponent(id: "c", quantity: quantity, variantId: "v", variantTitle: variant, productHandle: "handle", productTitle: product, image: nil)
    }

    private func usd(_ amount: String) -> Money { Money(amount: amount, currencyCode: "USD") }

    private func number(_ amount: String) -> Decimal { Decimal(string: amount) ?? 0 }

    /// A line of `quantity` at `price` each, `compareAt` each before, with `discounts` (a code and its amount) taken off it.
    private func line(
        _ id: String,
        _ price: String,
        quantity: Int = 1,
        compareAt: String? = nil,
        discounts: [(code: String, amount: String)] = [],
        productId: String? = nil
    ) -> CartLine {
        let subtotal = number(price) * Decimal(quantity)
        let total = discounts.reduce(subtotal) { $0 - number($1.amount) }
        return CartLine(
            id: id,
            quantity: quantity,
            variantId: "v-\(id)",
            variantTitle: "Default Title",
            productHandle: "handle-\(id)",
            productTitle: "Product \(id)",
            image: nil,
            price: usd(price),
            total: usd("\(total)"),
            subtotal: usd("\(subtotal)"),
            unitPrice: usd(price),
            compareAtUnitPrice: compareAt.map { usd($0) },
            productId: productId ?? id,
            discounts: discounts.map { CartDiscount(amount: usd($0.amount), label: $0.code) }
        )
    }

    private func cart(_ lines: CartLine...) -> Cart {
        let total = usd("\(lines.reduce(Decimal(0)) { $0 + number($1.total.amount) })")
        return Cart(id: "c", checkoutUrl: "https://shop.test/checkout", totalQuantity: lines.count, subtotal: total, total: total, lines: lines)
    }

    /// `expected` as an amount: "360.00" is "360.0".
    private func assertAmount(_ actual: Money, _ expected: String, line: UInt = #line) {
        XCTAssertEqual(number(actual.amount), number(expected), "\(actual.amount) \(actual.currencyCode)", line: line)
    }

    func testABundlesPartReadsAsItsProductItsVariantAndHowMany() {
        XCTAssertEqual(componentLabel(part("Men's T-shirt", "Small / Olive", 1)), "Men's T-shirt · Small / Olive × 1")
        XCTAssertEqual(componentLabel(part("Gift card", "Default Title", 2)), "Gift card × 2", "a product without options has no variant worth naming")
        // a part whose product has no title (Android's null) is named by its variant alone
        XCTAssertEqual(componentLabel(part("", "Small", 3)), "Small × 3")
    }

    // MARK: Free shipping

    func testFreeShippingSaysWhatIsLeftAndHowFarTheCartIs() throws {
        let below = try XCTUnwrap(freeShipping(subtotal: usd("120.0"), threshold: 150))
        assertAmount(below.remaining, "30.00")
        XCTAssertEqual(below.remaining.currencyCode, "USD")
        XCTAssertEqual(below.progress, 0.8, accuracy: 1e-6)
        XCTAssertFalse(below.reached)

        let empty = try XCTUnwrap(freeShipping(subtotal: usd("0.0"), threshold: 150))
        assertAmount(empty.remaining, "150.00")
        XCTAssertEqual(empty.progress, 0)

        let cents = try XCTUnwrap(freeShipping(subtotal: usd("149.99"), threshold: 150))
        assertAmount(cents.remaining, "0.01")
        XCTAssertFalse(cents.reached, "a cent short is not there yet")
    }

    func testFreeShippingIsReachedAtTheThresholdAndStaysReachedAboveIt() throws {
        for amount in ["150.0", "150.00", "324.0"] {
            let reached = try XCTUnwrap(freeShipping(subtotal: usd(amount), threshold: 150))
            XCTAssertTrue(reached.reached, amount)
            assertAmount(reached.remaining, "0")
            XCTAssertEqual(reached.progress, 1, amount)
        }
    }

    func testAStoreWithoutAThresholdShowsNoFreeShipping() {
        XCTAssertNil(freeShipping(subtotal: usd("120.0"), threshold: nil))
        XCTAssertNil(freeShipping(subtotal: usd("120.0"), threshold: 0), "zero is no threshold")
        XCTAssertNil(freeShipping(subtotal: usd("120.0"), threshold: -5))
        XCTAssertNil(freeShipping(subtotal: usd("120.0"), threshold: Double.nan))
        XCTAssertNil(freeShipping(subtotal: usd("lots"), threshold: 150), "an amount that can't be read")
    }

    // MARK: Lines

    func testALinesCompareAtIsForAllItsItemsAndOnlyWhenItIsHigher() throws {
        let was = try XCTUnwrap(compareAtTotal(line("a", "120.0", quantity: 3, compareAt: "150.0")))
        assertAmount(was, "450.0")
        XCTAssertEqual(was.currencyCode, "USD")
        XCTAssertNil(compareAtTotal(line("a", "120.0", quantity: 3)))
        XCTAssertNil(compareAtTotal(line("a", "120.0", compareAt: "120.0")), "Shopify may send the price itself, or 0")
        XCTAssertNil(compareAtTotal(line("a", "120.0", compareAt: "0.0")))
    }

    @MainActor
    func testALinesDiscountsAreNamedByTheirCodeElseTheirTitle() async throws {
        // the fixture cart, its line carrying a code's discount, an automatic one and one with neither name
        var cart = try XCTUnwrap(try fixture("Cart")["cart"] as? [String: Any])
        var node = try XCTUnwrap(((cart["lines"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first)
        let money: (String) -> [String: Any] = { ["amount": $0, "currencyCode": "USD"] }
        let allocations: [[String: Any]] = [
            ["discountedAmount": money("10.0"), "code": "WELCOME10"],
            ["discountedAmount": money("5.0"), "title": "Buy 3, save 10%"],
            ["discountedAmount": money("1.0")],
        ]
        node["discountAllocations"] = allocations
        cart["lines"] = ["nodes": [node]]
        let answer = cart
        let found = try await StubServer(reply: { _, _ in try responseBody(["cart": answer]) }).storefront().cart("c")
        XCTAssertEqual(found?.lines.first?.discounts, [
            CartDiscount(amount: usd("10.0"), label: "WELCOME10"),
            CartDiscount(amount: usd("5.0"), label: "Buy 3, save 10%"),
            CartDiscount(amount: usd("1.0"), label: "Discount"),
        ])
    }

    func testADiscountReadsAsItsLabelAndWhatItTakesOff() {
        // the amount as the device's locale writes it ("$12.00" in the US)
        XCTAssertEqual(discountLabel(CartDiscount(amount: usd("12.0"), label: "WELCOME10")), "WELCOME10 −" + usd("12.0").display())
        XCTAssertEqual(discountLabel(CartDiscount(amount: usd("36.0"), label: "Buy 3, save 10%")), "Buy 3, save 10% −" + usd("36.0").display())
    }

    // MARK: Summary

    @MainActor
    func testTheSummaryOfTheFixtureCart() async throws {
        // 3 × 120.00 (150.00 before), with an automatic discount of 36.00
        let found = try await StubServer().storefront().cart("gid://shopify/Cart/c1")
        let summary = cartSummary(try XCTUnwrap(found))
        assertAmount(summary.subtotal, "360.00")
        assertAmount(summary.discounts, "36.00")
        assertAmount(summary.savings, "126.00")
        assertAmount(summary.total, "324.00")
        XCTAssertEqual([summary.subtotal, summary.discounts, summary.savings, summary.total].map { $0.currencyCode }, ["CAD", "CAD", "CAD", "CAD"])
    }

    func testTheSummaryAddsUpEveryLineAndEveryDiscount() {
        let summary = cartSummary(cart(
            line("a", "50.0", quantity: 2, compareAt: "80.0", discounts: [("WELCOME10", "10.0"), ("VIP", "5.0")]),
            line("b", "20.0", discounts: [("WELCOME10", "2.0")]),
            line("c", "9.5")
        ))
        assertAmount(summary.subtotal, "129.50")
        assertAmount(summary.discounts, "17.00")
        assertAmount(summary.savings, "77.00") // 2 × 30 off the compare-at price, and the discounts
        assertAmount(summary.total, "112.50")
    }

    func testACartWithoutDiscountsOrCompareAtPricesSavesNothing() {
        let summary = cartSummary(cart(line("a", "50.0", quantity: 2), line("b", "20.0")))
        assertAmount(summary.subtotal, "120.00")
        assertAmount(summary.discounts, "0")
        assertAmount(summary.savings, "0")
        assertAmount(cartSummary(cart()).subtotal, "0")
    }

    // MARK: You may also like

    @MainActor
    func testSuggestionsLeaveOutWhatIsInTheCart() async throws {
        let recommended = try await StubServer().storefront().recommendations(productId: "gid://shopify/Product/1")
        XCTAssertGreaterThan(recommended.count, 1)
        let inCart = cart(line("a", "50.0", productId: recommended[0].id))
        XCTAssertEqual(suggestions(recommended: recommended, cart: inCart), Array(recommended.dropFirst()))
        XCTAssertEqual(suggestions(recommended: recommended, cart: nil), recommended, "no cart: all of them")
    }
}
