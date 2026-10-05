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

fileprivate func mockShopBrand() throws -> Brand {
    try parseBrand(XCTUnwrap(try fixture("shop").obj("shop")), configDomain: "mock.shop")
}

final class SectionsTests: XCTestCase {
    func testHomeKeepsKnownSectionsAndSkipsUnknownAndEmpty() throws {
        let sections = try Sections.fromHome(fixture("home_screen"))
        XCTAssertEqual(sections.map { kind($0) }, ["banner", "products", "collections"])
        guard sections.count == 3 else { return }
        guard case let .banner(style, _, _, _, _, link) = sections[0] else { return XCTFail("not a banner") }
        XCTAssertEqual(style, "hero")
        XCTAssertEqual(link, Route.collection("men"))
        guard case let .products(_, productsStyle, items) = sections[1] else { return XCTFail("not products") }
        XCTAssertEqual(items.count, 4, "collection products, cut to limit 4")
        XCTAssertEqual(productsStyle, "carousel", "style defaults to carousel")
    }

    func testMissingScreenGivesNoSections() throws {
        XCTAssertTrue(try Sections.fromHome(json(#"{"metaobject":null}"#)).isEmpty)
    }

    func testFallbackWithoutCoverStartsWithCollections() throws {
        let sections = try Sections.fallback(mockShopBrand(), fixture("fallback_home"))
        XCTAssertFalse(sections.isEmpty)
        XCTAssertEqual(sections.first.map { kind($0) }, "collections")
        XCTAssertTrue(sections.contains { section in
            if case let .products(_, style, items) = section {
                return style == "carousel" && !items.isEmpty
            }
            return false
        })
    }

    func testEmptyObjectsAreSkippedNotCrashed() throws {
        let card = try fixture("fallback_home").nodes("collections")[0].nodes("products")[0]
        let cardData = try JSONSerialization.data(withJSONObject: card)
        let cardText = String(decoding: cardData, as: UTF8.self)
        let data = try json("""
        {"metaobject":{"field":{"references":{"nodes":[
            {},
            {"type":"mobile_products","fields":[{"key":"products","references":{"nodes":[{}, \(cardText)]}}]}
        ]}}}}
        """)
        let sections = try Sections.fromHome(data)
        XCTAssertEqual(sections.count, 1)
        guard let first = sections.first, case let .products(_, _, items) = first else { return XCTFail("not products") }
        XCTAssertEqual(items.count, 1)
    }
}

final class HomeSectionsTests: XCTestCase {
    /// Which queries ran.
    private var calls: [String] = []

    /// Runs `homeSections` with canned responses.
    private func home(_ response: @escaping () throws -> [String: Any]) async throws -> [Section] {
        let brand = try mockShopBrand()
        return try await homeSections(
            brand,
            home: {
                self.calls.append("home")
                return try response()
            },
            fallback: {
                self.calls.append("fallback")
                return try fixture("fallback_home")
            }
        )
    }

    func testTheStoresScreenIsUsedWhenItHasSections() async throws {
        let sections = try await home { try fixture("home_screen") }
        XCTAssertEqual(calls, ["home"])
        XCTAssertEqual(sections.first.map { kind($0) }, "banner")
    }

    func testNoRenderableSectionsFallBack() async throws {
        let sections = try await home { try json(#"{"metaobject":null}"#) }
        XCTAssertEqual(calls, ["home", "fallback"])
        XCTAssertEqual(sections.first.map { kind($0) }, "collections")
    }

    func testGraphqlErrorsFallBack() async throws {
        // e.g. a token without metaobject access: a 200 response carrying errors
        let sections = try await home {
            throw StorefrontException(messages: ["Access denied for metaobject"], status: 200, isGraphQL: true)
        }
        XCTAssertEqual(calls, ["home", "fallback"])
        XCTAssertFalse(sections.isEmpty)
    }

    func testHttpFailuresAreRethrownNotReplacedByTheFallback() async throws {
        do {
            _ = try await home { throw StorefrontException(messages: ["HTTP 503"], status: 503) }
            XCTFail("expected a StorefrontException")
        } catch let e as StorefrontException {
            XCTAssertEqual(e.messages, ["HTTP 503"])
        }
        XCTAssertEqual(calls, ["home"], "the fallback must not run, or the screen would cache a degraded home")
    }

    func testInvalidResponsesAreRethrown() async throws {
        do {
            _ = try await home { throw StorefrontException(messages: ["Invalid response"], status: 200) }
            XCTFail("expected a StorefrontException")
        } catch is StorefrontException {
        }
        XCTAssertEqual(calls, ["home"])
    }

    func testAFailingFallbackStillSurfacesItsError() async throws {
        let brand = try mockShopBrand()
        do {
            _ = try await homeSections(
                brand,
                home: { try json(#"{"metaobject":null}"#) },
                fallback: { throw StorefrontException(messages: ["HTTP 500"], status: 500) }
            )
            XCTFail("expected a StorefrontException")
        } catch let e as StorefrontException {
            XCTAssertEqual(e.messages, ["HTTP 500"])
        }
    }
}
