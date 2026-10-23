import ArgonUI
import XCTest
@testable import ArgonStorefront

/// Screens v2 templates (Screens.swift) over the contract's sample templates (Fixtures/screens/), and the Liquid
/// objects of a screen.
final class ScreensTests: XCTestCase {
    private func template(_ name: String) throws -> ScreenTemplate {
        try XCTUnwrap(ScreenTemplate.decode(contractFixture("screens/\(name).json")))
    }

    private func section(_ template: ScreenTemplate, _ id: String) throws -> ScreenSection {
        try XCTUnwrap(template.sections.first { $0.id == id })
    }

    // MARK: Decoding

    func testHomeKeepsWhatThisAppDrawsOnIos() throws {
        let home = try template("home")
        // `picks` is Android's only, `old` hidden, `future` of a type this app doesn't know
        XCTAssertEqual(home.sections.map { $0.id }, ["hero", "slides", "cats", "new", "story", "atelier", "film", "sale", "gap", "bad"])
        XCTAssertEqual(home.metafields, ["shop.custom.promo"])
        XCTAssertEqual(home.metafieldIdentifiers("shop"), [MetafieldIdentifier(namespace: "custom", key: "promo")])
        XCTAssertEqual(home.metafieldIdentifiers("product"), [])
        XCTAssertEqual(home.placement("home"), SectionPlacement(above: home.sections))
        XCTAssertEqual(home.content.count, 10)
    }

    func testSettingsAreReadValueByValue() throws {
        let home = try template("home")
        let hero = try section(home, "hero")
        XCTAssertEqual(hero.track, "winter_hero")
        XCTAssertEqual(hero.promotionName, "winter_hero")
        XCTAssertEqual(hero.settings.image("image")?.width, 1024)
        XCTAssertEqual(hero.settings.image("image")?.alt, "Winter")
        XCTAssertEqual(hero.settings.text("heading"), "Winter is here")
        XCTAssertEqual(hero.settings.link("link"), "/collections/men")
        XCTAssertEqual(hero.settings.choice("style", ["hero", "card"], "hero"), "hero")
        XCTAssertEqual(hero.settings.color("text_color", "#000000"), "#FFFFFF")

        let slides = try section(home, "slides")
        XCTAssertEqual(slides.promotionName, "slideshow")
        XCTAssertEqual(slides.blocks.map { $0.id }, ["s1", "s2"])
        XCTAssertEqual(slides.blocks.map { $0.type }, ["slide", "slide"])
        XCTAssertNil(slides.blocks[1].settings.image("image"))
        XCTAssertEqual(slides.settings.number("interval", 5, 3...15), 6)
        XCTAssertTrue(slides.settings.boolean("autoplay", false))

        let new = try section(home, "new")
        XCTAssertEqual(new.settings.gids("products", "Product"), [])
        XCTAssertEqual(new.settings.gid("collection", "Collection"), "gid://shopify/Collection/429493780502")
        XCTAssertEqual(new.settings.number("limit", 8, 1...24), 4)

        XCTAssertEqual(try section(home, "sale").settings.datetime("ends_at"), Date(timeIntervalSince1970: 1_893_456_000))
        XCTAssertEqual(try section(home, "gap").settings.number("height", 24, 4...120), 32)
        XCTAssertTrue(try section(home, "gap").settings.boolean("divider", false))

        // a wrong type or value is the default, setting by setting
        let bad = try section(home, "bad").settings
        XCTAssertEqual(bad.number("limit", 8, 1...24), 8)
        XCTAssertEqual(bad.choice("style", ["carousel", "grid"], "carousel"), "carousel")
        XCTAssertEqual(bad.gids("products", "Product"), [])
        XCTAssertTrue(bad.boolean("show_all", true))
    }

