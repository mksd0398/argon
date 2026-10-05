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
import app.storefront.data.Route
import app.storefront.data.Section
import app.storefront.data.Sections
import app.storefront.data.StorefrontException
import coil3.compose.AsyncImage
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** The store's `mobile_screen` "home" sections; the fallback home (brand cover, collections, a carousel) when there are none. */
private suspend fun loadHome(): List<Section> {
    val brand = AppGraph.loadBrand()
    val api = AppGraph.storefront
    // a token without metaobject access errors here; it still gets the fallback home
    val sections = try {
        Sections.fromHome(api.query("HomeScreen", buildJsonObject { put("handle", "home") }), brand.hosts)
    } catch (e: StorefrontException) {
        emptyList()
    }
    return sections.ifEmpty { Sections.fallback(brand, api.query("FallbackHome")) }
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
