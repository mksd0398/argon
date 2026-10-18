package app.storefront.ui.sections

import androidx.compose.ui.graphics.toArgb
import app.storefront.data.CollectionCard
import app.storefront.data.Money
import app.storefront.data.PriceRange
import app.storefront.data.ProductCard
import app.storefront.data.ScreenTemplate
import app.storefront.data.SectionContent
import app.storefront.data.SectionNodes
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SectionViewsTest {
    private fun card(n: Int) = ProductCard("gid://shopify/Product/$n", "p$n", "P$n", priceRange = PriceRange(Money("1.0", "USD")))

    private val collection = CollectionCard("gid://shopify/Collection/1", "men", "Men", products = (1..5).map(::card))

    private fun env(nodes: SectionNodes) = SectionEnv(
        ScreenSections("home", "Home", ScreenTemplate(emptyList()), nodes, null, emptyList(), emptyList(), null),
        emptyMap(),
        mutableSetOf(),
    ) {}

    @Test
    fun productsAreTheListedOnesElseTheCollectionsFirstLimit() {
        val env = env(SectionNodes(mapOf(card(9).id to card(9)), mapOf(collection.id to collection)))
        val fromCollection = SectionContent.Products(null, collection.id, emptyList(), "carousel", 3, true)
        assertEquals(listOf("p1", "p2", "p3"), productsOf(fromCollection, env).map { it.handle })
        // listed products win, and one that didn't load is left out
        val listed = fromCollection.copy(products = listOf(card(9).id, card(8).id))
        assertEquals(listOf("p9"), productsOf(listed, env).map { it.handle })
        assertEquals(emptyList<ProductCard>(), productsOf(fromCollection, env(SectionNodes())))
    }

    @Test
    fun countdownParts() {
        val now = Instant.parse("2026-10-19T08:00:00Z")
        assertEquals(listOf(1L, 2L, 3L, 4L), remaining(Instant.parse("2026-10-20T10:03:04Z"), now))
        assertEquals("over: all zero", listOf(0L, 0L, 0L, 0L), remaining(now.minusSeconds(5), now))
    }

    @Test
    fun colorsAndHeights() {
        assertEquals(0xFF1F6FEB.toInt(), color("#1F6FEB")!!.toArgb())
        assertNull(color("red"))
        assertEquals(4f / 5f, bannerRatio("large"))
        assertEquals(21f / 9f, bannerRatio("small"))
    }
}
