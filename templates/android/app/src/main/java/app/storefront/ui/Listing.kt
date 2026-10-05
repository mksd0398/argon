package app.storefront.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.storefront.data.Filter
import app.storefront.data.ProductCard
import app.storefront.data.ProductPage
import app.storefront.data.Route
import app.storefront.data.StorefrontException
import app.storefront.data.obj
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** A sort menu entry: [key] is the Storefront sort-key enum value, [reverse] flips it. */
data class Sort(val label: String, val key: String, val reverse: Boolean = false)

// The same five entries, with the sort-key name each query's enum uses (ProductCollectionSortKeys vs ProductSortKeys).
val COLLECTION_SORTS = listOf(
    Sort("Featured", "COLLECTION_DEFAULT"),
    Sort("Best selling", "BEST_SELLING"),
    Sort("Price: low to high", "PRICE"),
    Sort("Price: high to low", "PRICE", reverse = true),
    Sort("Newest", "CREATED", reverse = true),
)
val CATALOG_SORTS = listOf(
    Sort("Featured", "BEST_SELLING"),
    Sort("Best selling", "BEST_SELLING"),
    Sort("Price: low to high", "PRICE"),
    Sort("Price: high to low", "PRICE", reverse = true),
    Sort("Newest", "CREATED_AT", reverse = true),
)
val SEARCH_SORTS = listOf(
    Sort("Relevance", "RELEVANCE"),
    Sort("Price: low to high", "PRICE"),
    Sort("Price: high to low", "PRICE", reverse = true),
)

private const val PAGE_SIZE = 24

/** The object under [key], or a StorefrontException when the response doesn't have it. */
internal fun JsonObject.connection(key: String) = obj(key) ?: throw StorefrontException(listOf("Invalid response"), null)

/** Variables shared by the Collection, Catalog and Search queries; [applied] are filter `input` JSON strings. */
internal fun listingVars(after: String?, sort: Sort, applied: List<String>, extra: Map<String, String> = emptyMap()): JsonObject =
    buildJsonObject {
        for ((name, value) in extra) put(name, value)
        put("first", PAGE_SIZE)
        put("after", after)
        put("sortKey", sort.key)
        put("reverse", sort.reverse)
        if (applied.isNotEmpty()) put("filters", JsonArray(applied.map { Json.parseToJsonElement(it) }))
    }

/**
 * A cursor-paged product list with a sort and filter selection (collection or search results). Plain observable state,
 * so the owning ViewModel keeps it across navigation. [fetch] loads the page after a cursor (null for the first page).
 */
class Listing(
    private val scope: CoroutineScope,
    val sorts: List<Sort>,
    private val fetch: suspend (after: String?, sort: Sort, applied: List<String>) -> ProductPage,
) {
    var sort by mutableStateOf(sorts.first()); private set
    var applied by mutableStateOf(emptyList<String>()); private set
    var items by mutableStateOf(emptyList<ProductCard>()); private set
    var filters by mutableStateOf(emptyList<Filter>()); private set
    var hasNext by mutableStateOf(false); private set

    /** Counts pages that have arrived, even ones that add no new items; a list footer keys its load-more trigger on it. */
    var pagesLoaded by mutableStateOf(0); private set
    var loading by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    private var cursor: String? = null
    private var job: Job? = null
    private var generation = 0

    /**
     * Starts over from the first page, with a new [sort] and/or filter selection. [resetFilters] also forgets the filters
     * the last response offered: pass it when the products behind the list change (a new search query).
     */
    fun reload(sort: Sort = this.sort, applied: List<String> = this.applied, resetFilters: Boolean = false) {
        job?.cancel()
        this.sort = sort
        this.applied = applied
        if (resetFilters) filters = emptyList()
        items = emptyList()
        hasNext = false
        cursor = null
        load()
    }

    fun loadMore() {
        if (hasNext && !loading) load()
    }

    private fun load() {
        loading = true
        error = null
        val mine = ++generation
        job = scope.launch {
            try {
                val first = cursor == null
                val page = fetch(cursor, sort, applied)
                items = (items + page.items).distinctBy { it.id } // a catalog that changes between pages can repeat a product
                cursor = page.endCursor
                hasNext = page.hasNext && page.endCursor != null // without a cursor "more" can only repeat the first page
                pagesLoaded++
                // a filtered first page that comes back without filters keeps the old ones, so the user can still clear them
                if (first && page.filters.isNotEmpty()) filters = page.filters
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: e.toString()
            } finally {
                // a superseded request must not clear the flag of the one that replaced it
                if (mine == generation) loading = false
            }
        }
    }
}

/** Sort and filter bar over a [ProductGrid], with the loading, error (Retry) and empty states of [l]. */
@Composable
fun ListingView(l: Listing, emptyText: String, onOpen: (Route) -> Unit) {
    Column(Modifier.fillMaxSize()) {
        ListingBar(l)
        Box(Modifier.weight(1f).fillMaxWidth()) {
            val error = l.error
            when {
                l.items.isNotEmpty() ->
                    ProductGrid(l.items, l.hasNext, { l.loadMore() }, { onOpen(Route.Product(it.handle)) }, error = error, loadKey = l.pagesLoaded)
                error != null -> ErrorView(error) { l.reload() }
                l.loading -> Spinner()
                else -> Text(emptyText, Modifier.align(Alignment.Center).padding(24.dp))
            }
        }
    }
}
