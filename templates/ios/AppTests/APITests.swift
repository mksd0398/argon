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

        // the shop's countries and languages, to pick a context from, are asked for without one
        _ = try await api.localization()
        XCTAssertEqual(server.names.last, "Localization")
        XCTAssertNil(server.calls.last?.variables["country"])
        XCTAssertNil(server.calls.last?.variables["language"])
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
    func testTheBuyerGoesWithEveryStorefrontOperationAndForgetsWhatWasKept() async throws {
        let server = StubServer()
        let api = server.storefront()
        _ = try await api.shop()
        XCTAssertNil(server.calls[0].variables["buyer"], "no buyer: a retail shopper")

        let buyer = Buyer(customerAccessToken: "tok", companyLocationId: "gid://shopify/CompanyLocation/1")
        api.buyer = buyer
        _ = try await api.shop()
        _ = try await api.products()
        _ = try await api.cart("gid://shopify/Cart/1")
        XCTAssertEqual(server.names, ["Shop", "Shop", "Catalog", "Cart"], "the shop kept for a retail shopper isn't the buyer's")
        for call in server.calls.dropFirst() {
            XCTAssertEqual(
                call.variables["buyer"] as? [String: String],
                ["customerAccessToken": "tok", "companyLocationId": "gid://shopify/CompanyLocation/1"],
                call.name
            )
        }

        api.buyer = buyer
        _ = try await api.shop()
        XCTAssertEqual(server.names.count, 4, "the same buyer keeps what was kept")

        api.buyer = Buyer(customerAccessToken: "tok")
        _ = try await api.shop()
        XCTAssertEqual(server.calls.last?.variables["buyer"] as? [String: String], ["customerAccessToken": "tok"], "no location: left out")
        api.buyer = nil
        _ = try await api.shop()
        XCTAssertEqual(server.names.count, 6)
        XCTAssertNil(server.calls.last?.variables["buyer"])
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

    // MARK: Fields the token may not read (ACCESS_DENIED)

    /// `data` beside `errors`, decoded the way the facades decode responses.
    private func answer(_ data: String, errors: String...) throws -> [String: Int?] {
        let body = "{\"data\":\(data),\"errors\":[\(errors.joined(separator: ","))]}"
        return try decodeResponse([String: Int?].self, from: Data(body.utf8), operation: "Test")
    }

    /// An ACCESS_DENIED error about the field at `path` (JSON array items).
    private func denied(_ path: String, _ message: String = "Access denied for a field.") -> String {
        "{\"message\":\"\(message)\",\"path\":[\(path)],\"extensions\":{\"code\":\"ACCESS_DENIED\"}}"
    }

    /// The messages of the ArgonAPIError.graphql `body` throws; nil when it throws anything else, or nothing.
    private func refusal(_ body: () throws -> [String: Int?]) -> [String]? {
        do {
            _ = try body()
            return nil
        } catch ArgonAPIError.graphql(let messages) {
            return messages
        } catch {
            return nil
        }
    }

    func testDeniedFieldsUnderRootsThatCameBackLeaveTheDataUsable() throws {
        let one = try answer(#"{"product":1,"shop":null}"#, errors: denied(#""product","variants","nodes",0,"quantityAvailable""#))
        XCTAssertEqual(one, ["product": 1, "shop": nil], "a null root nobody was denied doesn't matter")
        let several = try answer(
            #"{"products":3,"collection":7}"#,
            errors: denied(#""products","nodes",0,"rating""#), denied(#""products","nodes",1,"rating""#), denied(#""collection","metafield""#)
        )
        XCTAssertEqual(several, ["products": 3, "collection": 7])
    }

    func testADeniedRootFieldIsStillRefused() {
        // the home screen's metaobject without metaobject access: nothing to show, so the fallback home takes over
        XCTAssertEqual(
            refusal { try answer(#"{"metaobject":null}"#, errors: denied(#""metaobject""#, "Access denied for metaobject field.")) },
            ["Access denied for metaobject field."]
        )
        // a denied non-null field takes its whole root with it
        XCTAssertEqual(
            refusal { try answer(#"{"product":null,"shop":1}"#, errors: denied(#""product","metafields""#)) },
            ["Access denied for a field."]
        )
    }

    func testAccessDeniedBesideAnyOtherErrorIsRefused() {
        XCTAssertEqual(
            refusal { try answer(#"{"product":1}"#, errors: denied(#""product","rating""#), #"{"message":"Throttled","extensions":{"code":"THROTTLED"}}"#) },
            ["Access denied for a field.", "Throttled"]
        )
        XCTAssertEqual(refusal { try answer(#"{"product":1}"#, errors: #"{"message":"Internal error"}"#) }, ["Internal error"])
    }

    func testAccessDeniedThatCantBePlacedIsRefused() {
        let noPath = #"{"message":"Access denied","extensions":{"code":"ACCESS_DENIED"}}"#
        XCTAssertEqual(refusal { try answer(#"{"product":1}"#, errors: noPath) }, ["Access denied"])
        XCTAssertEqual(refusal { try answer(#"{"product":1}"#, errors: denied("0")) }, ["Access denied for a field."], "a path that starts with no field")
        XCTAssertEqual(refusal { try answer(#"{"product":1}"#, errors: denied(#""shop","name""#)) }, ["Access denied for a field."], "a root that isn't in the data")
        XCTAssertEqual(refusal { try answer("null", errors: denied(#""product","rating""#)) }, ["Access denied for a field."], "no data at all")
    }

    @MainActor
    func testAVariantWhoseStockTheTokenMayNotReadStillLoads() async throws {
        var data = try fixture("VariantBySelectedOptions")
        var product = try XCTUnwrap(data["product"] as? [String: Any])
        var variant = try XCTUnwrap(product["variantBySelectedOptions"] as? [String: Any])
        variant["quantityAvailable"] = NSNull()
        product["variantBySelectedOptions"] = variant
        data["product"] = product
        let error: [String: Any] = [
            "message": "Access denied for quantityAvailable field. Required access: `unauthenticated_read_product_inventory` access scope.",
            "path": ["product", "variantBySelectedOptions", "quantityAvailable"],
            "extensions": ["code": "ACCESS_DENIED"],
        ]
        let body = String(decoding: try JSONSerialization.data(withJSONObject: ["data": data, "errors": [error]]), as: UTF8.self)
        let api = StubServer(reply: { _, _ in body }).storefront()
        let found = try await api.variantBySelectedOptions(productHandle: "men-crewneck", options: ["Size": "Small", "Color": "Olive"])
        XCTAssertEqual(found?.title, "Small / Olive")
        XCTAssertNil(found?.quantityAvailable, "no stock count, not a broken page")
        XCTAssertEqual(found?.quantityRule?.min, 2)
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
        guard case let .userErrors(errors, cart)? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertNil(cart, "none came back")
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
        guard case let .userErrors(errors, cart)? = error else { return XCTFail("a user error is thrown even beside a cart") }
        XCTAssertNil(errors.first?.code, "the code may be null")
        XCTAssertEqual(cart?.totalQuantity, 3, "the cart that came back beside the errors comes with them")
        XCTAssertEqual(cart?.warnings.count, 1)

        let updated = try await StubServer().storefront().updateDiscountCodes(cartId: "c", codes: ["WELCOME10"])
        XCTAssertEqual(updated.warnings, [
            CartWarning(
                code: "DISCOUNT_NOT_FOUND",
                message: "Enter a valid discount code",
                target: "gid://shopify/Cart/c1-4c87091c818643b9a327512a0358dbc4?key=292130afc0a10e41c4b2cbd1a1b0ded3"
            ),
        ])
    }

    @MainActor
    func testAMutationAnsweredWithNeitherCartNorErrorsSaysTheCartIsUnavailable() async throws {
        let payload: [String: Any] = ["cart": NSNull(), "userErrors": [Any](), "warnings": [Any]()]
        let body = try responseBody(["cartNoteUpdate": payload])
        let error = await failure(body) { try await $0.updateNote(cartId: "c", note: "") }
        guard case let .userErrors(errors, cart)? = error else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(errors.map { $0.message }, ["The cart is unavailable"])
        XCTAssertNil(cart)
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

    func testCollectionAndSearchFacetsComeWithThePage() throws {
        let filter = #"{"id":"f","label":"Color","type":"LIST","values":[{"id":"v","label":"Red","count":2,"input":"{\"available\":true}"}]}"#
        let products = try decoded(Page<ProductCard>.self, #"{"filters":["# + filter + #"],"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}"#)
        let search = try decoded(Page<Node>.self, #"{"productFilters":["# + filter + #"],"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}"#)
        XCTAssertEqual(products.filters.first?.values.first?.input, #"{"available":true}"#)
        XCTAssertEqual(search.filters, products.filters)
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
        let kinds: [String] = results.items.map { node in
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
        let cards = try await server.storefront().productsByIds(["gone", "c", "p1"])
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
        XCTAssertEqual(try decoded(Cart.self, text).lines.map { $0.id }, ["gid://shopify/CartLine/54972"])
    }

    func testACartLineOnASellingPlanAndABundlesParts() throws {
        var cart = try XCTUnwrap(try fixture("Cart")["cart"] as? [String: Any])
        var lines = try XCTUnwrap((cart["lines"] as? [String: Any])?["nodes"] as? [[String: Any]])
        let image: [String: Any] = ["url": "https://cdn.test/tee.jpg", "altText": NSNull(), "width": 10, "height": 10]
        let tee: [String: Any] = [
            "__typename": "ProductVariant", "id": "v-tee", "title": "Small", "image": image,
            "product": ["handle": "tee", "title": "Tee"],
        ]
        lines[0]["__typename"] = "ComponentizableCartLine"
        lines[0]["sellingPlanAllocation"] = ["sellingPlan": ["id": "gid://shopify/SellingPlan/1", "name": "Deliver every month"]]
        lines[0]["lineComponents"] = [
            ["id": "gid://shopify/CartLine/part-1", "quantity": 2, "merchandise": tee],
            ["id": "gid://shopify/CartLine/part-2", "quantity": 1, "merchandise": ["__typename": "GiftCard"]],
        ]
        cart["lines"] = ["nodes": lines]
        cart["buyerIdentity"] = [
            "email": NSNull(), "phone": NSNull(), "countryCode": "CA",
            "purchasingCompany": ["company": ["id": "c1", "name": "Analytical Engines Ltd"], "location": ["id": "l1", "name": "Ottawa head office"]],
        ]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: cart), as: UTF8.self)
        let decodedCart = try decoded(Cart.self, text)
        let line = try XCTUnwrap(decodedCart.lines.first)
        XCTAssertEqual(line.sellingPlanName, "Deliver every month")
        XCTAssertEqual(line.components, [
            CartLineComponent(
                id: "gid://shopify/CartLine/part-1", quantity: 2, variantId: "v-tee", variantTitle: "Small",
                productHandle: "tee", productTitle: "Tee", image: Img(url: "https://cdn.test/tee.jpg", alt: nil, width: 10, height: 10)
            ),
        ], "a part that isn't a variant is left out")
        XCTAssertEqual(
            decodedCart.purchasingCompany,
            PurchasingCompany(company: Company(id: "c1", name: "Analytical Engines Ltd"), location: CompanyLocation(id: "l1", name: "Ottawa head office"))
        )
    }
}
