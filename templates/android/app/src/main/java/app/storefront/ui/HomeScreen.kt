package app.storefront.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonTopBar
import app.argon.ui.components.ArgonTopBarAction
import app.argon.ui.components.ArgonTopBarVariant
import app.storefront.AppGraph
import app.storefront.data.ArgonApiError
import app.storefront.data.Brand
import app.storefront.data.CollectionCard
import app.storefront.data.HomeContent
import app.storefront.data.HomeTemplate
import app.storefront.data.Metaobject
import app.storefront.data.Route
import app.storefront.data.Sections
import app.storefront.ui.home.HomeB2B
import app.storefront.ui.home.HomeBeauty
import app.storefront.ui.home.HomeFashion
import app.storefront.ui.home.HomeGrocery
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/**
 * What the home screen shows for [template]: the sections of the store's `mobile_screen` "home" ([home] runs the
 * HomeScreen query) and its first collections ([fallback] runs FallbackHome), fetched side by side and put together by
 * [Sections.content] (each part is the store's own when it has it, else made from the collections). A store that
 * refuses the metaobject query with GraphQL errors (a token without metaobject access) counts as having no sections.
 * HTTP and response-shape failures of either query are rethrown: the screen shows an error with Retry instead of
 * keeping a degraded home.
 */
internal suspend fun homeContent(
    template: HomeTemplate,
    brand: Brand,
    home: suspend () -> List<Metaobject>,
    fallback: suspend () -> List<CollectionCard>,
): HomeContent = coroutineScope {
    val collections = async { fallback() }
    val sections = try {
        Sections.fromHome(home(), brand.hosts)
    } catch (e: ArgonApiError.GraphQL) {
        // GraphQL messages name fields and permissions, never a token: logged so a merchant can see why the home fell back
        Logger.getLogger("HomeScreen").warning("home screen query refused, showing the store's collections: ${e.messages.joinToString("; ")}")
        emptyList()
    }
    Sections.content(template, brand, sections, collections.await())
}

private suspend fun loadHome(): HomeContent {
    val api = AppGraph.storefront
    return homeContent(AppGraph.homeTemplate, AppGraph.loadBrand(), home = { api.homeScreen("home") }, fallback = { api.fallbackHome() })
}

/**
 * The home's content and the buyer (a company location's id, null for retail) it was loaded for, kept for the back
 * stack entry: coming back from a product doesn't reload.
 * ponytail: no refresh until the app restarts or the buyer changes; add pull-to-refresh if merchants need live edits.
 */
internal class HomeModel : ViewModel() {
    var loaded by mutableStateOf<Pair<String?, HomeContent>?>(null)
}

/** The home tab: the top bar and the page of the store's [HomeTemplate] (`AppGraph.homeTemplate`). */
@Composable
fun HomeScreen(nav: NavController) {
    val template = AppGraph.homeTemplate
    val brand by AppGraph.brand.collectAsState()
    val company by AppGraph.buyer.company.collectAsState()
    val buyer = company?.locationId
    val model = viewModel<HomeModel>()
    var attempt by remember { mutableIntStateOf(0) }
    var error by remember { mutableStateOf<String?>(null) }
    val content = model.loaded?.second

    // Loaded at first, on Retry, and again when the buyer changes: a company's catalogue has its own products and prices.
    // Until the new content is here the page keeps showing the old one.
    LaunchedEffect(buyer, attempt) {
        val loaded = model.loaded
        if (loaded != null && loaded.first == buyer) return@LaunchedEffect
        error = null
        try {
            model.loaded = buyer to loadHome()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message ?: e.toString()
        }
    }
    // A load that failed offline or behind the lock screen (Android cuts the network while the device dozes) runs again
    // when the app is back, without a tap.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { if (error != null) attempt++ }

    val onOpen: (Route) -> Unit = { nav.open(it) }
    Scaffold(topBar = { HomeTopBar(template, brand) { nav.open(Route.Search("")) } }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            val failure = error
            when {
                content != null -> when (template) {
                    HomeTemplate.Fashion -> HomeFashion(content, onOpen)
                    HomeTemplate.Beauty -> HomeBeauty(content, onOpen)
                    HomeTemplate.Grocery -> HomeGrocery(content, onOpen)
                    HomeTemplate.B2B -> HomeB2B(content, onOpen)
                }
                failure != null -> ErrorView(failure) { attempt++ }
                else -> Spinner()
            }
        }
    }
}

/**
 * Each template's top bar: fashion centres the logo, beauty has it at the start, both with a search button; grocery and
 * B2B show a search field. The shop's name stands in for a missing logo.
 */
@Composable
private fun HomeTopBar(template: HomeTemplate, brand: Brand?, onSearch: () -> Unit) {
    val name = brand?.name.orEmpty()
    val logo = brand?.logo?.url
    val search = listOf(ArgonTopBarAction(ArgonIconName.Search, "Search", action = onSearch))
    when (template) {
        HomeTemplate.Fashion -> ArgonTopBar(name, variant = ArgonTopBarVariant.CenteredLogo, logoUrl = logo, trailing = search)
        HomeTemplate.Beauty -> ArgonTopBar(name, logoUrl = logo, trailing = search)
        HomeTemplate.Grocery -> SearchField("Search products", onSearch)
        HomeTemplate.B2B -> SearchField("Search by name or SKU", onSearch)
    }
}

/**
 * A search field that isn't typed in: a tap anywhere on it opens the search screen ([onSearch]), which has the real one.
 * The field is looks only; a screen reader gets the one button laid over it, named by the [placeholder].
 */
@Composable
private fun SearchField(placeholder: String, onSearch: () -> Unit) = Box {
    ArgonTopBar(placeholder, Modifier.clearAndSetSemantics {}.padding(bottom = ArgonTheme.spacing.s), variant = ArgonTopBarVariant.Search)
    Box(Modifier.matchParentSize().semantics { contentDescription = placeholder }.clickable(role = Role.Button, onClick = onSearch))
}
