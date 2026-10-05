package app.storefront.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SectionsTest {
    @Test
    fun homeKeepsKnownSectionsAndSkipsUnknownAndEmpty() {
        val sections = Sections.fromHome(fixture("home_screen"))
        assertEquals(
            listOf(Section.Banner::class, Section.Products::class, Section.Collections::class),
            sections.map { it::class },
        )
        val banner = sections[0] as Section.Banner
        assertEquals("hero", banner.style)
        assertEquals(Route.Collection("men"), banner.link)
        val products = sections[1] as Section.Products
        assertEquals("collection products, cut to limit 4", 4, products.items.size)
        assertEquals("style defaults to carousel", "carousel", products.style)
    }

    @Test
    fun missingScreenGivesNoSections() {
        assertEquals(emptyList<Section>(), Sections.fromHome(json("""{"metaobject":null}""")))
    }

    @Test
    fun fallbackWithoutCoverStartsWithCollections() {
        val brand = parseBrand(fixture("shop").obj("shop")!!, "mock.shop")
        val sections = Sections.fallback(brand, fixture("fallback_home"))
        assertTrue(sections.isNotEmpty())
        assertTrue(sections.first() is Section.Collections)
        assertTrue(sections.any { it is Section.Products && it.style == "carousel" && it.items.isNotEmpty() })
    }

    @Test
    fun emptyObjectsAreSkippedNotCrashed() {
        val card = fixture("fallback_home").nodes("collections").first().nodes("products").first()
        val data = json("""{"metaobject":{"field":{"references":{"nodes":[
            {},
            {"type":"mobile_products","fields":[{"key":"products","references":{"nodes":[{}, $card]}}]}
        ]}}}}""")
        val sections = Sections.fromHome(data)
        assertEquals(1, sections.size)
        assertEquals(1, (sections[0] as Section.Products).items.size)
    }
}
