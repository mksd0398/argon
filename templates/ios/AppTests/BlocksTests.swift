import XCTest
@testable import ArgonStorefront

/// The rules behind the shared blocks: what a discount is, and which colour a swatch takes.
final class BlocksTests: XCTestCase {
    private func usd(_ amount: String) -> Money { Money(amount: amount, currencyCode: "USD") }

    // MARK: Discount

    func testTheDiscountIsAWholePercentOffTheCompareAtPrice() {
        XCTAssertEqual(discountPercent(usd("80.0"), usd("100.0")), 20)
        XCTAssertEqual(discountPercent(usd("66.67"), usd("100.00")), 33)
        XCTAssertEqual(discountPercent(usd("12.50"), usd("25")), 50)
        XCTAssertEqual(discountPercent(usd("0.0"), usd("10.0")), 100, "free")
        XCTAssertEqual(discountPercent(usd("98.4"), usd("100.0")), 2, "1.6% rounds up")
        XCTAssertEqual(discountPercent(usd("98.7"), usd("100.0")), 1, "1.3% rounds down")
    }

    func testNoDiscountWithoutAHigherCompareAtPrice() {
        XCTAssertNil(discountPercent(usd("80.0"), nil))
        XCTAssertNil(discountPercent(usd("80.0"), usd("80.0")))
        XCTAssertNil(discountPercent(usd("80.0"), usd("60.0")), "a compare-at price under the price is no discount")
        XCTAssertNil(discountPercent(usd("80.0"), usd("0.0")), "Shopify's \"none\"")
        XCTAssertNil(discountPercent(usd("99.99"), usd("100.0")), "under 1%")
        XCTAssertNil(discountPercent(usd("abc"), usd("100.0")))
    }

    // MARK: Quantity rule

    func testTheQuantityRuleLabelSaysOnlyWhatRestricts() {
        XCTAssertEqual(quantityRuleLabel(QuantityRule(minimum: 2, maximum: 40, increment: 2)), "Min. 2 · Multiples of 2")
        XCTAssertEqual(quantityRuleLabel(QuantityRule(minimum: 6, increment: 1)), "Min. 6")
        XCTAssertEqual(quantityRuleLabel(QuantityRule(minimum: 1, increment: 5)), "Multiples of 5")
        XCTAssertNil(quantityRuleLabel(QuantityRule(minimum: 0, increment: 0)), "mock.shop's \"no rule\"")
        XCTAssertNil(quantityRuleLabel(nil))
    }

    // MARK: Swatch colours

    func testAColourNameIsItsColour() throws {
        let blue = try XCTUnwrap(SwatchColors.hex("blue"))
        XCTAssertEqual(SwatchColors.hex("Blue"), blue)
        XCTAssertEqual(SwatchColors.hex("  RED "), SwatchColors.hex("red"))
        XCTAssertEqual(SwatchColors.hex("Grey"), SwatchColors.hex("gray"), "both spellings")
        XCTAssertNotEqual(SwatchColors.hex("navy"), blue)
    }

    func testOtherwiseItsLastWordElseAnyWord() throws {
        let blue = try XCTUnwrap(SwatchColors.hex("blue"))
        let white = try XCTUnwrap(SwatchColors.hex("white"))
        XCTAssertEqual(SwatchColors.hex("Peacock Blue"), blue)
        XCTAssertEqual(SwatchColors.hex("Off White"), white)
        XCTAssertEqual(SwatchColors.hex("Navy Blue"), blue, "the last word before any other")
        XCTAssertEqual(SwatchColors.hex("Olive-Green"), SwatchColors.hex("green"), "words end at anything that isn't a letter")
        XCTAssertEqual(SwatchColors.hex("Grey Melange"), SwatchColors.hex("grey"), "the last word names no colour: another one does")
        XCTAssertEqual(SwatchColors.hex("Blue Stripe 2"), blue)
    }

    func testNamesWithoutAColourHaveNone() {
        XCTAssertNil(SwatchColors.hex("Ocean"))
        XCTAssertNil(SwatchColors.hex(""))
        XCTAssertNil(SwatchColors.hex("Multi"), "several colours have no one swatch")
        XCTAssertNil(SwatchColors.hex("Multi Colour"))
        XCTAssertNil(SwatchColors.hex("Bluebell"), "a whole word, not a part of one")
    }

    func testEveryKnownColourIsAReadableHex() throws {
        let names = [
            "black", "white", "grey", "gray", "silver", "red", "maroon", "pink", "rose", "orange", "peach", "yellow", "gold",
            "mustard", "green", "olive", "teal", "turquoise", "blue", "navy", "sky", "purple", "violet", "lavender", "magenta",
            "brown", "tan", "beige", "cream", "ivory", "khaki", "coral", "mint", "lime", "burgundy", "wine", "charcoal", "copper",
            "bronze",
        ]
        for name in names {
            let hex = try XCTUnwrap(SwatchColors.hex(name), name)
            XCTAssertNotNil(hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression), "\(name): \(hex)")
        }
    }

    func testAValuesSwatchIsTheStoresOwnElseItsNamesColour() {
        let image = Img(url: "https://cdn.test/floral.jpg", alt: nil, width: 10, height: 10)
        let own = ProductOptionValue(name: "Blue", swatch: Swatch(color: "#123456", image: nil))
        XCTAssertEqual(swatch(for: own), SwatchFill(colorHex: "#123456"), "the store's colour, whatever the name says")
        let pattern = ProductOptionValue(name: "Floral", swatch: Swatch(color: nil, image: image))
        XCTAssertEqual(swatch(for: pattern), SwatchFill(imageUrl: URL(string: "https://cdn.test/floral.jpg")))
        XCTAssertEqual(swatch(for: ProductOptionValue(name: "Sky Blue")), SwatchFill(colorHex: SwatchColors.hex("blue")))
        XCTAssertEqual(swatch(for: ProductOptionValue(name: "Blue", swatch: Swatch(color: nil, image: nil))), SwatchFill(colorHex: SwatchColors.hex("blue")), "an empty swatch is none")
        XCTAssertEqual(swatch(for: ProductOptionValue(name: "Ocean")), SwatchFill())

        let filter = FilterValue(id: "v", label: "Olive", count: 2, input: "{}", swatch: Swatch(color: "#6B6B3A", image: nil))
        XCTAssertEqual(swatch(for: filter), SwatchFill(colorHex: "#6B6B3A"))
        XCTAssertEqual(swatch(for: FilterValue(id: "v", label: "Olive", count: 2, input: "{}")), SwatchFill(colorHex: SwatchColors.hex("olive")))
    }
}
