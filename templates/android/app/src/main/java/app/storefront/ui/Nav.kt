package app.storefront.ui

import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import app.argon.ui.components.ArgonBottomBar
import app.argon.ui.components.ArgonBottomBarItem
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonTopBarAction
import app.argon.ui.gallery.ArgonGallery
import app.storefront.AppGraph
import app.storefront.BuildConfig
import app.storefront.data.Route
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.collectLatest

// Tab routes: home, shop, wishlist, cart, account. Pushed screens: product/{handle}, collection/{handle}, search?q={q},
// order/{id}, orders, return/{orderId}, profile, addresses, policy/{handle}, and in debug builds components (the Argon UI
// gallery). Ids and handles are Uri.encode()d into a route.
/** The app's five tabs. */
enum class AppTab(val route: String, internal val icon: ArgonIconName) {
    Home("home", ArgonIconName.Home),
    Shop("shop", ArgonIconName.Grid),
    Wishlist("wishlist", ArgonIconName.Heart),
    Cart("cart", ArgonIconName.Bag),
    Account("account", ArgonIconName.Person),
}

/**
 * Sends the shopper to another tab from anywhere (`AppGraph.tabs`): "See all" to Shop, "Sign in" to Account. The app's
 * root does the switching.
 */
class TabState {
    private val requests = MutableSharedFlow<AppTab>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    /** The tabs asked for, for the root to switch to. */
    val selections: SharedFlow<AppTab> = requests

    fun select(tab: AppTab) {
        requests.tryEmit(tab)
    }
}

/**
 * A short message shown over whichever screen is open (`AppGraph.toast`): what work that outlives its screen has to
 * tell the shopper (a quick add that failed). The app's root shows it as a snackbar; a newer one replaces it.
 */
class ToastState {
    private val shown = MutableSharedFlow<String>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    /** The messages to show, for the root's snackbar. */
    val messages: SharedFlow<String> = shown

    fun show(message: String) {
        shown.tryEmit(message)
    }
}

/** Switches to the tab at [route]; each tab keeps its own place. */
private fun NavController.openTab(route: String) = navigate(route) {
    popUpTo(graph.findStartDestination().id) { saveState = true }
    launchSingleTop = true
    restoreState = true
}

/** Opens [route] in the app, or in a Custom Tab for [Route.Web]. */
fun NavController.open(route: Route) {
    when (route) {
        is Route.Product -> navigate("product/${Uri.encode(route.handle)}")
        is Route.Collection -> navigate("collection/${Uri.encode(route.handle)}")
        is Route.Search -> navigate("search?q=${Uri.encode(route.query)}")
        is Route.Policy -> navigate("policy/${Uri.encode(route.handle)}")
        // no browser installed: nothing to open, and nothing to crash
        is Route.Web -> runCatching { CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(route.url)) }
    }
}

/** The back arrow for a pushed screen's `ArgonTopBar` (its `leading`). */
fun NavController.backAction() = ArgonTopBarAction(ArgonIconName.Back, "Back") { popBackStack() }

@Composable
fun BackButton(nav: NavController) =
    IconButton(onClick = { nav.popBackStack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }

@Composable
fun AppRoot() {
    val brand by AppGraph.brand.collectAsState()
    AppTheme(brand?.accent) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            // the app can't reach a real store without its Storefront token (mock.shop needs none)
            if (AppGraph.storefrontToken.isBlank() && AppGraph.shopDomain != "mock.shop") SetupScreen() else AppNav()
        }
    }
}

@Composable
private fun AppNav() {
    val nav = rememberNavController()
    val current = nav.currentBackStackEntryAsState().value?.destination?.route
    val onTab = AppTab.entries.any { it.route == current }
    val cartCount = AppGraph.cart.cart.collectAsState().value?.totalQuantity ?: 0
    val snackbar = remember { SnackbarHostState() }
    // a newer message replaces the one showing
    LaunchedEffect(Unit) { AppGraph.toast.messages.collectLatest { snackbar.showSnackbar(it) } }
    LaunchedEffect(Unit) { AppGraph.tabs.selections.collect { nav.openTab(it.route) } }
    Scaffold(
        // each screen's own Scaffold handles the system bars; this one only reserves room for the tab bar
        contentWindowInsets = WindowInsets(0),
        // the tab bar keeps the snackbar off the system navigation; without it the padding does
        snackbarHost = { SnackbarHost(snackbar, if (onTab) Modifier else Modifier.navigationBarsPadding()) },
        bottomBar = {
            if (onTab) {
                ArgonBottomBar(
                    // the Cart tab shows how many items are in the cart
                    AppTab.entries.map { tab -> ArgonBottomBarItem(tab.route, tab.name, tab.icon, badge = if (tab == AppTab.Cart) cartCount else null) },
                    selectedId = current.orEmpty(),
                    onSelect = { nav.openTab(it) },
                )
            }
        },
    ) { padding ->
        NavHost(nav, startDestination = "home", modifier = Modifier.padding(padding).consumeWindowInsets(padding)) {
            composable("home") { HomeScreen(nav) }
            composable("shop") { ShopScreen(nav) }
            composable("wishlist") { WishlistScreen(nav) }
            composable("cart") { CartScreen() }
            composable("account") { AccountScreen(nav) }
            composable("product/{handle}") { ProductScreen(it.arguments?.getString("handle").orEmpty(), nav) }
            composable("collection/{handle}") { CollectionScreen(it.arguments?.getString("handle").orEmpty(), nav) }
            composable("search?q={q}", arguments = listOf(navArgument("q") { type = NavType.StringType; defaultValue = "" })) {
                SearchScreen(it.arguments?.getString("q").orEmpty(), nav)
            }
            composable("order/{id}") { OrderScreen(it.arguments?.getString("id").orEmpty(), nav) }
            composable("orders") { OrdersScreen(nav) }
            composable("return/{orderId}") { ReturnScreen(it.arguments?.getString("orderId").orEmpty(), nav) }
            composable("profile") { ProfileScreen(nav) }
            composable("addresses") { AddressesScreen(nav) }
            composable("policy/{handle}") { PolicyScreen(it.arguments?.getString("handle").orEmpty(), nav) }
            if (BuildConfig.DEBUG) composable("components") { ArgonGallery(AppGraph.brand.value?.accent, onBack = { nav.popBackStack() }) }
        }
    }
}

@Composable
private fun SetupScreen() = Column(
    Modifier.fillMaxSize().padding(32.dp),
    verticalArrangement = Arrangement.Center,
    horizontalAlignment = Alignment.CenterHorizontally,
) {
    Text("Setup needed", style = MaterialTheme.typography.headlineSmall)
    Text(
        "STOREFRONT_TOKEN is empty. Set it in android/shopify.properties (see README).",
        Modifier.padding(top = 12.dp),
        textAlign = TextAlign.Center,
    )
}
