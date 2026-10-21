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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
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
import app.storefront.data.AnalyticsEvent
import app.storefront.data.Links
import app.storefront.data.Route
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

// Tab routes: home, shop, wishlist, cart, account, and with the settings' tabs search-tab and screen-tab/{handle}; a tab the
// bar leaves out is pushed instead (selectTab). Pushed screens: product/{handle}, collection/{handle}, search?q={q},
// order/{id}, orders, return/{orderId}, profile, addresses, policy/{handle}, page/{handle}, screen/{handle} (a custom page,
// screens v2), and in debug builds components (the Argon UI gallery). Ids and handles are Uri.encode()d into a route.
/** The app's built-in tabs, by the ids of their routes (the bar itself is `AppGraph.navigation.tabs`). */
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

    /**
     * How tall the product page's sticky add-to-cart bar is (above the system navigation), as it last measured itself:
     * on a product page the snackbar shows above the bar, not over its button.
     */
    var stickyBarHeight by mutableStateOf(0.dp)

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

// The tab roots of a search tab and a custom-page tab (the settings' `navigation.tabs`): the pushed search and custom
// page have their own routes, with a way back.
private const val SEARCH_TAB = "search-tab"
private const val SCREEN_TAB = "screen-tab/{handle}"

/** The route of the tab [id] ([ShellTab.id]). */
internal fun tabRoute(id: String): String = when {
    id == "search" -> SEARCH_TAB
    id.startsWith("screen:") -> "screen-tab/${Uri.encode(id.removePrefix("screen:"))}"
    else -> id
}

/** The tab id of a destination [route] ([handle]: its argument); null for a screen that is never a tab. */
internal fun tabId(route: String?, handle: String?): String? = when (route) {
    SEARCH_TAB -> "search"
    SCREEN_TAB -> "screen:$handle"
    "home", "shop", "wishlist", "cart", "account" -> route
    else -> null
}

/**
 * Goes to the tab [id]: switches to it when it is in the bar; otherwise (the cart, shop, wishlist or account of a bar
 * the settings left them out of) pushes its screen, which then has a way back.
 */
fun NavController.selectTab(id: String) {
    when {
        id == "home" || AppGraph.navigation.hasTab(id) -> openTab(tabRoute(id))
        id == "search" -> navigate("search?q=")
        id.startsWith("screen:") -> navigate("screen/${Uri.encode(id.removePrefix("screen:"))}")
        id in setOf("shop", "wishlist", "cart", "account") -> navigate(id) { launchSingleTop = true }
    }
}

/** The leading action of the root screen of tab [id]: none when it is in the bar, Back when it was pushed. */
fun NavController.tabLeading(id: String): List<ArgonTopBarAction> = if (AppGraph.navigation.hasTab(id)) emptyList() else listOf(backAction())

/** A settings icon name ([Navigation.ICONS][app.storefront.data.Navigation.ICONS]) as the component library's icon. */
internal fun shellIcon(name: String): ArgonIconName = when (name) {
    "home" -> ArgonIconName.Home
    "grid" -> ArgonIconName.Grid
    "search" -> ArgonIconName.Search
    "heart" -> ArgonIconName.Heart
    "bag" -> ArgonIconName.Bag
    "person" -> ArgonIconName.Person
    "tag" -> ArgonIconName.Tag
    "menu" -> ArgonIconName.Menu
    else -> ArgonIconName.Star
}

/** Opens [route] in the app (a [Route.Tab] switches to that tab), or in a Custom Tab for [Route.Web]. */
fun NavController.open(route: Route) {
    when (route) {
        is Route.Product -> navigate("product/${Uri.encode(route.handle)}")
        is Route.Collection -> navigate("collection/${Uri.encode(route.handle)}")
        is Route.Search -> navigate("search?q=${Uri.encode(route.query)}")
        is Route.Policy -> navigate("policy/${Uri.encode(route.handle)}")
        is Route.Page -> navigate("page/${Uri.encode(route.handle)}")
        is Route.Screen -> navigate("screen/${Uri.encode(route.handle)}")
        // a tab this app has (or its screen, pushed, when the bar leaves it out); any other id goes nowhere
        is Route.Tab -> selectTab(route.id)
        // no browser installed: nothing to open, and nothing to crash
        is Route.Web -> runCatching { CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(route.url)) }
    }
}

/** A route's short, stable name for analytics: "product/{handle}" is "product", "search?q={q}" is "search". */
internal fun screenName(route: String): String = route.substringBefore('/').substringBefore('?')

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
            // null until the device has said whether the welcome was seen: neither it nor the tabs flash up meanwhile
            val welcomed by AppGraph.onboardingStore.done.collectAsState()
            var startTab by remember { mutableStateOf<AppTab?>(null) }
            when {
                // the app can't reach a real store without its Storefront token (mock.shop needs none)
                AppGraph.storefrontToken.isBlank() && AppGraph.shopDomain != "mock.shop" -> SetupScreen()
                !AppGraph.onboarding || welcomed == true -> AppNav(startTab)
                welcomed == false -> OnboardingScreen { signIn ->
                    startTab = if (signIn) AppTab.Account else null
                    AppGraph.scope.launch { AppGraph.onboardingStore.finish() }
                }
            }
        }
    }
}

