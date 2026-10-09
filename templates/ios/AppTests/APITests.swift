import XCTest
@testable import ArgonStorefront

/// `data` decoded the way the facades decode responses.
private func decoded<T: Decodable>(_ type: T.Type, _ data: String) throws -> T {
    try decodeResponse(type, from: Data("{\"data\":\(data)}".utf8), operation: "Test")
}

final class StorefrontContextTests: XCTestCase {
    private let localization = """
    {"country":{"isoCode":"CA","name":"Canada","currency":{"isoCode":"CAD","symbol":"$"}},
     "language":{"isoCode":"EN"},
     "availableCountries":[
       {"isoCode":"CA","name":"Canada","currency":{"isoCode":"CAD","symbol":"$"},
        "availableLanguages":[{"isoCode":"EN"},{"isoCode":"FR"}]},
       {"isoCode":"BR","name":"Brazil","currency":{"isoCode":"BRL","symbol":"R$"},
        "availableLanguages":[{"isoCode":"PT_BR"}]}],
     "availableLanguages":[{"isoCode":"EN"},{"isoCode":"FR"}]}
    """

    private func device(_ identifier: String) throws -> StorefrontContext {
        StorefrontContext.device(try decoded(Localization.self, localization), locale: Locale(identifier: identifier))
    }

    func testTheDeviceCountryAndLanguageWhenTheShopHasThem() throws {
        XCTAssertEqual(try device("fr_CA"), StorefrontContext(country: "CA", language: "FR"))
        XCTAssertEqual(try device("en_CA"), StorefrontContext(country: "CA", language: "EN"), "EN_CA isn't a language; EN is")
        XCTAssertEqual(try device("pt_BR"), StorefrontContext(country: "BR", language: "PT_BR"), "a regional language")
    }

    func testWhatTheShopDoesntHaveIsLeftToItsDefault() throws {
        XCTAssertEqual(try device("de_DE"), StorefrontContext())
        XCTAssertEqual(try device("fr_FR"), StorefrontContext(country: nil, language: "FR"), "no French market, but French")
        XCTAssertEqual(try device("es_CA"), StorefrontContext(country: "CA", language: nil))
    }

    @MainActor
    func testTheContextGoesWithEveryStorefrontOperation() async throws {
        let server = StubServer()
        let api = server.storefront()
        _ = try await api.shop()
        XCTAssertNil(server.calls[0].variables["country"], "no context: the shop's defaults")
        XCTAssertNil(server.calls[0].variables["language"])

        api.context = StorefrontContext(country: "CA", language: "FR")
        _ = try await api.products()
        _ = try await api.cart("gid://shopify/Cart/1")
        for call in server.calls.dropFirst() {
            XCTAssertEqual(call.variables["country"] as? String, "CA", call.name)
            XCTAssertEqual(call.variables["language"] as? String, "FR", call.name)
        }
    }

    @MainActor
    func testShopLocalizationPoliciesAndMenusAreKeptUntilTheContextChanges() async throws {
        let server = StubServer()
        let api = server.storefront()
        for _ in 0..<2 {
            _ = try await api.shop()
            _ = try await api.localization()
            _ = try await api.policies()
            _ = try await api.menu("main-menu")
        }
        XCTAssertEqual(server.names, ["Shop", "Localization", "ShopPolicies", "Menu"])
        _ = try await api.menu("footer")
        XCTAssertEqual(server.names.last, "Menu", "menus are kept per handle")

        api.context = StorefrontContext()
        _ = try await api.shop()
        XCTAssertEqual(server.names.count, 5, "the same context keeps them")
        api.context = StorefrontContext(country: "CA")
        _ = try await api.shop()
        XCTAssertEqual(server.names.count, 6, "a new context fetches again")
    }

    @MainActor
    func testProductsAreNotKept() async throws {
        let server = StubServer()
        let api = server.storefront()
        _ = try await api.product("men-crewneck")
        _ = try await api.product("men-crewneck")
        XCTAssertEqual(server.names, ["Product", "Product"])
    }
}

final class APIErrorTests: XCTestCase {
    @MainActor
    private func failure<T>(_ body: String, _ call: (StorefrontAPI) async throws -> T) async -> ArgonAPIError? {
        let api = StubServer(reply: { _, _ in body }).storefront()
        return await thrownError { try await call(api) } as? ArgonAPIError
    }

