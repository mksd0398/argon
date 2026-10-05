import XCTest
@testable import App

/// A captured mock.shop response's `data` object from AppTests/Fixtures.
func fixture(_ name: String) throws -> [String: Any] {
    let bundle = Bundle(for: ParseTests.self)
    // a synchronized folder may copy Fixtures/ flat into the test bundle
    guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        ?? bundle.url(forResource: name, withExtension: "json") else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(name)"])
    }
    return try json(String(contentsOf: url, encoding: .utf8))
}

func json(_ text: String) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Not a JSON object"])
    }
    return object
}

final class ParseTests: XCTestCase {
    // Shaped like Customer.graphql and Order.graphql (no captured response: the Customer Account API needs a signed-in customer).
    func testCustomerAndOrderFollowTheirQueries() throws {
        let customer = try parseCustomer(json("""
        {"firstName":"Ada","lastName":null,"emailAddress":{"emailAddress":"ada@example.com"},"orders":{"nodes":[
        {"id":"gid://shopify/Order/1","name":"#1001","processedAt":"2026-10-01T10:00:00Z","financialStatus":"PAID",
        "totalPrice":{"amount":"190.0","currencyCode":"CAD"}}]}}
        """))
        XCTAssertEqual(customer.name, "Ada")
        XCTAssertEqual(customer.email, "ada@example.com")
        XCTAssertEqual(customer.orders, [
            OrderSummary(
                id: "gid://shopify/Order/1",
                name: "#1001",
                processedAt: "2026-10-01T10:00:00Z",
                financialStatus: "PAID",
                total: Money(amount: "190.0", currencyCode: "CAD")
            ),
        ])

        let order = try parseOrder(json("""
        {"id":"gid://shopify/Order/1","name":"#1001","processedAt":"2026-10-01T10:00:00Z","financialStatus":"PAID",
        "fulfillments":{"nodes":[{"status":"SUCCESS"}]},"lineItems":{"nodes":[{"title":"Hoodie","variantTitle":"Small / Green",
        "quantity":2,"image":{"url":"https://cdn.test/h.jpg"},"totalPrice":{"amount":"180.0","currencyCode":"CAD"}}]},
        "subtotal":{"amount":"180.0","currencyCode":"CAD"},"totalPrice":{"amount":"190.0","currencyCode":"CAD"}}
        """))
        XCTAssertEqual(order.fulfillments, ["SUCCESS"])
        XCTAssertEqual(order.lines, [
            OrderLine(
                title: "Hoodie",
                variantTitle: "Small / Green",
                quantity: 2,
                image: Img(url: "https://cdn.test/h.jpg", alt: nil, width: nil, height: nil),
                total: Money(amount: "180.0", currencyCode: "CAD")
            ),
        ])
        XCTAssertEqual(order.subtotal, Money(amount: "180.0", currencyCode: "CAD"))
        XCTAssertEqual(order.total, Money(amount: "190.0", currencyCode: "CAD"))
    }

    func testProductHasAllOptionsAndVariants() throws {
        let raw = try XCTUnwrap(try fixture("product").obj("product"))
        let product = try parseProduct(raw)
        XCTAssertEqual(product.options.map { $0.name }, ["Size", "Color"])
        XCTAssertEqual(product.variants.count, raw.nodes("variants").count)
        XCTAssertEqual(product.variants.first?.options, ["Size": "Small", "Color": "Green"])
        XCTAssertFalse(product.images.isEmpty)
        XCTAssertTrue(product.metafields.isEmpty, "unset metafields come back null and are skipped")
    }

    func testCartHasEveryLine() throws {
        let raw = try XCTUnwrap(try fixture("cart").obj("cart"))
        let cart = try parseCart(raw)
        XCTAssertEqual(cart.lines.count, raw.nodes("lines").count)
        XCTAssertEqual(cart.totalQuantity, 3)
    }

    func testCompareAtOnlyWhenAbovePrice() throws {
        func card(_ compareAt: String) throws -> ProductCard {
            try parseProductCard(json("""
            {"id":"gid://shopify/Product/1","handle":"tee","title":"Tee","availableForSale":true,"featuredImage":null,
             "priceRange":{"minVariantPrice":{"amount":"40.0","currencyCode":"USD"}},
             "compareAtPriceRange":{"minVariantPrice":{"amount":"\(compareAt)","currencyCode":"USD"}}}
            """))
        }
        XCTAssertNil(try card("40.0").compareAt)
        XCTAssertEqual(try card("50.0").compareAt, Money(amount: "50.0", currencyCode: "USD"))
    }

    func testCollectionPage() throws {
        let connection = try XCTUnwrap(try fixture("collection_men").obj("collection")?.obj("products"))
        let page = try parseProductPage(connection, filtersKey: "filters")
        XCTAssertEqual(page.items.count, 10)
        XCTAssertFalse(page.hasNext)
        XCTAssertFalse(try XCTUnwrap(page.endCursor).isEmpty)
    }

    func testBrandAndMenuUseTheShopHosts() throws {
        let brand = try parseBrand(XCTUnwrap(try fixture("shop").obj("shop")), configDomain: "mock.shop")
        XCTAssertEqual(brand.hosts, ["mock.shop", "demostore.hydrogen.mock.shop"])
        XCTAssertNil(brand.accent, "mock.shop has no brand colours")
        let menu = try parseMenu(XCTUnwrap(try fixture("menu").obj("menu")), hosts: brand.hosts)
        XCTAssertEqual(menu.first, MenuItem(title: "Men", route: .collection("men"), children: []))
    }
}
