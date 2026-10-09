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
    fun productVariablesCarryMetafieldsAndTheSelection() = runBlocking {
        val s = api()
        s.product("men-crewneck", mapOf("Size" to "Small"), listOf(MetafieldIdentifier("custom", "care")))
        val vars = calls.single().second
        assertEquals("""[{"namespace":"custom","key":"care"}]""", vars["metafields"].toString())
        assertEquals("""[{"name":"Size","value":"Small"}]""", vars["selectedOptions"].toString())

        s.product("men-crewneck")
        assertEquals("the identifiers are required, even none", "[]", calls.last().second["metafields"].toString())
        assertNull(calls.last().second["selectedOptions"])
    }

    @Test
    fun cartInputsLeaveTheirNullFieldsOut() = runBlocking {
        val s = api()
        s.cartCreate(CartInput(lines = listOf(CartLineInput("v1", 2))))
        assertEquals("""{"lines":[{"merchandiseId":"v1","quantity":2}]}""", calls.single().second["input"].toString())
        s.updateBuyerIdentity("c", CartBuyerIdentityInput(customerAccessToken = "tok"))
        assertEquals("""{"customerAccessToken":"tok"}""", calls.last().second["buyerIdentity"].toString())
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

    @Test
    fun transportErrorsPassThrough() = runBlocking {
        val http = ArgonApiError.Http(503)
        val e = assertThrows(ArgonApiError.Http::class.java) { runBlocking { StorefrontApi({ _, _ -> throw http }).shop() } }
        assertSame(http, e)
    }
}
