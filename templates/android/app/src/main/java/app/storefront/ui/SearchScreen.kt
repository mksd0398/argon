package app.storefront.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavController
import app.storefront.AppGraph
import app.storefront.data.ProductCard
import app.storefront.data.Route
import app.storefront.data.cards
import app.storefront.data.obj
import app.storefront.data.objects
import app.storefront.data.parseProductPage
import app.storefront.data.str
import coil3.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** The typed text and, once submitted, the results of that query. State lives here so it survives opening a product. */
class SearchModel(initial: String) : ViewModel() {
    var text by mutableStateOf(initial)

    /** The query whose results [listing] holds; null before the first search. */
    var submitted by mutableStateOf<String?>(null)
        private set

    val listing = Listing(viewModelScope, SEARCH_SORTS) { after, sort, applied ->
        val data = AppGraph.storefront.query("Search", listingVars(after, sort, applied, mapOf("query" to submitted.orEmpty())))
        parseProductPage(data.connection("search"), "productFilters")
    }

    init {
        submit(initial)
    }

    fun submit(query: String) {
        val q = query.trim()
        if (q.isEmpty()) return
        text = q
        submitted = q
        listing.reload(SEARCH_SORTS.first(), emptyList(), resetFilters = true)
    }
}

private class Suggestions(val queries: List<String>, val collections: List<Pair<String, String>>, val products: List<ProductCard>)

private suspend fun loadSuggestions(query: String): Suggestions {
    val p = AppGraph.storefront.query("PredictiveSearch", buildJsonObject { put("query", query) }).obj("predictiveSearch")
    return Suggestions(
        queries = p?.objects("queries").orEmpty().mapNotNull { it.str("text") },
        collections = p?.objects("collections").orEmpty().mapNotNull { c -> c.str("handle")?.let { it to (c.str("title") ?: it) } },
        products = p?.objects("products").orEmpty().cards(),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(initial: String, nav: NavController) {
    val model = viewModel<SearchModel>(factory = viewModelFactory { initializer { SearchModel(initial) } })
    val focus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    var suggestions by remember { mutableStateOf<Suggestions?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    val showResults = model.submitted != null && model.text.trim() == model.submitted

    LaunchedEffect(Unit) { if (model.submitted == null) focus.requestFocus() }
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
        topBar = {
            TopAppBar(
                title = {
                    TextField(
                        value = model.text,
                        onValueChange = { model.text = it },
                        placeholder = { Text("Search products") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = { model.submit(model.text); focusManager.clearFocus() }),
                        trailingIcon = {
                            if (model.text.isNotEmpty()) IconButton(onClick = { model.text = "" }) { Icon(Icons.Filled.Close, contentDescription = "Clear") }
                        },
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = Color.Transparent,
                            unfocusedContainerColor = Color.Transparent,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent,
                        ),
                        modifier = Modifier.fillMaxWidth().focusRequester(focus),
                    )
                },
                navigationIcon = { BackButton(nav) },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            if (showResults) {
                ListingView(model.listing, "No products match \"${model.submitted}\".") { nav.open(it) }
            } else {
                LazyColumn(Modifier.fillMaxSize()) {
                    failure?.let { item { Text(it, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) } }
                    suggestions?.let { s ->
                        items(s.queries) { q ->
                            SuggestionRow(q, Icons.Filled.Search) { model.submit(q); focusManager.clearFocus() }
                        }
                        if (s.collections.isNotEmpty()) item { SuggestionLabel("Collections") }
                        items(s.collections) { (handle, title) -> SuggestionRow(title, null) { nav.open(Route.Collection(handle)) } }
                        if (s.products.isNotEmpty()) item { SuggestionLabel("Products") }
                        items(s.products) { p -> ProductRow(p) { nav.open(Route.Product(p.handle)) } }
                    }
                }
            }
        }
    }
}

@Composable
private fun SuggestionLabel(text: String) =
    Text(text, Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)

@Composable
private fun SuggestionRow(text: String, icon: ImageVector?, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) Icon(icon, contentDescription = null)
        Text(text)
    }
}

@Composable
private fun ProductRow(card: ProductCard, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AsyncImage(
            model = card.image?.url,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(48.dp).clip(RoundedCornerShape(6.dp)),
        )
        Column {
            Text(card.title, maxLines = 1)
            Text(card.price.display(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
