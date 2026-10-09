package app.storefront.ui

import app.storefront.data.Filter
import app.storefront.data.FilterValue
import app.storefront.data.ArgonApiError
import app.storefront.data.Money
import app.storefront.data.Page
import app.storefront.data.PriceRange
import app.storefront.data.ProductCard
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ListingTest {
    // Unconfined runs the launched load inline, and the fake fetches never suspend, so each call completes before it returns.
    private val scope = CoroutineScope(Dispatchers.Unconfined)

    private fun card(id: String) = ProductCard(id, "h-$id", "T-$id", true, null, PriceRange(Money("1.00", "USD")))
    private fun page(ids: List<String>, next: String?, filters: List<Filter> = emptyList()) =
        Page(ids.map(::card), next, next != null, filters)

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
            if (fail) throw ArgonApiError.GraphQL(listOf("boom")) else page(listOf("a"), null)
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
    fun aNewQueryDropsTheFiltersOfTheOldOne() {
        val color = Filter("f", "Color", "LIST", listOf(FilterValue("v", "Red", 2, """{"variantOption":{"name":"Color","value":"Red"}}""")))
        var query = "shirt"
        val l = Listing(scope, SEARCH_SORTS) { _, _, _ -> page(listOf("a"), null, if (query == "shirt") listOf(color) else emptyList()) }
        l.reload()
        assertEquals(listOf(color), l.filters)
        query = "hat" // a different search: no facets of its own, and none of the old query's either
        l.reload(SEARCH_SORTS[0], emptyList(), resetFilters = true)
        assertTrue(l.filters.isEmpty())
        assertTrue(l.applied.isEmpty())
    }

    @Test
    fun filtersAreClearedAtOnceNotWhenTheNewPageArrives() {
        val color = Filter("f", "Color", "LIST", emptyList())
        var pending: CompletableDeferred<Page<ProductCard>>? = null
        val l = Listing(scope, SEARCH_SORTS) { _, _, _ -> pending?.await() ?: page(listOf("a"), null, listOf(color)) }
        l.reload()
        pending = CompletableDeferred()
        l.reload(resetFilters = true)
        assertTrue("the old query's facets must not show while the new one loads", l.filters.isEmpty())
        assertTrue(l.loading)
    }

    @Test
    fun pageCounterAdvancesEvenWhenAPageAddsNothing() {
        val l = Listing(scope, COLLECTION_SORTS) { after, _, _ ->
            when (after) {
                null -> page(listOf("a", "b"), "c1")
                "c1" -> page(listOf("a"), "c2") // only a repeat
                else -> page(emptyList(), "c3") // an empty page that still has a next
            }
        }
        l.reload()
        assertEquals(1, l.pagesLoaded)
        l.loadMore()
        assertEquals(2, l.pagesLoaded)
        assertEquals(2, l.items.size)
        l.loadMore()
        assertEquals("a footer keyed on this restarts although items.size didn't change", 3, l.pagesLoaded)
        assertEquals(2, l.items.size)
        assertTrue(l.hasNext)
    }

    @Test
    fun moreWithoutACursorIsNotMore() {
        val l = Listing(scope, COLLECTION_SORTS) { _, _, _ -> Page(listOf(card("a")), null, hasNextPage = true) }
        l.reload()
        assertFalse(l.hasNext)
    }

    @Test
    fun priceFilterGivesMinAndOrMax() {
        assertEquals("""{"price":{"min":10.0,"max":50.5}}""", priceFilter("10", " 50.5 "))
        assertEquals("""{"price":{"max":20.0}}""", priceFilter("", "20"))
        assertEquals("a comma-decimal keyboard's comma", """{"price":{"min":12.5}}""", priceFilter("12,5", ""))
        assertNull(priceFilter("", "abc"))
        assertNull("not a JSON number", priceFilter("NaN", "Infinity"))
    }
}
