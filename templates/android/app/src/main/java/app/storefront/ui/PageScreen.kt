package app.storefront.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.navigation.NavController
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonTopBar
import app.storefront.AppGraph
import app.storefront.data.Route
import app.storefront.data.StorePage
import app.storefront.ui.sections.ScreenSections
import app.storefront.ui.sections.loadScreenSections
import app.storefront.ui.sections.rememberSectionEnv
import app.storefront.ui.sections.sectionItems

/**
 * An online store page (`page/{handle}`, the links `/pages/<handle>`): its title in the top bar, its body as HTML. A page
 * with no body opens on the web instead.
 */
@Composable
fun PageScreen(handle: String, nav: NavController) {
    var title by remember { mutableStateOf("") }
    Scaffold(topBar = { ArgonTopBar(title, leading = listOf(nav.backAction())) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Loader({ AppGraph.storefront.page(handle) ?: error("This page isn't available") }) { page ->
                LaunchedEffect(page) {
                    title = page.title
                    // a page whose content isn't its body (an Online Store 2.0 page of sections, a contact form) is the web's
                    webPage(page, AppGraph.shopDomain)?.let {
                        nav.popBackStack()
                        nav.open(it)
                    }
                }
                HtmlText(page.body.orEmpty(), Modifier.verticalScroll(rememberScrollState()).padding(ArgonTheme.spacing.l))
            }
        }
    }
}

/** What a custom page loaded: its sections, or none when the store has no such page. */
private class CustomPage(val sections: ScreenSections?)

/**
 * A custom page of the store's own (`screen/{handle}`, the links `app://screens/<handle>`): the `app_screen` [handle],
 * its title in the top bar and its sections. A page the store doesn't have says so. [isTab]: the root of a
 * `screen:<handle>` tab of the settings, without a way back.
 */
@Composable
fun CustomScreen(handle: String, nav: NavController, isTab: Boolean = false) {
    var title by remember { mutableStateOf("") }
    Scaffold(topBar = { ArgonTopBar(title, leading = if (isTab) emptyList() else listOf(nav.backAction())) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Loader({ CustomPage(loadScreenSections(handle, quiet = false)?.takeIf { it.hasContent }) }) { page ->
                val sections = page.sections
                LaunchedEffect(sections) { title = sections?.title.orEmpty() }
                val env = rememberSectionEnv(sections, { nav.open(it) })
                if (sections == null) {
                    Text(
                        "This page isn't available.",
                        Modifier.align(Alignment.Center).padding(ArgonTheme.spacing.xl),
                        style = ArgonTheme.type.body,
                        color = ArgonTheme.colors.muted,
                        textAlign = TextAlign.Center,
                    )
                } else {
                    LazyColumn(
                        Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(vertical = ArgonTheme.spacing.l),
                        verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xl),
                    ) { sectionItems(sections.placement.above, env) }
                }
            }
        }
    }
}

/**
 * Where [page] opens instead of the app's page: on the web (the shop's [domain]) when it has no body (an Online Store
 * 2.0 page of sections, a contact form), which the app can't draw; null when the app draws it.
 */
internal fun webPage(page: StorePage, domain: String): Route.Web? =
    if (page.body.isNullOrBlank()) Route.Web("https://$domain/pages/${page.handle}") else null
