package app.storefront.ui

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.storefront.AppGraph
import app.storefront.data.Brand
import app.storefront.data.Route
import app.storefront.data.Section
import app.storefront.data.Sections
import app.storefront.data.StorefrontException
import coil3.compose.AsyncImage
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * The sections of the `mobile_screen` "home" ([home] runs the HomeScreen query); the fallback home ([fallback] runs
 * FallbackHome) when it has none to render, or when the store refuses the metaobject query with GraphQL errors (a token
 * without metaobject access). HTTP and response-shape failures are rethrown: the screen shows an error with Retry
 * instead of caching a degraded home.
 */
internal suspend fun homeSections(brand: Brand, home: suspend () -> JsonObject, fallback: suspend () -> JsonObject): List<Section> {
    val sections = try {
        Sections.fromHome(home(), brand.hosts)
    } catch (e: StorefrontException) {
        if (!e.isGraphQL) throw e
        emptyList()
    }
    return sections.ifEmpty { Sections.fallback(brand, fallback()) }
}

private suspend fun loadHome(): List<Section> {
    val api = AppGraph.storefront
    return homeSections(
        AppGraph.loadBrand(),
        home = { api.query("HomeScreen", buildJsonObject { put("handle", "home") }) },
        fallback = { api.query("FallbackHome") },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(nav: NavController) {
    val brand by AppGraph.brand.collectAsState()
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    brand?.let { b ->
                        if (b.logo != null) {
                            AsyncImage(b.logo.url, b.name, Modifier.height(32.dp).widthIn(max = 160.dp), contentScale = ContentScale.Fit)
                        } else {
                            Text(b.name, fontWeight = FontWeight.Bold)
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { nav.open(Route.Search("")) }) { Icon(Icons.Filled.Search, contentDescription = "Search") }
                },
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Loader(::loadHome) { sections ->
                if (sections.isEmpty()) {
                    Text("Nothing to show yet.", Modifier.align(Alignment.Center))
                } else {
                    LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                        items(sections) { SectionView(it) { route -> nav.open(route) } }
                    }
                }
            }
        }
    }
}
