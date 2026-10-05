package app.storefront.ui

import app.storefront.data.Filter
import app.storefront.data.FilterValue
import app.storefront.data.Money
import app.storefront.data.ProductCard
import app.storefront.data.ProductPage
import app.storefront.data.StorefrontException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ListingTest {
    // Unconfined runs the launched load inline, and the fake fetches never suspend, so each call completes before it returns.
    private val scope = CoroutineScope(Dispatchers.Unconfined)

    private fun card(id: String) = ProductCard(id, "h-$id", "T-$id", true, null, Money("1.00", "USD"), null)
    private fun page(ids: List<String>, next: String?, filters: List<Filter> = emptyList()) =
        ProductPage(ids.map(::card), filters, next, next != null)

    @Test
    fun pagesAppendFromTheCursorUntilTheLast() {
        val cursors = mutableListOf<String?>()
        val l = Listing(scope, COLLECTION_SORTS) { after, _, _ ->
            cursors += after
            if (after == null) page(listOf("a", "b"), "c1") else page(listOf("c"), null)
        }
        l.reload()
        assertEquals(listOf("a", "b"), l.items.map { it.id })
        assertTrue(l.hasNext)
        l.loadMore()
        assertEquals(listOf("a", "b", "c"), l.items.map { it.id })
        assertFalse(l.hasNext)
        l.loadMore() // nothing left: no request
        assertEquals(listOf<String?>(null, "c1"), cursors)
    }

    @Test
    fun aRepeatedProductIsKeptOnce() {
        val l = Listing(scope, COLLECTION_SORTS) { after, _, _ ->
            if (after == null) page(listOf("a", "b"), "c1") else page(listOf("b", "c"), null)
        }
        l.reload()
        l.loadMore()
        assertEquals(listOf("a", "b", "c"), l.items.map { it.id })
    }

    @Test
    fun reloadStartsOverWithTheNewSortAndFilters() {
        val seen = mutableListOf<Triple<String?, Sort, List<String>>>()
        val l = Listing(scope, COLLECTION_SORTS) { after, sort, applied ->
            seen += Triple(after, sort, applied)
            page(listOf("x${seen.size}"), "next")
        }
        l.reload()
        l.loadMore()
        l.reload(sort = COLLECTION_SORTS[3])
        l.reload(applied = listOf("""{"available":true}"""))
        assertEquals(listOf("x4"), l.items.map { it.id })
        assertEquals(
            listOf(
                Triple(null, COLLECTION_SORTS[0], emptyList<String>()),
                Triple("next", COLLECTION_SORTS[0], emptyList<String>()),
                Triple(null, COLLECTION_SORTS[3], emptyList<String>()),
                Triple(null, COLLECTION_SORTS[3], listOf("""{"available":true}""")),
            ),
            seen,
        )
    }

    @Test
    fun failureShowsTheMessageAndReloadRecovers() {
        var fail = true
        val l = Listing(scope, COLLECTION_SORTS) { _, _, _ ->
            if (fail) throw StorefrontException(listOf("boom"), 200) else page(listOf("a"), null)
        }
        l.reload()
        assertEquals("boom", l.error)
        assertFalse(l.loading)
        assertTrue(l.items.isEmpty())
        fail = false
        l.reload()
        assertNull(l.error)
        assertEquals(listOf("a"), l.items.map { it.id })
    }

    @Test
    fun filtersComeFromTheFirstPageAndSurviveAnEmptyOne() {
        val color = Filter("f", "Color", "LIST", listOf(FilterValue("v", "Red", 2, """{"variantOption":{"name":"Color","value":"Red"}}""")))
        var withFilters = true
        val l = Listing(scope, COLLECTION_SORTS) { after, _, _ ->
            if (after == null) page(listOf("a"), "n", if (withFilters) listOf(color) else emptyList()) else page(listOf("b"), null)
        }
        l.reload()
        assertEquals(listOf(color), l.filters)
        l.loadMore() // later pages carry no filters of their own
        assertEquals(listOf(color), l.filters)
        withFilters = false
        l.reload(applied = listOf("""{"available":true}"""))
        assertEquals(listOf(color), l.filters)
    }

    @Test
    fun variablesCarrySortFiltersAndCursor() {
        val vars = listingVars(null, COLLECTION_SORTS[3], listOf("""{"available":true}"""), mapOf("handle" to "men"))
        assertEquals("men", vars["handle"]!!.jsonPrimitive.content)
        assertEquals(24, vars["first"]!!.jsonPrimitive.content.toInt())
        assertEquals(JsonNull, vars["after"])
        assertEquals("PRICE", vars["sortKey"]!!.jsonPrimitive.content)
        assertTrue(vars["reverse"]!!.jsonPrimitive.boolean)
        val filters = vars["filters"] as JsonArray
        assertTrue(filters.single().jsonObject["available"]!!.jsonPrimitive.boolean)

        val next = listingVars("c1", SEARCH_SORTS[0], emptyList())
        assertEquals(JsonPrimitive("c1"), next["after"])
        assertEquals("RELEVANCE", next["sortKey"]!!.jsonPrimitive.content)
        assertNull("no filters key when none are applied", next["filters"])
    }

    @Test
    fun priceFilterGivesMinAndOrMax() {
        assertEquals("""{"price":{"min":10.0,"max":50.5}}""", priceFilter("10", " 50.5 "))
        assertEquals("""{"price":{"max":20.0}}""", priceFilter("", "20"))
        assertNull(priceFilter("", "abc"))
    }
}
