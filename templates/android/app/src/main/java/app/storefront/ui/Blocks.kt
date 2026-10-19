package app.storefront.ui

import android.text.method.LinkMovementMethod
import android.view.Gravity
import android.widget.TextView
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.res.ResourcesCompat
import androidx.core.text.HtmlCompat
import androidx.core.view.WindowCompat
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.storefront.AppGraph
import app.storefront.data.FilterValue
import app.storefront.data.Img
import app.storefront.data.Money
import app.storefront.data.ProductOptionValue
import app.storefront.data.Route
import app.storefront.data.ShopPolicies
import app.storefront.data.Swatch
import coil3.compose.AsyncImage
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException

// The blocks every page is built from. Product cards and QuickAdd are in ProductCardView.kt.

/**
 * Any image the app shows, filling the space it's given (cropped), on a quiet placeholder while it loads or when there
 * is none: [url] from the store's CDN, or a file bundled with the app (`file:///android_asset/...`, a stock banner,
 * [app.storefront.data.StockImages]), which Coil reads from the APK. Without [placeholder] nothing is drawn behind the
 * image: for one shown whole ([ContentScale.Fit]) on its screen's own background, like the full-screen viewer's.
 */
@Composable
fun StoreImage(
    url: String?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    placeholder: Boolean = true,
) = AsyncImage(
    model = url,
    contentDescription = contentDescription,
    modifier = if (placeholder) modifier.background(ArgonTheme.colors.border.copy(alpha = 0.5f)) else modifier,
    contentScale = contentScale,
)

/** [image] with its own alt text; [contentDescription] when it has none. */
@Composable
fun StoreImage(
    image: Img?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    placeholder: Boolean = true,
) = StoreImage(image?.url, image?.alt ?: contentDescription, modifier, contentScale, placeholder)

/**
 * Light status bar icons while [light], dark ones while [darkIcons]: for a screen whose picture runs up under the status
 * bar (dark icons over a light one). Otherwise, and once that screen is gone, the icons follow the theme again (dark on
 * the light theme).
 */
@Composable
fun StatusBarIcons(light: Boolean, darkIcons: Boolean = false) {
    val view = LocalView.current
    val dark = isAppDark()
    DisposableEffect(view, light, darkIcons, dark) {
        val bars = view.context.componentActivity()?.window?.let { WindowCompat.getInsetsController(it, view) }
        // "light status bars" is the system's name for a light background: dark icons
        bars?.isAppearanceLightStatusBars = darkIcons || (!light && !dark)
        onDispose { bars?.isAppearanceLightStatusBars = !dark }
    }
}

/** A small label over an image or beside a price: "Sold out", "Bundle"; [isSale] puts it on the sale colour: "Sale", "Save 20%". */
@Composable
fun LabelTag(text: String, modifier: Modifier = Modifier, isSale: Boolean = false) = Text(
    text,
    modifier
        .background(if (isSale) ArgonTheme.colors.sale else ArgonTheme.colors.surface, ArgonTheme.radius.s)
        .padding(horizontal = ArgonTheme.spacing.s, vertical = ArgonTheme.spacing.xxs),
    style = ArgonTheme.type.caption,
    color = if (isSale) ArgonTheme.colors.paper else ArgonTheme.colors.ink,
    maxLines = 1,
)

/** The whole percent [price] is below [compareAt] ("Save 20%"); null without a higher compare-at, or when it rounds below 1. */
fun discountPercent(price: Money, compareAt: Money?): Int? {
    // Shopify reports "no compare-at" as null or 0.0; only a higher compare-at is a real discount
    val now = price.amount.toBigDecimalOrNull() ?: return null
    val was = compareAt?.amount?.toBigDecimalOrNull()?.takeIf { it > now } ?: return null
    return ((was - now).toDouble() / was.toDouble() * 100).roundToInt().takeIf { it >= 1 }
}

