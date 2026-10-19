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

/// What a home template is given to lay out (`Sections.content`): the store's own sections first, the stock banners and
/// the first collections for whatever they leave out. How the home screen loads the two is in HomeContentTests.
final class SectionsContentTests: XCTestCase {
    private let stock: (HomeTemplate, Int) -> String? = { template, index in "file:///stock/home-\(template.rawValue)-\(index).jpg" }
    private let brand = Brand(name: "Shop", logo: nil, cover: nil, accent: nil, hosts: ["shop.test"])

    @MainActor
    func testAStoreWithoutSectionsGetsStockBannersItsCollectionsAndARailForEach() async throws {
        let content = Sections.content(.grocery, brand, [], try await fallbackFixture(), image: stock)
        XCTAssertEqual(content.banners.map { $0.heading }, ["Fresh today", "Fill your basket", "Baked this morning"])
        XCTAssertEqual(content.banners.map { $0.buttonLabel }, ["Shop now", "Start shopping", "Order now"])
        XCTAssertEqual(content.banners.map { $0.image?.url }, [
            "file:///stock/home-grocery-1.jpg", "file:///stock/home-grocery-2.jpg", "file:///stock/home-grocery-3.jpg",
        ])
        XCTAssertEqual(content.banners.map { $0.link }, [.collection("men"), .collection("men"), .collection("men")], "the first collection with products")
        XCTAssertEqual(content.banners.map { $0.style }, ["hero", "hero", "hero"])
        XCTAssertEqual(content.categories.map { $0.handle }, ["men", "women", "unisex"])
        XCTAssertEqual(content.rails.map { $0.heading }, ["Men", "Women", "Unisex"])
        XCTAssertEqual(content.rails.map { $0.items.count }, [3, 3, 3])
        XCTAssertEqual(content.rails.first?.items.first?.handle, "hoodie-old")
        XCTAssertFalse(content.isEmpty)
    }

    @MainActor
    func testTheStoresOwnSectionsComeFirst() async throws {
        let sections = Sections.fromHome(try await homeFixture(), hosts: ["mock.shop"])
        let content = Sections.content(.fashion, brand, sections, try await fallbackFixture(), image: stock)
        XCTAssertEqual(content.banners.map { $0.heading }, ["New season"], "its banner, not the stock ones")
        XCTAssertEqual(content.banners.first?.buttonLabel, "Shop men")
        XCTAssertEqual(content.banners.first?.link, .collection("men"))
        XCTAssertFalse(content.banners.first?.image?.url.hasPrefix("file:") ?? true)
        XCTAssertEqual(content.rails.map { $0.heading }, ["Featured"], "its product section, not a rail per collection")
        XCTAssertEqual(content.rails.first?.items.count, 3)
        XCTAssertEqual(content.categories.map { $0.handle }, ["men", "women", "unisex"])
    }

    func testEachPartFallsBackOnItsOwn() {
        let tee = ProductCard(id: "p1", handle: "tee", title: "Tee", available: true, image: nil, price: Money(amount: "40.0", currencyCode: "USD"), compareAt: nil)
        let stocked = CollectionCard(id: "c1", handle: "tops", title: "Tops", image: nil, products: [tee])
        let empty = CollectionCard(id: "c2", handle: "soon", title: "Coming soon", image: nil)
        // a store with one banner and nothing else
        let banner = Section.banner(style: "card", image: nil, heading: "Sale", text: "This week", buttonLabel: nil, link: nil)
        let content = Sections.content(.beauty, brand, [banner], [empty, stocked], image: stock)
        XCTAssertEqual(content.banners, [HomeContent.Banner(style: "card", image: nil, heading: "Sale", text: "This week", buttonLabel: nil, link: nil)])
        XCTAssertEqual(content.categories, [stocked], "collections without products are left out")
        XCTAssertEqual(content.rails, [HomeContent.Rail(heading: "Tops", style: "carousel", items: [tee])])

        // the stock banners link to the first collection that has products
        let stockOnly = Sections.content(.beauty, brand, [], [empty, stocked], image: stock)
        XCTAssertEqual(stockOnly.banners.map { $0.heading }, ["Your daily ritual", "Skin first", "Colour that stays"])
        XCTAssertEqual(stockOnly.banners.map { $0.link }, [.collection("tops"), .collection("tops"), .collection("tops")])
    }

