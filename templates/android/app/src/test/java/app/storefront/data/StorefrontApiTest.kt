package app.storefront.data

import java.util.Locale
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class StorefrontApiTest {
    /** What the facade sent, in order: operation name and variables. */
    private val calls = mutableListOf<Pair<String, JsonObject>>()
    private val names get() = calls.map { it.first }

    /** A StorefrontApi answering with [reply] (the operation's fixture by default). */
    private fun api(locale: Locale? = null, reply: (String) -> JsonObject = ::fixture) =
        StorefrontApi({ name, vars -> calls += name to vars; reply(name) }, locale)

    private fun JsonObject.string(key: String) = get(key)?.jsonPrimitive?.content

    // Context

    @Test
    fun theContextIsPickedOnceFromTheDeviceLocaleWhereTheShopSells() = runBlocking {
        // the fixture shop sells in Canada, in English only
        val s = api(Locale.forLanguageTag("fr-CA"))
        s.shop()
        s.products()
        assertEquals(listOf("Localization", "Shop", "Catalog"), names)
        assertNull("Localization runs in the shop's default context", calls[0].second["country"])
        assertEquals("CA", calls[1].second.string("country"))
        assertNull("French isn't sold: the shop's default language", calls[1].second["language"])
        assertEquals("CA", calls[2].second.string("country"))
        assertEquals(StorefrontContext("CA", null), s.context)
    }

    @Test
    fun aRegionalOrPlainLanguageMatches() {
        val localization = runBlocking { fixtureStorefront().localization() }
        assertEquals(StorefrontContext("CA", "EN"), StorefrontContext.pick(Locale.CANADA, localization))
        assertEquals("not sold in the US", StorefrontContext(null, "EN"), StorefrontContext.pick(Locale.US, localization))
        val portuguese = localization.copy(availableLanguages = listOf(Localization.Language("PT_BR")))
        assertEquals(StorefrontContext(null, "PT_BR"), StorefrontContext.pick(Locale.forLanguageTag("pt-BR"), portuguese))
    }

    @Test
    fun withoutALocaleCallsUseTheShopsDefault() = runBlocking {
        api().shop()
        assertEquals(listOf("Shop"), names)
        assertEquals(JsonObject(emptyMap()), calls[0].second)
    }

    @Test
    fun settingTheContextUsesItAndDropsTheCache() = runBlocking {
        val s = api(Locale.CANADA)
        s.shop()
        s.context = StorefrontContext("US", "ES")
        s.shop()
        assertEquals("a picked context isn't picked again", listOf("Localization", "Shop", "Shop"), names)
        assertEquals("US", calls[2].second.string("country"))
        assertEquals("ES", calls[2].second.string("language"))
    }

    // Caching

    @Test
    fun shopLocalizationPoliciesAndMenusAreKeptForTheSession() = runBlocking {
        val s = api()
        val shop = s.shop()
        assertSame(shop, s.shop())
        s.localization(); s.localization()
        s.policies(); s.policies()
        s.menu("main-menu"); s.menu("main-menu"); s.menu("footer")
        s.product("men-crewneck"); s.product("men-crewneck")
        assertEquals(listOf("Shop", "Localization", "ShopPolicies", "Menu", "Menu", "Product", "Product"), names)
        assertEquals("footer", calls[4].second.string("handle"))
    }

    // Variables

    @Test
    fun aCollectionCarriesItsSortFiltersAndCursor() = runBlocking {
        val s = api()
        s.collection("men", listOf("""{"available":true}"""), "PRICE", reverse = true, after = "c1")
        val vars = calls.single().second
        assertEquals("men", vars.string("handle"))
        assertEquals("24", vars.string("first"))
        assertEquals("c1", vars.string("after"))
        assertEquals("PRICE", vars.string("sortKey"))
        assertEquals("true", vars.string("reverse"))
        assertEquals("filter inputs go as JSON, not strings", "true", (vars["filters"] as JsonArray).single().jsonObject.string("available"))

        s.search("hat")
        val first = calls.last().second
        assertEquals("hat", first.string("query"))
        assertNull("no filters key when none are applied", first["filters"])
        assertNull("no cursor on the first page", first["after"])
        assertNull("the document's default types", first["types"])
    }

    @Test
    fun productVariablesCarryTheSelection() = runBlocking {
        val s = api()
        s.product("men-crewneck", mapOf("Size" to "Small"))
        assertEquals("""[{"name":"Size","value":"Small"}]""", calls.single().second["selectedOptions"].toString())

        s.product("men-crewneck")
        assertEquals("only the handle", setOf("handle"), calls.last().second.keys)
    }

    @Test
    fun productMetafieldsAreTheirOwnQuery() = runBlocking {
        val s = api()
        assertEquals("nothing to ask for: no request", emptyList<Metafield>(), s.productMetafields("men-crewneck", emptyList()))
        assertTrue(calls.isEmpty())

        s.productMetafields("men-crewneck", listOf(MetafieldIdentifier("custom", "care")))
        assertEquals("ProductMetafields", names.single())
        assertEquals("men-crewneck", calls.single().second.string("handle"))
        assertEquals("""[{"namespace":"custom","key":"care"}]""", calls.single().second["metafields"].toString())

        val gone = api { json("""{"product":null}""") }.productMetafields("gone", listOf(MetafieldIdentifier("custom", "care")))
        assertEquals("no such product: none", emptyList<Metafield>(), gone)
    }

    // Buyer

    @Test
    fun theBuyerGoesWithEveryCallAndSettingItDropsTheCache() = runBlocking {
        val s = api()
        s.shop()
        assertNull("retail: no buyer", calls[0].second["buyer"])

        s.buyer = Buyer("tok", "gid://shopify/CompanyLocation/1")
        s.shop()
        s.products()
        s.localization()
        s.cartCreate()
        assertEquals("the shop is asked again for the buyer", listOf("Shop", "Shop", "Catalog", "Localization", "CartCreate"), names)
        for ((name, vars) in calls.drop(1)) {
            assertEquals(name, """{"customerAccessToken":"tok","companyLocationId":"gid://shopify/CompanyLocation/1"}""", vars["buyer"].toString())
        }

        s.buyer = null
        s.shop()
        assertNull("back to retail", calls.last().second["buyer"])
        assertEquals(6, calls.size)
    }

    @Test
    fun aBuyerWithoutACompanyIsJustTheirToken() = runBlocking {
        val s = api()
        s.buyer = Buyer("tok")
        s.shop()
        assertEquals("""{"customerAccessToken":"tok"}""", calls.single().second["buyer"].toString())
    }

    @Test
    fun cartInputsLeaveTheirNullFieldsOut() = runBlocking {
        val s = api()
        s.cartCreate(CartInput(lines = listOf(CartLineInput("v1", 2))))
        assertEquals("""{"lines":[{"merchandiseId":"v1","quantity":2}]}""", calls.single().second["input"].toString())
        s.updateBuyerIdentity("c", CartBuyerIdentityInput(customerAccessToken = "tok"))
        assertEquals("""{"customerAccessToken":"tok"}""", calls.last().second["buyerIdentity"].toString())
        s.updateBuyerIdentity("c", CartBuyerIdentityInput(customerAccessToken = "tok", companyLocationId = "gid://shopify/CompanyLocation/1"))
        assertEquals(
            """{"customerAccessToken":"tok","companyLocationId":"gid://shopify/CompanyLocation/1"}""",
            calls.last().second["buyerIdentity"].toString(),
        )
    }

    // Models

    @Test
    fun aRatingMetafieldIsStarsOutOfFive() {
        assertEquals(4.6, Ratings.parse("""{"value":"4.6","scale_min":"1.0","scale_max":"5.0"}""")!!, 1e-9)
        assertEquals("a plain number", 4.5, Ratings.parse("4.5")!!, 1e-9)
        assertEquals(3.0, Ratings.parse(" 3 ")!!, 1e-9)
        assertEquals("numbers as JSON numbers", 4.0, Ratings.parse("""{"value":4,"scale_max":5}""")!!, 1e-9)
        assertEquals("another scale is brought to 5", 4.0, Ratings.parse("""{"value":"8.0","scale_min":"1.0","scale_max":"10.0"}""")!!, 1e-9)
        assertEquals("no scale: out of 5", 2.5, Ratings.parse("""{"value":"2.5"}""")!!, 1e-9)
        assertEquals("kept to 0...5", 5.0, Ratings.parse("7")!!, 1e-9)
        assertEquals(0.0, Ratings.parse("-1")!!, 1e-9)
        for (unreadable in listOf(null, "", "  ", "great", "{}", """{"value":"n/a"}""", """{"value":"4","scale_max":"0"}""", "[4.6]", "NaN", "4.6 stars")) {
            assertNull("$unreadable", Ratings.parse(unreadable))
        }
    }

    @Test
    fun aQuantityRuleNeverGoesBelowOne() {
        assertEquals("a store without rules sends 0", 1 to 1, QuantityRule(0, null, 0).let { it.min to it.step })
        assertEquals(2 to 6, QuantityRule(2, 40, 6).let { it.min to it.step })
        assertEquals("the defaults: any quantity", Triple(1, null, 1), QuantityRule().let { Triple(it.min, it.maximum, it.step) })
        assertEquals(1 to 1, QuantityRule(-3, null, -1).let { it.min to it.step })
    }

    private fun card(vararg options: ProductOption, available: Boolean = true, max: String? = null) = ProductCard(
        "p", "tee", "Tee",
        priceRange = PriceRange(Money("40.0", "USD"), max?.let { Money(it, "USD") }),
        options = options.toList(),
        firstVariant = CardVariant("v1", available = available),
    )

    private fun option(name: String, vararg values: String) = ProductOption(name = name, optionValues = values.map { ProductOptionValue(name = it) })

    @Test
    fun aCardsColoursAreItsColourOptionsValues() {
        assertEquals(listOf("Red", "Blue"), card(option("Size", "S"), option("Colour", "Red", "Blue")).colors.map { it.name })
        assertEquals(listOf("Red"), card(option("color", "Red")).colors.map { it.name })
        assertEquals(listOf("Nude"), card(option("SHADE", "Nude"), option("Color", "Red")).colors.map { it.name })
        assertTrue("no colour option", card(option("Size", "S", "M")).colors.isEmpty())
        assertTrue("the name has to be the whole word", card(option("Colourway", "Red")).colors.isEmpty())
    }

    @Test
    fun aCardQuickAddsOnlyWhenThereIsNothingToChoose() {
        assertEquals("v1", card(option("Title", "Default Title")).quickAddVariantId)
        assertEquals("v1", card(option("Size", "One size"), option("Color", "Red")).quickAddVariantId)
        assertEquals("no options at all", "v1", card().quickAddVariantId)
        assertNull("a size to choose", card(option("Size", "S", "M")).quickAddVariantId)
        assertNull("sold out", card(option("Title", "Default Title"), available = false).quickAddVariantId)
        assertNull("no variant", card().copy(firstVariant = null).quickAddVariantId)
    }

    @Test
    fun aCardHasAPriceRangeWhenTheDearestVariantCostsMore() {
        assertTrue(card(max = "55.0").hasPriceRange)
        assertFalse(card(max = "40.0").hasPriceRange)
        assertFalse("40.00 is 40.0", card(max = "40.00").hasPriceRange)
        assertFalse("no max selected", card().hasPriceRange)
    }

    @Test
    fun anUnknownTemplateIsTheDefault() {
        assertEquals(HomeTemplate.entries, listOf("fashion", "beauty", "grocery", "b2b").map { HomeTemplate.of(it) })
        assertEquals(HomeTemplate.Fashion, HomeTemplate.of(""))
        assertEquals(HomeTemplate.Fashion, HomeTemplate.of("luxury"))
        assertEquals(HomeTemplate.B2B, HomeTemplate.of(" B2B "))
        assertEquals(CollectionTemplate.entries, listOf("top", "bottom").map { CollectionTemplate.of(it) })
        assertEquals(CollectionTemplate.Top, CollectionTemplate.of(""))
        assertEquals(CollectionTemplate.Top, CollectionTemplate.of("side"))
    }

    @Test
    fun aPolicyIsFoundByItsHandle() = runBlocking {
        val policies = fixtureStorefront().policies()
        assertEquals("Privacy Policy", policies.policy("privacy-policy")?.title)
        assertEquals(policies.refundPolicy, policies.policy("refund-policy"))
        assertNull(policies.policy("no-such-policy"))
        assertTrue(policies.all.none { it.handle == "terms-of-sale" })
    }

    @Test
    fun aCustomerOrderIsNotACompanyOrder() = runBlocking {
        val order = CustomerAccountApi { _, _ ->
            json(
                """{"order":{"id":"o","name":"#1","processedAt":"2026-10-01T10:00:00Z","totalPrice":{"amount":"9.0","currencyCode":"CAD"},
                "purchasingEntity":{"__typename":"Customer"},"returnInformation":{"returnableLineItems":{"nodes":[]}}}}""",
            )
        }.order("o")!!
        assertNull(order.purchasingCompany)
        assertFalse("nothing to return", order.hasReturnableItems)
        assertTrue(order.transactions.isEmpty() && order.refunds.isEmpty() && order.returns.isEmpty())
    }

    // Pages

    @Test
    fun aPageWithoutPageInfoHasNoNextPage() = runBlocking {
        val page = api { json("""{"metaobjects":{"nodes":[{"id":"gid://shopify/Metaobject/1","type":"t","fields":[]}]}}""") }.metaobjects("t")
        assertEquals(1, page.items.size)
        assertFalse(page.hasNextPage)
        assertNull(page.endCursor)
    }

    // Polymorphic results

    @Test
    fun productMediaDecodeByType() = runBlocking {
        val preview = """"previewImage":{"url":"https://cdn.test/p.jpg"}"""
        val product = api {
            json(
                """{"product":{"id":"p","handle":"h","title":"T","media":{"nodes":[
                {"__typename":"MediaImage","id":"m1","mediaContentType":"IMAGE","alt":"Front",$preview,"image":{"url":"https://cdn.test/i.jpg","width":10}},
                {"__typename":"Video","id":"m2",$preview,"sources":[{"url":"https://cdn.test/v.mp4","mimeType":"video/mp4","width":640,"height":360}]},
                {"__typename":"ExternalVideo","id":"m3",$preview,"host":"YOUTUBE","embedUrl":"https://youtube.test/e","originUrl":"https://youtube.test/w"},
                {"__typename":"Model3d","id":"m4",$preview,"sources":[{"url":"https://cdn.test/m.glb","format":"glb","filesize":1024}]},
                {"__typename":"Hologram","id":"m5",$preview}
                ]}}}""",
            )
        }.product("h")!!
        val (image, video, external, model, other) = product.media
        assertEquals(Media.Image("m1", "Front", Img("https://cdn.test/p.jpg"), Img("https://cdn.test/i.jpg", width = 10)), image)
        assertEquals(640, (video as Media.Video).sources.single().width)
        assertEquals("YOUTUBE", (external as Media.ExternalVideo).host)
        assertEquals(1024, (model as Media.Model3d).sources.single().filesize)
        assertEquals(Media.Other("Hologram", "m5", previewImage = Img("https://cdn.test/p.jpg")), other)
        assertEquals("only images are gallery images", listOf(Img("https://cdn.test/i.jpg", width = 10)), product.images)
    }

    @Test
    fun searchResultsDecodeByTypeAndKeepFilterInputsAsJson() = runBlocking {
        val card = fixture("Catalog").getValue("products").jsonObject.getValue("nodes").let { (it as JsonArray)[0].jsonObject }
        val page = api {
            json(
                """{"search":{"totalCount":4,"pageInfo":{"hasNextPage":true,"endCursor":"c2"},
                "productFilters":[{"id":"f","label":"Color","type":"LIST","values":[
                  {"id":"v1","label":"Red","count":2,"input":"{\"variantOption\":{\"name\":\"Color\",\"value\":\"Red\"}}"},
                  {"id":"v2","label":"In stock","count":5,"input":{"available":true}}]}],
                "nodes":[${JsonObject(card + ("__typename" to JsonPrimitive("Product")))},
                  {"__typename":"Page","id":"pg","handle":"faq","title":"FAQ"},
                  {"__typename":"Article","id":"a","handle":"news-1","title":"News","blog":{"handle":"news"}},
                  {"__typename":"Collection"}]}}""",
            )
        }.search("x", types = listOf("PRODUCT", "PAGE", "ARTICLE"))
        assertEquals(listOf(ProductCard::class, StorePage::class, Article::class, SearchResult.Other::class), page.items.map { it::class })
        assertEquals("gray-leather-sneakers", (page.items[0] as ProductCard).handle)
        assertEquals("news", (page.items[2] as Article).blog?.handle)
        assertEquals(SearchResult.Other("Collection"), page.items[3])
        assertEquals("c2", page.endCursor)
        assertEquals(
            listOf("""{"variantOption":{"name":"Color","value":"Red"}}""", """{"available":true}"""),
            page.filters.single().values.map { it.input },
        )
        assertEquals("""["PRODUCT","PAGE","ARTICLE"]""", calls.single().second["types"].toString())
    }

    @Test
    fun menuItemsRouteByTheirResourceType() = runBlocking {
        val menu = api {
            json(
                """{"menu":{"id":"m","handle":"main-menu","title":"Main","items":[
                {"id":"1","title":"Tee","url":"https://shop.test/products/tee","type":"PRODUCT","resource":{"__typename":"Product","handle":"tee"}},
                {"id":"2","title":"Sale","url":"https://shop.test/collections/sale","type":"COLLECTION","resource":{"__typename":"Collection","handle":"sale"},
                 "items":[{"id":"3","title":"Story","url":"https://shop.test/blogs/news/story","type":"ARTICLE",
                   "resource":{"__typename":"Article","handle":"story","blog":{"handle":"news"}}}]},
                {"id":"4","title":"FAQ","url":"https://shop.test/pages/faq","type":"PAGE","resource":{"__typename":"Page","handle":"faq"}},
                {"id":"5","title":"Nowhere","url":"mailto:a@b.test","type":"HTTP"}]}}""",
            )
        }.menu("main-menu")!!
        assertEquals(Menu.Resource("Article", "story", ResourceRef("news")), menu.items[1].items.single().resource)
        assertEquals(
            listOf(
                MenuItem("Tee", Route.Product("tee"), emptyList()),
                MenuItem("Sale", Route.Collection("sale"), listOf(MenuItem("Story", Route.Web("https://shop.test/blogs/news/story"), emptyList()))),
                MenuItem("FAQ", Route.Web("https://shop.test/pages/faq"), emptyList()),
            ),
            menuTree(menu.items, setOf("shop.test")),
        )
    }

    @Test
    fun theFixtureShopsHostsKeepItsMenuInTheApp() = runBlocking {
        val s = fixtureStorefront()
        val brand = s.shop().toBrand("mock.shop")
        assertEquals(setOf("mock.shop", "demostore.hydrogen.mock.shop"), brand.hosts)
        assertNull("mock.shop has no brand colours", brand.accent)
        assertEquals(MenuItem("Men", Route.Collection("men"), emptyList()), menuTree(s.menu("main-menu")!!.items, brand.hosts)[0])
    }

    @Test
    fun anOrderDiscountIsAnAmountOrAPercentage() = runBlocking {
        val order = CustomerAccountApi { _, _ ->
            json(
                """{"order":{"id":"o","name":"#1","processedAt":"2026-10-01T10:00:00Z","totalPrice":{"amount":"9.0","currencyCode":"CAD"},
                "discountApplications":{"nodes":[
                  {"value":{"__typename":"MoneyV2","amount":"5.0","currencyCode":"CAD"}},
                  {"value":{"__typename":"PricingPercentageValue","percentage":12.5}}]}}}""",
            )
        }.order("o")!!
        assertEquals(listOf(Money("5.0", "CAD"), PricingValue.Percentage(12.5)), order.discountApplications.map { it.value })
        assertTrue("nothing fulfilled yet", order.fulfillments.isEmpty())
    }

    @Test
    fun compareAtOnlyWhenAbovePrice() {
        fun card(compareAt: String) = ProductCard("p", "tee", "Tee", priceRange = PriceRange(Money("40.0", "USD")), compareAtPriceRange = PriceRange(Money(compareAt, "USD")))
        assertNull(card("40.0").compareAt)
        assertNull(card("0.0").compareAt)
        assertEquals(Money("50.0", "USD"), card("50.0").compareAt)
    }

    // Errors

    private fun cartPayload(name: String, cart: String, errors: String = "[]", warnings: String = "[]") =
        json("""{"${name.replaceFirstChar { it.lowercase() }}":{"cart":$cart,"userErrors":$errors,"warnings":$warnings}}""")

    private val cartJson get() = fixture("Cart").getValue("cart").toString()

    @Test
    fun cartUserErrorsAreThrownWithTheCartBesideThem() = runBlocking {
        val errors = """[{"field":["lines","0","quantity"],"message":"Only 2 left","code":"MERCHANDISE_NOT_ENOUGH_STOCK"},{"field":null,"message":"Try again","code":null}]"""
        val e = assertThrows(ArgonApiError.UserErrors::class.java) {
            runBlocking { api { cartPayload(it, cartJson, errors) }.updateLines("c", listOf(CartLineUpdateInput("l", 9))) }
        }
        assertEquals(
            listOf(UserError(listOf("lines", "0", "quantity"), "Only 2 left", "MERCHANDISE_NOT_ENOUGH_STOCK"), UserError(null, "Try again", null)),
            e.errors,
        )
        assertEquals("Only 2 left\nTry again", e.message)
        assertEquals(3, e.cart?.totalQuantity)
    }

    @Test
    fun aMutationWithoutACartIsRefused() = runBlocking {
        val e = assertThrows(ArgonApiError.UserErrors::class.java) { runBlocking { api { cartPayload(it, "null") }.cartCreate() } }
        assertEquals("The cart is unavailable", e.message)
        assertNull(e.cart)

        val missing = assertThrows(ArgonApiError.Decoding::class.java) { runBlocking { api { json("{}") }.addLines("c", emptyList()) } }
        assertEquals("CartLinesAdd", missing.operation)
    }

    @Test
    fun warningsComeBackOnTheCartNotThrown() = runBlocking {
        val cart = api { cartPayload(it, cartJson, warnings = """[{"code":"MERCHANDISE_NOT_ENOUGH_STOCK","message":"Only 2 left","target":"l"}]""") }
            .addLines("c", listOf(CartLineInput("v", 3)))
        assertEquals(listOf(CartWarning("MERCHANDISE_NOT_ENOUGH_STOCK", "Only 2 left", "l")), cart.warnings)
    }

    @Test
    fun aResponseTheModelDoesntFitIsADecodingError() = runBlocking {
        val e = assertThrows(ArgonApiError.Decoding::class.java) {
            runBlocking { api { json("""{"product":{"id":"p","handle":"h"}}""") }.product("h") }
        }
        assertEquals("Product", e.operation)
        assertTrue(e.detail, "title" in e.detail)
        assertEquals("Invalid response", e.message)
    }

    @Test
    fun customerUserErrorsAreThrown() = runBlocking {
        val account = CustomerAccountApi { _, _ ->
            json("""{"customerUpdate":{"customer":null,"userErrors":[{"field":["input","firstName"],"message":"First name is too long","code":"TOO_LONG"}]}}""")
        }
        val e = assertThrows(ArgonApiError.UserErrors::class.java) { runBlocking { account.updateName("A".repeat(300), null) } }
        assertEquals("TOO_LONG", e.errors.single().code)
    }

    // Sample account

    @Test
    fun theSampleAccountAnswersEveryOperationFromItsFile() = runBlocking {
        val read = mutableListOf<String>()
        // the CLI copies each Customer Account fixture to assets/sample/<Operation>.sample.json
        val account = CustomerAccountApi(
            sampleTransport { path ->
                read += path
                StorefrontApiTest::class.java.getResource("/fixtures/" + path.removePrefix("sample/").replace(".sample.json", ".json"))!!.readText()
            },
        )
        assertEquals("Ada Lovelace", account.customer().name)
        assertEquals("mutations answer their sample too: nothing is saved", "Ada King", account.updateName("Zed", null).displayName)
        assertEquals("Analytical Engines Ltd", account.companies().single().company.name)
        assertEquals(listOf("sample/Customer.sample.json", "sample/CustomerUpdate.sample.json", "sample/CustomerCompanies.sample.json"), read)

        val missing = assertThrows(ArgonApiError.Decoding::class.java) {
            runBlocking { CustomerAccountApi(sampleTransport { throw java.io.FileNotFoundException(it) }).customer() }
        }
        assertEquals("Customer", missing.operation)
        assertEquals("no sample", missing.detail)
    }

    @Test
    fun transportErrorsPassThrough() = runBlocking {
        val http = ArgonApiError.Http(503)
        val e = assertThrows(ArgonApiError.Http::class.java) { runBlocking { StorefrontApi({ _, _ -> throw http }).shop() } }
        assertSame(http, e)
    }
}
