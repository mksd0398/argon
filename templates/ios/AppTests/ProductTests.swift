import XCTest
@testable import ArgonStorefront

final class ProductTests: XCTestCase {
    func testMetafieldIdentifiersSplitOnTheFirstDot() {
        XCTAssertEqual(
            metafieldIdentifiers("custom.material, custom.care"),
            [MetafieldIdentifier(namespace: "custom", key: "material"), MetafieldIdentifier(namespace: "custom", key: "care")]
        )
        XCTAssertEqual(metafieldIdentifiers("a.b.c"), [MetafieldIdentifier(namespace: "a", key: "b.c")])
    }

    func testBlankAndMalformedEntriesAreSkipped() {
        XCTAssertEqual(metafieldIdentifiers(""), [])
        XCTAssertEqual(metafieldIdentifiers("bad, ,.x,y.,a.b,"), [MetafieldIdentifier(namespace: "a", key: "b")])
    }

    private func variant(_ id: String, _ available: Bool, _ size: String) -> Variant {
        Variant(
            id: id,
            title: size,
            available: available,
            options: ["Size": size],
            price: Money(amount: "10.00", currencyCode: "USD"),
            compareAt: nil,
            image: nil
        )
    }

    func testSelectionStartsAtTheFirstAvailableVariant() {
        XCTAssertEqual(initialSelection([variant("1", false, "S"), variant("2", true, "M"), variant("3", true, "L")]), ["Size": "M"])
    }

    func testSelectionFallsBackToTheFirstVariantWhenNoneIsAvailable() {
        XCTAssertEqual(initialSelection([variant("1", false, "S"), variant("2", false, "M")]), ["Size": "S"])
        XCTAssertEqual(initialSelection([]), [:])
    }
}
