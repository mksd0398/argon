import XCTest
@testable import ArgonStorefront

final class VariantsTests: XCTestCase {
    private func variant(_ id: String, _ size: String, _ color: String) -> Variant {
        Variant(
            id: id,
            title: "\(size) / \(color)",
            available: true,
            options: ["Size": size, "Color": color],
            price: Money(amount: "10.0", currencyCode: "USD"),
            compareAt: nil,
            image: nil
        )
    }

    private var variants: [Variant] { [variant("1", "S", "Red"), variant("2", "S", "Blue"), variant("3", "M", "Red")] }

    func testExactSelectionMatches() {
        XCTAssertEqual(Variants.match(variants, selection: ["Size": "S", "Color": "Blue"])?.id, "2")
    }

    func testCombinationWithoutVariantIsNull() {
        XCTAssertNil(Variants.match(variants, selection: ["Size": "M", "Color": "Blue"]))
    }

    func testNoVariantsIsNull() {
        XCTAssertNil(Variants.match([], selection: ["Size": "S"]))
    }
}
