package app.storefront.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalFocusManager
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavController
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonListItem
import app.argon.ui.components.ArgonListLeading
import app.argon.ui.components.ArgonTopBar
import app.argon.ui.components.ArgonTopBarAction
import app.argon.ui.components.ArgonTopBarVariant
import app.storefront.AppGraph
import app.storefront.data.AnalyticsEvent
import app.storefront.data.Page
import app.storefront.data.ProductCard
import app.storefront.data.Route
import app.storefront.data.analyticsItem
import app.storefront.ui.sections.rememberScreenSections
import app.storefront.ui.sections.screenBackground
import app.storefront.ui.sections.rememberSectionEnv
import app.storefront.ui.sections.sectionItems
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

/** The typed text and, once submitted, the results of that query. State lives here so it survives opening a product. */
class SearchModel(initial: String) : ViewModel() {
    var text by mutableStateOf(initial)

    /** The query whose results [listing] holds; null before the first search. */
    var submitted by mutableStateOf<String?>(null)
        private set

    val listing = Listing(viewModelScope, SEARCH_SORTS) { after, sort, applied ->
        val page = AppGraph.storefront.search(submitted.orEmpty(), applied, sort.key, sort.reverse, after)
        val products = page.items.filterIsInstance<ProductCard>()
        // analytics' `view_item_list`: the results as they open (their first page)
        if (after == null) AppGraph.analytics.track(AnalyticsEvent.ViewItemList(null, "Search results", products.map { it.analyticsItem() }))
        Page(products, page.endCursor, page.hasNextPage, page.filters)
    }

    init {
        submit(initial)
    }

    fun submit(query: String) {
        val q = query.trim()
        if (q.isEmpty()) return
        text = q
        submitted = q
        AppGraph.analytics.track(AnalyticsEvent.Search(q))
        listing.reload(SEARCH_SORTS.first(), emptyList(), resetFilters = true)
    }
}

private class Suggestions(val queries: List<String>, val collections: List<Pair<String, String>>, val products: List<ProductCard>)

private suspend fun loadSuggestions(query: String): Suggestions {
    val p = AppGraph.storefront.predictiveSearch(query)
    return Suggestions(
        queries = p.queries.map { it.text },
        collections = p.collections.map { it.handle to (it.title ?: it.handle) },
        products = p.products,
    )
}

/**
 * Search (`search?q=`): the field in the top bar, suggestions while typing (queries, collections, products), and the
 * results of a submitted query in the store's collection template ([ListingView], with search's own sorts). [isTab]: the
 * root of the settings' search tab, without a way back.
 */
@Composable
fun SearchScreen(initial: String, nav: NavController, isTab: Boolean = false) {
    val model = viewModel<SearchModel>(factory = viewModelFactory { initializer { SearchModel(initial) } })
    val focus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    var suggestions by remember { mutableStateOf<Suggestions?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    val showResults = model.submitted != null && model.text.trim() == model.submitted
    // screens v2: the store's sections over the results
    val sections = rememberScreenSections("search")
    val env = rememberSectionEnv(sections, { nav.open(it) })

    fun submit(query: String) {
        model.submit(query)
        focusManager.clearFocus()
    }

    // opened to type: the field has the keyboard (the request goes to the field inside the bar)
    LaunchedEffect(Unit) { if (model.submitted == null) runCatching { focus.requestFocus() } }
    // 300 ms debounce: typing again cancels this effect (and a request in flight) before it queries
    LaunchedEffect(model.text) {
        val q = model.text.trim()
        if (q.isEmpty() || q == model.submitted) {
            suggestions = null
            failure = null
            return@LaunchedEffect
        }
        delay(300)
        try {
            suggestions = loadSuggestions(q)
            failure = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            failure = e.message ?: e.toString()
        }
    }

    Scaffold(
        containerColor = screenBackground(sections),
        topBar = {
            ArgonTopBar(
                "Search products",
                Modifier.focusRequester(focus).padding(bottom = ArgonTheme.spacing.s),
                variant = ArgonTopBarVariant.Search,
                leading = if (isTab) emptyList() else listOf(nav.backAction()),
                trailing = if (model.text.isEmpty()) emptyList() else listOf(ArgonTopBarAction(ArgonIconName.Close, "Clear") { model.text = "" }),
                searchText = model.text,
                onSearchTextChange = { model.text = it },
                onSearch = { submit(it) },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            if (showResults) {
                ListingView(
                    model.listing,
                    "No products match \"${model.submitted}\".",
                    { nav.open(it) },
                    above = { sectionItems(sections?.placement?.above.orEmpty(), env, ArgonTheme.spacing.l) },
                )
            } else {
                LazyColumn(Modifier.fillMaxSize()) {
                    failure?.let { item { Text(it, Modifier.padding(ArgonTheme.spacing.l), style = ArgonTheme.type.body, color = ArgonTheme.colors.sale) } }
                    suggestions?.let { s ->
                        items(s.queries) { q -> ArgonListItem(q, leading = ArgonListLeading.Icon(ArgonIconName.Search), onClick = { submit(q) }) }
                        if (s.collections.isNotEmpty()) item { SuggestionLabel("Collections") }
                        items(s.collections) { (handle, title) -> ArgonListItem(title, onClick = { nav.open(Route.Collection(handle)) }) }
                        if (s.products.isNotEmpty()) item { SuggestionLabel("Products") }
                        items(s.products) { p ->
                            ArgonListItem(
                                p.title,
                                subtitle = p.price.display(),
                                leading = p.image?.let { ArgonListLeading.Image(it.url) },
                                onClick = { nav.open(Route.Product(p.handle)) },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SuggestionLabel(text: String) = SectionHeader(
    text,
    Modifier.padding(start = ArgonTheme.spacing.l, end = ArgonTheme.spacing.l, top = ArgonTheme.spacing.l, bottom = ArgonTheme.spacing.xs),
)
