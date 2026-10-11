import XCTest
@testable import ArgonStorefront

final class CartViewTests: XCTestCase {
    private func part(_ product: String, _ variant: String, _ quantity: Int) -> CartLineComponent {
        CartLineComponent(id: "c", quantity: quantity, variantId: "v", variantTitle: variant, productHandle: "handle", productTitle: product, image: nil)
    }

    func testABundlesPartReadsAsItsProductItsVariantAndHowMany() {
        XCTAssertEqual(componentLabel(part("Men's T-shirt", "Small / Olive", 1)), "Men's T-shirt · Small / Olive × 1")
        XCTAssertEqual(componentLabel(part("Gift card", "Default Title", 2)), "Gift card × 2", "a product without options has no variant worth naming")
        // a part whose product has no title (Android's null) is named by its variant alone
        XCTAssertEqual(componentLabel(part("", "Small", 3)), "Small × 3")
    }
}
