import XCTest
@testable import ArgonStorefront

/// The case name, so tests can compare section lists by kind.
fileprivate func kind(_ section: Section) -> String {
    switch section {
    case .banner: return "banner"
    case .products: return "products"
    case .collections: return "collections"
    }
}

@MainActor
fileprivate func mockShopBrand() async throws -> Brand {
    Brand(shop: try await StubServer().storefront().shop(), configDomain: "mock.shop")
}

@MainActor
fileprivate func homeFixture() async throws -> [Metaobject] {
    try await StubServer().storefront().homeScreen("home")
}

@MainActor
fileprivate func fallbackFixture() async throws -> [CollectionCard] {
    try await StubServer().storefront().fallbackHome()
}

final class SectionsTests: XCTestCase {
    @MainActor
    func testHomeKeepsItsSectionsInOrder() async throws {
        let sections = Sections.fromHome(try await homeFixture(), hosts: ["mock.shop"])
        XCTAssertEqual(sections.map { kind($0) }, ["banner", "products", "collections"])
        guard sections.count == 3 else { return }
        guard case let .banner(style, image, heading, _, buttonLabel, link) = sections[0] else { return XCTFail("not a banner") }
        XCTAssertEqual(style, "hero")
        XCTAssertNotNil(image)
        XCTAssertEqual(heading, "New season")
        XCTAssertEqual(buttonLabel, "Shop men")
        XCTAssertEqual(link, Route.collection("men"))
        guard case let .products(productsHeading, productsStyle, items) = sections[1] else { return XCTFail("not products") }
        XCTAssertEqual(productsHeading, "Featured")
        XCTAssertEqual(items.count, 3, "the collection's products, under the limit of 4")
        XCTAssertEqual(productsStyle, "carousel", "style defaults to carousel")
        guard case let .collections(_, collections) = sections[2] else { return XCTFail("not collections") }
        XCTAssertEqual(collections.map { $0.handle }, ["men", "women", "unisex"])
    }

    @MainActor
    func testAProductsSectionIsCutToItsLimit() async throws {
        var nodes = try await homeFixture()
        let products = nodes[1]
        let fields = products.fields.filter { $0.key != "limit" }
            + [MetaobjectField(key: "limit", type: nil, value: "2", reference: nil, references: [])]
        nodes[1] = Metaobject(id: products.id, type: products.type, fields: fields)
        guard case let .products(_, _, items)? = Sections.fromHome(nodes).dropFirst().first else { return XCTFail("not products") }
        XCTAssertEqual(items.count, 2)
    }

    func testNoScreenGivesNoSections() {
        XCTAssertTrue(Sections.fromHome([]).isEmpty)
    }

    @MainActor
    func testFallbackWithoutCoverStartsWithCollections() async throws {
        let sections = Sections.fallback(try await mockShopBrand(), try await fallbackFixture())
        XCTAssertEqual(sections.map { kind($0) }, ["collections", "products"])
        guard case let .products(heading, style, items)? = sections.last else { return XCTFail("not products") }
        XCTAssertEqual(heading, "Men")
        XCTAssertEqual(style, "carousel")
        XCTAssertEqual(items.count, 3)
    }
}

final class HomeSectionsTests: XCTestCase {
    /// Which loads ran.
    private var calls: [String] = []

    /// Runs `homeSections` with canned screens.
    @MainActor
    private func home(_ screen: @escaping () throws -> [Metaobject]) async throws -> [Section] {
        let brand = try await mockShopBrand()
        let fallback = try await fallbackFixture()
        return try await homeSections(
            brand,
            home: {
                self.calls.append("home")
                return try screen()
            },
            fallback: {
                self.calls.append("fallback")
                return fallback
            }
        )
    }

    @MainActor
    func testTheStoresScreenIsUsedWhenItHasSections() async throws {
        let screen = try await homeFixture()
        let sections = try await home { screen }
        XCTAssertEqual(calls, ["home"])
        XCTAssertEqual(sections.first.map { kind($0) }, "banner")
    }

    @MainActor
    func testNoRenderableSectionsFallBack() async throws {
        let sections = try await home { [] }
        XCTAssertEqual(calls, ["home", "fallback"])
        XCTAssertEqual(sections.first.map { kind($0) }, "collections")
    }

    @MainActor
    func testGraphqlErrorsFallBack() async throws {
        // e.g. a token without metaobject access: a 200 response carrying errors
        let sections = try await home { throw ArgonAPIError.graphql(messages: ["Access denied for metaobject"]) }
        XCTAssertEqual(calls, ["home", "fallback"])
        XCTAssertFalse(sections.isEmpty)
    }

    @MainActor
    func testHttpFailuresAreRethrownNotReplacedByTheFallback() async throws {
        let failed = await thrownError { try await self.home { throw ArgonAPIError.http(status: 503) } }
        guard case let .http(status)? = failed as? ArgonAPIError else { return XCTFail("expected an HTTP error") }
        XCTAssertEqual(status, 503)
        XCTAssertEqual(calls, ["home"], "the fallback must not run, or the screen would cache a degraded home")
    }

    @MainActor
    func testInvalidResponsesAreRethrown() async throws {
        let failed = await thrownError { try await self.home { throw ArgonAPIError.decoding(operation: "HomeScreen", detail: "") } }
        guard case .decoding? = failed as? ArgonAPIError else { return XCTFail("expected a decoding error") }
        XCTAssertEqual(calls, ["home"])
    }

    @MainActor
    func testAFailingFallbackStillSurfacesItsError() async throws {
        let brand = try await mockShopBrand()
        let failed = await thrownError {
            try await homeSections(brand, home: { [] }, fallback: { throw ArgonAPIError.http(status: 500) })
        }
        guard case let .http(status)? = failed as? ArgonAPIError else { return XCTFail("expected an HTTP error") }
        XCTAssertEqual(status, 500)
    }
}
