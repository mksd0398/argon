package app.storefront.ui.sections

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import app.argon.ui.ArgonTheme
import app.storefront.AppGraph
import app.storefront.data.AnalyticsEvent
import app.storefront.data.Customer
import app.storefront.data.Liquid
import app.storefront.data.Links
import app.storefront.data.Metafield
import app.storefront.data.Placement
import app.storefront.data.Promotion
import app.storefront.data.Route
import app.storefront.data.ScreenContext
import app.storefront.data.ScreenSection
import app.storefront.data.ScreenTemplate
import app.storefront.data.SectionBlock
import app.storefront.data.SectionNodes
import app.storefront.data.Shop
import app.storefront.data.content
import app.storefront.data.sectionNodeIds
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

// Screens v2: a screen's sections (the `app_screen` metaobject with the screen's handle), loaded once per visit and drawn
// above and below the screen's own content, or as the whole screen (home, a custom page). One file per group of section
// types in this folder; this one loads them, evaluates their Liquid and reports their promotions.

/**
 * What a screen's sections need, loaded together: the template, every product and collection they show ([nodes], one
 * `SectionNodes` query), and the objects their Liquid reads (the shop, the screen's product or collection metafields, the
 * customer when signed in).
 */
class ScreenSections(
    val screen: String,
    val title: String,
    val template: ScreenTemplate,
    val nodes: SectionNodes,
    val shop: Shop?,
    val shopMetafields: List<Metafield>,
    /** The screen's product's (or collection's) metafields the template reads. */
    val ownMetafields: List<Metafield>,
    val customer: Customer?,
) {
    /** The sections drawn around the screen's own content. */
    val placement: Placement get() = template.placement(screen)

    /** It has a section this app can draw (`main` aside): a home without any falls back to the v1 home. */
    val hasContent: Boolean get() = template.sections.any { it.content != null }
}

private val log = Logger.getLogger("Sections")

private suspend fun <T> quietly(what: String, load: suspend () -> T): T? = try {
    load()
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    log.warning("$what not loaded: ${e.message}")
    null
}

/**
 * The sections of the screen [handle], or null when the store has none for it (no `app_screen`, or a template that
 * isn't one). [product] / [collection]: the handle of the screen's product or collection, whose metafields the Liquid
 * may read. Only the screen itself can fail, and only when not [quiet] (a custom page shows the error); everything else
 * loads on its own and is left out when it fails.
 */
suspend fun loadScreenSections(handle: String, product: String? = null, collection: String? = null, quiet: Boolean = true): ScreenSections? {
    val api = AppGraph.storefront
    val screen = if (quiet) quietly("screen $handle") { api.appScreen(handle) } else api.appScreen(handle)
    val template = ScreenTemplate.decode(screen?.template) ?: return null
    return coroutineScope {
        val nodes = async { quietly("section products") { api.sectionNodes(sectionNodeIds(template.sections)) } ?: SectionNodes() }
        val shop = async { quietly("shop") { api.shop() } }
        val shopMetafields = async { quietly("shop metafields") { api.shopMetafields(template.metafields("shop")) }.orEmpty() }
        val own = async {
            when {
                product != null -> quietly("product metafields") { api.productMetafields(product, template.metafields("product")) }
                collection != null && collection != "all" -> quietly("collection metafields") { api.collectionMetafields(collection, template.metafields("collection")) }
                else -> null
            }.orEmpty()
        }
        // the customer is loaded only for a template whose Liquid reads it
        val customer = async { if (AppGraph.hasAccount.value && "customer." in screen?.template.orEmpty()) quietly("customer") { AppGraph.customerAccount.customer() } else null }
        ScreenSections(handle, screen?.title.orEmpty(), template, nodes.await(), shop.await(), shopMetafields.await(), own.await(), customer.await())
    }
}

/** A screen's sections, kept for its back stack entry: loaded once per visit. [seen]: the sections whose view was reported. */
internal class SectionsModel : ViewModel() {
    var loaded by mutableStateOf<ScreenSections?>(null)
    var done = false
    val seen = mutableSetOf<String>()
}

/**
 * The sections of the screen [handle], loaded quietly once per visit: null while they load, and for good when the store
 * has none (the screen is then exactly as without screens v2).
 */
@Composable
fun rememberScreenSections(handle: String, product: String? = null, collection: String? = null): ScreenSections? {
    val model = viewModel<SectionsModel>(key = "sections:$handle")
    LaunchedEffect(handle, product, collection) {
        if (model.done) return@LaunchedEffect
        model.loaded = loadScreenSections(handle, product, collection)
        model.done = true
    }
    return model.loaded
}

