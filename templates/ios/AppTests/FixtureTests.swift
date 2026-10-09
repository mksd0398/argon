import XCTest
@testable import ArgonStorefront

/// Every contract fixture decoded through its facade method (the transport answers with the fixture), with key fields checked.
final class FixtureTests: XCTestCase {
    private static let cartId = "gid://shopify/Cart/c1-7469366f149b403dafd17bc5a9dab879?key=9c19aa7d7298298cf1b25c5af5542807"
    private static let covered: Set<String> = [
        "Shop", "Localization", "ShopPolicies", "Menu", "Product", "VariantBySelectedOptions", "Catalog", "Products",
        "ProductRecommendations", "Collection", "Collections", "Search", "PredictiveSearch", "StoreAvailability", "Locations",
        "Page", "Pages", "Blogs", "Blog", "Article", "Articles", "Metaobject", "Metaobjects", "HomeScreen", "FallbackHome",
        "Cart", "CartCreate", "CartLinesAdd", "CartLinesUpdate", "CartLinesRemove", "CartBuyerIdentityUpdate",
        "CartDiscountCodesUpdate", "CartGiftCardCodesAdd", "CartGiftCardCodesRemove", "CartNoteUpdate", "CartAttributesUpdate",
        "CartDeliveryAddressesAdd", "CartDeliveryAddressesUpdate", "CartDeliveryAddressesRemove",
        "CartSelectedDeliveryOptionsUpdate",
        "Customer", "Orders", "Order", "CustomerAddresses", "CustomerUpdate", "CustomerAddressCreate", "CustomerAddressUpdate",
        "CustomerAddressDelete", "CustomerEmailMarketingSubscribe", "CustomerEmailMarketingUnsubscribe", "OrderReturnOptions",
        "OrderRequestReturn",
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
        let identifiers = [MetafieldIdentifier(namespace: "custom", key: "material")]
        let found = try await server.storefront().product("men-crewneck", metafields: identifiers)
        let product = try XCTUnwrap(found)
        let sent = server.calls.first?.variables["metafields"] as? [[String: String]]
        XCTAssertEqual(sent, [["namespace": "custom", "key": "material"]])
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
        XCTAssertEqual(product.sellingPlanGroups, [])
        XCTAssertTrue(product.metafields.isEmpty, "unset metafields come back null and are skipped")
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
        XCTAssertNil(variant.sku)
        XCTAssertEqual(variant.price, Money(amount: "120.0", currencyCode: "CAD"))
        let sent = server.calls.first?.variables["selectedOptions"] as? [[String: String]]
        XCTAssertEqual(sent, [["name": "Color", "value": "Olive"], ["name": "Size", "value": "Small"]])
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
    }

    @MainActor
    func testProducts() async throws {
        let server = StubServer()
        let cards = try await server.storefront().products(ids: ["gid://shopify/Product/1"])
        XCTAssertEqual(cards, [])
        XCTAssertEqual(server.calls.first?.variables["ids"] as? [String], ["gid://shopify/Product/1"])
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
        XCTAssertEqual(collection.filters, [])
        XCTAssertEqual(collection.products.items.count, 3)
        XCTAssertTrue(collection.products.hasNextPage)
        XCTAssertEqual(collection.products.endCursor, "eyJjIjoicG9zaXRpb24iLCJ2Ijo0LCJpIjo4MjYwfQ")
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
        XCTAssertEqual(results.totalCount, 4)
        XCTAssertEqual(results.products.map { $0.handle }, ["men-t-shirt", "women-t-shirt", "half-zip"])
        XCTAssertEqual(results.filters, [])
        XCTAssertFalse(results.results.hasNextPage)
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
        XCTAssertEqual(cart.lines.first?.total, Money(amount: "360.0", currencyCode: "CAD"))
        XCTAssertEqual(cart.note, "Gift wrap, please")
        XCTAssertEqual(cart.attributes, [CartAttribute(key: "source", value: "app")])
        XCTAssertEqual(cart.discountCodes, [CartDiscountCode(code: "WELCOME10", applicable: false)])
        XCTAssertEqual(cart.buyerIdentity?.countryCode, "CA")
        XCTAssertEqual(cart.deliveryGroups, [])
    }

