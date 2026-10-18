import XCTest
@testable import ArgonStorefront

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

    func testBlankIsNull() {
        XCTAssertNil(Links.resolve("", hosts: hosts))
        XCTAssertNil(Links.resolve(nil, hosts: hosts))
        XCTAssertNil(Links.resolve("#", hosts: hosts), "a link without a path goes nowhere")
    }

    func testMyshopifyHostStaysInApp() {
        XCTAssertEqual(Links.resolve("https://nalli.myshopify.com/products/x", hosts: hosts), Route.product("x"))
    }

    func testOtherStorePathOpensInBrowserOnShopDomain() {
        XCTAssertEqual(Links.resolve("/blogs/news", hosts: hosts), Route.web("https://nalli.com/blogs/news"))
    }

    func testOnlyHttpSchemesOpenInBrowser() {
        XCTAssertNil(Links.resolve("javascript:alert(1)", hosts: hosts))
        XCTAssertNil(Links.resolve("mailto:hi@nalli.com", hosts: hosts))
        XCTAssertEqual(Links.resolve("http://instagram.com/x", hosts: hosts), Route.web("http://instagram.com/x"))
    }

    func testPagesOpenInTheApp() {
        XCTAssertEqual(Links.resolve("/pages/shipping", hosts: hosts), Route.page("shipping"))
        XCTAssertEqual(Links.resolve("https://nalli.com/en-in/pages/about?ref=x", hosts: hosts), Route.page("about"))
    }

    func testAppScreens() {
        XCTAssertEqual(Links.resolve("app://screens/about", hosts: hosts), Route.screen("about"))
        XCTAssertEqual(Links.resolve(" app://screens/size-guide/ ", hosts: hosts), Route.screen("size-guide"))
        XCTAssertNil(Links.resolve("app://screens/", hosts: hosts))
        XCTAssertNil(Links.resolve("app://elsewhere/about", hosts: hosts))
    }

    func testTabs() {
        XCTAssertEqual(Links.resolve("/cart", hosts: hosts), Route.tab("cart"))
        XCTAssertEqual(Links.resolve("/account", hosts: hosts), Route.tab("account"))
        XCTAssertEqual(Links.resolve("/wishlist/", hosts: hosts), Route.tab("wishlist"))
        XCTAssertEqual(Links.resolve("/", hosts: hosts), Route.tab("home"))
        XCTAssertEqual(Links.resolve("https://nalli.com/", hosts: hosts), Route.tab("home"))
        XCTAssertEqual(Links.resolve("https://instagram.com/", hosts: hosts), Route.web("https://instagram.com/"))
    }

    func testRawSpaceInQueryIsEncoded() {
        XCTAssertEqual(Links.resolve("/search?q=red saree", hosts: hosts), Route.search("red saree"))
    }
}
