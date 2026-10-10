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
