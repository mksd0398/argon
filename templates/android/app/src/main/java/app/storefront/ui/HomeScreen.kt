package app.storefront.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
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
import app.storefront.ui.home.BAR_HEIGHT
import app.storefront.ui.home.HomeB2B
import app.storefront.ui.home.HomeBeauty
import app.storefront.ui.home.HomeFashion
import app.storefront.ui.home.HomeGrocery
import app.storefront.ui.home.heroSolid
import app.storefront.ui.sections.ScreenSections
import app.storefront.ui.sections.loadScreenSections
import app.storefront.ui.sections.rememberSectionEnv
import app.storefront.ui.sections.screenBackground
import app.storefront.ui.sections.sectionItems
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
    /** The v1 content; null (with [loaded] set) when the home is the store's `app_screen` [sections]. */
    var loaded by mutableStateOf<Pair<String?, HomeContent?>?>(null)
    var sections by mutableStateOf<ScreenSections?>(null)
}

/**
 * The home: the store's `app_screen` "home" when it has sections this app can draw (screens v2), else the v1 home
 * ([loadHome]), exactly as without it. Both are asked for side by side; the v1 one is dropped when it isn't needed.
 */
private suspend fun loadPage(): Pair<ScreenSections?, HomeContent?> = coroutineScope {
    val v1 = async { runCatching { loadHome() } }
    val sections = loadScreenSections("home")?.takeIf { it.hasContent }
    if (sections != null) {
        v1.cancel()
        sections to null
    } else {
        null to v1.await().getOrThrow()
    }
}

/**
 * The home tab: the top bar and the page of the store's [HomeTemplate] (`AppGraph.homeTemplate`), or the store's own
 * sections (screens v2, [loadPage]). With the settings' drawer (`navigation.drawer`) the bar's menu button opens it.
 */
@Composable
fun HomeScreen(nav: NavController) {
    val menu = AppGraph.navigation.drawerMenu
    if (menu == null) HomePage(nav, null) else HomeDrawer(menu, { nav.open(it) }) { openMenu -> HomePage(nav, openMenu) }
}

