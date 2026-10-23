import XCTest
@testable import ArgonStorefront

/// Every contract fixture decoded through its facade method (the transport answers with the fixture), with key fields checked.
final class FixtureTests: XCTestCase {
    private static let cartId = "gid://shopify/Cart/c1-4c87091c818643b9a327512a0358dbc4?key=292130afc0a10e41c4b2cbd1a1b0ded3"
    private static let covered: Set<String> = [
        "Shop", "Localization", "ShopPolicies", "Menu", "Product", "ProductMetafields", "VariantBySelectedOptions", "Catalog",
        "Products", "ProductRecommendations", "Collection", "Collections", "Search", "PredictiveSearch", "StoreAvailability",
        "Locations", "Page", "Pages", "Blogs", "Blog", "Article", "Articles", "Metaobject", "Metaobjects", "HomeScreen",
        "FallbackHome", "AppScreen", "SectionNodes", "CollectionMetafields", "ShopMetafields",
        "Cart", "CartCreate", "CartLinesAdd", "CartLinesUpdate", "CartLinesRemove", "CartBuyerIdentityUpdate",
        "CartDiscountCodesUpdate", "CartGiftCardCodesAdd", "CartGiftCardCodesRemove", "CartNoteUpdate", "CartAttributesUpdate",
        "CartDeliveryAddressesAdd", "CartDeliveryAddressesUpdate", "CartDeliveryAddressesRemove",
        "CartSelectedDeliveryOptionsUpdate",
        "Customer", "Orders", "Order", "CustomerAddresses", "CustomerUpdate", "CustomerAddressCreate", "CustomerAddressUpdate",
        "CustomerAddressDelete", "CustomerEmailMarketingSubscribe", "CustomerEmailMarketingUnsubscribe", "OrderReturnOptions",
        "OrderRequestReturn", "CustomerCompanies", "CustomerStoreCredit",
    ]

    func testEveryFixtureHasADecodingTest() {
        let names = fixtureNames()
        XCTAssertFalse(names.isEmpty, "no fixtures in the test bundle")
        XCTAssertEqual(names.subtracting(Self.covered), [], "fixtures without a decoding test")
        XCTAssertEqual(Self.covered.subtracting(names), [], "tests without a fixture")
    }

    // MARK: Shop

    @MainActor
    func testShop() async throws {
        let shop = try await StubServer().storefront().shop()
        XCTAssertEqual(shop.name, "Mock.shop")
        XCTAssertEqual(shop.moneyFormat, "${{amount}}")
        XCTAssertEqual(shop.primaryDomain.host, "demostore.hydrogen.mock.shop")
        XCTAssertNotNil(shop.brand?.logo)
        XCTAssertNil(shop.brand?.coverImage)
        XCTAssertEqual(shop.brand?.primaryColors, [])
        XCTAssertEqual(shop.paymentSettings.currencyCode, "CAD")
        XCTAssertEqual(Brand(shop: shop, configDomain: "mock.shop").hosts, ["mock.shop", "demostore.hydrogen.mock.shop"])
    }

    @MainActor
    func testLocalization() async throws {
        let localization = try await StubServer().storefront().localization()
        XCTAssertEqual(localization.country.isoCode, "CA")
        XCTAssertEqual(localization.country.currency.isoCode, "CAD")
        XCTAssertEqual(localization.language.isoCode, "EN")
        XCTAssertEqual(localization.availableCountries.map { $0.isoCode }, ["CA"])
        XCTAssertEqual(localization.availableCountries.first?.availableLanguages?.map { $0.isoCode }, ["EN"])
        XCTAssertEqual(localization.availableLanguages.map { $0.isoCode }, ["EN"])
    }

    @MainActor
    func testShopPolicies() async throws {
        let policies = try await StubServer().storefront().policies()
        XCTAssertEqual(policies.privacyPolicy?.handle, "privacy-policy")
        XCTAssertEqual(policies.refundPolicy?.title, "Refund Policy")
        XCTAssertNil(policies.termsOfSale)
        XCTAssertEqual(policies.subscriptionPolicy?.handle, "subscription-policy")
        XCTAssertNil(policies.subscriptionPolicy?.id, "the subscription policy has no id")
        XCTAssertEqual(
            policies.all.map { $0.handle },
            ["privacy-policy", "terms-of-service", "refund-policy", "shipping-policy", "subscription-policy"]
        )
        XCTAssertEqual(policies.policy("shipping-policy")?.title, "Shipping Policy")
        XCTAssertNil(policies.policy("legal-notice"), "the shop has none")
    }

    @MainActor
    func testMenu() async throws {
        let server = StubServer()
        let found = try await server.storefront().menu("main-menu")
        let menu = try XCTUnwrap(found)
        XCTAssertEqual(server.calls.first?.variables["handle"] as? String, "main-menu")
        XCTAssertEqual(menu.handle, "main-menu")
        XCTAssertEqual(menu.items.map { $0.title }, ["Men", "Women", "Unisex"])
        XCTAssertNil(menu.items[0].resource, "mock.shop links collections by URL only")
        XCTAssertEqual(menu.items[0].type, "COLLECTION")
        let routes = Links.menu(menu.items, hosts: ["mock.shop", "demostore.hydrogen.mock.shop"])
        XCTAssertEqual(routes.first, MenuItem(title: "Men", route: .collection("men"), children: []))
    }

    // MARK: Products

    @MainActor
    func testProduct() async throws {
        let server = StubServer()
        let found = try await server.storefront().product("men-crewneck")
        let product = try XCTUnwrap(found)
        XCTAssertEqual(server.calls.first?.variables["handle"] as? String, "men-crewneck")
        XCTAssertNil(server.calls.first?.variables["metafields"], "metafields are asked for apart (ProductMetafields)")
        XCTAssertEqual(product.handle, "men-crewneck")
        XCTAssertEqual(product.vendor, "Mock.shop")
        XCTAssertTrue(product.available)
        XCTAssertEqual(product.options.map { $0.name }, ["Size", "Color"])
        XCTAssertEqual(product.options[0].optionValues.map { $0.name }, ["Small", "Medium", "Large"])
        XCTAssertEqual(product.options[1].optionValues[1].firstSelectableVariant?.title, "Small / Olive")
        XCTAssertEqual(product.variants.count, 3)
        XCTAssertEqual(product.variants.first?.options, ["Size": "Small", "Color": "Green"])
        XCTAssertNil(product.variants.first?.compareAt)
        XCTAssertEqual(product.selectedOrFirstAvailableVariant?.id, "gid://shopify/ProductVariant/43696905224214")
        XCTAssertEqual(product.adjacentVariants.count, 3)
        XCTAssertEqual(product.media.count, 3)
        XCTAssertEqual(product.images.count, 3, "every media item is an image")
        XCTAssertEqual(product.priceRange.minVariantPrice, Money(amount: "120.0", currencyCode: "CAD"))
        XCTAssertNotNil(product.options[0].id, "a product's options have ids (a card's don't)")
        XCTAssertFalse(product.requiresSellingPlan)
        XCTAssertEqual(product.tags, ["men", "tops"])
        XCTAssertNil(product.onlineStoreUrl, "not published to an online store")
        XCTAssertNil(product.rating, "mock.shop has no reviews")
        XCTAssertNil(product.ratingCount)
        XCTAssertNil(product.variants.first?.quantityRule, "the selected variant's details come with variantBySelectedOptions")
        XCTAssertEqual(product.variants.first?.sellingPlanAllocations, [])
    }

