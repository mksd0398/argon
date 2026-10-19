package app.storefront.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
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
import androidx.compose.ui.text.style.TextAlign
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavController
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonTopBar
import app.storefront.AppGraph
import app.storefront.data.ProductCard
import app.storefront.data.Route
import app.storefront.ui.sections.rememberScreenSections
import app.storefront.ui.sections.screenBackground
import app.storefront.ui.sections.rememberSectionEnv
import app.storefront.ui.sections.sectionItems
import kotlinx.coroutines.CancellationException

private const val MAX_NODES = 250 // `nodes(ids:)` takes at most this many ids per request

private suspend fun fetchCards(ids: List<String>): List<ProductCard> = AppGraph.storefront.productsByIds(ids)

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

/** The Wishlist tab: the saved products as a grid of cards, newest first, between the store's sections (screens v2). */
@Composable
fun WishlistScreen(nav: NavController) {
    val model = viewModel<WishlistModel>(factory = viewModelFactory { initializer { WishlistModel(::fetchCards) } })
    val ids by AppGraph.wishlist.ids.collectAsState()
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(ids, attempt) { model.sync(ids) }
    // screens v2: the store's sections above and below the saved products
    val sections = rememberScreenSections("wishlist")
    val env = rememberSectionEnv(sections, { nav.open(it) })
    val placement = sections?.placement

    Scaffold(topBar = { ArgonTopBar("Wishlist", leading = nav.tabLeading("wishlist")) }, containerColor = screenBackground(sections)) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            val cards = model.cards(ids)
            val error = model.error
            when {
                // a failed fetch of a newly saved product shows as the grid's Retry footer
                cards.isNotEmpty() ->
                    ProductGrid(
                        cards,
                        hasNext = error != null,
                        onLoadMore = { attempt++ },
                        onOpen = { nav.open(Route.Product(it.handle)) },
                        error = error,
                        above = { sectionItems(placement?.above.orEmpty(), env, ArgonTheme.spacing.l) },
                        below = { sectionItems(placement?.below.orEmpty(), env, ArgonTheme.spacing.l) },
                    )
                error != null -> ErrorView(error) { attempt++ }
                model.pending(ids) -> Spinner()
                else -> Text(
                    "Tap ♡ on a product to save it",
                    Modifier.align(Alignment.Center).padding(ArgonTheme.spacing.xl),
                    style = ArgonTheme.type.body,
                    color = ArgonTheme.colors.muted,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}