    func testEachReaderFallsBackToItsDefault() {
        let settings = SectionSettings([
            "big": .int(100), "small": .double(0.5), "word": .string("7"),
            "lower": .string("#1f6feb"), "short": .string("#123"),
            "http": .object(["url": .string("http://cdn.shopify.com/a.png")]),
            "ids": .array([.string("gid://shopify/Product/1"), .string("gid://shopify/Product/1"), .string("nope"),
                           .string("gid://shopify/Collection/2"), .int(3), .string("gid://shopify/Product/4")]),
            "when": .string("soon"), "flag": .string("true"), "blank": .string("  "),
        ])
        XCTAssertEqual(settings.number("big", 8, 1...24), 24, "clamped to the range")
        XCTAssertEqual(settings.number("small", 8, 1...24), 1)
        XCTAssertEqual(settings.number("word", 8, 1...24), 8, "not a number")
        XCTAssertEqual(settings.number("missing", 8, 1...24), 8)
        XCTAssertEqual(settings.color("lower", "#FFFFFF"), "#1F6FEB")
        XCTAssertEqual(settings.color("short", "#FFFFFF"), "#FFFFFF")
        XCTAssertNil(settings.image("http"), "only https images")
        XCTAssertEqual(settings.gids("ids", "Product"), ["gid://shopify/Product/1", "gid://shopify/Product/4"])
        XCTAssertNil(settings.gid("word", "Product"))
        XCTAssertNil(settings.datetime("when"))
        XCTAssertFalse(settings.boolean("flag", false), "a string is not a boolean")
        XCTAssertNil(settings.link("blank"))
        XCTAssertNil(settings.text("big"))
    }

    func testABrokenTemplateIsNoTemplateAndABrokenSectionIsSkipped() {
        XCTAssertNil(ScreenTemplate.decode(nil))
        XCTAssertNil(ScreenTemplate.decode("{ not json"))
        XCTAssertNil(ScreenTemplate.decode("[1, 2]"), "not an object")
        XCTAssertEqual(ScreenTemplate.decode("{}"), ScreenTemplate())
        let decoded = ScreenTemplate.decode("""
        {"sections": [
          {"type": "spacer"}, {"id": 5, "type": "spacer"}, {"id": "a"}, "text",
          {"id": "ios", "type": "spacer", "platforms": ["ios"]},
          {"id": "both", "type": "spacer", "platforms": []},
          {"id": "android", "type": "spacer", "platforms": ["android"]},
          {"id": "shown", "type": "spacer", "hidden": false, "settings": "nope", "blocks": "nope"}
        ], "metafields": ["product.custom.fabric", "order.custom.x", "shop.promo", 3]}
        """)
        XCTAssertEqual(decoded?.sections.map { $0.id }, ["ios", "both", "shown"])
        XCTAssertEqual(decoded?.sections.last?.settings, SectionSettings())
        XCTAssertEqual(decoded?.metafields, ["product.custom.fabric"])
    }

    func testARepeatedIdAndOutOfRangeNumbersAreSafe() {
        let decoded = ScreenTemplate.decode("""
        {"sections": [{"id": "a", "type": "spacer"}, {"id": "a", "type": "banner"}, {"id": "b", "type": "custom",
          "settings": {"render": "native", "nodes": [{"type": "heading", "level": 1e300, "text": "Hi"},
            {"type": "collection", "id": "gid://shopify/Collection/1", "limit": -1e300}]}}]}
        """)
        XCTAssertEqual(decoded?.sections.map { $0.type }, ["spacer", "custom"], "the first of two with one id")
        XCTAssertEqual(CustomNode.decode(decoded?.sections.last?.settings.values["nodes"]), [
            .heading(level: 3, text: "Hi"), .collection("gid://shopify/Collection/1", limit: 1),
        ])
        let image = SectionSettings(["image": .object(["url": .string("https://cdn.shopify.com/a.png"), "width": .double(1e300), "height": .double(-5)])])
        XCTAssertEqual(image.image("image")?.width, 100_000)
        XCTAssertNil(image.image("image")?.height)
        XCTAssertNil(boundedInt(.nan, 1...3))
        XCTAssertNil(boundedInt(.infinity, 1...3))
    }

    // MARK: Detailing (the screen's look, section style, the newer types)