    @MainActor
    func testProductMetafields() async throws {
        let server = StubServer()
        let api = server.storefront()
        let identifiers = [MetafieldIdentifier(namespace: "custom", key: "material"), MetafieldIdentifier(namespace: "custom", key: "care")]
        let metafields = try await api.productMetafields(handle: "men-crewneck", identifiers: identifiers)
        XCTAssertEqual(
            metafields,
            [Metafield(namespace: "custom", key: "material", type: "single_line_text_field", value: "100% organic cotton")],
            "the one the product has no value for comes back null and is left out"
        )
        XCTAssertEqual(server.calls.first?.variables["handle"] as? String, "men-crewneck")
        let sent = server.calls.first?.variables["metafields"] as? [[String: String]]
        XCTAssertEqual(sent, [["namespace": "custom", "key": "material"], ["namespace": "custom", "key": "care"]])

        let none = try await api.productMetafields(handle: "men-crewneck", identifiers: [])
        XCTAssertEqual(none, [])
        XCTAssertEqual(server.names, ["ProductMetafields"], "nothing to ask for: no request")
    }

    @MainActor
    func testVariantBySelectedOptions() async throws {
        let server = StubServer()
        let found = try await server.storefront().variantBySelectedOptions(
            productHandle: "men-crewneck",
            options: ["Size": "Small", "Color": "Olive"]
        )
        let variant = try XCTUnwrap(found)
        XCTAssertEqual(variant.title, "Small / Olive")
        XCTAssertEqual(variant.options, ["Size": "Small", "Color": "Olive"])
        XCTAssertEqual(variant.sku, "CREW-S-OLV")
        XCTAssertEqual(variant.price, Money(amount: "120.0", currencyCode: "CAD"))
        let sent = server.calls.first?.variables["selectedOptions"] as? [[String: String]]
        XCTAssertEqual(sent, [["name": "Color", "value": "Olive"], ["name": "Size", "value": "Small"]])

        // the selected variant in full
        XCTAssertEqual(variant.barcode, "0123456789012")
        XCTAssertEqual(variant.quantityAvailable, 4)
        XCTAssertFalse(variant.currentlyNotInStock)
        XCTAssertEqual(variant.unitPrice, Money(amount: "60.0", currencyCode: "CAD"))
        XCTAssertEqual(
            variant.unitPriceMeasurement,
            UnitPriceMeasurement(measuredType: "COUNT", quantityUnit: "ITEM", quantityValue: 2, referenceUnit: "ITEM", referenceValue: 1)
        )
        XCTAssertEqual(variant.quantityRule, QuantityRule(minimum: 2, maximum: 40, increment: 2))
        XCTAssertEqual(variant.quantityPriceBreaks, [
            QuantityPriceBreak(minimumQuantity: 10, price: Money(amount: "108.0", currencyCode: "CAD")),
            QuantityPriceBreak(minimumQuantity: 20, price: Money(amount: "96.0", currencyCode: "CAD")),
        ])
        XCTAssertTrue(variant.requiresComponents)
        XCTAssertEqual(variant.components.map { $0.quantity }, [1, 1])
        let part = try XCTUnwrap(variant.components.first?.variant)
        XCTAssertEqual(part.id, "gid://shopify/ProductVariant/43696932126742")
        XCTAssertEqual(part.title, "Small / Olive")
        XCTAssertEqual(part.price, Money(amount: "40.0", currencyCode: "CAD"))
        XCTAssertEqual(part.product, ProductRef(handle: "men-t-shirt", title: "Men's T-shirt"))
        XCTAssertNotNil(part.image)
        let bundle = try XCTUnwrap(variant.groupedBy.first)
        XCTAssertEqual(variant.groupedBy.count, 1)
        XCTAssertEqual(bundle.id, "gid://shopify/ProductVariant/43696903847958")
        XCTAssertEqual(bundle.title, "Weekend set")
        XCTAssertEqual(bundle.price, Money(amount: "180.0", currencyCode: "CAD"))
        XCTAssertEqual(bundle.product, ProductRef(handle: "hoodie-old", title: "Hoodie"))
        XCTAssertTrue(bundle.image?.url.hasSuffix("3d4d46da1bdbda2bf52f92987e6d4108770eb0a8f233f63a279849fce731f5af.jpg") == true, "its product's image")
        XCTAssertEqual(variant.sellingPlanAllocations, [
            SellingPlanAllocation(
                sellingPlan: SellingPlan(id: "gid://shopify/SellingPlan/4400001", name: "Deliver every month"),
                priceAdjustments: [
                    SellingPlanAllocation.PriceAdjustment(
                        price: Money(amount: "108.0", currencyCode: "CAD"),
                        compareAtPrice: Money(amount: "120.0", currencyCode: "CAD"),
                        perDeliveryPrice: Money(amount: "108.0", currencyCode: "CAD")
                    ),
                ]
            ),
        ])
    }

    @MainActor
    func testCatalog() async throws {
        let page = try await StubServer().storefront().products()
        XCTAssertEqual(page.items.count, 3)
        XCTAssertEqual(page.items.first?.handle, "gray-leather-sneakers")
        XCTAssertEqual(page.items.first?.price, Money(amount: "1000.0", currencyCode: "CAD"))
        XCTAssertNil(page.items.first?.compareAt, "a 0.0 compare-at price is no discount")
        XCTAssertTrue(page.hasNextPage)
        XCTAssertEqual(page.endCursor, "eyJjIjoicHJpY2UiLCJ2IjoiMTIwLjAiLCJpIjoxMX0")

        // what a card adds to the list
        let card = try XCTUnwrap(page.items.first)
        XCTAssertEqual(card.vendor, "Mock.shop")
        XCTAssertEqual(card.maxPrice, Money(amount: "1000.0", currencyCode: "CAD"))
        XCTAssertFalse(card.hasPriceRange)
        XCTAssertEqual(card.options.map { $0.name }, ["Size"])
        XCTAssertNil(card.options.first?.id, "a card's options carry names and swatches only")
        XCTAssertEqual(card.colors, [], "no colour option")
        XCTAssertEqual(card.firstVariant?.id, "gid://shopify/ProductVariant/43696961355798")
        XCTAssertEqual(card.firstVariant?.available, true)
        XCTAssertEqual(card.firstVariant?.quantityRule, QuantityRule(minimum: 0, maximum: nil, increment: 0))
        XCTAssertEqual(card.firstVariant?.quantityRule?.min, 1, "mock.shop's 0 means 1")
        XCTAssertNil(card.quickAddVariantId, "there is a size to choose")
        XCTAssertNil(card.rating)
        XCTAssertNil(card.ratingCount)
        XCTAssertEqual(page.items[1].colors.count, 3)
    }