/**
 * A price: [prefix] ("From") before it, the compare-at price struck through after it, and a "Save 20%" tag when it is a
 * discount ([discountPercent]). The tag drops to a second line where the row is too narrow (a product card). The price
 * is label/headline/title sized by [size].
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PriceView(price: Money, compareAt: Money?, modifier: Modifier = Modifier, size: ArgonSize = ArgonSize.M, prefix: String? = null) {
    val type = ArgonTheme.type
    val (main, small) = when (size) {
        ArgonSize.S -> type.label to type.caption
        ArgonSize.M -> type.headline to type.label
        ArgonSize.L -> type.title to type.body
    }
    val spacing = ArgonTheme.spacing
    val saved = discountPercent(price, compareAt)
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(spacing.xs), verticalArrangement = Arrangement.spacedBy(spacing.xs)) {
        if (prefix != null) Text(prefix, Modifier.alignByBaseline(), style = small, color = ArgonTheme.colors.muted, maxLines = 1)
        Text(price.display(), Modifier.alignByBaseline(), style = main, color = ArgonTheme.colors.ink, maxLines = 1)
        if (compareAt != null && saved != null) {
            val was = compareAt.display()
            Text(
                was,
                Modifier.alignByBaseline().semantics { contentDescription = "Was $was" },
                style = small,
                color = ArgonTheme.colors.muted,
                textDecoration = TextDecoration.LineThrough,
                maxLines = 1,
            )
            LabelTag("Save $saved%", Modifier.alignByBaseline().padding(start = spacing.xs), isSale = true)
        }
    }
}

/**
 * A section's heading, with an optional action on the trailing side ("View all"). It brings no padding of its own: give
 * it the page's gutter.
 */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, actionLabel: String? = null, onAction: (() -> Unit)? = null) =
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f).semantics { heading() }, style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
        if (actionLabel != null && onAction != null) {
            Text(
                actionLabel,
                Modifier.clickable(role = Role.Button, onClick = onAction).heightIn(min = 44.dp).wrapContentHeight(),
                style = ArgonTheme.type.label,
                color = ArgonTheme.colors.muted,
            )
        }
    }

/** Colours for option values named after one, for stores that haven't set swatches. The same table as iOS. */
object SwatchColors {
    private val table = mapOf(
        "black" to "#000000", "white" to "#FFFFFF", "grey" to "#808080", "gray" to "#808080", "silver" to "#C0C0C0",
        "red" to "#D0312D", "maroon" to "#800000", "pink" to "#F4A6C0", "rose" to "#E8909C", "orange" to "#F28C28",
        "peach" to "#FFCBA4", "yellow" to "#F7D13D", "gold" to "#D4AF37", "mustard" to "#D9A404", "green" to "#3F8F4F",
        "olive" to "#808000", "teal" to "#008080", "turquoise" to "#40E0D0", "blue" to "#2F6FCF", "navy" to "#1F2A5C",
        "sky" to "#87CEEB", "purple" to "#7B3FA0", "violet" to "#8F5FD7", "lavender" to "#B9A5E0", "magenta" to "#C2188B",
        "brown" to "#7B4B2A", "tan" to "#D2B48C", "beige" to "#E8DCC4", "cream" to "#FFFDD0", "ivory" to "#FFFFF0",
        "khaki" to "#C3B091", "coral" to "#FF7F50", "mint" to "#98E0B8", "lime" to "#A4D431", "burgundy" to "#800020",
        "wine" to "#722F37", "charcoal" to "#36454F", "copper" to "#B87333", "bronze" to "#CD7F32",
    )

    /**
     * The `#RRGGBB` of the colour [name] names: the whole name when it is a known colour, else its last word ("Peacock
     * Blue" is blue, "Off White" white), else any of its words. Null for a name with none, and for "multi" (several
     * colours have no one swatch).
     */
    fun hex(name: String): String? {
        val whole = name.trim().lowercase()
        val words = whole.split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }
        val candidates = listOf(whole) + listOfNotNull(words.lastOrNull()) + words
        return candidates.firstOrNull { it in table || it == "multi" }?.let { table[it] }
    }
}