/** The tabs and every pushed screen; [startTab] is the tab to open on instead of Home (the welcome's "Sign in"). */
@Composable
private fun AppNav(startTab: AppTab? = null) {
    val nav = rememberNavController()
    val entry = nav.currentBackStackEntryAsState().value
    val current = entry?.destination?.route
    // the bar's tabs (the settings', else the built-in five); the bar shows on their roots
    val navigation = AppGraph.navigation
    val currentTab = tabId(current, entry?.arguments?.getString("handle"))
    val onTab = currentTab != null && navigation.hasTab(currentTab)
    var announcementClosed by rememberSaveable { mutableStateOf(false) }
    val announcement = AppGraph.announcement?.takeIf { !announcementClosed }
    val cartCount = AppGraph.cart.cart.collectAsState().value?.totalQuantity ?: 0
    val snackbar = remember { SnackbarHostState() }
    // a newer message replaces the one showing
    LaunchedEffect(Unit) { AppGraph.toast.messages.collectLatest { snackbar.showSnackbar(it) } }
    LaunchedEffect(Unit) {
        if (startTab != null) {
            // not before the first screen is on the stack: the NavHost below sets the graph while it is laid out, which
            // is after this effect starts, and a NavController without its graph can't navigate
            nav.currentBackStackEntryFlow.first()
            nav.selectTab(startTab.route)
        }
        AppGraph.tabs.selections.collect { nav.selectTab(it.route) }
    }
    // a tapped notification's link (push): opened through Links once the graph is set
    LaunchedEffect(Unit) {
        nav.currentBackStackEntryFlow.first()
        AppGraph.notificationLink.filterNotNull().collect { link ->
            AppGraph.notificationLink.value = null
            Links.resolve(link, AppGraph.brand.value?.hosts ?: setOf(AppGraph.shopDomain))?.let { nav.open(it) }
        }
    }
    // Analytics' `screen_view`, from the one place every screen passes through. By back stack entry: tapping the tab that
    // is already open navigates to the same entry, which is not another view.
    DisposableEffect(nav) {
        var shown: String? = null
        val listener = NavController.OnDestinationChangedListener { controller, destination, _ ->
            val entry = controller.currentBackStackEntry?.id
            val route = destination.route
            if (entry != shown && route != null) {
                shown = entry
                AppGraph.analytics.track(AnalyticsEvent.ScreenView(screenName(route)))
            }
        }
        nav.addOnDestinationChangedListener(listener)
        onDispose { nav.removeOnDestinationChangedListener(listener) }
    }
    Scaffold(
        // each screen's own Scaffold handles the system bars; this one only reserves room for the tab bar
        contentWindowInsets = WindowInsets(0),
        // the tab bar keeps the snackbar off the system navigation; without it the padding does, and on a product page
        // the snackbar also clears the sticky add-to-cart bar
        snackbarHost = {
            val lift = if (current?.startsWith("product/") == true) AppGraph.toast.stickyBarHeight else 0.dp
            SnackbarHost(snackbar, if (onTab) Modifier else Modifier.navigationBarsPadding().padding(bottom = lift))
        },
        // the settings' announcement, over the top bar of every tab root, until it is closed for the session
        topBar = { if (onTab && announcement != null) AnnouncementBar(announcement, { nav.open(it) }) { announcementClosed = true } },
        bottomBar = {
            if (onTab) {
                ArgonBottomBar(
                    // the Cart tab shows how many items are in the cart
                    navigation.tabs.map { tab -> ArgonBottomBarItem(tab.id, tab.title, shellIcon(tab.icon), iconUrl = tab.iconUrl, badge = if (tab.id == "cart") cartCount else null) },
                    selectedId = currentTab.orEmpty(),
                    onSelect = { nav.openTab(tabRoute(it)) },
                    showLabels = navigation.labels,
                    containerColor = navigation.tabBarBackground.toColor(),
                    activeColor = navigation.tabBarActive.toColor(),
                    inactiveColor = navigation.tabBarInactive.toColor(),
                )
            }
        },
    ) { padding ->
        NavHost(nav, startDestination = "home", modifier = Modifier.padding(padding).consumeWindowInsets(padding)) {
            composable("home") { HomeScreen(nav) }
            composable("shop") { ShopScreen(nav) }
            composable("wishlist") { WishlistScreen(nav) }
            composable("cart") { CartScreen(nav) }
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
            if (AppGraph.kwikPass != null) composable("kwikpass") { KwikPassScreen(nav) }
            composable("addresses") { AddressesScreen(nav) }
            composable("policy/{handle}") { PolicyScreen(it.arguments?.getString("handle").orEmpty(), nav) }
            composable("page/{handle}") { PageScreen(it.arguments?.getString("handle").orEmpty(), nav) }
            composable("screen/{handle}") { CustomScreen(it.arguments?.getString("handle").orEmpty(), nav) }
            composable(SEARCH_TAB) { SearchScreen("", nav, isTab = true) }
            composable(SCREEN_TAB) { CustomScreen(it.arguments?.getString("handle").orEmpty(), nav, isTab = true) }
            if (BuildConfig.DEBUG) composable("components") { ArgonGallery(AppGraph.brand.value?.accent, onBack = { nav.popBackStack() }) }
        }
        // push: the one offer to turn notifications on, after a first purchase
        PushOffer()
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
