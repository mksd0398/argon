package app.storefront.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShopScreen(nav: NavController) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Shop") },
                actions = {
                    IconButton(onClick = { nav.open(Route.Search("")) }) { Icon(Icons.Filled.Search, contentDescription = "Search") }
                },
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Loader(::loadMenu) { menu ->
                if (menu.isEmpty()) {
                    Text("Nothing to show yet.", Modifier.align(Alignment.Center))
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
    var open by rememberSaveable { mutableStateOf(false) }
    val parent = item.children.isNotEmpty()
    Column {
        Row(
            Modifier.fillMaxWidth().clickable { if (parent) open = !open else onOpen(item.route) }
                .padding(start = 16.dp + 16.dp * depth, end = 16.dp, top = 14.dp, bottom = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(item.title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
            if (parent) {
                Icon(
                    if (open) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                    contentDescription = if (open) "Collapse" else "Expand",
                )
            }
        }
        HorizontalDivider()
        if (parent && open) {
            // a header item (url "#") is a Web placeholder without an http(s) URL and has nothing to open
            val real = item.route !is Route.Web || item.route.url.startsWith("http")
            if (real) MenuRow(MenuItem("All ${item.title}", item.route, emptyList()), depth + 1, onOpen)
            for (child in item.children) MenuRow(child, depth + 1, onOpen)
        }
    }
}
