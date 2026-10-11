import XCTest
@testable import ArgonStorefront

/// What the catalogue models work out from what they decode: ratings, quantity rules, and a card's shortcuts.
final class CatalogModelTests: XCTestCase {
    // MARK: Ratings

    func testARatingMetafieldIsJsonOnItsOwnScale() throws {
        let standard = try XCTUnwrap(Ratings.parse(#"{"value":"4.6","scale_min":"1.0","scale_max":"5.0"}"#))
        XCTAssertEqual(standard, 4.6, accuracy: 0.0001)
        let outOfTen = try XCTUnwrap(Ratings.parse(#"{"value":"8","scale_min":"1","scale_max":"10"}"#))
        XCTAssertEqual(outOfTen, 4, accuracy: 0.0001, "brought to a scale of 5")
        let numbers = try XCTUnwrap(Ratings.parse(#"{"value":4.5,"scale_max":5}"#))
        XCTAssertEqual(numbers, 4.5, accuracy: 0.0001, "numbers as well as strings")
        let noScale = try XCTUnwrap(Ratings.parse(#"{"value":"3.2"}"#))
        XCTAssertEqual(noScale, 3.2, accuracy: 0.0001, "no scale is a scale of 5")
    }

    func testAPlainNumberIsARatingOutOfFive() {
        XCTAssertEqual(Ratings.parse("4.25"), 4.25)
        XCTAssertEqual(Ratings.parse(" 3 "), 3)
        XCTAssertEqual(Ratings.parse("7"), 5, "never past five stars")
        XCTAssertEqual(Ratings.parse("-1"), 0)
        XCTAssertEqual(Ratings.parse(#"{"value":"9","scale_max":"5"}"#), 5)
    }

    func testAnUnreadableRatingIsNone() {
        for value in [nil, "", "  ", "great", "{}", #"{"value":"good"}"#, #"{"value":"4","scale_max":"0"}"#, "NaN", "[4.5]"] {
            XCTAssertNil(Ratings.parse(value), value ?? "nil")
        }
    }

    func testTheRatingCountIsAWholeNumber() {
        XCTAssertEqual(Ratings.count("128"), 128)
        XCTAssertEqual(Ratings.count(" 12 "), 12)
        XCTAssertNil(Ratings.count("many"))
        XCTAssertNil(Ratings.count("12.5"))
        XCTAssertNil(Ratings.count(nil))
    }

    // MARK: Quantity rule

    func testAQuantityRuleNeverGoesUnderOne() throws {
        // mock.shop sends 0 where a store sends 1
        let none = try JSONDecoder().decode(QuantityRule.self, from: Data(#"{"minimum":0,"maximum":null,"increment":0}"#.utf8))
        XCTAssertEqual(none, QuantityRule(minimum: 0, maximum: nil, increment: 0))
        XCTAssertEqual(none.min, 1)
        XCTAssertEqual(none.step, 1)
        XCTAssertNil(none.maximum)

        let cases = try JSONDecoder().decode(QuantityRule.self, from: Data(#"{"minimum":6,"maximum":48,"increment":6}"#.utf8))
        XCTAssertEqual(cases.min, 6)
        XCTAssertEqual(cases.step, 6)
        XCTAssertEqual(cases.maximum, 48)
        XCTAssertEqual(QuantityRule(minimum: 1, increment: 1).min, 1)
    }

    // MARK: Product card

    private func option(_ name: String, _ values: [String]) -> ProductOption {
        ProductOption(name: name, optionValues: values.map { ProductOptionValue(name: $0) })
    }

    private func card(options: [ProductOption] = [], firstVariant: CardVariant? = nil, price: String = "10.0", maxPrice: String? = nil) -> ProductCard {
        ProductCard(
            id: "p", handle: "h", title: "T", available: true, image: nil,
            price: Money(amount: price, currencyCode: "USD"), compareAt: nil,
            maxPrice: maxPrice.map { Money(amount: $0, currencyCode: "USD") },
            options: options,
            firstVariant: firstVariant
        )
    }

    func testQuickAddNeedsAnAvailableVariantAndNothingToChoose() {
        let variant = CardVariant(id: "v1", available: true)
        XCTAssertEqual(card(options: [option("Title", ["Default Title"])], firstVariant: variant).quickAddVariantId, "v1")
        XCTAssertEqual(card(firstVariant: variant).quickAddVariantId, "v1", "no options at all")
        XCTAssertEqual(card(options: [option("Size", ["One size"]), option("Color", ["Red"])], firstVariant: variant).quickAddVariantId, "v1")
        XCTAssertNil(card(options: [option("Size", ["S", "M"])], firstVariant: variant).quickAddVariantId, "a size to choose: the card opens the product")
        XCTAssertNil(card(options: [option("Size", ["One size"]), option("Color", ["Red", "Blue"])], firstVariant: variant).quickAddVariantId)
        XCTAssertNil(card(firstVariant: CardVariant(id: "v1", available: false)).quickAddVariantId, "sold out")
        XCTAssertNil(card().quickAddVariantId, "no variant known")
    }

    func testColorsAreTheFirstColourOptionsValues() {
        XCTAssertEqual(card(options: [option("Size", ["S", "M"]), option("Colour", ["Red", "Blue"])]).colors.map { $0.name }, ["Red", "Blue"])
        XCTAssertEqual(card(options: [option("color", ["Red"]), option("Shade", ["Dark"])]).colors.map { $0.name }, ["Red"], "the first one")
        XCTAssertEqual(card(options: [option("SHADE", ["Dark", "Light"])]).colors.map { $0.name }, ["Dark", "Light"])
        XCTAssertEqual(card(options: [option("Size", ["S"]), option("Colourway", ["Red"])]).colors, [], "the whole name, not a part of it")
        XCTAssertEqual(card().colors, [])
    }

    func testAPriceRangeIsAMaximumAboveThePrice() {
        XCTAssertTrue(card(price: "35.0", maxPrice: "42.0").hasPriceRange)
        XCTAssertFalse(card(price: "35.0", maxPrice: "35.00").hasPriceRange, "the same amount, written differently")
        XCTAssertFalse(card(price: "35.0", maxPrice: "0.0").hasPriceRange)
        XCTAssertFalse(card(price: "35.0").hasPriceRange, "no maximum known")
    }

    // MARK: Templates

    func testATemplateNameThatIsUnknownIsTheDefault() {
        XCTAssertEqual(HomeTemplate(config: "beauty"), .beauty)
        XCTAssertEqual(HomeTemplate(config: " B2B "), .b2b)
        XCTAssertEqual(HomeTemplate(config: "grocery"), .grocery)
        XCTAssertEqual(HomeTemplate(config: ""), .fashion)
        XCTAssertEqual(HomeTemplate(config: "luxury"), .fashion)
        XCTAssertEqual(CollectionTemplate(config: "bottom"), .bottom)
        XCTAssertEqual(CollectionTemplate(config: ""), .top)
        XCTAssertEqual(CollectionTemplate(config: "sideways"), .top)
    }
}