/**
 * What every section of one screen is drawn with: its Liquid [context] (the screen's objects), and the way out of it
 * ([open], which reports `select_promotion` first). [seen] keeps `view_promotion` to once per section per visit.
 */
class SectionEnv(
    val sections: ScreenSections,
    private val context: Map<String, Any?>,
    private val seen: MutableSet<String>,
    private val onOpen: (Route) -> Unit,
) {
    val nodes: SectionNodes get() = sections.nodes

    private fun promotion(section: ScreenSection, block: SectionBlock?) =
        Promotion(section.id, section.trackName, "${sections.screen}:${sections.template.sections.indexOf(section)}", block?.id)

    /** [raw] with its Liquid evaluated for [section] (and [block]); null when that leaves nothing. */
    fun text(raw: String?, section: ScreenSection, block: SectionBlock? = null): String? =
        raw?.let { liquid(it, section, block) }?.takeIf { it.isNotBlank() }

    /** [raw] with its Liquid evaluated, whitespace and all (a run of a paragraph, a whole html). */
    fun liquid(raw: String, section: ScreenSection, block: SectionBlock? = null): String =
        if (Liquid.hasLiquid(raw)) Liquid.render(raw, ScreenContext.forSection(context, section, block)) else raw

    /** Where [link] leads ([Links.resolve]); null: nowhere. */
    fun route(link: String?): Route? = Links.resolve(link, AppGraph.brand.value?.hosts ?: setOf(AppGraph.shopDomain))

    /** Opens [route], reported as a tap on [section] (its [block]). */
    fun open(route: Route, section: ScreenSection, block: SectionBlock? = null) {
        AppGraph.analytics.track(AnalyticsEvent.SelectPromotion(promotion(section, block)))
        onOpen(route)
    }

    /** Reports [section] in view, once per visit of the screen. */
    fun viewed(section: ScreenSection) {
        if (seen.add(section.id)) AppGraph.analytics.track(AnalyticsEvent.ViewPromotion(promotion(section, null)))
    }
}

/**
 * The [SectionEnv] of [sections] (null while there are none): the Liquid context of the screen, with its [product] or
 * [collection] (their Liquid objects, [ScreenContext]), the cart as it is now, the shop and the customer.
 */
@Composable
fun rememberSectionEnv(
    sections: ScreenSections?,
    onOpen: (Route) -> Unit,
    product: Map<String, Any?>? = null,
    collection: Map<String, Any?>? = null,
): SectionEnv? {
    if (sections == null) return null
    val model = viewModel<SectionsModel>(key = "sections:${sections.screen}")
    val cart by AppGraph.cart.cart.collectAsState()
    val context = remember(sections, cart, product, collection) {
        buildMap {
            put("shop", ScreenContext.shop(sections.shop, sections.shopMetafields))
            put("cart", ScreenContext.cart(cart))
            sections.customer?.let { put("customer", ScreenContext.customer(it)) }
            product?.let { put("product", it) }
            collection?.let { put("collection", it) }
        }
    }
    return SectionEnv(sections, context, model.seen, onOpen)
}

/** [sections] as items of a lazy list, one item each (its `view_promotion` when it is first composed). */
fun LazyListScope.sectionItems(sections: List<ScreenSection>, env: SectionEnv?, modifier: Modifier = Modifier) {
    if (env == null) return
    items(sections, key = { "section:${it.id}" }, contentType = { "section:${it.type}" }) { SectionView(it, env, modifier) }
}

/** [sections] as full-width items of a lazy grid; [gutter] is the grid's side padding, which they reach over. */
fun LazyGridScope.sectionItems(sections: List<ScreenSection>, env: SectionEnv?, gutter: Dp) {
    if (env == null) return
    items(sections.size, key = { "section:${sections[it].id}" }, span = { GridItemSpan(maxLineSpan) }) { SectionView(sections[it], env, Modifier.bleed(gutter)) }
}

/** [sections] one under the other, for a screen that isn't a lazy list. */
@Composable
fun SectionColumn(sections: List<ScreenSection>, env: SectionEnv?, modifier: Modifier = Modifier) {
    if (env == null || sections.isEmpty()) return
    Column(modifier, verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.l)) { for (section in sections) key(section.id) { SectionView(section, env) } }
}

/** Full width inside a parent padded by [horizontal] on each side: sections bring their own margins. */
fun Modifier.bleed(horizontal: Dp): Modifier = layout { measurable, constraints ->
    val extra = if (constraints.hasBoundedWidth) horizontal.roundToPx() * 2 else 0
    val placeable = measurable.measure(constraints.copy(minWidth = constraints.minWidth + extra, maxWidth = constraints.maxWidth + extra))
    layout(placeable.width - extra, placeable.height) { placeable.place(-extra / 2, 0) }
}
