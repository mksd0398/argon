package app.storefront.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavController
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonTopBar
import app.argon.ui.components.ArgonTopBarAction
import app.storefront.AppGraph
import app.storefront.data.Route

/**
 * One collection's products. Handle "all" is the whole catalogue: Storefront has no `collection(handle: "all")`, so it
 * uses the root `products` query (no filters or description there, and its own sorts).
 */
class CollectionModel(private val handle: String) : ViewModel() {
    private val all = handle == "all"

    var title by mutableStateOf(if (all) "All products" else "")
        private set

    /** The collection's description, once the first page is here; empty when it has none. */
    var description by mutableStateOf("")
        private set

    val listing = Listing(viewModelScope, if (all) CATALOG_SORTS else COLLECTION_SORTS) { after, sort, applied ->
        val api = AppGraph.storefront
        if (all) {
            api.products(sortKey = sort.key, reverse = sort.reverse, after = after)
        } else {
            val collection = api.collection(handle, applied, sort.key, sort.reverse, after) ?: error("Collection not found")
            title = collection.title
            description = withoutLeadingCss(collection.description)
            collection.products
        }
    }

    init {
        listing.reload()
    }
}

/**
 * A collection (`collection/{handle}`): its title in the top bar with search and the cart, and its products in the
 * store's collection template ([ListingView]).
 */
@Composable
fun CollectionScreen(handle: String, nav: NavController) {
    val model = viewModel<CollectionModel>(factory = viewModelFactory { initializer { CollectionModel(handle) } })
    val cart by AppGraph.cart.cart.collectAsState()
    Scaffold(
        topBar = {
            ArgonTopBar(
                model.title,
                leading = listOf(nav.backAction()),
                trailing = listOf(
                    ArgonTopBarAction(ArgonIconName.Search, "Search") { nav.open(Route.Search("")) },
                    // the cart is a tab: its count as the badge, none on an empty cart
                    ArgonTopBarAction(ArgonIconName.Bag, "Cart", badge = cart?.totalQuantity?.takeIf { it > 0 }) { AppGraph.tabs.select(AppTab.Cart) },
                ),
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            ListingView(model.listing, "No products in this collection.", { nav.open(it) }, description = model.description)
        }
    }
}