    @MainActor
    func testProducts() async throws {
        let server = StubServer()
        let ids = ["gid://shopify/Product/7982905098262", "gid://shopify/Product/1", "gid://shopify/Product/7982856273942"]
        let cards = try await server.storefront().productsByIds(ids)
        XCTAssertEqual(server.calls.first?.variables["ids"] as? [String], ids)
        XCTAssertEqual(cards.map { $0.handle }, ["men-crewneck", "sweatpants"], "the id that is no product comes back null and is left out")

        let crewneck = try XCTUnwrap(cards.first)
        XCTAssertEqual(try XCTUnwrap(crewneck.rating), 4.6, accuracy: 0.0001)
        XCTAssertEqual(crewneck.ratingCount, 128)
        XCTAssertEqual(
            crewneck.firstVariant,
            CardVariant(
                id: "gid://shopify/ProductVariant/43696905224214",
                sku: "CREW-S-GRN",
                available: true,
                quantityRule: QuantityRule(minimum: 2, maximum: 40, increment: 2)
            )
        )
        XCTAssertEqual(crewneck.colors.map { $0.name }, ["Green", "Olive", "Ocean"])
        XCTAssertEqual(crewneck.colors.first?.swatch, Swatch(color: "#3F6B4F", image: nil))
        XCTAssertFalse(crewneck.hasPriceRange)
        XCTAssertNil(crewneck.quickAddVariantId, "sizes and colours to choose")
        XCTAssertTrue(cards[1].hasPriceRange, "35 to 42")
        XCTAssertNil(cards[1].rating)
        XCTAssertEqual(cards[1].firstVariant?.sku, "")
    }

    @MainActor
    func testProductRecommendations() async throws {
        let cards = try await StubServer().storefront().recommendations(productId: "gid://shopify/Product/7982905098262")
        XCTAssertEqual(cards.map { $0.handle }, ["hoodie-old", "men-t-shirt", "sweatpants"])
    }

