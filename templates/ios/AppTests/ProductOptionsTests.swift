import XCTest
@testable import ArgonStorefront

final class ProductOptionsTests: XCTestCase {
    private func option(_ name: String, _ values: String...) -> ProductOption {
        ProductOption(name: name, optionValues: values.map { ProductOptionValue(name: $0) })
    }

    private func img(_ url: String) -> Img { Img(url: url, alt: nil, width: nil, height: nil) }

    private func variant(_ size: String, _ color: String, available: Bool = true, compareAt: String? = nil, image: Img? = nil) -> Variant {
        Variant(
            id: "\(size)-\(color)",
            title: "\(size) / \(color)",
            available: available,
            options: ["Size": size, "Color": color],
            price: Money(amount: "80.0", currencyCode: "USD"),
            compareAt: compareAt.map { Money(amount: $0, currencyCode: "USD") },
            image: image
        )
    }

    private var size: ProductOption { option("Size", "S", "M") }
    private var color: ProductOption { option("Color", "Red", "Blue") }

    // S/Blue is sold out, M/Blue doesn't exist
    private var variants: [Variant] { [variant("S", "Red"), variant("S", "Blue", available: false), variant("M", "Red")] }

    func testAProductWithoutOptionsHasNothingToChoose() {
        XCTAssertEqual(visibleOptions(sampleProduct(options: [option("Title", "Default Title")])), [])
        XCTAssertEqual(visibleOptions(sampleProduct(options: [size, color])), [size, color])
        let titles = option("Title", "Hardcover", "Paperback")
        XCTAssertEqual(visibleOptions(sampleProduct(options: [titles])), [titles], "a real option named Title stays")
    }

    func testAValueIsAvailableWhenItGivesABuyableVariantWithTheRestOfTheSelection() {
        let selection = ["Size": "S", "Color": "Red"]
        XCTAssertEqual(availableValues(variants, selection, size), ["S", "M"])
        XCTAssertEqual(availableValues(variants, selection, color), ["Red"], "S in Blue is sold out")
    }

    func testACombinationThatDoesNotExistIsNotAvailable() {
        XCTAssertEqual(availableValues(variants, ["Size": "M", "Color": "Red"], color), ["Red"])
        XCTAssertEqual(availableValues(variants, ["Size": "S", "Color": "Blue"], size), [], "from S/Blue, M would be the missing M/Blue")
        XCTAssertEqual(availableValues([], ["Size": "S"], size), [])
    }

    func testPastTheLoadedVariantsAnUnlistedCombinationCountsAsAvailable() {
        // 250 variants loaded (the API's page): a combination that isn't among them may still exist
        let many = (1...250).map { variant("\($0)", "Red", available: $0 != 2) }
        let sizes = option("Size", "1", "2", "999")
        XCTAssertEqual(availableValues(many, ["Size": "1", "Color": "Red"], sizes), ["1", "999"], "listed and sold out is still struck")
        XCTAssertEqual(availableValues(many, ["Size": "1", "Color": "Red"], color), ["Red", "Blue"])
    }

    // MARK: Gallery

    func testAVariantsImageIsFoundAmongTheProductsWhateverItsSizeParameters() {
        let images = [img("https://cdn.test/a.jpg"), img("https://cdn.test/b.jpg?v=1")]
        XCTAssertEqual(imageIndex(images, img("https://cdn.test/b.jpg?width=600")), 1)
        XCTAssertEqual(imageIndex(images, img("https://cdn.test/a.jpg")), 0)
        XCTAssertNil(imageIndex(images, img("https://cdn.test/c.jpg")))
        XCTAssertNil(imageIndex(images, nil))
        XCTAssertNil(imageIndex([], img("https://cdn.test/a.jpg")))
    }

    func testTheGallerysTagsSayOnlyWhatIsTrue() {
        XCTAssertEqual(galleryTags(nil), [])
        XCTAssertEqual(galleryTags(variant("S", "Red")), [])
        XCTAssertEqual(
            galleryTags(variant("S", "Red", available: false, compareAt: "100.0")),
            [GalleryTag(text: "Sale −20%", isSale: true), GalleryTag(text: "Sold out")]
        )
        var bundle = variant("S", "Red")
        bundle.requiresComponents = true
        XCTAssertEqual(galleryTags(bundle), [GalleryTag(text: "Bundle")])
    }
}