/** What an `ArgonSwatch` is drawn with: a colour (`#RRGGBB`) or an image; neither when nothing is known of the colour. */
data class SwatchFill(val colorHex: String? = null, val imageUrl: String? = null)

/**
 * The swatch of a value named [name]: the store's own ([swatch], a colour or an image) when it has one, else the colour
 * its name says ([SwatchColors]).
 */
fun swatch(swatch: Swatch?, name: String): SwatchFill {
    val color = swatch?.color
    val image = swatch?.image?.previewImage?.url
    return if (color != null || image != null) SwatchFill(color, image) else SwatchFill(SwatchColors.hex(name))
}

/** The swatch of a product option's value. */
fun swatch(value: ProductOptionValue): SwatchFill = swatch(value.swatch, value.name)

/** The swatch of a filter's value. */
fun swatch(value: FilterValue): SwatchFill = swatch(value.swatch, value.label)

/**
 * The reassurances under a page: "Secure checkout", and "Shipping policy" and "Returns policy" for the policies the shop
 * has, each opening it ([Route.Policy]). The policies are the session's (`StorefrontApi.policies`); when they can't be
 * loaded only the first item shows.
 */
@Composable
fun TrustRow(onOpen: (Route) -> Unit, modifier: Modifier = Modifier) {
    val policies by produceState<ShopPolicies?>(null) {
        value = try {
            AppGraph.storefront.policies()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
    }
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.Top) {
        TrustItem(ArgonIconName.Lock, "Secure checkout", Modifier.weight(1f))
        policies?.shippingPolicy?.let { policy ->
            TrustItem(ArgonIconName.Truck, "Shipping policy", Modifier.weight(1f).clickable(role = Role.Button) { onOpen(Route.Policy(policy.handle)) })
        }
        policies?.refundPolicy?.let { policy ->
            TrustItem(ArgonIconName.Returns, "Returns policy", Modifier.weight(1f).clickable(role = Role.Button) { onOpen(Route.Policy(policy.handle)) })
        }
    }
}

@Composable
private fun TrustItem(icon: ArgonIconName, label: String, modifier: Modifier) = Column(
    modifier.heightIn(min = 44.dp),
    verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs, Alignment.CenterVertically),
    horizontalAlignment = Alignment.CenterHorizontally,
) {
    ArgonIcon(icon, size = 22.dp, tint = ArgonTheme.colors.ink)
    Text(label, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted, textAlign = TextAlign.Center)
}

private val STYLE_BLOCKS = Regex("""<(style|script)\b[^>]*>.*?</\1\s*>""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))

/** [html] without its `<style>` and `<script>` blocks: the renderer would show their CSS and code as words. */
internal fun withoutStyleBlocks(html: String): String = html.replace(STYLE_BLOCKS, "")

/**
 * The merchant's HTML (a product description, a policy, a section's rich text) through the platform's HTML renderer:
 * paragraphs, lists, bold, links. [centered]: each line centred (a section's `alignment`).
 */
@Composable
fun HtmlText(html: String, modifier: Modifier = Modifier, centered: Boolean = false) {
    if (html.isBlank()) return
    val color = ArgonTheme.colors.ink.toArgb()
    val linkColor = ArgonTheme.colors.accent.toArgb()
    AndroidView(
        factory = {
            TextView(it).apply {
                movementMethod = LinkMovementMethod.getInstance()
                // the body style of the theme (Hanken Grotesk, 16 sp), not the platform's default font
                textSize = 16f
                runCatching { ResourcesCompat.getFont(it, app.argon.ui.R.font.hanken_grotesk) }.getOrNull()?.let { font -> typeface = font }
            }
        },
        update = {
            it.setTextColor(color)
            it.setLinkTextColor(linkColor)
            it.gravity = if (centered) Gravity.CENTER_HORIZONTAL else Gravity.START
            it.text = HtmlCompat.fromHtml(withoutStyleBlocks(html), HtmlCompat.FROM_HTML_MODE_COMPACT).trimEnd()
        },
        modifier = modifier.fillMaxWidth(),
    )
}