    func testTheScreensLookIsReadLeniently() {
        let look = ScreenTemplate.decode(##"{"screen": {"top_bar": "transparent", "top_bar_tint": "dark", "background": "#f7f3ee"}, "sections": []}"##)?.screen
        XCTAssertEqual(look, ScreenLook(topBar: "transparent", tint: "dark", background: "#F7F3EE"))
        XCTAssertEqual(look?.transparent(false), true)
        // missing: the settings decide (home's transparentOnHome), light, the theme's background
        let none = ScreenTemplate.decode(#"{"sections": []}"#)?.screen
        XCTAssertEqual(none, ScreenLook())
        XCTAssertEqual(none?.transparent(true), true)
        XCTAssertEqual(none?.transparent(false), false)
        XCTAssertEqual(ScreenLook(topBar: "solid").transparent(true), false, "solid wins over transparentOnHome")
        // each bad value is its default
        let bad = ScreenTemplate.decode(##"{"screen": {"top_bar": "glass", "top_bar_tint": 3, "background": "#12345"}, "sections": []}"##)?.screen
        XCTAssertEqual(bad, ScreenLook())
        XCTAssertEqual(ScreenTemplate.decode(#"{"screen": "loud", "sections": []}"#)?.screen, ScreenLook())
    }

    func testTheNewerTypesAreKeptWithTheirBlocks() throws {
        let decoded = try XCTUnwrap(ScreenTemplate.decode("""
        {"sections": [
          {"id": "m", "type": "marquee", "settings": {"text": "Free shipping", "speed": "fast"}},
          {"id": "f", "type": "faq", "blocks": [{"id": "q1", "type": "question", "settings": {"question": "Returns?", "answer": "<p>30 days</p>"}}]},
          {"id": "x", "type": "features", "settings": {"layout": "grid"}, "blocks": [{"id": "f1", "type": "feature", "settings": {"icon": "truck"}}, {"id": "f2", "type": "feature", "settings": {"icon": "rocket"}}]},
          {"id": "g", "type": "image_grid", "settings": {"columns": "3", "aspect": "portrait"}, "blocks": [{"id": "t1", "type": "tile", "settings": {"heading": "Men"}}]}
        ]}
        """))
        XCTAssertEqual(decoded.sections.map { $0.type }, ["marquee", "faq", "features", "image_grid"])
        XCTAssertEqual(decoded.sections[1].blocks.map { $0.id }, ["q1"])
        XCTAssertEqual(featureIcon(decoded.sections[2].blocks[0].settings), .truck)
        XCTAssertEqual(featureIcon(decoded.sections[2].blocks[1].settings), .check, "an icon outside the set is check")
        // every feature icon is one of Argon's
        XCTAssertEqual(featureIcons.compactMap { ArgonIconName(rawValue: $0) }.count, featureIcons.count)
        XCTAssertEqual(marqueeSpeed("slow"), 30)
        XCTAssertEqual(marqueeSpeed("medium"), 60)
        XCTAssertEqual(marqueeSpeed("fast"), 90)
        XCTAssertEqual(tileRatio("square"), 1)
        XCTAssertEqual(tileRatio("portrait"), 0.8)
        XCTAssertEqual(tileRatio("landscape"), 4.0 / 3.0)
    }

    func testEverySectionsStyle() throws {
        let decoded = try XCTUnwrap(ScreenTemplate.decode("""
        {"sections": [
          {"id": "a", "type": "rich_text", "settings": {"background": "#ffeedd", "padding": "small"}},
          {"id": "b", "type": "banner", "settings": {"padding": "medium"}},
          {"id": "c", "type": "spacer", "settings": {"padding": "large", "background": "red"}},
          {"id": "d", "type": "products", "settings": {"padding": "huge"}},
          {"id": "e", "type": "marquee"},
          {"id": "f", "type": "marquee", "settings": {"background": "#336699"}}
        ]}
        """))
        XCTAssertEqual(decoded.sections.map { $0.padding }, [12, 24, 40, 0, 0, 0])
        XCTAssertEqual(decoded.sections.map { $0.background }, ["#FFEEDD", nil, nil, nil, "text", "#336699"])
    }

    func testAPageWithoutABodyOpensOnTheWeb() {
        XCTAssertEqual(webPage(StorePage(id: "1", handle: "contact", title: "Contact", body: " "), domain: "shop.test"), .web("https://shop.test/pages/contact"))
        XCTAssertEqual(webPage(StorePage(id: "2", handle: "sections", title: "Sections"), domain: "shop.test"), .web("https://shop.test/pages/sections"))
        XCTAssertNil(webPage(StorePage(id: "3", handle: "about", title: "About", body: "<p>Hello</p>"), domain: "shop.test"))
    }

    // MARK: Main

    func testProductSectionsGoAroundItsBlocksInTheTemplatesOrder() throws {
        let product = try template("product")
        let placement = product.placement("product")
        XCTAssertEqual(placement.above.map { $0.id }, ["promo"])
        XCTAssertEqual(placement.main?.id, "main")
        XCTAssertEqual(placement.below.map { $0.id }, ["fabric"])
        // reviews hidden, teleporter unknown, bundle and rails not listed: after the others, in their own order
        XCTAssertEqual(
            ScreenTemplate.productBlocks(placement.main),
            [.gallery, .title, .price, .options, .purchase, .details, .bundle, .rails]
        )
        XCTAssertEqual(ScreenTemplate.productBlocks(nil), ProductPageBlock.allCases)
        XCTAssertEqual(
            product.metafieldIdentifiers("product"),
            [MetafieldIdentifier(namespace: "custom", key: "fabric"), MetafieldIdentifier(namespace: "custom", key: "care")]
        )
    }

    func testMainPlacement() throws {
        let template = try XCTUnwrap(ScreenTemplate.decode("""
        {"sections": [{"id": "a", "type": "spacer"}, {"id": "main", "type": "main", "settings": {"filters": "bottom"}},
                      {"id": "b", "type": "spacer"}]}
        """))
        XCTAssertEqual(template.placement("cart").above.map { $0.id }, ["a"])
        XCTAssertEqual(template.placement("cart").below.map { $0.id }, ["b"])
        // nothing goes below an endless grid
        XCTAssertEqual(template.placement("collection").above.map { $0.id }, ["a", "b"])
        XCTAssertEqual(template.placement("collection").below, [])
        XCTAssertEqual(template.placement("search").above.map { $0.id }, ["a", "b"])
        XCTAssertEqual(ScreenTemplate.collectionTemplate(template.placement("collection").main), .bottom)
        XCTAssertEqual(template.index(of: template.sections[2]), 2)

        // without main, everything is above
        let noMain = try XCTUnwrap(ScreenTemplate.decode(#"{"sections": [{"id": "a", "type": "spacer"}]}"#))
        XCTAssertEqual(noMain.placement("account"), SectionPlacement(above: noMain.sections))
        XCTAssertNil(ScreenTemplate.collectionTemplate(noMain.placement("collection").main))
    }

    // MARK: Products and collections

    func testOneQueryLoadsEveryProductAndCollection() throws {
        // the two sections of the home share their collection; `picks` is Android's only
        XCTAssertEqual(try template("home").nodeIds, ["gid://shopify/Collection/429493780502"])
        XCTAssertEqual(try template("about").nodeIds, ["gid://shopify/Product/7982904639510", "gid://shopify/Collection/429493780502"])
    }

    @MainActor
    func testAProductsSectionShowsItsProductsElseItsCollections() async throws {
        let nodes = try await StubServer().storefront().sectionNodes(["gid://shopify/Product/7982904639510", "gid://shopify/Collection/429493780502"])
        var byId: [String: Node] = [:]
        for node in nodes {
            if let card = node.productCard { byId[card.id] = node }
            if let card = node.collectionCard { byId[card.id] = node }
        }
        let fromCollection = SectionSettings([
            "collection": .string("gid://shopify/Collection/429493780502"), "products": .array([]), "limit": .int(1),
        ])
        XCTAssertEqual(sectionProducts(fromCollection, nodes: byId).map { $0.handle }, ["hoodie-old"])
        let listed = SectionSettings([
            "collection": .string("gid://shopify/Collection/429493780502"),
            "products": .array([.string("gid://shopify/Product/1"), .string("gid://shopify/Product/7982904639510")]),
        ])
        XCTAssertEqual(sectionProducts(listed, nodes: byId).map { $0.handle }, ["hoodie-old"], "the products that loaded, not the collection's")
    }

    // MARK: Custom section

    func testCustomNodesAreDecodedAndUnknownOnesSkipped() throws {
        let about = try template("about")
        let intro = try section(about, "intro")
        XCTAssertEqual(CustomNode.decode(intro.settings.values["nodes"]), [
            .heading(level: 2, text: "Hello {{ customer.first_name | default: 'there' }}"),
            .paragraph([TextRun(text: "Made in "), TextRun(text: "Italy", bold: true, link: "/pages/about")]),
            .list(ordered: true, items: [[TextRun(text: "One")], [TextRun(text: "Two", italic: true)]]),
            .image(url: "https://cdn.shopify.com/s/files/1/about.jpg", alt: "Workshop", link: nil),
            .button(label: "Shop now", link: "/collections/all"),
            .divider,
            .product("gid://shopify/Product/7982904639510"),
            .collection("gid://shopify/Collection/429493780502", limit: 4),
        ])
        XCTAssertEqual(intro.settings.choice("render", ["native", "web"], "web"), "native")
        XCTAssertEqual(try section(about, "table").settings.number("height", 0, 0...2000), 0)
        // native without nodes is drawn as web
        XCTAssertNil(try section(about, "lost").settings.values["nodes"])
        XCTAssertEqual(CustomNode.decode(nil), [])
        XCTAssertEqual(CustomNode.decode(.array([.object(["type": .string("image")]), .string("x")])), [], "an image needs its url")
    }

    func testTheWebDocumentCarriesTheTheme() {
        let page = customDocument("<p>Hi</p>", accent: "#1F6FEB", text: "#17150F", background: "#F6F4F0")
        XCTAssertTrue(page.contains(#"<meta name="viewport" content="width=device-width, initial-scale=1">"#))
        XCTAssertTrue(page.contains("--accent:#1F6FEB;--text:#17150F;--background:#F6F4F0"))
        XCTAssertTrue(page.contains("body{margin:0;"))
        XCTAssertTrue(page.contains("img{max-width:100%;height:auto}"))
        XCTAssertTrue(page.contains("<body><p>Hi</p></body>"))
    }

    // MARK: Liquid objects

    func testMetafieldValuesAreTextUnlessTheirTypeIsJson() {
        func value(_ type: String, _ text: String) -> JSONValue {
            ScreenContext.metafieldValue(Metafield(namespace: "custom", key: "k", type: type, value: text))
        }
        XCTAssertEqual(value("single_line_text_field", "123"), .string("123"))
        XCTAssertEqual(value("product_reference", "gid://shopify/Product/1"), .string("gid://shopify/Product/1"))
        XCTAssertEqual(value("number_integer", "3"), .int(3))
        XCTAssertEqual(value("number_decimal", "2.5"), .double(2.5))
        XCTAssertEqual(value("boolean", "true"), .bool(true))
        XCTAssertEqual(value("list.single_line_text_field", #"["a","b"]"#), .array([.string("a"), .string("b")]))
        XCTAssertEqual(value("json", #"{"a":1}"#), .object(["a": .int(1)]))
        XCTAssertEqual(value("json", "{broken"), .string("{broken"))
        XCTAssertEqual(
            ScreenContext.metafieldValues([
                Metafield(namespace: "custom", key: "fabric", type: "single_line_text_field", value: "Linen"),
                Metafield(namespace: "specs", key: "count", type: "number_integer", value: "2"),
            ]),
            .object(["custom": .object(["fabric": .string("Linen")]), "specs": .object(["count": .int(2)])])
        )
    }

    @MainActor
    func testAScreensObjects() async throws {
        let api = StubServer().storefront()
        let shop = try await api.shop()
        let product = try await api.product("men-crewneck")
        let cart = try await api.cart("gid://shopify/Cart/c1-4c87091c818643b9a327512a0358dbc4?key=292130afc0a10e41c4b2cbd1a1b0ded3")
        let context = ScreenContext.build(
            shop: shop,
            shopMetafields: [Metafield(namespace: "custom", key: "promo", type: "single_line_text_field", value: "Free shipping")],
            product: product,
            productMetafields: [Metafield(namespace: "custom", key: "fabric", type: "single_line_text_field", value: "Cotton")],
            cart: cart
        )
        let render = { (template: String) in Liquid.render(template, context, timeZone: TimeZone(identifier: "UTC")!) }
        XCTAssertEqual(render("{{ shop.name }} {{ shop.currency }} {{ shop.metafields.custom.promo }}"), "Mock.shop CAD Free shipping")
        XCTAssertEqual(
            render("{{ product.title }}|{{ product.handle }}|{{ product.url }}|{{ product.tags | join: ',' }}|{{ product.available }}"),
            "Men's Crewneck|men-crewneck|/products/men-crewneck|men,tops|true"
        )
        XCTAssertEqual(render("{{ product.price | money }} {{ product.metafields.custom.fabric }}"), "$120.00 Cotton")
        XCTAssertEqual(render("{{ cart.item_count }} {{ cart.total_price }}"), "3 324.0")
        XCTAssertEqual(render("[{{ customer.first_name }}][{{ collection.title }}]"), "[][]", "signed out, and not a collection screen")

        let collection = ScreenContext.build(
            shop: shop,
            collection: (title: "Men", handle: "men", description: "For him"),
            collectionMetafields: [Metafield(namespace: "custom", key: "banner_text", type: "single_line_text_field", value: "40% off")]
        )
        XCTAssertEqual(
            Liquid.render("{{ collection.title }} {{ collection.url }} {{ collection.metafields.custom.banner_text }} {{ cart.item_count }}", collection),
            "Men /collections/men 40% off 0"
        )
    }
}
