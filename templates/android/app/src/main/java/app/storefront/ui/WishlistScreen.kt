package app.storefront.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavController
import app.storefront.AppGraph
import app.storefront.data.ProductCard
import app.storefront.data.Route
import app.storefront.data.cards
import app.storefront.data.objects
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private const val MAX_NODES = 250 // `nodes(ids:)` takes at most this many ids per request

private suspend fun fetchCards(ids: List<String>): List<ProductCard> =
    AppGraph.storefront.query("Products", buildJsonObject { put("ids", JsonArray(ids.map(::JsonPrimitive))) }).objects("nodes").cards()

/**
 * The product cards behind the wishlist ids. Cards are fetched once per id and kept, so hearting or un-hearting
 * never reloads the others; the list is always read in wishlist order (newest first), whatever order the store answers in.
 * ponytail: a card is not refreshed until the app restarts (same as the other screens); add pull-to-refresh with them.
 */
class WishlistModel(private val fetch: suspend (List<String>) -> List<ProductCard>) : ViewModel() {
    private val known = mutableStateMapOf<String, ProductCard?>() // null: asked for, but the product no longer exists

    var error by mutableStateOf<String?>(null)
        private set

    /** Fetches the cards of [ids] not asked for yet. A failure sets [error]; the next call retries. */
    suspend fun sync(ids: List<String>) {
        error = null
        try {
            for (batch in ids.filter { it !in known }.chunked(MAX_NODES)) {
                val found = fetch(batch).associateBy { it.id }
                for (id in batch) known[id] = found[id]
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message ?: e.toString()
        }
    }

    /** The cards of [ids], in that order; products that no longer exist are left out. */
    fun cards(ids: List<String>) = ids.mapNotNull { known[it] }

    fun pending(ids: List<String>) = ids.any { it !in known }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WishlistScreen(nav: NavController) {
    val model = viewModel<WishlistModel>(factory = viewModelFactory { initializer { WishlistModel(::fetchCards) } })
    val ids by AppGraph.wishlist.ids.collectAsState()
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(ids, attempt) { model.sync(ids) }

    Scaffold(topBar = { TopAppBar(title = { Text("Wishlist") }) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            val cards = model.cards(ids)
            val error = model.error
            when {
                // a failed fetch of a newly saved product shows as the grid's Retry footer
                cards.isNotEmpty() ->
                    ProductGrid(cards, hasNext = error != null, onLoadMore = { attempt++ }, onOpen = { nav.open(Route.Product(it.handle)) }, error = error)
                error != null -> ErrorView(error) { attempt++ }
                model.pending(ids) -> Spinner()
                else -> Text("Tap ♡ on a product to save it", Modifier.align(Alignment.Center))
            }
        }
    }
}