    @MainActor
    func testCartCreate() async throws {
        let server = StubServer()
        let result = try await server.storefront().cartCreate(CartInput(lines: [CartLineInput(merchandiseId: "v1", quantity: 1)]))
        let input = server.calls.first?.variables["input"] as? [String: Any]
        let line = (input?["lines"] as? [[String: Any]])?.first
        XCTAssertEqual(line?["merchandiseId"] as? String, "v1")
        XCTAssertEqual(result.cart.totalQuantity, 1)
        XCTAssertEqual(result.cart.note, "")
        XCTAssertEqual(result.warnings, [])
    }

    @MainActor
    func testCartLinesAdd() async throws {
        let result = try await StubServer().storefront().addLines(cartId: Self.cartId, lines: [CartLineInput(merchandiseId: "v1")])
        XCTAssertEqual(result.cart.totalQuantity, 2)
        XCTAssertEqual(result.cart.lines.first?.quantity, 2)
    }

    @MainActor
    func testCartLinesUpdate() async throws {
        let line = CartLineUpdateInput(id: "gid://shopify/CartLine/49959", quantity: 3)
        let result = try await StubServer().storefront().updateLines(cartId: Self.cartId, lines: [line])
        XCTAssertEqual(result.cart.lines.first?.quantity, 3)
    }

    @MainActor
    func testCartLinesRemove() async throws {
        let result = try await StubServer().storefront().removeLines(cartId: Self.cartId, lineIds: ["gid://shopify/CartLine/49959"])
        XCTAssertEqual(result.cart.lines, [])
        XCTAssertEqual(result.cart.totalQuantity, 0)
        XCTAssertEqual(result.warnings.map { $0.code }, ["DISCOUNT_NOT_FOUND"], "warnings come back with the cart")
    }

    @MainActor
    func testCartBuyerIdentityUpdate() async throws {
        let result = try await StubServer().storefront().updateBuyerIdentity(
            cartId: Self.cartId,
            buyerIdentity: CartBuyerIdentityInput(customerAccessToken: "tok")
        )
        XCTAssertEqual(result.cart.buyerIdentity?.countryCode, "CA")
        XCTAssertEqual(result.warnings.count, 1)
    }

    @MainActor
    func testCartDiscountCodesUpdate() async throws {
        let result = try await StubServer().storefront().updateDiscountCodes(cartId: Self.cartId, codes: ["WELCOME10"])
        XCTAssertEqual(result.cart.discountCodes.map { $0.code }, ["WELCOME10"])
        XCTAssertEqual(result.warnings.first?.message, "Enter a valid discount code")
    }

    @MainActor
    func testCartGiftCardCodesAdd() async throws {
        let result = try await StubServer().storefront().addGiftCards(cartId: Self.cartId, codes: ["GIFT"])
        XCTAssertEqual(result.cart.giftCards, [])
        XCTAssertEqual(result.warnings.first?.target, Self.cartId)
    }

    @MainActor
    func testCartGiftCardCodesRemove() async throws {
        let result = try await StubServer().storefront().removeGiftCards(cartId: Self.cartId, ids: ["gid://shopify/AppliedGiftCard/1"])
        XCTAssertEqual(result.cart.giftCards, [])
        XCTAssertEqual(result.cart.id, Self.cartId)
    }

    @MainActor
    func testCartNoteUpdate() async throws {
        let result = try await StubServer().storefront().updateNote(cartId: Self.cartId, note: "Gift wrap, please")
        XCTAssertEqual(result.cart.note, "Gift wrap, please")
    }

    @MainActor
    func testCartAttributesUpdate() async throws {
        let server = StubServer()
        let result = try await server.storefront().updateAttributes(cartId: Self.cartId, attributes: [CartAttribute(key: "source", value: "app")])
        XCTAssertEqual(result.cart.attributes, [CartAttribute(key: "source", value: "app")])
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
        let added = try XCTUnwrap(result.cart.deliveryAddresses.first)
        XCTAssertTrue(added.selected)
        XCTAssertEqual(added.address?.city, "Ottawa")
        XCTAssertNil(added.address?.address2)
    }

    @MainActor
    func testCartDeliveryAddressesUpdate() async throws {
        let update = CartSelectableAddressUpdateInput(id: "gid://shopify/CartSelectableAddress/9876543210", address: CartDeliveryAddressInput(address2: "Suite 400"))
        let result = try await StubServer().storefront().updateDeliveryAddresses(cartId: Self.cartId, addresses: [update])
        XCTAssertEqual(result.cart.deliveryAddresses.first?.address?.address2, "Suite 400")
    }

