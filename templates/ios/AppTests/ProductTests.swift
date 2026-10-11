import XCTest
@testable import ArgonStorefront

/// A product with only what a test gives it.
func sampleProduct(handle: String = "h", options: [ProductOption] = [], variants: [Variant] = [], onlineStoreUrl: String? = nil) -> Product {
    let free = Money(amount: "0.0", currencyCode: "USD")
    return Product(
        id: "p",
        handle: handle,
        title: "T",
        vendor: "",
        productType: "",
        descriptionHtml: "",
        available: true,
        isGiftCard: false,
        requiresSellingPlan: false,
        encodedVariantExistence: nil,
        encodedVariantAvailability: nil,
        seo: nil,
        priceRange: PriceRange(minVariantPrice: free, maxVariantPrice: free),
        media: [],
        options: options,
        selectedOrFirstAvailableVariant: nil,
        adjacentVariants: [],
        variants: variants,
        onlineStoreUrl: onlineStoreUrl
    )
}

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

    private func variant(_ id: String, _ available: Bool, _ size: String, barcode: String? = nil) -> Variant {
        Variant(
            id: id,
            title: size,
            available: available,
            options: ["Size": size],
            price: Money(amount: "10.00", currencyCode: "USD"),
            compareAt: nil,
            image: nil,
            barcode: barcode
        )
    }

    func testSelectionStartsAtTheFirstAvailableVariant() {
        XCTAssertEqual(initialSelection([variant("1", false, "S"), variant("2", true, "M"), variant("3", true, "L")]), ["Size": "M"])
    }

    func testSelectionFallsBackToTheFirstVariantWhenNoneIsAvailable() {
        XCTAssertEqual(initialSelection([variant("1", false, "S"), variant("2", false, "M")]), ["Size": "S"])
        XCTAssertEqual(initialSelection([]), [:])
    }

    // MARK: Share

    func testShareSendsTheWebStorePageElseTheProductsAddressOnTheShopsDomain() {
        var published = sampleProduct(handle: "men-crewneck", onlineStoreUrl: "https://shop.example/en/products/men-crewneck")
        XCTAssertEqual(shareUrl(published, domain: "mock.shop"), "https://shop.example/en/products/men-crewneck")
        published.onlineStoreUrl = nil
        XCTAssertEqual(shareUrl(published, domain: "mock.shop"), "https://mock.shop/products/men-crewneck")
        published.onlineStoreUrl = " "
        XCTAssertEqual(shareUrl(published, domain: "mock.shop"), "https://mock.shop/products/men-crewneck")
    }

    // MARK: The selected variant in full: latest selection wins

    private let small = ["Size": "S"]
    private let medium = ["Size": "M"]

    func testAnAnswerForTheSelectionOnScreenIsKept() {
        let answer = RichVariant(selection: medium, variant: variant("2", true, "M", barcode: "0002"))
        XCTAssertEqual(latestAnswer(nil, answer, selection: medium), answer)
        XCTAssertEqual(
            latestAnswer(RichVariant(selection: small, variant: nil), answer, selection: medium),
            answer,
            "it replaces the answer of an earlier selection"
        )
    }

    func testAStaleAnswerNeverOverwritesANewerOne() {
        // the shopper went from S to M; M has answered, and now S's answer comes in late
        let current = RichVariant(selection: medium, variant: variant("2", true, "M", barcode: "0002"))
        let late = RichVariant(selection: small, variant: variant("1", true, "S", barcode: "0001"))
        XCTAssertEqual(latestAnswer(current, late, selection: medium), current)
        XCTAssertNil(latestAnswer(nil, late, selection: medium), "nor does it show while M is still on its way")
    }

    func testThePageShowsTheFullVariantOnceItAnswersThisSelection() {
        let product = sampleProduct(variants: [variant("1", true, "S"), variant("2", true, "M")])
        let full = variant("2", true, "M", barcode: "0002")
        XCTAssertEqual(shownVariant(product, medium, nil)?.id, "2", "until it answers: the product's own")
        XCTAssertNil(shownVariant(product, medium, nil)?.barcode)
        XCTAssertEqual(shownVariant(product, medium, RichVariant(selection: medium, variant: full)), full)
        XCTAssertNil(
            shownVariant(product, small, RichVariant(selection: medium, variant: full))?.barcode,
            "an answer for another selection isn't shown for this one"
        )
        XCTAssertEqual(
            shownVariant(product, medium, RichVariant(selection: medium, variant: nil))?.id,
            "2",
            "a failed call leaves the product's own variant"
        )
    }

    func testASelectionOutsideTheLoadedVariantsGoesByTheFullVariantAlone() {
        // a product with more than 250 variants: XL isn't in the list
        let product = sampleProduct(variants: [variant("1", true, "S")])
        let extraLarge = ["Size": "XL"]
        XCTAssertNil(shownVariant(product, extraLarge, nil))
        XCTAssertEqual(shownVariant(product, extraLarge, RichVariant(selection: extraLarge, variant: variant("9", true, "XL")))?.id, "9")
        XCTAssertNil(shownVariant(product, extraLarge, RichVariant(selection: extraLarge, variant: nil)), "no such variant: Unavailable")
    }
}
