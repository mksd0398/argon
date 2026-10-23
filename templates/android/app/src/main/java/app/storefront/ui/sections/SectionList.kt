package app.storefront.ui.sections

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
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
import app.storefront.data.SectionContent
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
    // a network failure is not a bug; anything else (a response the app can't read) is reported
    if (e !is java.io.IOException) app.storefront.data.CrashReports.record(e, "load $what")
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
        tapped(section, block)
        onOpen(route)
    }

    /** Reports a tap on [section] (its [block]) that opens nothing of its own: an FAQ's question. */
    fun tapped(section: ScreenSection, block: SectionBlock? = null) = AppGraph.analytics.track(AnalyticsEvent.SelectPromotion(promotion(section, block)))

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

/** The screen's background behind its sections (the template's `screen.background`): the theme's while they load, or without one. */
@Composable
fun screenBackground(sections: ScreenSections?): Color = sections?.template?.screen?.background?.let(::color) ?: MaterialTheme.colorScheme.background

/**
 * The section runs edge to edge: a hero banner (the default style), a slideshow, a marquee, a video, or any section with
 * a `background` colour. Two such sections side by side sit flush.
 */
internal val ScreenSection.fullBleed: Boolean
    get() = background != null || when (val c = content) {
        is SectionContent.Banner -> c.style != "card"
        is SectionContent.Slideshow, is SectionContent.Marquee, is SectionContent.Video -> true
        else -> false
    }

/**
 * The screen opens with a picture that runs edge to edge: its first section is a hero banner, a slideshow or a video.
 * Only then may the top bar lie clear over it; over anything else (a row of collections, text) it would hide the content,
 * so the bar stays solid whatever the settings ask.
 */
internal val ScreenTemplate.opensWithPicture: Boolean
    get() = when (val c = sections.firstOrNull { it.type != ScreenTemplate.MAIN }?.content) {
        is SectionContent.Banner -> c.style != "card"
        is SectionContent.Slideshow, is SectionContent.Video -> true
        else -> false
    }

/**
 * The space between [previous] and [current] (null: [current] comes first, no space): none when both are [fullBleed]
 * (a hero and the marquee under it), else [gap], so a heading never sits on an edge-to-edge strip.
 */
internal fun gapBefore(previous: ScreenSection?, current: ScreenSection, gap: Dp): Dp =
    if (previous == null || (previous.fullBleed && current.fullBleed)) 0.dp else gap

/**
 * Takes back [spacing] above the item: placed that much higher and reported that much shorter, so the gap the list's
 * arrangement puts above it closes while everything under it keeps its own gap.
 */
private fun Modifier.pullUp(spacing: Dp): Modifier = if (spacing == 0.dp) this else layout { measurable, constraints ->
    val by = spacing.roundToPx()
    val placeable = measurable.measure(constraints)
    layout(placeable.width, (placeable.height - by).coerceAtLeast(0)) { placeable.place(0, -by) }
}

/** The modifier of item [index] of [sections]: [modifier], pulled up by [spacing] where it sits flush with the section above. */
private fun flushed(sections: List<ScreenSection>, index: Int, modifier: Modifier, spacing: Dp): Modifier =
    if (index > 0 && spacing > 0.dp && gapBefore(sections[index - 1], sections[index], spacing) == 0.dp) modifier.pullUp(spacing) else modifier

/**
 * [sections] as items of a lazy list, one item each (its `view_promotion` when it is first composed). [spacing]: the
 * space the list puts above each section after the first (its `spacedBy`, or [modifier]'s top padding), taken back
 * between two sections that sit flush ([gapBefore]).
 */
fun LazyListScope.sectionItems(sections: List<ScreenSection>, env: SectionEnv?, modifier: Modifier = Modifier, spacing: Dp = 0.dp) {
    if (env == null) return
    items(sections.size, key = { "section:${sections[it].id}" }, contentType = { "section:${sections[it].type}" }) {
        SectionView(sections[it], env, flushed(sections, it, modifier, spacing))
    }
}

/**
 * [sections] as full-width items of a lazy grid; [gutter] is the grid's side padding, which they reach over. [spacing]:
 * the grid's vertical spacing (the product grid's), taken back between two sections that sit flush.
 */
fun LazyGridScope.sectionItems(sections: List<ScreenSection>, env: SectionEnv?, gutter: Dp, spacing: Dp = ArgonTheme.spacing.l) {
    if (env == null) return
    items(sections.size, key = { "section:${sections[it].id}" }, span = { GridItemSpan(maxLineSpan) }) {
        SectionView(sections[it], env, flushed(sections, it, Modifier.bleed(gutter), spacing))
    }
}

/** [sections] one under the other, for a screen that isn't a lazy list: spacing l apart, flush where [gapBefore] says. */
@Composable
fun SectionColumn(sections: List<ScreenSection>, env: SectionEnv?, modifier: Modifier = Modifier) {
    if (env == null || sections.isEmpty()) return
    Column(modifier) {
        sections.forEachIndexed { i, section ->
            key(section.id) { SectionView(section, env, Modifier.padding(top = gapBefore(sections.getOrNull(i - 1), section, ArgonTheme.spacing.l))) }
        }
    }
}

/** Full width inside a parent padded by [horizontal] on each side: sections bring their own margins. */
fun Modifier.bleed(horizontal: Dp): Modifier = layout { measurable, constraints ->
    val extra = if (constraints.hasBoundedWidth) horizontal.roundToPx() * 2 else 0
    val placeable = measurable.measure(constraints.copy(minWidth = constraints.minWidth + extra, maxWidth = constraints.maxWidth + extra))
    layout(placeable.width - extra, placeable.height) { placeable.place(-extra / 2, 0) }
}
