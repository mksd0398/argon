package app.storefront.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
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
import app.storefront.AppGraph

/**
 * One collection's products. Handle "all" is the whole catalogue: Storefront has no `collection(handle: "all")`, so it
 * uses the root `products` query (no filters there).
 */
class CollectionModel(private val handle: String) : ViewModel() {
    private val all = handle == "all"

    var title by mutableStateOf(if (all) "All products" else "")
        private set

    val listing = Listing(viewModelScope, if (all) CATALOG_SORTS else COLLECTION_SORTS) { after, sort, applied ->
        val api = AppGraph.storefront
        if (all) {
            api.products(sortKey = sort.key, reverse = sort.reverse, after = after)
        } else {
            val collection = api.collection(handle, applied, sort.key, sort.reverse, after) ?: error("Collection not found")
            title = collection.title
            collection.products
        }
    }

    init {
        listing.reload()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CollectionScreen(handle: String, nav: NavController) {
    val model = viewModel<CollectionModel>(factory = viewModelFactory { initializer { CollectionModel(handle) } })
    Scaffold(topBar = { TopAppBar(title = { Text(model.title) }, navigationIcon = { BackButton(nav) }) }) { padding ->
        Box(Modifier.padding(padding)) {
            ListingView(model.listing, "No products in this collection.") { nav.open(it) }
        }
    }
}
