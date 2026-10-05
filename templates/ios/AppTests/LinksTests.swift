import XCTest
@testable import App

final class LinksTests: XCTestCase {
    private let hosts = ["nalli.com", "nalli.myshopify.com"]

    func testShopUrlWithLocaleOpensProduct() {
        XCTAssertEqual(
            Links.resolve("https://nalli.com/en-in/products/silk-saree?variant=1", hosts: ["nalli.com", "nalli.myshopify.com"]),
            Route.product("silk-saree")
        )
    }

    func testCollectionPath() {
        XCTAssertEqual(Links.resolve("/collections/all/", hosts: hosts), Route.collection("all"))
    }

    func testSearchQueryIsDecoded() {
        XCTAssertEqual(Links.resolve("/search?q=red+saree", hosts: hosts), Route.search("red saree"))
    }

    func testOtherHostOpensInBrowser() {
        XCTAssertEqual(Links.resolve("https://instagram.com/x", hosts: hosts), Route.web("https://instagram.com/x"))
    }

    func testBlankOrRootIsNull() {
        XCTAssertNil(Links.resolve("", hosts: hosts))
        XCTAssertNil(Links.resolve(nil, hosts: hosts))
        XCTAssertNil(Links.resolve("/", hosts: hosts))
    }

    func testMyshopifyHostStaysInApp() {
        XCTAssertEqual(Links.resolve("https://nalli.myshopify.com/products/x", hosts: hosts), Route.product("x"))
    }

    func testOtherStorePathOpensInBrowserOnShopDomain() {
        XCTAssertEqual(Links.resolve("/pages/shipping", hosts: hosts), Route.web("https://nalli.com/pages/shipping"))
    }

    func testOnlyHttpSchemesOpenInBrowser() {
        XCTAssertNil(Links.resolve("javascript:alert(1)", hosts: hosts))
        XCTAssertNil(Links.resolve("mailto:hi@nalli.com", hosts: hosts))
        XCTAssertEqual(Links.resolve("http://instagram.com/x", hosts: hosts), Route.web("http://instagram.com/x"))
    }

    func testRawSpaceInQueryIsEncoded() {
        XCTAssertEqual(Links.resolve("/search?q=red saree", hosts: hosts), Route.search("red saree"))
    }
}