    @MainActor
    func testCartDeliveryAddressesRemove() async throws {
        let result = try await StubServer().storefront().removeDeliveryAddresses(
            cartId: Self.cartId,
            addressIds: ["gid://shopify/CartSelectableAddress/9876543210"]
        )
        XCTAssertEqual(result.cart.deliveryAddresses, [])
    }

    @MainActor
    func testCartSelectedDeliveryOptionsUpdate() async throws {
        let option = CartSelectedDeliveryOptionInput(deliveryGroupId: "gid://shopify/CartDeliveryGroup/1", deliveryOptionHandle: "e5f6a7b8-express")
        let result = try await StubServer().storefront().selectDeliveryOptions(cartId: Self.cartId, options: [option])
        let group = try XCTUnwrap(result.cart.deliveryGroups.first)
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
        XCTAssertEqual(page.items.map { $0.name }, ["#1002", "#1001"])
        XCTAssertEqual(page.items.first?.total, Money(amount: "130.0", currencyCode: "CAD"))
        XCTAssertEqual(page.items.first?.number, 1002)
        XCTAssertEqual(page.items.first?.images.count, 1)
        XCTAssertEqual(page.items.last?.images, [], "a line without an image")
        XCTAssertNotNil(page.items.last?.cancelledAt)
        XCTAssertTrue(page.hasNextPage)
        XCTAssertEqual(page.endCursor, "eyJsYXN0X2lkIjo2MDAwMDAxfQ==")
    }

    @MainActor
    func testOrder() async throws {
        let found = try await StubServer().customerAccount().order("gid://shopify/Order/6000002")
        let order = try XCTUnwrap(found)
        XCTAssertEqual(order.name, "#1002")
        XCTAssertEqual(order.confirmationNumber, "X7K2P9QZ1")
        XCTAssertEqual(order.fulfillmentStatus, "FULFILLED")
        XCTAssertEqual(order.subtotal, Money(amount: "108.0", currencyCode: "CAD"))
        XCTAssertEqual(order.total, Money(amount: "130.0", currencyCode: "CAD"))
        XCTAssertEqual(order.discounts, [.percentage(10)])
        XCTAssertEqual(order.shippingAddress?.zoneCode, "ON")
        XCTAssertEqual(order.lines.first?.title, "Men's Crewneck")
        XCTAssertEqual(order.lines.first?.price, Money(amount: "120.0", currencyCode: "CAD"))
        XCTAssertEqual(order.lines.first?.total, Money(amount: "108.0", currencyCode: "CAD"))
        let fulfillment = try XCTUnwrap(order.fulfillments.first)
        XCTAssertEqual(fulfillment.status, "SUCCESS")
        XCTAssertEqual(fulfillment.tracking.first?.company, "Canada Post")
        XCTAssertEqual(fulfillment.lines, [FulfillmentLine(lineItemId: "gid://shopify/LineItem/5000001", quantity: 1)])
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
        guard case let .userErrors(errors)? = failed as? ArgonAPIError else { return XCTFail("expected userErrors, got \(String(describing: failed))") }
        XCTAssertEqual(errors, [
            UserError(
                field: ["addressId"],
                code: "DELETING_CUSTOMER_DEFAULT_ADDRESS_NOT_ALLOWED",
                message: "Customer's default address cannot be deleted."
            ),
        ])
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
        let found = try await StubServer().customerAccount().returnOptions("gid://shopify/Order/6000002")
        let options = try XCTUnwrap(found)
        XCTAssertEqual(options.orderId, "gid://shopify/Order/6000002")
        let item = try XCTUnwrap(options.returnableItems.first)
        XCTAssertEqual(item.lineItemId, "gid://shopify/LineItem/5000001")
        XCTAssertEqual(item.quantity, 1)
        XCTAssertEqual(item.reasons.map { $0.handle }, ["size-too-small", "not-as-described"])
        XCTAssertEqual(options.returns, [])
    }

    @MainActor
    func testOrderRequestReturn() async throws {
        let server = StubServer()
        let line = ReturnLineInput(lineItemId: "gid://shopify/LineItem/5000001", quantity: 1, returnReasonDefinitionId: "gid://shopify/ReturnReasonDefinition/1")
        let requested = try await server.customerAccount().requestReturn("gid://shopify/Order/6000002", lines: [line])
        let sent = (server.calls.first?.variables["requestedLineItems"] as? [[String: Any]])?.first
        XCTAssertEqual(sent?["quantity"] as? Int, 1)
        XCTAssertEqual(requested, OrderReturn(id: "gid://shopify/Return/3000001", name: "#1002-R1", status: "REQUESTED"))
    }
}
