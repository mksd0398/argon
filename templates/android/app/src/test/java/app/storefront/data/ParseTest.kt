package app.storefront.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A captured mock.shop response's `data` object from src/test/resources/fixtures. */
internal fun fixture(name: String): JsonObject =
    json(ParseTest::class.java.getResource("/fixtures/$name.json")!!.readText())

internal fun json(text: String): JsonObject = Json.parseToJsonElement(text).jsonObject

class ParseTest {
    // Shaped like Customer.graphql and Order.graphql (no captured response: the Customer Account API needs a signed-in customer).
    @Test
    fun customerAndOrderFollowTheirQueries() {
        val customer = parseCustomer(
            json(
                """{"firstName":"Ada","lastName":null,"emailAddress":{"emailAddress":"ada@example.com"},"orders":{"nodes":[
                {"id":"gid://shopify/Order/1","name":"#1001","processedAt":"2026-10-01T10:00:00Z","financialStatus":"PAID",
                "totalPrice":{"amount":"190.0","currencyCode":"CAD"}}]}}""",
            ),
        )
        assertEquals("Ada", customer.name)
        assertEquals("ada@example.com", customer.email)
        assertEquals(OrderSummary("gid://shopify/Order/1", "#1001", "2026-10-01T10:00:00Z", "PAID", Money("190.0", "CAD")), customer.orders.single())

        val order = parseOrder(
            json(
                """{"id":"gid://shopify/Order/1","name":"#1001","processedAt":"2026-10-01T10:00:00Z","financialStatus":"PAID",
                "fulfillments":{"nodes":[{"status":"SUCCESS"}]},"lineItems":{"nodes":[{"title":"Hoodie","variantTitle":"Small / Green",
                "quantity":2,"image":{"url":"https://cdn.test/h.jpg"},"totalPrice":{"amount":"180.0","currencyCode":"CAD"}}]},
                "subtotal":{"amount":"180.0","currencyCode":"CAD"},"totalPrice":{"amount":"190.0","currencyCode":"CAD"}}""",
            ),
        )
        assertEquals(listOf("SUCCESS"), order.fulfillments)
        assertEquals(OrderLine("Hoodie", "Small / Green", 2, Img("https://cdn.test/h.jpg", null, null, null), Money("180.0", "CAD")), order.lines.single())
        assertEquals(Money("180.0", "CAD"), order.subtotal)
        assertEquals(Money("190.0", "CAD"), order.total)
    }

    @Test
    fun productHasAllOptionsAndVariants() {
        val raw = fixture("product").obj("product")!!
        val product = parseProduct(raw)
        assertEquals(listOf("Size", "Color"), product.options.map { it.first })
        assertEquals(raw.nodes("variants").size, product.variants.size)
        assertEquals(mapOf("Size" to "Small", "Color" to "Green"), product.variants[0].options)
        assertTrue(product.images.isNotEmpty())
        assertTrue("unset metafields come back null and are skipped", product.metafields.isEmpty())
    }

    @Test
    fun cartHasEveryLine() {
        val raw = fixture("cart").obj("cart")!!
        val cart = parseCart(raw)
        assertEquals(raw.obj("lines")!!.objects("nodes").size, cart.lines.size)
        assertEquals(3, cart.totalQuantity)
    }

    @Test
    fun compareAtOnlyWhenAbovePrice() {
        fun card(compareAt: String) = parseProductCard(json("""
            {"id":"gid://shopify/Product/1","handle":"tee","title":"Tee","availableForSale":true,"featuredImage":null,
             "priceRange":{"minVariantPrice":{"amount":"40.0","currencyCode":"USD"}},
             "compareAtPriceRange":{"minVariantPrice":{"amount":"$compareAt","currencyCode":"USD"}}}
        """))
        assertNull(card("40.0").compareAt)
        assertEquals(Money("50.0", "USD"), card("50.0").compareAt)
    }

    @Test
    fun collectionPage() {
        val page = parseProductPage(fixture("collection_men").obj("collection")!!.obj("products")!!, "filters")
        assertEquals(10, page.items.size)
        assertFalse(page.hasNext)
        assertTrue(page.endCursor!!.isNotEmpty())
    }

    @Test
    fun brandAndMenuUseTheShopHosts() {
        val brand = parseBrand(fixture("shop").obj("shop")!!, "mock.shop")
        assertEquals(setOf("mock.shop", "demostore.hydrogen.mock.shop"), brand.hosts)
        assertNull("mock.shop has no brand colours", brand.accent)
        val menu = parseMenu(fixture("menu").obj("menu")!!, brand.hosts)
        assertEquals(MenuItem("Men", Route.Collection("men"), emptyList()), menu[0])
    }
}
