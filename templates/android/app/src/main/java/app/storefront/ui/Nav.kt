package app.storefront.ui

import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
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
import app.storefront.AppGraph
import app.storefront.data.Route

// Tab routes: home, shop, wishlist, cart, account. Pushed screens: product/{handle}, collection/{handle}, search?q={q}, order/{id}.
private enum class Tab(val route: String, val icon: ImageVector) {
    Home("home", Icons.Filled.Home),
    Shop("shop", Icons.AutoMirrored.Filled.List),
    Wishlist("wishlist", Icons.Filled.Favorite),
    Cart("cart", Icons.Filled.ShoppingCart),
    Account("account", Icons.Filled.Person),
}

/** Opens [route] in the app, or in a Custom Tab for [Route.Web]. */
fun NavController.open(route: Route) {
    when (route) {
        is Route.Product -> navigate("product/${Uri.encode(route.handle)}")
        is Route.Collection -> navigate("collection/${Uri.encode(route.handle)}")
        is Route.Search -> navigate("search?q=${Uri.encode(route.query)}")
        // no browser installed: nothing to open, and nothing to crash
        is Route.Web -> runCatching { CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(route.url)) }
    }
}

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
    val cartCount = AppGraph.cart.cart.collectAsState().value?.totalQuantity ?: 0
    Scaffold(
        // each screen's own Scaffold handles the system bars; this one only reserves room for the tab bar
        contentWindowInsets = WindowInsets(0),
        bottomBar = {
            if (Tab.entries.any { it.route == current }) {
                NavigationBar {
                    for (tab in Tab.entries) {
                        NavigationBarItem(
                            selected = tab.route == current,
                            onClick = {
                                nav.navigate(tab.route) {
                                    popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = {
                                // the Cart tab shows how many items are in the cart
                                BadgedBox(badge = { if (tab == Tab.Cart && cartCount > 0) Badge { Text("$cartCount") } }) {
                                    Icon(tab.icon, contentDescription = null)
                                }
                            },
                            label = { Text(tab.name) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(nav, startDestination = "home", modifier = Modifier.padding(padding).consumeWindowInsets(padding)) {
            composable("home") { HomeScreen(nav) }
            composable("shop") { ShopScreen(nav) }
            composable("wishlist") { WishlistScreen(nav) }
            composable("cart") { CartScreen() }
            composable("account") { Placeholder("Account") }
            composable("product/{handle}") { ProductScreen(it.arguments?.getString("handle").orEmpty(), nav) }
            composable("collection/{handle}") { CollectionScreen(it.arguments?.getString("handle").orEmpty(), nav) }
            composable("search?q={q}", arguments = listOf(navArgument("q") { type = NavType.StringType; defaultValue = "" })) {
                SearchScreen(it.arguments?.getString("q").orEmpty(), nav)
            }
            composable("order/{id}") { Placeholder("Order: ${it.arguments?.getString("id")}") }
        }
    }
}

// Screens that arrive in later tasks.
@Composable
private fun Placeholder(text: String) = Box(Modifier.fillMaxSize(), Alignment.Center) { Text(text) }

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
