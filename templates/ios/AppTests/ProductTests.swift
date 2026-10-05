import XCTest
@testable import ArgonStorefront

final class ProductTests: XCTestCase {
    func testMetafieldIdentifiersSplitOnTheFirstDot() {
        XCTAssertEqual(
            metafieldIdentifiers("custom.material, custom.care"),
            [["namespace": "custom", "key": "material"], ["namespace": "custom", "key": "care"]]
        )
        XCTAssertEqual(metafieldIdentifiers("a.b.c"), [["namespace": "a", "key": "b.c"]])
    }

    func testBlankAndMalformedEntriesAreSkipped() {
        XCTAssertEqual(metafieldIdentifiers(""), [])
        XCTAssertEqual(metafieldIdentifiers("bad, ,.x,y.,a.b,"), [["namespace": "a", "key": "b"]])
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

    private func product(_ variants: Variant...) -> Product {
        Product(
            id: "p",
            handle: "h",
            title: "T",
            vendor: "V",
            descriptionHtml: "",
            images: [],
            options: [(name: "Size", values: variants.map { $0.title })],
            variants: variants,
            metafields: []
        )
    }

    func testSelectionStartsAtTheFirstAvailableVariant() {
        XCTAssertEqual(initialSelection(product(variant("1", false, "S"), variant("2", true, "M"), variant("3", true, "L"))), ["Size": "M"])
    }

    func testSelectionFallsBackToTheFirstVariantWhenNoneIsAvailable() {
        XCTAssertEqual(initialSelection(product(variant("1", false, "S"), variant("2", false, "M"))), ["Size": "S"])
        XCTAssertEqual(initialSelection(product()), [:])
    }
}
