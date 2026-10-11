package app.storefront.data

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SectionsTest {
    private val api = fixtureStorefront()
    private val brand = runBlocking { api.shop().toBrand("mock.shop") }

    /** The home sections of a HomeScreen response [data]. */
    private fun home(data: String) = runBlocking { Sections.fromHome(StorefrontApi({ _, _ -> json(data) }).homeScreen()) }

    @Test
    fun homeKeepsKnownSectionsAndSkipsUnknownAndEmpty() {
        val sections = Sections.fromHome(runBlocking { api.homeScreen() })
        assertEquals(
            listOf(Section.Banner::class, Section.Products::class, Section.Collections::class),
            sections.map { it::class },
        )
        val banner = sections[0] as Section.Banner
        assertEquals("hero", banner.style)
        assertEquals(Route.Collection("men"), banner.link)
        assertTrue(banner.image!!.url.endsWith(".png"))
        val products = sections[1] as Section.Products
        assertEquals("no products listed: the collection's (3, under the limit of 4)", 3, products.items.size)
        assertEquals("style defaults to carousel", "carousel", products.style)
        assertEquals(3, (sections[2] as Section.Collections).items.size)
    }

    @Test
    fun missingScreenGivesNoSections() {
        assertEquals(emptyList<Section>(), home("""{"metaobject":null}"""))
    }

    @Test
    fun fallbackWithoutCoverStartsWithCollections() {
        val sections = Sections.fallback(brand, runBlocking { api.fallbackHome() })
        assertTrue(sections.isNotEmpty())
        assertTrue(sections.first() is Section.Collections)
        assertTrue(sections.any { it is Section.Products && it.style == "carousel" && it.items.isNotEmpty() })
    }

    // Home content

    private val collections = runBlocking { api.fallbackHome() }

    @Test
    fun aStoreWithoutAHomeScreenGetsStockBannersAndItsCollections() {
        val content = Sections.content(HomeTemplate.Grocery, brand, emptyList(), collections)
        assertEquals(listOf("Fresh today", "Fill your basket", "Baked this morning"), content.banners.map { it.heading })
        assertEquals(listOf("Shop now", "Start shopping", "Order now"), content.banners.map { it.buttonLabel })
        assertEquals(
            listOf(1, 2, 3).map { "file:///android_asset/home/home-grocery-$it.jpg" },
            content.banners.map { it.image?.url },
        )
        assertTrue("each opens the first stocked collection", content.banners.all { it.link == Route.Collection("men") })
        assertEquals(listOf("men", "women", "unisex"), content.categories.map { it.handle })
        assertEquals(listOf("Men", "Women", "Unisex"), content.rails.map { it.heading })
        assertEquals(collections[1].products, content.rails[1].items)
    }

    @Test
    fun everyTemplateHasItsOwnThreeBanners() {
        val first = HomeTemplate.entries.associateWith { Sections.content(it, brand, emptyList(), emptyList()).banners }
        assertEquals(
            mapOf(
                HomeTemplate.Fashion to "The new season", HomeTemplate.Beauty to "Your daily ritual",
                HomeTemplate.Grocery to "Fresh today", HomeTemplate.B2B to "Stocked and ready to ship",
            ),
            first.mapValues { it.value[0].heading },
        )
        assertEquals("View bulk pricing", first.getValue(HomeTemplate.B2B)[2].buttonLabel)
        assertEquals("file:///android_asset/home/home-b2b-3.jpg", StockImages.url(HomeTemplate.B2B, 3))
        assertTrue(first.values.all { it.size == 3 })
        assertTrue("no stocked collection: the banners open nothing", first.values.flatten().all { it.link == null })
    }

    @Test
    fun emptyCollectionsAreNotOffered() {
        val empty = collections[0].copy(id = "empty", handle = "empty", products = emptyList())
        val content = Sections.content(HomeTemplate.Fashion, brand, emptyList(), listOf(empty) + collections)
        assertEquals(listOf("men", "women", "unisex"), content.categories.map { it.handle })
        assertEquals(Route.Collection("men"), content.banners[0].link)
        assertEquals(3, content.rails.size)

        val nothing = Sections.content(HomeTemplate.Fashion, brand, emptyList(), listOf(empty))
        assertEquals("the banners stay", 3, nothing.banners.size)
        assertTrue(nothing.categories.isEmpty() && nothing.rails.isEmpty())
    }

    @Test
    fun theStoresOwnSectionsWinPartByPart() {
        val sections = Sections.fromHome(runBlocking { api.homeScreen() }, brand.hosts)
        val content = Sections.content(HomeTemplate.Beauty, brand, sections, collections)
        assertEquals("the store's banner, not the stock ones", listOf("New season"), content.banners.map { it.heading })
        assertEquals(listOf("Featured"), content.rails.map { it.heading })
        assertEquals(listOf("men", "women", "unisex"), content.categories.map { it.handle })

        // a store with only a banner still gets categories and rails from its collections
        val bannerOnly = Sections.content(HomeTemplate.Beauty, brand, sections.filterIsInstance<Section.Banner>(), collections.take(2))
        assertEquals(listOf("New season"), bannerOnly.banners.map { it.heading })
        assertEquals(listOf("men", "women"), bannerOnly.categories.map { it.handle })
        assertEquals(listOf("Men", "Women"), bannerOnly.rails.map { it.heading })

        // collection sections are merged, each collection once
        val twice = sections.filterIsInstance<Section.Collections>().let { it + it }
        assertEquals(3, Sections.content(HomeTemplate.Beauty, brand, twice, emptyList()).categories.size)
    }

    private val cards = fixture("Catalog").getValue("products").jsonObject.getValue("nodes").jsonArray
        .map { JsonObject(it.jsonObject + ("__typename" to JsonPrimitive("Product"))) }

    @Test
    fun theLimitCutsTheProducts() {
        val sections = home(
            """{"metaobject":{"field":{"references":{"nodes":[{"__typename":"Metaobject","id":"m","type":"mobile_products","fields":[
            {"key":"limit","value":"2"},{"key":"style","value":"grid"},{"key":"products","references":{"nodes":[${cards.joinToString(",")}]}}]}]}}}}""",
        )
        val products = sections.single() as Section.Products
        assertEquals(cards.take(2).map { it.getValue("handle").jsonPrimitive.content }, products.items.map { it.handle })
        assertEquals("grid", products.style)
    }

    @Test
    fun brokenReferencesAreSkippedNotCrashed() {
        val card = cards[0]
        val sections = home(
            """{"metaobject":{"field":{"references":{"nodes":[
            {},
            {"__typename":"Metaobject","id":"m1","type":"mobile_products","fields":[{"key":"products","references":{"nodes":[{}, {"__typename":"Collection"}, $card]}}]},
            {"__typename":"Metaobject","id":"m2","type":"mobile_reviews","fields":[]}
            ]}}}}""",
        )
        assertEquals(1, sections.size)
        assertEquals(listOf("gray-leather-sneakers"), (sections[0] as Section.Products).items.map { it.handle })
    }
}