@Composable
private fun HomePage(nav: NavController, openMenu: (() -> Unit)?) {
    val template = AppGraph.homeTemplate
    val brand by AppGraph.brand.collectAsState()
    val company by AppGraph.buyer.company.collectAsState()
    val cartCount = AppGraph.cart.cart.collectAsState().value?.totalQuantity ?: 0
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
            val (sections, content) = loadPage()
            model.sections = sections
            model.loaded = buyer to content
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
    // a bar without the cart tab has the cart behind a bag button here
    val actions = BarActions(
        onSearch = { nav.open(Route.Search("")) },
        onMenu = openMenu,
        onCart = if (AppGraph.navigation.hasTab("cart")) null else ({ AppGraph.tabs.select(AppTab.Cart) }),
        cartCount = cartCount,
    )
    // screens v2: the store's own home, its sections under the top bar; over the first one when the template's
    // `screen.top_bar` is transparent (unset: by transparentOnHome), on the template's background
    val sections = model.sections.takeIf { model.loaded != null }
    val env = rememberSectionEnv(sections, onOpen)
    if (sections != null) {
        val look = sections.template.screen
        val background = screenBackground(sections)
        if (look.topBar?.let { it == "transparent" } ?: AppGraph.navigation.transparentOnHome) {
            OverBar({ solid -> HomeTopBar(template, brand, solid, overlay = true, actions, lightContent = !look.darkTint) }, light = !look.darkTint) { list ->
                LazyColumn(
                    Modifier.fillMaxSize().background(background),
                    list,
                    contentPadding = PaddingValues(bottom = ArgonTheme.spacing.xl),
                    verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xl),
                ) { sectionItems(sections.placement.above, env) }
            }
        } else {
            Scaffold(topBar = { HomeTopBar(template, brand, 1f, overlay = false, actions) }, containerColor = background) { padding ->
                LazyColumn(
                    Modifier.padding(padding).fillMaxSize(),
                    contentPadding = PaddingValues(top = ArgonTheme.spacing.s, bottom = ArgonTheme.spacing.xl),
                    verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xl),
                ) { sectionItems(sections.placement.above, env) }
            }
        }
        return
    }
    // The fashion page runs up under the status bar and lays its bar over its hero, so it is not in a scaffold; while it
    // loads (or fails) there is no hero yet, and it has the scaffold and the solid bar of the others.
    val fashion = template == HomeTemplate.Fashion
    if (fashion && content != null) {
        HomeFashion(content, onOpen) { solid -> HomeTopBar(template, brand, solid, overlay = true, actions) }
        return
    }
    Scaffold(topBar = { HomeTopBar(template, brand, 1f, overlay = fashion, actions) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            val failure = error
            when {
                content != null -> when (template) {
                    HomeTemplate.Fashion -> Unit // above
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
 * [content] (a list with the given state, from the top edge of the screen) with [bar] lying over it: clear while its
 * first item is in view, solid once it has scrolled under the bar, as the fashion page's hero does ([heroSolid]). While
 * clear the status bar icons are [light] (else dark, over a light picture). The home's and custom pages'.
 */
@Composable
internal fun OverBar(bar: @Composable (solid: Float) -> Unit, light: Boolean = true, content: @Composable (LazyListState) -> Unit) {
    val list = rememberLazyListState()
    val density = LocalDensity.current
    val barHeight = WindowInsets.statusBars.getTop(density) + with(density) { BAR_HEIGHT.toPx() }
    val solid by remember(list, barHeight) {
        derivedStateOf {
            val first = list.layoutInfo.visibleItemsInfo.firstOrNull { it.index == 0 }
            if (first == null) (if (list.firstVisibleItemIndex == 0) 0f else 1f) else heroSolid(-first.offset.toFloat(), first.size.toFloat(), barHeight)
        }
    }
    StatusBarIcons(light = light && solid < 0.5f, darkIcons = !light && solid < 0.5f)
    Box(Modifier.fillMaxSize()) {
        content(list)
        bar(solid)
    }
}

/** What the home's top bar offers besides its title: search, the drawer's menu button and the cart's bag button (each when given). */
private class BarActions(val onSearch: () -> Unit, val onMenu: (() -> Unit)?, val onCart: (() -> Unit)?, val cartCount: Int)

/**
 * The home's top bar. Each template has its own: fashion centres the logo over its hero ([overlay]: clear at [solid] 0,
 * the normal bar at 1), beauty has it at the start, both with a search button; grocery and B2B show a search field. The
 * settings' `topBar.style` replaces it (`standard`, `centered_logo`, `search`) where the page isn't laid under it. The
 * shop's name stands in for a missing logo. [lightContent]: the overlay's title and icons over the picture (false: dark).
 */
@Composable
private fun HomeTopBar(template: HomeTemplate, brand: Brand?, solid: Float, overlay: Boolean, actions: BarActions, lightContent: Boolean = true) {
    val name = brand?.name.orEmpty()
    val logo = brand?.logo?.url
    val leading = listOfNotNull(actions.onMenu?.let { ArgonTopBarAction(ArgonIconName.Menu, "Menu", action = it) })
    val cart = listOfNotNull(actions.onCart?.let { ArgonTopBarAction(ArgonIconName.Bag, "Cart", badge = actions.cartCount.takeIf { n -> n > 0 }, action = it) })
    val trailing = listOf(ArgonTopBarAction(ArgonIconName.Search, "Search", action = actions.onSearch)) + cart
    val placeholder = if (template == HomeTemplate.B2B) "Search by name or SKU" else "Search products"
    val style = when {
        overlay -> "overlay"
        else -> AppGraph.navigation.topBarStyle ?: when (template) {
            HomeTemplate.Fashion -> "overlay"
            HomeTemplate.Beauty -> "standard"
            HomeTemplate.Grocery, HomeTemplate.B2B -> "search"
        }
    }
    when (style) {
        "overlay" -> ArgonTopBar(name, variant = ArgonTopBarVariant.Overlay, logoUrl = logo, leading = leading, trailing = trailing, solid = solid, lightContent = lightContent)
        "centered_logo" -> ArgonTopBar(name, variant = ArgonTopBarVariant.CenteredLogo, logoUrl = logo, leading = leading, trailing = trailing)
        "search" -> SearchField(placeholder, actions.onSearch, leading, cart)
        else -> ArgonTopBar(name, logoUrl = logo, leading = leading, trailing = trailing)
    }
}

/**
 * A search field that isn't typed in: a tap anywhere on it opens the search screen ([onSearch]), which has the real one.
 * The field is looks only; a screen reader gets the one button laid over it, named by the [placeholder]. [leading] and
 * [trailing] (the drawer's menu, the cart) stay buttons of their own beside it.
 */
@Composable
private fun SearchField(
    placeholder: String,
    onSearch: () -> Unit,
    leading: List<ArgonTopBarAction> = emptyList(),
    trailing: List<ArgonTopBarAction> = emptyList(),
) = Box {
    ArgonTopBar(
        placeholder,
        Modifier.clearAndSetSemantics {}.padding(bottom = ArgonTheme.spacing.s),
        variant = ArgonTopBarVariant.Search,
        leading = leading,
        trailing = trailing,
    )
    // Material's SearchBar puts itself at zIndex 1, which is also the order taps are tried in: the button has to sit
    // above that, or a tap on the field lands in the field (a cursor, the keyboard) and never opens the search screen.
    // No ripple of its own: it would be a grey rectangle over the bar and the status bar. It leaves the bar's own
    // buttons uncovered.
    Box(
        Modifier.matchParentSize().padding(start = if (leading.isEmpty()) 0.dp else 56.dp, end = if (trailing.isEmpty()) 0.dp else 56.dp)
            .zIndex(2f).semantics { contentDescription = placeholder }
            .clickable(interactionSource = null, indication = null, role = Role.Button, onClick = onSearch),
    )
}