    @MainActor
    func testCollection() async throws {
        let found = try await StubServer().storefront().collection("men")
        let collection = try XCTUnwrap(found)
        XCTAssertEqual(collection.title, "Men")
        XCTAssertFalse(collection.description.isEmpty)
        XCTAssertNotNil(collection.image)
        XCTAssertEqual(collection.products.items.count, 3)
        XCTAssertTrue(collection.products.hasNextPage)
        XCTAssertEqual(collection.products.endCursor, "eyJjIjoicG9zaXRpb24iLCJ2Ijo0LCJpIjo4MjYwfQ")
        XCTAssertEqual(collection.products.items.first?.colors.first?.swatch?.color, "#81a69b")

        let filters = collection.products.filters
        XCTAssertEqual(filters.map { $0.id }, ["filter.v.availability", "filter.v.price", "filter.v.option.color", "filter.v.option.size"])
        XCTAssertEqual(filters.map { $0.type }, ["LIST", "PRICE_RANGE", "LIST", "LIST"])
        XCTAssertEqual(filters.map { $0.presentation }, ["TEXT", "TEXT", "SWATCH", "TEXT"])
        let color = filters[2]
        XCTAssertEqual(color.values.map { $0.label }, ["Green", "Olive", "Ocean"])
        XCTAssertEqual(color.values[0].count, 9)
        XCTAssertEqual(color.values[0].input, #"{"variantOption":{"name":"color","value":"Green"}}"#)
        XCTAssertEqual(color.values[0].swatch, Swatch(color: "#3F6B4F", image: nil))
        XCTAssertNil(color.values[1].swatch?.color)
        XCTAssertEqual(color.values[1].swatch?.image?.width, 4096, "a swatch that is an image")
        XCTAssertNil(color.values[2].swatch, "the store gave this value no swatch")
        XCTAssertNil(filters[0].values[0].swatch)
    }

    @MainActor
    func testCollections() async throws {
        let page = try await StubServer().storefront().collections()
        XCTAssertEqual(page.items.map { $0.handle }, ["men", "women", "unisex"])
        XCTAssertNotNil(page.items.first?.description)
        XCTAssertTrue(page.hasNextPage)
    }

    // MARK: Search

    @MainActor
    func testSearch() async throws {
        let results = try await StubServer().storefront().search("shirt")
        XCTAssertEqual(results.products.map { $0.handle }, ["men-t-shirt", "women-t-shirt", "half-zip"])
        XCTAssertEqual(results.filters, [])
        XCTAssertFalse(results.hasNextPage)
    }

    @MainActor
    func testPredictiveSearch() async throws {
        let server = StubServer()
        let found = try await server.storefront().predictiveSearch("t")
        XCTAssertEqual(server.calls.first?.variables["limit"] as? Int, 8)
        XCTAssertEqual(found.products.count, 3)
        XCTAssertEqual(found.collections, [ResourceLink(handle: "tops", title: "Tops")])
        XCTAssertEqual(found.queries, [])
        XCTAssertEqual(found.articles, [])
    }

    // MARK: Stores

    @MainActor
    func testStoreAvailability() async throws {
        let availability = try await StubServer().storefront().storeAvailability(variantId: "gid://shopify/ProductVariant/43696905224214")
        XCTAssertEqual(availability.map { $0.available }, [true, false])
        XCTAssertEqual(availability.first?.quantityAvailable, 4)
        XCTAssertEqual(availability.first?.location.name, "Ottawa Store")
        XCTAssertEqual(availability.first?.location.address.latitude, 45.4215)
    }

    @MainActor
    func testLocations() async throws {
        let page = try await StubServer().storefront().locations()
        XCTAssertEqual(page.items.map { $0.name }, ["Ottawa Store", "Toronto Warehouse"])
        XCTAssertEqual(page.items.last?.address.address2, "Unit 2")
        XCTAssertEqual(page.items.first?.address.formatted.count, 3)
        XCTAssertFalse(page.hasNextPage)
    }

    // MARK: Content

    @MainActor
    func testPage() async throws {
        let found = try await StubServer().storefront().page("contact")
        let page = try XCTUnwrap(found)
        XCTAssertEqual(page.title, "Contact")
        XCTAssertEqual(page.body, "")
        XCTAssertEqual(page.updatedAt, "2023-01-19T19:23:56Z")
        XCTAssertNil(page.seo?.title)
    }

    @MainActor
    func testPages() async throws {
        let page = try await StubServer().storefront().pages()
        XCTAssertEqual(page.items.map { $0.handle }, ["contact", "liquid"])
        XCTAssertNil(page.items.first?.body, "not selected in the list")
    }

    @MainActor
    func testBlogs() async throws {
        let page = try await StubServer().storefront().blogs()
        XCTAssertEqual(page.items.map { $0.handle }, ["news"])
        XCTAssertNil(page.items.first?.articles)
    }

    @MainActor
    func testBlog() async throws {
        let found = try await StubServer().storefront().blog("news")
        let blog = try XCTUnwrap(found)
        XCTAssertEqual(blog.title, "News")
        XCTAssertEqual(blog.articles?.items.count, 3)
        XCTAssertEqual(blog.articles?.items.first?.author, "Teddy Hwang")
        XCTAssertEqual(blog.articles?.items.first?.blogHandle, "news")
    }

    @MainActor
    func testArticle() async throws {
        let server = StubServer()
        let found = try await server.storefront().article(blogHandle: "news", articleHandle: "making-liquid")
        let article = try XCTUnwrap(found)
        XCTAssertEqual(server.calls.first?.variables["blogHandle"] as? String, "news")
        XCTAssertEqual(article.title, "Making Liquid")
        XCTAssertEqual(article.blogHandle, "news")
        XCTAssertNil(article.image)
        XCTAssertTrue(article.contentHtml?.hasPrefix("<p>") == true)
        XCTAssertEqual(article.tags, [])
    }

    @MainActor
    func testArticles() async throws {
        let page = try await StubServer().storefront().articles()
        XCTAssertEqual(page.items.count, 3)
        XCTAssertEqual(page.items.last?.handle, "liquidpeak-450")
        XCTAssertNil(page.items.first?.contentHtml)
    }

    @MainActor
    func testMetaobject() async throws {
        let found = try await StubServer().storefront().metaobject(type: "mobile_banner", handle: "new-season")
        let metaobject = try XCTUnwrap(found)
        XCTAssertEqual(metaobject.type, "mobile_banner")
        XCTAssertEqual(metaobject.handle, "new-season")
        XCTAssertEqual(metaobject.field("heading")?.value, "New season")
        guard case let .image(image)? = metaobject.field("image")?.reference else { return XCTFail("not an image reference") }
        XCTAssertEqual(image?.alt, "New season")
        XCTAssertEqual(metaobject.field("collection")?.reference, .other("Collection"), "a reference the query selects no fields for")
        XCTAssertNil(metaobject.field("link")?.reference)
    }

    @MainActor
    func testMetaobjects() async throws {
        let page = try await StubServer().storefront().metaobjects(type: "mobile_banner")
        XCTAssertEqual(page.items.map { $0.handle }, ["new-season", "free-shipping"])
        XCTAssertEqual(page.items.last?.field("style")?.value, "card")
    }

    // MARK: Home

    @MainActor
    func testHomeScreen() async throws {
        let sections = try await StubServer().storefront().homeScreen("home")
        XCTAssertEqual(sections.map { $0.type }, ["mobile_banner", "mobile_products", "mobile_collections"])
        let collection = sections[1].field("collection")?.reference?.collectionCard
        XCTAssertEqual(collection?.handle, "men")
        XCTAssertEqual(collection?.products.count, 3)
        XCTAssertEqual(sections[2].field("collections")?.references.compactMap { $0.collectionCard }.count, 3)
    }

    @MainActor
    func testFallbackHome() async throws {
        let collections = try await StubServer().storefront().fallbackHome()
        XCTAssertEqual(collections.map { $0.handle }, ["men", "women", "unisex"])
        XCTAssertEqual(collections.map { $0.products.count }, [3, 3, 3])
        XCTAssertEqual(collections.first?.products.first?.vendor, "Mock.shop")
        XCTAssertEqual(collections.first?.products.first?.colors.map { $0.name }, ["Green", "Olive", "Ocean"])
    }

    // MARK: Screens v2

    @MainActor
    func testAppScreen() async throws {
        let server = StubServer()
        let found = try await server.storefront().appScreen("home")
        let screen = try XCTUnwrap(found)
        XCTAssertEqual(server.calls.first?.variables["handle"] as? String, "home")
        XCTAssertEqual(screen.handle, "home")
        XCTAssertEqual(screen.title, "Home")
        XCTAssertEqual(screen.updatedAt, "2026-10-19T08:00:00Z")
        let template = try XCTUnwrap(ScreenTemplate.decode(screen.template))
        XCTAssertEqual(template.sections.first?.id, "hero")
        XCTAssertEqual(template.metafields, ["shop.custom.promo"])
    }

    @MainActor
    func testAScreenTheStoreDoesNotHaveIsTheOneTheAppWasBuiltWith() async throws {
        let built = #"{"version":2,"sections":[]}"#
        let none = StubServer(reply: { _, _ in #"{"data":{"metaobject":null}}"# }).storefront()
        none.builtInScreen = { $0 == "home" ? built : nil }
        let home = try await none.appScreen("home")
        XCTAssertEqual(home?.template, built)
        let cart = try await none.appScreen("cart")
        XCTAssertNil(cart)
        // the store's own screen wins
        let own = StubServer().storefront()
        own.builtInScreen = { _ in built }
        let screen = try await own.appScreen("home")
        XCTAssertEqual(screen?.title, "Home")
    }

    @MainActor
    func testSectionNodes() async throws {
        let server = StubServer()
        let api = server.storefront()
        let ids = ["gid://shopify/Product/7982904639510", "gid://shopify/Collection/429493780502", "gid://shopify/Product/1"]
        let nodes = try await api.sectionNodes(ids)
        XCTAssertEqual(server.calls.first?.variables["ids"] as? [String], ids)
        XCTAssertEqual(nodes.count, 2, "the id that is no node any more comes back null and is left out")
        XCTAssertEqual(nodes.first?.productCard?.handle, "hoodie-old")
        let collection = try XCTUnwrap(nodes.last?.collectionCard)
        XCTAssertEqual(collection.handle, "men")
        XCTAssertEqual(collection.products.map { $0.handle }.count, 2)
        XCTAssertNotNil(collection.image)

        let none = try await api.sectionNodes([])
        XCTAssertEqual(none, [])
        XCTAssertEqual(server.names, ["SectionNodes"], "nothing to ask for: no request")
    }

    @MainActor
    func testCollectionMetafields() async throws {
        let server = StubServer()
        let identifiers = [MetafieldIdentifier(namespace: "custom", key: "banner_text"), MetafieldIdentifier(namespace: "custom", key: "size")]
        let metafields = try await server.storefront().collectionMetafields(handle: "men", identifiers: identifiers)
        XCTAssertEqual(metafields, [Metafield(namespace: "custom", key: "banner_text", type: "single_line_text_field", value: "Up to 40% off")])
        XCTAssertEqual(server.calls.first?.variables["handle"] as? String, "men")
        let sent = server.calls.first?.variables["metafields"] as? [[String: String]]
        XCTAssertEqual(sent, [["namespace": "custom", "key": "banner_text"], ["namespace": "custom", "key": "size"]])
    }

    @MainActor
    func testShopMetafields() async throws {
        let server = StubServer()
        let api = server.storefront()
        let metafields = try await api.shopMetafields(identifiers: [MetafieldIdentifier(namespace: "custom", key: "promo")])
        XCTAssertEqual(metafields, [Metafield(namespace: "custom", key: "promo", type: "single_line_text_field", value: "Free shipping over $75")])
        let none = try await api.shopMetafields(identifiers: [])
        XCTAssertEqual(none, [])
        XCTAssertEqual(server.names, ["ShopMetafields"], "nothing to ask for: no request")
    }

    // MARK: Cart

    @MainActor
    func testCart() async throws {
        let found = try await StubServer().storefront().cart(Self.cartId)
        let cart = try XCTUnwrap(found)
        XCTAssertEqual(cart.id, Self.cartId)
        XCTAssertEqual(cart.totalQuantity, 3)
        XCTAssertEqual(cart.subtotal, Money(amount: "360.0", currencyCode: "CAD"))
        XCTAssertEqual(cart.lines.count, 1)
        XCTAssertEqual(cart.lines.first?.productHandle, "men-crewneck")
        XCTAssertEqual(cart.lines.first?.variantTitle, "Small / Green")
        XCTAssertEqual(cart.total, Money(amount: "324.0", currencyCode: "CAD"))
        XCTAssertEqual(cart.note, "Gift wrap, please")
        XCTAssertEqual(cart.attributes, [CartAttribute(key: "source", value: "app")])
        XCTAssertEqual(cart.discountCodes, [CartDiscountCode(code: "WELCOME10", applicable: false)])
        XCTAssertEqual(cart.buyerIdentity?.countryCode, "CA")
        XCTAssertEqual(cart.deliveryGroups, [])
        XCTAssertEqual(cart.warnings, [], "warnings come with mutations only")
        XCTAssertNil(cart.purchasingCompany, "a retail cart")
        let line = try XCTUnwrap(cart.lines.first)
        XCTAssertEqual(line.id, "gid://shopify/CartLine/54972")
        XCTAssertEqual(line.sku, "")
        XCTAssertEqual(line.quantityRule, QuantityRule(minimum: 0, maximum: nil, increment: 0))
        XCTAssertNil(line.sellingPlanName, "a one-time purchase")
        XCTAssertEqual(line.components, [], "not a bundle")
        // 3 × 120.00, 150.00 each before, and an automatic discount on the line
        XCTAssertEqual(line.subtotal, Money(amount: "360.0", currencyCode: "CAD"))
        XCTAssertEqual(line.total, Money(amount: "324.0", currencyCode: "CAD"))
        XCTAssertEqual(line.unitPrice, Money(amount: "120.0", currencyCode: "CAD"))
        XCTAssertEqual(line.compareAtUnitPrice, Money(amount: "150.0", currencyCode: "CAD"))
        XCTAssertEqual(line.discounts, [CartDiscount(amount: Money(amount: "36.0", currencyCode: "CAD"), label: "Buy 3, save 10%")])
        XCTAssertEqual(line.productId, "gid://shopify/Product/7982905098262")
    }

    @MainActor
    func testCartCreate() async throws {
        let server = StubServer()
        let result = try await server.storefront().cartCreate(CartInput(lines: [CartLineInput(merchandiseId: "v1", quantity: 1)]))
        let input = server.calls.first?.variables["input"] as? [String: Any]
        let line = (input?["lines"] as? [[String: Any]])?.first
        XCTAssertEqual(line?["merchandiseId"] as? String, "v1")
        XCTAssertEqual(result.totalQuantity, 1)
        XCTAssertEqual(result.note, "")
        XCTAssertEqual(result.warnings, [])
    }

    @MainActor
    func testCartLinesAdd() async throws {
        let result = try await StubServer().storefront().addLines(cartId: Self.cartId, lines: [CartLineInput(merchandiseId: "v1")])
        XCTAssertEqual(result.totalQuantity, 2)
        XCTAssertEqual(result.lines.first?.quantity, 2)
    }

    @MainActor
    func testCartLinesUpdate() async throws {
        let line = CartLineUpdateInput(id: "gid://shopify/CartLine/49959", quantity: 3)
        let result = try await StubServer().storefront().updateLines(cartId: Self.cartId, lines: [line])
        XCTAssertEqual(result.lines.first?.quantity, 3)
    }

    @MainActor
    func testCartLinesRemove() async throws {
        let result = try await StubServer().storefront().removeLines(cartId: Self.cartId, lineIds: ["gid://shopify/CartLine/49959"])
        XCTAssertEqual(result.lines, [])
        XCTAssertEqual(result.totalQuantity, 0)
        XCTAssertEqual(result.warnings.map { $0.code }, ["DISCOUNT_NOT_FOUND"], "warnings come back with the cart")
    }

    @MainActor
    func testCartBuyerIdentityUpdate() async throws {
        let result = try await StubServer().storefront().updateBuyerIdentity(
            cartId: Self.cartId,
            buyerIdentity: CartBuyerIdentityInput(customerAccessToken: "tok")
        )
        XCTAssertEqual(result.buyerIdentity?.countryCode, "CA")
        XCTAssertEqual(result.warnings.count, 1)
    }

    @MainActor
    func testCartDiscountCodesUpdate() async throws {
        let result = try await StubServer().storefront().updateDiscountCodes(cartId: Self.cartId, codes: ["WELCOME10"])
        XCTAssertEqual(result.discountCodes.map { $0.code }, ["WELCOME10"])
        XCTAssertEqual(result.warnings.first?.message, "Enter a valid discount code")
        let line = try XCTUnwrap(result.lines.first)
        XCTAssertNil(line.compareAtUnitPrice, "no compare-at price on this line")
        XCTAssertEqual(line.discounts, [], "the code doesn't apply: no discount on the line")
        XCTAssertEqual(line.subtotal, line.total)
    }

    @MainActor
    func testCartGiftCardCodesAdd() async throws {
        let result = try await StubServer().storefront().addGiftCards(cartId: Self.cartId, codes: ["GIFT"])
        XCTAssertEqual(result.giftCards, [])
        XCTAssertEqual(result.warnings.first?.target, Self.cartId)
    }

    @MainActor
    func testCartGiftCardCodesRemove() async throws {
        let result = try await StubServer().storefront().removeGiftCards(cartId: Self.cartId, ids: ["gid://shopify/AppliedGiftCard/1"])
        XCTAssertEqual(result.giftCards, [])
        XCTAssertEqual(result.id, Self.cartId)
    }

    @MainActor
    func testCartNoteUpdate() async throws {
        let result = try await StubServer().storefront().updateNote(cartId: Self.cartId, note: "Gift wrap, please")
        XCTAssertEqual(result.note, "Gift wrap, please")
    }

    @MainActor
    func testCartAttributesUpdate() async throws {
        let server = StubServer()
        let result = try await server.storefront().updateAttributes(cartId: Self.cartId, attributes: [CartAttribute(key: "source", value: "app")])
        XCTAssertEqual(result.attributes, [CartAttribute(key: "source", value: "app")])
        let sent = server.calls.first?.variables["attributes"] as? [[String: String]]
        XCTAssertEqual(sent, [["key": "source", "value": "app"]])
    }

    @MainActor
    func testCartDeliveryAddressesAdd() async throws {
        let server = StubServer()
        let address = CartSelectableAddressInput(address: CartDeliveryAddressInput(city: "Ottawa", countryCode: "CA"), selected: true)
        let result = try await server.storefront().addDeliveryAddresses(cartId: Self.cartId, addresses: [address])
        let sent = (server.calls.first?.variables["addresses"] as? [[String: Any]])?.first
        let deliveryAddress = (sent?["address"] as? [String: Any])?["deliveryAddress"] as? [String: Any]
        XCTAssertEqual(deliveryAddress?["city"] as? String, "Ottawa")
        XCTAssertEqual(sent?["selected"] as? Bool, true)
        let added = try XCTUnwrap(result.deliveryAddresses.first)
        XCTAssertTrue(added.selected)
        XCTAssertEqual(added.address?.city, "Ottawa")
        XCTAssertNil(added.address?.address2)
    }

    @MainActor
    func testCartDeliveryAddressesUpdate() async throws {
        let update = CartSelectableAddressUpdateInput(id: "gid://shopify/CartSelectableAddress/9876543210", address: CartDeliveryAddressInput(address2: "Suite 400"))
        let result = try await StubServer().storefront().updateDeliveryAddresses(cartId: Self.cartId, addresses: [update])
        XCTAssertEqual(result.deliveryAddresses.first?.address?.address2, "Suite 400")
    }

    @MainActor
    func testCartDeliveryAddressesRemove() async throws {
        let result = try await StubServer().storefront().removeDeliveryAddresses(
            cartId: Self.cartId,
            addressIds: ["gid://shopify/CartSelectableAddress/9876543210"]
        )
        XCTAssertEqual(result.deliveryAddresses, [])
    }

    @MainActor
    func testCartSelectedDeliveryOptionsUpdate() async throws {
        let option = CartSelectedDeliveryOptionInput(deliveryGroupId: "gid://shopify/CartDeliveryGroup/1", deliveryOptionHandle: "e5f6a7b8-express")
        let result = try await StubServer().storefront().selectDeliveryOptions(cartId: Self.cartId, options: [option])
        let group = try XCTUnwrap(result.deliveryGroups.first)
        XCTAssertEqual(group.selectedDeliveryOption?.handle, "a1b2c3d4-standard")
        XCTAssertEqual(group.deliveryOptions.map { $0.title }, ["Standard", "Express"])
        XCTAssertEqual(group.deliveryOptions.last?.estimatedCost, Money(amount: "25.0", currencyCode: "CAD"))
        XCTAssertEqual(group.deliveryAddress.formatted.first, "Ada Lovelace")
    }

    // MARK: Customer Account

    @MainActor
    func testCustomer() async throws {
        let customer = try await StubServer().customerAccount().customer()
        XCTAssertEqual(customer.name, "Ada Lovelace")
        XCTAssertEqual(customer.email, "ada@example.com")
        XCTAssertEqual(customer.emailAddress?.marketingState, "SUBSCRIBED")
        XCTAssertEqual(customer.phone, "+16135550123")
        XCTAssertEqual(customer.defaultAddress?.city, "Ottawa")
        XCTAssertEqual(customer.defaultAddress?.formatted.count, 5)
    }

    @MainActor
    func testOrders() async throws {
        let server = StubServer()
        let page = try await server.customerAccount().orders()
        let variables = try XCTUnwrap(server.calls.first?.variables)
        XCTAssertEqual(variables["reverse"] as? Bool, true, "newest first")
        XCTAssertEqual(variables["first"] as? Int, 20)
        XCTAssertEqual(page.items.map { $0.name }, ["#1005", "#1004", "#1003", "#1002"])
        XCTAssertFalse(page.hasNextPage)
        XCTAssertEqual(page.endCursor, "eyJsYXN0X2lkIjoxMDAyfQ==")

        let shipping = page.items[0]
        XCTAssertEqual(shipping.total, Money(amount: "158.9", currencyCode: "CAD"))
        XCTAssertEqual(shipping.number, 1005)
        XCTAssertEqual(shipping.financialStatus, "PAID")
        XCTAssertEqual(shipping.fulfillmentStatus, "IN_PROGRESS")
        XCTAssertEqual(shipping.images.count, 2)
        XCTAssertEqual(shipping.titles, ["Half Zip", "Workout Shirt"])
        XCTAssertEqual(shipping.itemCount, 4)
        XCTAssertEqual(shipping.latestShipmentStatus, "IN_TRANSIT")
        XCTAssertEqual(shipping.estimatedDeliveryAt, "2026-10-14T18:00:00Z")
        XCTAssertNil(shipping.deliveredAt, "not delivered yet")

        let delivered = page.items[1]
        XCTAssertEqual(delivered.latestShipmentStatus, "DELIVERED")
        XCTAssertNil(delivered.estimatedDeliveryAt)
        XCTAssertEqual(delivered.deliveredAt, "2026-09-25T13:05:00Z")
        XCTAssertEqual(delivered.itemCount, 4, "summed over its lines")
        XCTAssertEqual(delivered.images.count, 3)

        XCTAssertNil(page.items[2].latestShipmentStatus, "nothing has shipped")
        XCTAssertEqual(page.items[2].fulfillmentStatus, "UNFULFILLED")
        XCTAssertNil(page.items[2].cancelledAt)
        XCTAssertEqual(page.items[3].cancelledAt, "2026-07-14T16:00:00Z")
        XCTAssertEqual(page.items[3].itemCount, 1)
    }

    @MainActor
    func testOrder() async throws {
        let found = try await StubServer().customerAccount().order("gid://shopify/Order/6001004")
        let order = try XCTUnwrap(found)
        let cad = { (amount: String) in Money(amount: amount, currencyCode: "CAD") }
        XCTAssertEqual(order.name, "#1004")
        XCTAssertEqual(order.number, 1004)
        XCTAssertEqual(order.confirmationNumber, "XK4R7T2PQ")
        XCTAssertEqual(order.financialStatus, "PARTIALLY_REFUNDED")
        XCTAssertEqual(order.fulfillmentStatus, "FULFILLED")
        XCTAssertNil(order.cancelledAt)
        XCTAssertEqual(order.statusPageUrl, "https://shopify.com/68817551382/account/orders/6001004")
        XCTAssertEqual(order.subtotal, cad("230.0"))
        XCTAssertEqual(order.totalShipping, cad("12.0"))
        XCTAssertEqual(order.totalTax, cad("29.9"))
        XCTAssertEqual(order.total, cad("271.9"))
        XCTAssertEqual(order.totalRefunded, cad("35.0"))
        XCTAssertEqual(order.discounts, [.percentage(10)])
        XCTAssertEqual(order.shippingAddress?.zoneCode, "ON")
        XCTAssertEqual(order.billingAddress?.formatted.count, 5)

        XCTAssertFalse(order.edited)
        XCTAssertTrue(order.requiresShipping)
        XCTAssertEqual(order.note, "Please leave the parcel at the front desk.")
        XCTAssertEqual(order.poNumber, "PO-2291")
        XCTAssertEqual(
            order.purchasingCompany,
            PurchasingCompany(
                company: Company(id: "gid://shopify/Company/9100001", name: "Analytical Engines Ltd"),
                location: CompanyLocation(id: "gid://shopify/CompanyLocation/9200001", name: "Ottawa head office")
            )
        )
        XCTAssertEqual(order.shippingLine, OrderShippingLine(title: "Standard shipping", originalPrice: cad("12.0")))
        XCTAssertEqual(
            order.paymentInformation,
            OrderPaymentInformation(
                paymentStatus: "PARTIALLY_REFUNDED",
                totalPaidAmount: cad("271.9"),
                totalOutstandingAmount: cad("0.0"),
                paymentCollectionUrl: nil,
                paymentTerms: PaymentTerms(paymentTermsName: "Net 30", nextDueAt: "2026-10-21T09:40:00Z", overdue: false)
            )
        )
        XCTAssertEqual(order.transactions, [
            OrderTransaction(
                id: "gid://shopify/OrderTransaction/7100001", kind: "SALE", status: "SUCCESS", type: "CARD",
                processedAt: "2026-09-21T09:40:00Z", amount: cad("271.9"), cardBrand: "visa", last4: "4242"
            ),
            OrderTransaction(
                id: "gid://shopify/OrderTransaction/7100002", kind: "REFUND", status: "SUCCESS", type: "CARD",
                processedAt: "2026-10-02T10:15:00Z", amount: cad("35.0"), cardBrand: "visa", last4: "4242"
            ),
        ])

        XCTAssertEqual(order.lines.map { $0.title }, ["Men's Crewneck", "Sweatpants", "Men's T-shirt"])
        let line = try XCTUnwrap(order.lines.first)
        XCTAssertEqual(line.id, "gid://shopify/LineItem/5000001")
        XCTAssertEqual(line.variantTitle, "Medium / Olive")
        XCTAssertEqual(line.sku, "MENCREWNECK-MO")
        XCTAssertEqual(line.quantity, 1)
        XCTAssertEqual(line.refundableQuantity, 1)
        XCTAssertEqual(line.price, cad("120.0"))
        XCTAssertEqual(line.total, cad("120.0"))
        XCTAssertEqual(line.totalDiscount, cad("0.0"))
        XCTAssertEqual(line.variantId, "gid://shopify/ProductVariant/43696905224214")
        XCTAssertNotNil(line.image)
        XCTAssertEqual(order.lines[1].refundableQuantity, 0, "already returned")

        XCTAssertEqual(order.fulfillments.count, 1)
        let fulfillment = try XCTUnwrap(order.fulfillments.first)
        XCTAssertEqual(fulfillment.status, "SUCCESS")
        XCTAssertEqual(fulfillment.latestShipmentStatus, "DELIVERED")
        XCTAssertEqual(fulfillment.estimatedDeliveryAt, "2026-09-25T18:00:00Z")
        XCTAssertFalse(fulfillment.isPickedUp)
        XCTAssertEqual(fulfillment.tracking, [
            TrackingInfo(
                company: "Canada Post",
                number: "7023210039414604",
                url: "https://www.canadapost-postescanada.ca/track-reperage/en#/details/7023210039414604"
            ),
        ])
        XCTAssertEqual(fulfillment.events.map { $0.status }, ["CONFIRMED", "IN_TRANSIT", "OUT_FOR_DELIVERY", "DELIVERED"])
        XCTAssertEqual(fulfillment.events.last?.happenedAt, "2026-09-25T13:05:00Z")
        XCTAssertEqual(fulfillment.lines, [
            FulfillmentLine(lineItemId: "gid://shopify/LineItem/5000001", quantity: 1),
            FulfillmentLine(lineItemId: "gid://shopify/LineItem/5000002", quantity: 2),
            FulfillmentLine(lineItemId: "gid://shopify/LineItem/5000003", quantity: 1),
        ])

        XCTAssertEqual(order.refunds, [
            OrderRefund(id: "gid://shopify/Refund/7300001", createdAt: "2026-10-02T10:15:00Z", returnName: "#1004-R1", totalRefunded: cad("35.0")),
        ])
        XCTAssertEqual(order.returns.count, 1)
        let returned = try XCTUnwrap(order.returns.first)
        XCTAssertEqual(returned.id, "gid://shopify/Return/3000001")
        XCTAssertEqual(returned.name, "#1004-R1")
        XCTAssertEqual(returned.status, "CLOSED")
        XCTAssertEqual(returned.createdAt, "2026-09-27T17:20:00Z")
        XCTAssertEqual(returned.closedAt, "2026-10-02T10:15:00Z")
        XCTAssertEqual(returned.lines.count, 1)
        let returnLine = try XCTUnwrap(returned.lines.first)
        XCTAssertEqual(returnLine.id, "gid://shopify/ReturnLineItem/3100001")
        XCTAssertEqual(returnLine.quantity, 2)
        XCTAssertEqual(returnLine.reason, "Size was too small")
        XCTAssertEqual(returnLine.lineItemId, "gid://shopify/LineItem/5000002")
        XCTAssertEqual(returnLine.title, "Sweatpants")
        XCTAssertEqual(returnLine.variantTitle, "Medium / Green")
        XCTAssertNotNil(returnLine.image)
        XCTAssertEqual(returned.exchangeLines.map { $0.id }, ["gid://shopify/ExchangeLineItem/3200001"])
        XCTAssertEqual(returned.exchangeLines.first?.title, "Sweatpants")
        XCTAssertEqual(returned.exchangeLines.first?.variantTitle, "Large / Green")
        XCTAssertEqual(returned.exchangeLines.first?.quantity, 1)
        XCTAssertTrue(order.hasReturnableItems)
    }

    @MainActor
    func testCustomerAddresses() async throws {
        let page = try await StubServer().customerAccount().addresses()
        XCTAssertEqual(page.items.map { $0.isDefault }, [true, false])
        XCTAssertEqual(page.items.last?.company, "Analytical Engines Ltd")
        XCTAssertFalse(page.hasNextPage)
    }

    @MainActor
    func testCustomerUpdate() async throws {
        let server = StubServer()
        let customer = try await server.customerAccount().updateName(first: "Ada", last: "King")
        XCTAssertEqual(server.calls.first?.variables["input"] as? [String: String], ["firstName": "Ada", "lastName": "King"])
        XCTAssertEqual(customer.displayName, "Ada King")
        XCTAssertNil(customer.email, "not selected by the mutation")
    }

    @MainActor
    func testCustomerAddressCreate() async throws {
        let server = StubServer()
        let input = CustomerAddressInput(firstName: "Ada", address1: "1 Front St W", city: "Toronto", zoneCode: "ON", countryCode: "CA")
        let address = try await server.customerAccount().createAddress(input)
        let variables = try XCTUnwrap(server.calls.first?.variables)
        XCTAssertEqual(variables["defaultAddress"] as? Bool, false)
        XCTAssertEqual((variables["address"] as? [String: String])?["countryCode"], "CA")
        XCTAssertNil((variables["address"] as? [String: String])?["lastName"], "unset fields are left out")
        XCTAssertEqual(address.id, "gid://shopify/CustomerAddress/8000002")
        XCTAssertEqual(address.formatted.count, 5)
    }

    @MainActor
    func testCustomerAddressUpdate() async throws {
        let server = StubServer()
        let address = try await server.customerAccount().updateAddress(
            "gid://shopify/CustomerAddress/8000002",
            CustomerAddressInput(address2: "Floor 3")
        )
        XCTAssertNil(server.calls.first?.variables["defaultAddress"], "left as it is")
        XCTAssertEqual(address.address2, "Floor 3")
    }

    @MainActor
    func testCustomerAddressDeleteThrowsItsUserErrors() async throws {
        let failed = await thrownError { try await StubServer().customerAccount().deleteAddress("gid://shopify/CustomerAddress/8000001") }
        guard case let .userErrors(errors, cart)? = failed as? ArgonAPIError else { return XCTFail("expected userErrors, got \(String(describing: failed))") }
        XCTAssertEqual(errors, [
            UserError(
                field: ["addressId"],
                code: "DELETING_CUSTOMER_DEFAULT_ADDRESS_NOT_ALLOWED",
                message: "Customer's default address cannot be deleted."
            ),
        ])
        XCTAssertNil(cart)
        XCTAssertEqual(failed?.localizedDescription, "Customer's default address cannot be deleted.")
    }

    @MainActor
    func testCustomerEmailMarketingSubscribe() async throws {
        let email = try await StubServer().customerAccount().subscribeEmailMarketing()
        XCTAssertEqual(email, CustomerEmailAddress(emailAddress: "ada@example.com", marketingState: "SUBSCRIBED"))
    }

    @MainActor
    func testCustomerEmailMarketingUnsubscribe() async throws {
        let email = try await StubServer().customerAccount().unsubscribeEmailMarketing()
        XCTAssertEqual(email.marketingState, "UNSUBSCRIBED")
    }

    @MainActor
    func testOrderReturnOptions() async throws {
        let server = StubServer()
        let found = try await server.customerAccount().returnOptions("gid://shopify/Order/6001004")
        let options = try XCTUnwrap(found)
        XCTAssertEqual(server.calls.first?.variables["id"] as? String, "gid://shopify/Order/6001004")
        XCTAssertEqual(options.orderId, "gid://shopify/Order/6001004")
        XCTAssertEqual(options.orderName, "#1004")
        XCTAssertFalse(options.hasRestockingFee)
        XCTAssertTrue(options.hasReturnShippingFee)
        XCTAssertEqual(options.returnShippingMethods, ["MERCHANT_PROVIDED_LABEL"])
        XCTAssertEqual(options.returnShippingMethodNote, "We email a prepaid label once the return is approved.")
        XCTAssertEqual(options.fees, [
            ReturnFee(kind: "ReturnShippingFee", title: "Return shipping", amount: Money(amount: "8.0", currencyCode: "CAD")),
        ])
        XCTAssertEqual(options.nonReturnableSummary, "Some items were already returned.")

        XCTAssertEqual(options.returnableItems.map { $0.lineItemId }, ["gid://shopify/LineItem/5000001", "gid://shopify/LineItem/5000003"])
        let item = try XCTUnwrap(options.returnableItems.first)
        XCTAssertEqual(item.quantity, 1)
        XCTAssertEqual(item.title, "Men's Crewneck")
        XCTAssertEqual(item.variantTitle, "Medium / Olive")
        XCTAssertEqual(item.sku, "MENCREWNECK-MO")
        XCTAssertEqual(item.productId, "gid://shopify/Product/7982905098262")
        XCTAssertEqual(item.variantId, "gid://shopify/ProductVariant/43696905224214")
        XCTAssertEqual(item.price, Money(amount: "120.0", currencyCode: "CAD"))
        XCTAssertNotNil(item.image)
        XCTAssertEqual(item.reasons.map { $0.handle }, ["size-too-small", "size-too-large", "not-as-described", "changed-my-mind", "damaged"])
        XCTAssertEqual(item.reasons.first, ReturnReason(id: "gid://shopify/ReturnReasonDefinition/1", handle: "size-too-small", name: "Size was too small"))
        XCTAssertEqual(options.returns, [
            OrderReturn(id: "gid://shopify/Return/3000001", name: "#1004-R1", status: "CLOSED", createdAt: "2026-09-27T17:20:00Z"),
        ])
    }

    @MainActor
    func testOrderRequestReturn() async throws {
        let server = StubServer()
        let line = ReturnLineInput(
            lineItemId: "gid://shopify/LineItem/5000001",
            quantity: 1,
            returnReasonDefinitionId: "gid://shopify/ReturnReasonDefinition/1",
            customerNote: "Exchange for: Men's Crewneck - Large / Olive (SKU MENCREWNECK-LO)"
        )
        let requested = try await server.customerAccount().requestReturn("gid://shopify/Order/6001004", lines: [line])
        XCTAssertEqual(server.calls.first?.variables["orderId"] as? String, "gid://shopify/Order/6001004")
        let sent = (server.calls.first?.variables["requestedLineItems"] as? [[String: Any]])?.first
        XCTAssertEqual(sent?["lineItemId"] as? String, "gid://shopify/LineItem/5000001")
        XCTAssertEqual(sent?["quantity"] as? Int, 1)
        XCTAssertEqual(sent?["returnReasonDefinitionId"] as? String, "gid://shopify/ReturnReasonDefinition/1")
        XCTAssertEqual(sent?["customerNote"] as? String, "Exchange for: Men's Crewneck - Large / Olive (SKU MENCREWNECK-LO)")
        XCTAssertEqual(requested, OrderReturn(id: "gid://shopify/Return/3000002", name: "#1004-R2", status: "REQUESTED"))
    }

    @MainActor
    func testCustomerCompanies() async throws {
        let contacts = try await StubServer().customerAccount().companies()
        XCTAssertEqual(contacts, [
            CompanyContact(
                id: "gid://shopify/CompanyContact/9000001",
                title: "Purchasing lead",
                company: Company(
                    id: "gid://shopify/Company/9100001",
                    name: "Analytical Engines Ltd",
                    locations: [
                        CompanyLocation(id: "gid://shopify/CompanyLocation/9200001", name: "Ottawa head office"),
                        CompanyLocation(id: "gid://shopify/CompanyLocation/9200002", name: "Toronto warehouse"),
                    ]
                )
            ),
        ])
    }

    @MainActor
    func testCustomerStoreCredit() async throws {
        let accounts = try await StubServer().customerAccount().storeCredit()
        XCTAssertEqual(accounts, [
            StoreCreditAccount(id: "gid://shopify/StoreCreditAccount/9300001", balance: Money(amount: "25.0", currencyCode: "CAD")),
        ])
    }
}