    @MainActor
    func testGraphqlErrorsAreThrownEvenWithData() async {
        let error = await failure(#"{"errors":[{"message":"Throttled"},{}],"data":{"shop":null}}"#) { try await $0.shop() }
        guard case let .graphql(messages)? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(messages, ["Throttled", "Unknown error"])
        XCTAssertEqual(error?.localizedDescription, "Throttled\nUnknown error")
    }

    @MainActor
    func testAResponseOfAnotherShapeIsADecodingErrorNamingWhere() async {
        let error = await failure(#"{"data":{"shop":{"name":1}}}"#) { try await $0.shop() }
        guard case let .decoding(operation, detail)? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(operation, "Shop")
        XCTAssertTrue(detail.contains("shop"), detail)
        XCTAssertEqual(error?.localizedDescription, "Invalid response")
    }

    @MainActor
    func testNoDataOrNotJsonIsADecodingError() async {
        for body in ["<html>", "[1,2]", #"{"data":null}"#, #"{"data":{}}"#] {
            let error = await failure(body) { try await $0.shop() }
            guard case .decoding? = error else { return XCTFail("\(body): \(String(describing: error))") }
        }
    }

    @MainActor
    func testCartUserErrorsAreThrownWithTheirCodes() async throws {
        let userErrors: [[String: Any]] = [
            ["field": ["lines", "0", "merchandiseId"], "message": "The merchandise does not exist", "code": "INVALID"],
        ]
        let payload: [String: Any] = ["cart": NSNull(), "userErrors": userErrors, "warnings": [Any]()]
        let body = try responseBody(["cartLinesAdd": payload])
        let error = await failure(body) { try await $0.addLines(cartId: "c", lines: [CartLineInput(merchandiseId: "bad")]) }
        guard case let .userErrors(errors)? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(errors, [UserError(field: ["lines", "0", "merchandiseId"], code: "INVALID", message: "The merchandise does not exist")])
        XCTAssertEqual(error?.localizedDescription, "The merchandise does not exist")
    }

    @MainActor
    func testUserErrorsBesideACartAreThrownAndWarningsComeBackWithIt() async throws {
        var payload = try XCTUnwrap(try fixture("CartDiscountCodesUpdate")["cartDiscountCodesUpdate"] as? [String: Any])
        let userErrors: [[String: Any]] = [["message": "Discount codes are limited", "code": NSNull()]]
        payload["userErrors"] = userErrors
        let refused = try responseBody(["cartDiscountCodesUpdate": payload])
        let error = await failure(refused) { try await $0.updateDiscountCodes(cartId: "c", codes: []) }
        guard case let .userErrors(errors)? = error else { return XCTFail("a user error is thrown even beside a cart") }
        XCTAssertNil(errors.first?.code, "the code may be null")

        let result = try await StubServer().storefront().updateDiscountCodes(cartId: "c", codes: ["WELCOME10"])
        XCTAssertEqual(result.warnings, [
            CartWarning(
                code: "DISCOUNT_NOT_FOUND",
                message: "Enter a valid discount code",
                target: "gid://shopify/Cart/c1-7469366f149b403dafd17bc5a9dab879?key=9c19aa7d7298298cf1b25c5af5542807"
            ),
        ])
    }
}

final class PageTests: XCTestCase {
    @MainActor
    func testTheCursorGoesOutAsAfterAndComesBackAsEndCursor() async throws {
        let server = StubServer()
        let api = server.storefront()
        let first = try await api.products()
        XCTAssertNil(server.calls[0].variables["after"], "the first page has no cursor")
        XCTAssertEqual(server.calls[0].variables["first"] as? Int, 24)
        XCTAssertTrue(first.hasNextPage)
        _ = try await api.products(after: first.endCursor)
        XCTAssertEqual(server.calls[1].variables["after"] as? String, first.endCursor)
    }

    @MainActor
    func testListingVariablesCarrySortAndFilters() async throws {
        let server = StubServer()
        let api = server.storefront()
        _ = try await api.collection("men", filters: [#"{"available":true}"#, "not json"], sortKey: "PRICE", reverse: true)
        let variables = server.calls[0].variables
        XCTAssertEqual(variables["handle"] as? String, "men")
        XCTAssertEqual(variables["sortKey"] as? String, "PRICE")
        XCTAssertEqual(variables["reverse"] as? Bool, true)
        let filters = try XCTUnwrap(variables["filters"] as? [[String: Any]])
        XCTAssertEqual(filters.count, 1, "an unreadable filter is skipped")
        XCTAssertEqual(filters.first?["available"] as? Bool, true)

        _ = try await api.search("hat")
        let search = server.calls[1].variables
        XCTAssertEqual(search["query"] as? String, "hat")
        XCTAssertNil(search["filters"], "no filters key when none are applied")
        XCTAssertNil(search["sortKey"], "no sort key: the document's default")
        XCTAssertEqual(search["reverse"] as? Bool, false)
    }

    func testAPageDecodesItsConnection() throws {
        let page = try decoded(
            [String: Page<StorePage>].self,
            #"{"pages":{"pageInfo":{"hasNextPage":true,"endCursor":"c2"},"nodes":[{"id":"1","handle":"a","title":"A"}]}}"#
        )["pages"]
        XCTAssertEqual(page, Page(items: [StorePage(id: "1", handle: "a", title: "A")], endCursor: "c2", hasNextPage: true))
        let last = try decoded([String: Page<StorePage>].self, #"{"p":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}"#)["p"]
        XCTAssertEqual(last, Page(items: [], endCursor: nil, hasNextPage: false))
    }
}

final class PolymorphicDecodingTests: XCTestCase {
    private let image = #"{"url":"https://cdn.test/a.jpg","altText":"A","width":10,"height":20}"#
    private let card = """
    {"__typename":"Product","id":"p1","handle":"tee","title":"Tee","availableForSale":true,"featuredImage":null,
     "priceRange":{"minVariantPrice":{"amount":"40.0","currencyCode":"USD"}},
     "compareAtPriceRange":{"minVariantPrice":{"amount":"50.0","currencyCode":"USD"}}}
    """

    func testMediaOfEachType() throws {
        let media = try decoded([Media].self, """
        [{"__typename":"MediaImage","id":"1","mediaContentType":"IMAGE","alt":"A","previewImage":\(image),"image":\(image)},
         {"__typename":"Video","id":"2","mediaContentType":"VIDEO","alt":null,"previewImage":null,
          "sources":[{"url":"https://cdn.test/v.mp4","mimeType":"video/mp4","format":"mp4","width":640,"height":360}]},
         {"__typename":"ExternalVideo","id":"3","mediaContentType":"EXTERNAL_VIDEO","alt":null,"previewImage":null,
          "host":"YOUTUBE","embedUrl":"https://www.youtube.com/embed/x","originUrl":"https://youtu.be/x"},
         {"__typename":"Model3d","id":"4","mediaContentType":"MODEL_3D","alt":null,"previewImage":\(image),
          "sources":[{"url":"https://cdn.test/m.glb","mimeType":"model/gltf-binary","format":"glb","filesize":1024}]},
         {"__typename":"Hologram","id":"5","mediaContentType":"HOLOGRAM","alt":null,"previewImage":null}]
        """)
        let img = Img(url: "https://cdn.test/a.jpg", alt: "A", width: 10, height: 20)
        XCTAssertEqual(media.map { $0.content }, [
            .image(img),
            .video([MediaSource(url: "https://cdn.test/v.mp4", mimeType: "video/mp4", format: "mp4", width: 640, height: 360)]),
            .externalVideo(host: "YOUTUBE", embedUrl: "https://www.youtube.com/embed/x", originUrl: "https://youtu.be/x"),
            .model3d([MediaSource(url: "https://cdn.test/m.glb", mimeType: "model/gltf-binary", format: "glb", filesize: 1024)]),
            .other("Hologram"),
        ])
        XCTAssertEqual(media[3].previewImage, img)
    }

    func testMenuResources() throws {
        let resources = try decoded([MenuResource?].self, """
        [{"__typename":"Collection","handle":"men"},{"__typename":"Product","handle":"tee"},{"__typename":"Page","handle":"about"},
         {"__typename":"Blog","handle":"news"},{"__typename":"ShopPolicy","handle":"refund-policy"},
         {"__typename":"Article","handle":"hello","blog":{"handle":"news"}},
         {"__typename":"Metaobject","handle":"summer","type":"lookbook"},{"__typename":"CustomerAccountPage"},null]
        """)
        XCTAssertEqual(resources, [
            .collection(handle: "men"), .product(handle: "tee"), .page(handle: "about"), .blog(handle: "news"),
            .shopPolicy(handle: "refund-policy"), .article(handle: "hello", blogHandle: "news"),
            .metaobject(handle: "summer", type: "lookbook"), .other("CustomerAccountPage"), nil,
        ])
    }

    func testMenuItemsRouteThroughTheirResourceElseTheirUrl() throws {
        let menu = try decoded(StoreMenu.self, """
        {"id":"m","handle":"main-menu","title":"Main","items":[
          {"id":"1","title":"Tee","url":"https://other.test/x","type":"PRODUCT","resourceId":"p","resource":{"__typename":"Product","handle":"tee"},"items":[]},
          {"id":"2","title":"Shop","url":"#","type":"HTTP","resourceId":null,"resource":null,"items":[
            {"id":"3","title":"Sale","url":"/collections/sale","type":"COLLECTION","resourceId":null,"resource":null}]},
          {"id":"4","title":"Nowhere","url":"mailto:a@b.test","type":"HTTP","resourceId":null,"resource":null,"items":[]}]}
        """)
        XCTAssertEqual(menu.items[1].items.first?.items, [], "the third level has no items of its own")
        XCTAssertEqual(Links.menu(menu.items, hosts: ["shop.test"]), [
            MenuItem(title: "Tee", route: .product("tee"), children: []),
            MenuItem(title: "Shop", route: .web("#"), children: [MenuItem(title: "Sale", route: .collection("sale"), children: [])]),
        ])
    }

    @MainActor
    func testSearchResultsOfEachType() async throws {
        let body = """
        {"data":{"search":{"totalCount":4,"productFilters":[],"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
          \(card),
          {"__typename":"Page","id":"g1","handle":"about","title":"About"},
          {"__typename":"Article","id":"a1","handle":"hello","title":"Hello","excerpt":null,"publishedAt":"2026-10-01T00:00:00Z",
           "image":null,"authorV2":null,"blog":{"handle":"news"}},
          {"__typename":"Collection"}]}}}
        """
        let results = try await StubServer(reply: { _, _ in body }).storefront().search("a", types: ["PRODUCT", "PAGE", "ARTICLE"])
        let kinds: [String] = results.results.items.map { node in
            switch node {
            case .product: return "product"
            case .page: return "page"
            case let .article(article): return "article in \(article.blogHandle)"
            case let .other(typename): return typename
            default: return "?"
            }
        }
        XCTAssertEqual(kinds, ["product", "page", "article in news", "Collection"])
        XCTAssertEqual(results.products.first?.compareAt, Money(amount: "50.0", currencyCode: "USD"), "a higher compare-at is kept")
    }

    @MainActor
    func testNodesKeepOnlyTheProductsThatCameBack() async throws {
        let body = #"{"data":{"nodes":[null,{"__typename":"Collection"},"# + card + "]}}"
        let server = StubServer(reply: { _, _ in body })
        let cards = try await server.storefront().products(ids: ["gone", "c", "p1"])
        XCTAssertEqual(cards.map { $0.id }, ["p1"])
    }

    @MainActor
    func testBrokenOrUnknownHomeSectionsAreSkipped() async throws {
        let body = """
        {"data":{"metaobject":{"field":{"references":{"nodes":[
          {"__typename":"Metaobject"},
          {"__typename":"Page"},
          {"__typename":"Metaobject","id":"s1","type":"mobile_unknown","fields":[]},
          {"__typename":"Metaobject","id":"s2","type":"mobile_products","fields":[
            {"key":"products","value":"[]","reference":null,"references":{"nodes":[{"__typename":"Product"},\(card)]}},
            {"key":"collection","value":null,"reference":null,"references":null}]},
          {"__typename":"Metaobject","id":"s3","type":"mobile_collections","fields":[
            {"key":"collections","value":"[]","reference":null,"references":{"nodes":[]}}]}]}}}}}
        """
        let nodes = try await StubServer(reply: { _, _ in body }).storefront().homeScreen("home")
        XCTAssertEqual(nodes.map { $0.id }, ["s1", "s2", "s3"], "nodes without fields are dropped")
        let sections = Sections.fromHome(nodes)
        XCTAssertEqual(sections.count, 1, "unknown types and empty sections are skipped")
        guard case let .products(_, style, items)? = sections.first else { return XCTFail("not products") }
        XCTAssertEqual(style, "carousel")
        XCTAssertEqual(items.map { $0.id }, ["p1"], "a broken product reference is skipped")
    }

    func testOrderDiscountValues() throws {
        let values = try decoded([DiscountValue].self, """
        [{"__typename":"MoneyV2","amount":"5.0","currencyCode":"CAD"},{"__typename":"PricingPercentageValue","percentage":12.5},
         {"__typename":"FutureValue"}]
        """)
        XCTAssertEqual(values, [.amount(Money(amount: "5.0", currencyCode: "CAD")), .percentage(12.5), .other("FutureValue")])
    }

    func testCartLinesOfOtherMerchandiseAreLeftOut() throws {
        var cart = try XCTUnwrap(try fixture("Cart")["cart"] as? [String: Any])
        var lines = try XCTUnwrap((cart["lines"] as? [String: Any])?["nodes"] as? [[String: Any]])
        lines.append(["__typename": "CartLine", "id": "gid://shopify/CartLine/2", "quantity": 1, "merchandise": ["__typename": "GiftCard"]])
        cart["lines"] = ["nodes": lines]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: cart), as: UTF8.self)
        XCTAssertEqual(try decoded(Cart.self, text).lines.map { $0.id }, ["gid://shopify/CartLine/49959"])
    }
}
