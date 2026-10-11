import XCTest
@testable import ArgonStorefront

/// What the home screen loads (`homeContent`: the store's sections and its first collections, side by side) and what the
/// templates read from it, on the HomeScreen and FallbackHome fixtures.
final class HomeContentTests: XCTestCase {
    /// Which queries ran.
    private var calls: [String] = []

    @MainActor
    private func api() -> StorefrontAPI { StubServer().storefront() }

    /// Runs `homeContent` with the fixtures; `calls` records which queries ran.
    @MainActor
    private func load(
        _ template: HomeTemplate = .fashion,
        fallback: (@MainActor () async throws -> [CollectionCard])? = nil,
        home: @escaping @MainActor () async throws -> [Metaobject]
    ) async throws -> HomeContent {
        let api = self.api()
        let brand = Brand(shop: try await api.shop(), configDomain: "mock.shop")
        return try await homeContent(
            template,
            brand,
            home: {
                self.calls.append("home")
                return try await home()
            },
            fallback: {
                self.calls.append("fallback")
                if let fallback = fallback { return try await fallback() }
                return try await api.fallbackHome()
            }
        )
    }

    @MainActor
    func testTheStoresOwnSectionsShowAndItsCollectionsFillTheRest() async throws {
        let api = self.api()
        let content = try await load { try await api.homeScreen() }
        XCTAssertEqual(Set(calls), ["home", "fallback"], "both queries run, whatever the first answers")
        XCTAssertEqual(content.banners.map { $0.heading }, ["New season"], "the store's banner, not the stock ones")
        XCTAssertEqual(content.rails.map { $0.heading }, ["Featured"])
        XCTAssertEqual(content.categories.map { $0.handle }, ["men", "women", "unisex"])
    }

    @MainActor
    func testAStoreWithoutAHomeScreenGetsItsTemplatesBannersAndItsCollections() async throws {
        let content = try await load(.grocery) { [] }
        XCTAssertEqual(content.banners.map { $0.heading }, ["Fresh today", "Fill your basket", "Baked this morning"])
        XCTAssertEqual(content.categories.map { $0.handle }, ["men", "women", "unisex"])
        XCTAssertEqual(content.rails.map { $0.heading }, ["Men", "Women", "Unisex"])
    }

    @MainActor
    func testARefusedHomeScreenQueryCountsAsNoSections() async throws {
        // e.g. a token without metaobject access: a 200 response carrying errors
        let content = try await load(.b2b) { throw ArgonAPIError.graphql(messages: ["Access denied for metaobject"]) }
        XCTAssertEqual(content.banners.first?.heading, "Stocked and ready to ship")
        XCTAssertEqual(content.rails.count, 3)
    }

    @MainActor
    func testHttpFailuresAreRethrownNotReplacedByTheCollections() async throws {
        let failed = await thrownError { try await self.load { throw ArgonAPIError.http(status: 503) } }
        guard case let .http(status)? = failed as? ArgonAPIError else { return XCTFail("expected an HTTP error") }
        XCTAssertEqual(status, 503)
    }

    @MainActor
    func testInvalidResponsesAreRethrown() async throws {
        let failed = await thrownError {
            try await self.load { throw ArgonAPIError.decoding(operation: "HomeScreen", detail: "no data") }
        }
        guard case .decoding? = failed as? ArgonAPIError else { return XCTFail("expected a decoding error") }
    }

    @MainActor
    func testAFailingCollectionsQueryFailsTheHomeEvenWithItsOwnSections() async throws {
        let api = self.api()
        let failed = await thrownError {
            try await self.load(fallback: { throw ArgonAPIError.http(status: 500) }) { try await api.homeScreen() }
        }
        guard case .http? = failed as? ArgonAPIError else { return XCTFail("expected an HTTP error") }
        XCTAssertEqual(failed?.localizedDescription, "HTTP 500")
    }

    @MainActor
    func testAStoreWithNothingToSellKeepsTheBanners() async throws {
        let content = try await load(fallback: { [] }) { [] }
        XCTAssertTrue(content.isEmpty)
        XCTAssertEqual(content.banners.count, 3)
    }

    @MainActor
    func testViewAllOpensTheRailsCollectionElseTheWholeCatalogue() async throws {
        let collections = try await load { [] }
        guard collections.rails.count > 1 else { return XCTFail("expected a rail per collection") }
        XCTAssertEqual(collections.routeOf(collections.rails[1]), .collection("women"), "a rail made from a collection")
        let api = self.api()
        let own = try await load { try await api.homeScreen() }
        guard let rail = own.rails.first else { return XCTFail("expected the store's rail") }
        XCTAssertEqual(own.routeOf(rail), .collection("all"), "the store's own rail names no collection")
    }

    func testARailWithoutAHeadingStillHasATitle() {
        XCTAssertEqual(HomeContent.Rail(heading: nil, style: "carousel", items: []).title, "Featured")
        XCTAssertEqual(HomeContent.Rail(heading: " ", style: "carousel", items: []).title, "Featured")
        XCTAssertEqual(HomeContent.Rail(heading: "New in", style: "carousel", items: []).title, "New in")
    }

    @MainActor
    func testTheHeroLeavesTheSecondBannerForTheCard() async throws {
        let banners = try await load { [] }.banners
        guard banners.count == 3 else { return XCTFail("expected the three stock banners") }
        XCTAssertEqual(heroBanners(banners), [banners[0], banners[2]])
        XCTAssertEqual(heroBanners(Array(banners.prefix(1))), Array(banners.prefix(1)), "a lone banner is the hero")
        XCTAssertTrue(heroBanners([]).isEmpty)
    }

    func testTheBarOverTheHeroTurnsSolidAsTheLastOfTheHeroScrollsOut() {
        let hero: CGFloat = 1350
        let bar: CGFloat = 200
        XCTAssertEqual(heroSolid(scrolled: 0, heroHeight: hero, barHeight: bar), 0, "at the top")
        XCTAssertEqual(heroSolid(scrolled: hero - 2 * bar, heroHeight: hero, barHeight: bar), 0, "two bar heights of the hero left: still clear")
        XCTAssertEqual(heroSolid(scrolled: hero - 1.5 * bar, heroHeight: hero, barHeight: bar), 0.5, accuracy: 1e-6)
        XCTAssertEqual(heroSolid(scrolled: hero - bar, heroHeight: hero, barHeight: bar), 1, "the hero ends where the bar does")
        XCTAssertEqual(heroSolid(scrolled: hero + 500, heroHeight: hero, barHeight: bar), 1, "scrolled past")
        XCTAssertEqual(heroSolid(scrolled: -80, heroHeight: hero, barHeight: bar), 0, "pulled down past the top")
        // a bar whose height isn't known switches when the hero is gone
        XCTAssertEqual(heroSolid(scrolled: hero - 1, heroHeight: hero, barHeight: 0), 0)
        XCTAssertEqual(heroSolid(scrolled: hero, heroHeight: hero, barHeight: 0), 1)
    }
}