    func testAStoreWithNothingKeepsItsBannersAndSaysSo() {
        let empty = CollectionCard(id: "c2", handle: "soon", title: "Coming soon", image: nil)
        let content = Sections.content(.b2b, brand, [], [empty], image: { _, _ in nil })
        XCTAssertEqual(content.banners.map { $0.heading }, ["Stocked and ready to ship", "Tools for the trade", "Order by the pallet"])
        XCTAssertEqual(content.banners.map { $0.buttonLabel }, ["Browse the catalogue", "Shop now", "View bulk pricing"])
        XCTAssertEqual(content.banners.map { $0.link }, [nil, nil, nil], "no collection to link to")
        XCTAssertEqual(content.banners.map { $0.image }, [nil, nil, nil], "the bundle has no stock image")
        XCTAssertEqual(content.categories, [])
        XCTAssertEqual(content.rails, [])
        XCTAssertTrue(content.isEmpty)
    }

    func testEveryTemplateHasItsThreeBanners() {
        XCTAssertEqual(HomeTemplate.allCases, [.fashion, .beauty, .grocery, .b2b])
        for template in HomeTemplate.allCases {
            XCTAssertEqual(template.bannerCopy.count, 3, template.rawValue)
        }
        XCTAssertEqual(HomeTemplate.fashion.bannerCopy.map { $0.heading }, ["The new season", "Everyday essentials", "Made to last"])
        XCTAssertEqual(HomeTemplate.fashion.bannerCopy.map { $0.button }, ["Shop now", "Explore", "Discover"])
    }

    func testFullBleedSectionsSitFlushAndOrdinaryOnesKeepTheirGap() {
        func section(_ type: String, _ settings: [String: JSONValue] = [:]) -> ScreenSection {
            ScreenSection(id: type, type: type, settings: SectionSettings(settings))
        }
        let hero = section("banner"), card = section("banner", ["style": .string("card")])
        let text = section("rich_text"), products = section("products")
        let tinted = section("rich_text", ["background": .string("#FFEEDD")])
        for bleed in [hero, section("banner", ["style": .string("hero")]), section("slideshow"), section("marquee"), section("video"), tinted] {
            XCTAssertTrue(bleed.fullBleed, bleed.type)
            XCTAssertEqual(gapBefore(bleed, text, gap: 24), 24)
            XCTAssertEqual(gapBefore(text, bleed, gap: 24), 24)
            XCTAssertEqual(gapBefore(hero, bleed, gap: 24), 0)
        }
        XCTAssertFalse(card.fullBleed)
        XCTAssertEqual(gapBefore(hero, section("marquee"), gap: 24), 0)
        XCTAssertEqual(gapBefore(text, products, gap: 24), 24)
        XCTAssertEqual(gapBefore(card, products, gap: 24), 24)
        // the first section has nothing above it
        XCTAssertEqual(gapBefore(nil, products, gap: 24), 0)
    }

    func testTheBarIsClearOnlyOverAPictureFirst() {
        func section(_ type: String, _ settings: [String: JSONValue] = [:]) -> ScreenSection {
            ScreenSection(id: type, type: type, settings: SectionSettings(settings))
        }
        for first in ["banner", "slideshow", "video"] {
            XCTAssertTrue(ScreenTemplate(sections: [section(first), section("rich_text")]).opensWithPicture, first)
        }
        for first in [section("collections"), section("rich_text"), section("banner", ["style": .string("card")]), section("marquee")] {
            XCTAssertFalse(ScreenTemplate(sections: [first, section("banner")]).opensWithPicture, first.type)
        }
        XCTAssertFalse(ScreenTemplate().opensWithPicture)
    }
}
