package app.storefront.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonDivider
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonTag
import app.argon.ui.components.ArgonTagStyle
import app.storefront.AppGraph
import app.storefront.data.CollectionTemplate
import app.storefront.data.Filter
import app.storefront.data.Page
import app.storefront.data.ProductCard
import app.storefront.data.Route
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** A sort to choose: [key] is the Storefront sort-key enum value, [reverse] flips it. */
data class Sort(val label: String, val key: String, val reverse: Boolean = false)

// Each list names its sorts with the keys of its own query's enum: ProductCollectionSortKeys, ProductSortKeys,
// SearchSortKeys. The first of a list is the order the list opens in.
val COLLECTION_SORTS = listOf(
    Sort("Featured", "COLLECTION_DEFAULT"),
    Sort("Best selling", "BEST_SELLING"),
    Sort("Price: low to high", "PRICE"),
    Sort("Price: high to low", "PRICE", reverse = true),
    Sort("Newest", "CREATED", reverse = true),
)

// the whole catalogue has no order of the merchant's own ("Featured"): it opens on best selling
val CATALOG_SORTS = listOf(
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

/**
 * A cursor-paged product list with a sort and filter selection (collection or search results). Plain observable state,
 * so the owning ViewModel keeps it across navigation. [fetch] loads the page after a cursor (null for the first page);
 * [applied] are the selected filter values' `input` JSON.
 */
class Listing(
    private val scope: CoroutineScope,
    val sorts: List<Sort>,
    private val fetch: suspend (after: String?, sort: Sort, applied: List<String>) -> Page<ProductCard>,
) {
    var sort by mutableStateOf(sorts.first()); private set
    var applied by mutableStateOf(emptyList<String>()); private set
    var items by mutableStateOf(emptyList<ProductCard>()); private set
    var filters by mutableStateOf(emptyList<Filter>()); private set
    var hasNext by mutableStateOf(false); private set

    /** The currency the list's prices are in, once a product has shown it: what a price filter's amounts are written in. */
    var currencyCode by mutableStateOf<String?>(null); private set

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
                hasNext = page.hasNextPage && page.endCursor != null // without a cursor "more" can only repeat the first page
                pagesLoaded++
                page.items.firstOrNull()?.let { currencyCode = it.price.currencyCode }
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

// The filter selection is `Listing.applied`: the `input` JSON of every selected filter value, in the order they were
// selected (a price range is one entry, `{"price":{"min":10.0,"max":50.0}}`, see FilterSheet.kt).

/** [applied] with [input] added, or taken out when it is there: a checkbox, a swatch or a switch was tapped. */
internal fun toggled(applied: List<String>, input: String): List<String> = if (input in applied) applied - input else applied + input

/** Whether [applied] has a value of [filter]: its chip shows as selected. */
internal fun isActive(filter: Filter, applied: List<String>): Boolean =
    if (filter.type == "PRICE_RANGE") priceSelection(applied) != null else filter.values.any { it.input in applied }

/** A selected filter value as a removable tag: the [input] to take out of the selection, and the [label] shown. */
data class ActiveFilter(val input: String, val label: String)

/**
 * The tags of [applied], in its order. A value is named by its label among [filters]; a switch by its filter's label
 * ("On sale", not "true"); a price range by its two prices (in [currencyCode] when known); and a value the list no
 * longer offers by the last word of its input (`{"variantOption":{"name":"color","value":"Green"}}` is "Green"), so it can
 * still be removed.
 */
internal fun activeFilters(applied: List<String>, filters: List<Filter>, currencyCode: String? = null): List<ActiveFilter> = applied.map { input ->
    val price = priceRange(input)
    val filter = filters.firstOrNull { candidate -> candidate.values.any { it.input == input } }
    val label = when {
        price != null -> listOfNotNull(price.first, price.second).joinToString(" – ") { priceText(it, currencyCode) }
        filter == null -> lastValue(runCatching { Json.parseToJsonElement(input) }.getOrNull())
        filter.type == "BOOLEAN" -> filter.label
        else -> filter.values.first { it.input == input }.label
    }
    ActiveFilter(input, label.ifBlank { input })
}

private tailrec fun lastValue(element: JsonElement?): String = when (element) {
    is JsonObject -> lastValue(element.values.lastOrNull())
    is JsonPrimitive -> element.content
    else -> ""
}

/** "14 products", "1 product"; "24+ products" while there are more pages to load. */
internal fun resultCount(loaded: Int, hasNext: Boolean): String =
    if (hasNext) "$loaded+ products" else if (loaded == 1) "1 product" else "$loaded products"

/** "Filters (2)": [label] with how many are selected; just the label when none is. */
internal fun countLabel(label: String, count: Int): String = if (count > 0) "$label ($count)" else label

// room under the grid's last row for the floating pill of the `bottom` template
private val PillClearance = 80.dp

/**
 * A product list in the store's collection [template] (`AppGraph.collectionTemplate`), with the loading, error (Retry)
 * and empty states of [l]. Over the grid, scrolling with it: the [description] (three lines, "Read more"), the selected
 * filters as removable tags with "Clear all", and in the `bottom` template the result count. The sort and filter
 * controls are a bar pinned over the grid (`top`) or a pill floating over its bottom edge (`bottom`); both open the same
 * sort and filter sheets. Filters show only when the list offers any (the whole catalogue has none).
 */
@Composable
fun ListingView(
    l: Listing,
    emptyText: String,
    onOpen: (Route) -> Unit,
    description: String = "",
    template: CollectionTemplate = AppGraph.collectionTemplate,
) {
    val spacing = ArgonTheme.spacing
    var sortOpen by remember { mutableStateOf(false) }
    // the filter sheet: closed (null), or open at the filter with this id ("": at its top)
    var filtersAt by remember { mutableStateOf<String?>(null) }
    var readMore by rememberSaveable { mutableStateOf(false) }
    // only the filters the sheet has a control for
    val filters = l.filters.filter { filterControl(it) != null }
    val hasFilters = filters.isNotEmpty() || l.applied.isNotEmpty()
    val active = activeFilters(l.applied, l.filters, l.currencyCode)
    val bottom = template == CollectionTemplate.Bottom
    val count = if (bottom && l.items.isNotEmpty()) resultCount(l.items.size, l.hasNext) else null

    // what scrolls away over the grid; null when there is nothing to put there
    val header: (@Composable () -> Unit)? = if (description.isBlank() && active.isEmpty() && count == null) null else {
        {
            Column(verticalArrangement = Arrangement.spacedBy(spacing.s)) {
                if (description.isNotBlank()) Description(description, readMore) { readMore = true }
                if (active.isNotEmpty()) {
                    ActiveFilters(active, onRemove = { l.reload(applied = l.applied - it) }, onClear = { l.reload(applied = emptyList()) })
                }
                if (count != null) Text(count, style = ArgonTheme.type.label, color = ArgonTheme.colors.muted)
            }
        }
    }

    Column(Modifier.fillMaxSize()) {
        if (!bottom) ListingBar(filters, l.applied, hasFilters, onSort = { sortOpen = true }, onFilters = { filtersAt = it })
        Box(Modifier.weight(1f).fillMaxWidth()) {
            val error = l.error
            if (l.items.isNotEmpty()) {
                ProductGrid(
                    l.items,
                    l.hasNext,
                    { l.loadMore() },
                    { onOpen(Route.Product(it.handle)) },
                    error = error,
                    loadKey = l.pagesLoaded,
                    contentPadding = PaddingValues(start = spacing.l, top = spacing.l, end = spacing.l, bottom = if (bottom) PillClearance else spacing.l),
                    header = header,
                )
            } else {
                // no products (yet): the header stays, so a filter that leaves nothing can be taken off again
                Column(Modifier.fillMaxSize()) {
                    if (header != null) Box(Modifier.padding(spacing.l)) { header() }
                    Box(Modifier.weight(1f).fillMaxWidth()) {
                        when {
                            error != null -> ErrorView(error) { l.reload() }
                            l.loading -> Spinner()
                            else -> Text(
                                if (l.applied.isEmpty()) emptyText else "No products match these filters.",
                                Modifier.align(Alignment.Center).padding(spacing.xl),
                                style = ArgonTheme.type.body,
                                color = ArgonTheme.colors.muted,
                                textAlign = TextAlign.Center,
                            )
                        }
                    }
                }
            }
            if (bottom) {
                ListingPill(l.applied.size, hasFilters, onSort = { sortOpen = true }, onFilters = { filtersAt = "" }, Modifier.align(Alignment.BottomCenter))
            }
        }
    }

    SortSheet(sortOpen, l.sorts, l.sort, onSelect = { sortOpen = false; l.reload(sort = it) }, onDismiss = { sortOpen = false })
    FilterSheet(
        isPresented = filtersAt != null,
        filters = filters,
        applied = l.applied,
        // a change applies at once: the list reloads behind the sheet, and the sheet's button says how many it leaves
        onChange = { l.reload(applied = it) },
        onDismiss = { filtersAt = null },
        results = if (l.loading || l.error != null) null else resultCount(l.items.size, l.hasNext),
        currencyCode = l.currencyCode,
        scrollTo = filtersAt,
    )
}

/** A collection's description: three lines, and "Read more" to show the rest when there is more. */
@Composable
private fun Description(text: String, expanded: Boolean, onExpand: () -> Unit) {
    var cut by remember { mutableStateOf(false) }
    Column {
        Text(
            text,
            style = ArgonTheme.type.body,
            color = ArgonTheme.colors.muted,
            maxLines = if (expanded) Int.MAX_VALUE else 3,
            overflow = TextOverflow.Ellipsis,
            onTextLayout = { cut = it.hasVisualOverflow },
        )
        if (cut && !expanded) {
            Text(
                "Read more",
                Modifier.clickable(role = Role.Button, onClick = onExpand).heightIn(min = 44.dp).wrapContentHeight(),
                style = ArgonTheme.type.label,
                color = ArgonTheme.colors.ink,
            )
        }
    }
}

/** The selected filters as tags (a tap takes one off), wrapping onto more lines, then "Clear all". */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ActiveFilters(active: List<ActiveFilter>, onRemove: (String) -> Unit, onClear: () -> Unit) =
    FlowRow(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
        for (filter in active) {
            ArgonTag(
                filter.label,
                Modifier.align(Alignment.CenterVertically),
                style = ArgonTagStyle.Input,
                onClick = { onRemove(filter.input) },
                onRemove = { onRemove(filter.input) },
            )
        }
        ArgonButton("Clear all", Modifier.align(Alignment.CenterVertically), style = ArgonButtonStyle.Tertiary, size = ArgonSize.S, action = onClear)
    }

/**
 * The `top` template's controls, pinned over the grid: Sort, "Filters (n)", then a chip per filter that opens the sheet
 * at that filter ([onFilters] gets its id, "" for the sheet's top). The chips scroll sideways; the two buttons stay.
 */
@Composable
private fun ListingBar(filters: List<Filter>, applied: List<String>, hasFilters: Boolean, onSort: () -> Unit, onFilters: (String) -> Unit) {
    val spacing = ArgonTheme.spacing
    Column {
        Row(
            Modifier.fillMaxWidth().padding(start = spacing.l, top = spacing.xs, bottom = spacing.xs),
            horizontalArrangement = Arrangement.spacedBy(spacing.s),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ArgonButton("Sort", style = ArgonButtonStyle.Secondary, size = ArgonSize.S, icon = ArgonIconName.ChevronDown, action = onSort)
            if (hasFilters) {
                ArgonButton(countLabel("Filters", applied.size), style = ArgonButtonStyle.Secondary, size = ArgonSize.S, icon = ArgonIconName.Filter) { onFilters("") }
            }
            LazyRow(Modifier.weight(1f), contentPadding = PaddingValues(end = spacing.l), horizontalArrangement = Arrangement.spacedBy(spacing.s)) {
                items(filters) { filter -> ArgonTag(filter.label, isSelected = isActive(filter, applied), onClick = { onFilters(filter.id) }) }
            }
        }
        ArgonDivider()
    }
}

/** The `bottom` template's controls: a pill floating over the grid's bottom edge, "Sort" | "Filter (n)". */
@Composable
private fun ListingPill(selected: Int, hasFilters: Boolean, onSort: () -> Unit, onFilters: () -> Unit, modifier: Modifier = Modifier) {
    val shape = ArgonTheme.radius.pill
    Row(
        // the border keeps its edge in dark mode, where a shadow doesn't show
        modifier.padding(bottom = ArgonTheme.spacing.l).shadow(6.dp, shape).background(ArgonTheme.colors.surface, shape).border(1.dp, ArgonTheme.colors.border, shape),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ArgonButton("Sort", style = ArgonButtonStyle.Tertiary, size = ArgonSize.S, icon = ArgonIconName.Sort, action = onSort)
        if (hasFilters) {
            Box(Modifier.width(1.dp).height(24.dp).background(ArgonTheme.colors.border))
            ArgonButton(countLabel("Filter", selected), style = ArgonButtonStyle.Tertiary, size = ArgonSize.S, icon = ArgonIconName.Filter, action = onFilters)
        }
    }
}
