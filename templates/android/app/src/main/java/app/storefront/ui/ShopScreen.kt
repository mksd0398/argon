package app.storefront.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonDivider
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonTopBar
import app.argon.ui.components.ArgonTopBarAction
import app.storefront.AppGraph
import app.storefront.data.MenuItem
import app.storefront.data.Route
import app.storefront.data.menuTree

/** The `main-menu` tree; when the store has none, its first collections as a flat list. */
private suspend fun loadMenu(): List<MenuItem> {
    val brand = AppGraph.loadBrand()
    val api = AppGraph.storefront
    val menu = api.menu("main-menu")?.let { menuTree(it.items, brand.hosts) }.orEmpty()
    return menu.ifEmpty { api.fallbackHome().map { MenuItem(it.title, Route.Collection(it.handle), emptyList()) } }
}

/** The Shop tab: the store's menu as a list that expands in place, with search in the top bar. */
@Composable
fun ShopScreen(nav: NavController) {
    Scaffold(
        topBar = { ArgonTopBar("Shop", trailing = listOf(ArgonTopBarAction(ArgonIconName.Search, "Search") { nav.open(Route.Search("")) })) },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Loader(::loadMenu) { menu ->
                if (menu.isEmpty()) {
                    Text("Nothing to show yet.", Modifier.align(Alignment.Center), style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
                } else {
                    LazyColumn { items(menu) { MenuRow(it, 0) { route -> nav.open(route) } } }
                }
            }
        }
    }
}

/** A leaf opens its route. A parent expands (its own route, when it has one, becomes the first child "All ..."). */
@Composable
private fun MenuRow(item: MenuItem, depth: Int, onOpen: (Route) -> Unit) {
    val spacing = ArgonTheme.spacing
    var open by rememberSaveable { mutableStateOf(false) }
    val parent = item.children.isNotEmpty()
    Column {
        Row(
            Modifier.fillMaxWidth().clickable { if (parent) open = !open else onOpen(item.route) }
                .heightIn(min = 48.dp)
                .padding(start = spacing.l * (depth + 1), end = spacing.l, top = spacing.m, bottom = spacing.m),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(item.title, Modifier.weight(1f), style = ArgonTheme.type.body, color = ArgonTheme.colors.ink)
            if (parent) {
                ArgonIcon(
                    if (open) ArgonIconName.ChevronUp else ArgonIconName.ChevronDown,
                    tint = ArgonTheme.colors.muted,
                    contentDescription = if (open) "Collapse" else "Expand",
                )
            }
        }
        ArgonDivider()
        if (parent && open) {
            // a header item (url "#") is a Web placeholder without an http(s) URL and has nothing to open
            val real = item.route !is Route.Web || item.route.url.startsWith("http")
            if (real) MenuRow(MenuItem("All ${item.title}", item.route, emptyList()), depth + 1, onOpen)
            for (child in item.children) MenuRow(child, depth + 1, onOpen)
        }
    }
}
