package app.storefront.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.storefront.AppGraph
import app.storefront.data.CollectionCard
import app.storefront.data.HomeContent
import app.storefront.data.Img
import app.storefront.data.ProductCard
import app.storefront.data.Route
import app.storefront.data.Section
import app.storefront.ui.ProductCardRow
import app.storefront.ui.ProductCardStyle
import app.storefront.ui.ProductCardView
import app.storefront.ui.SectionHeader
import app.storefront.ui.StoreImage

// The blocks the four home templates share. Each one is a whole section (its heading included) and takes the page's full
// width: it brings its own side margin (spacing.l), so a row of cards can scroll off the screen's edges.

/** A rail's heading; a store's product section may have none. */
internal val Section.Products.title: String get() = heading?.takeIf { it.isNotBlank() } ?: "Featured"

/**
 * Where a rail's "View all" leads: the collection it shows, else the whole catalogue.
 * ponytail: a rail doesn't carry its collection, so it is matched to a category by its title (true for a store without a
 * home screen, whose rails are its collections). Upgrade: keep the collection's handle on `Section.Products`.
 */
internal fun HomeContent.routeOf(rail: Section.Products): Route =
    Route.Collection(categories.firstOrNull { it.title == rail.heading }?.handle ?: "all")

/** The banners of a hero carousel: all but the second, which a template shows as a card further down the page. */
internal fun heroBanners(banners: List<Section.Banner>): List<Section.Banner> = banners.filterIndexed { index, _ -> index != 1 }

/**
 * A banner: its image in a box of [ratio] (width to height), with the heading, the text and the button over it at the
 * bottom start. The whole banner opens its link. [compact] is for short banners: tighter margins, a small button, no text.
 * [textColor]: the words' colour (a section's `text_color`); the light ink of the dark palette by default.
 */
@Composable
internal fun BannerView(
    banner: Section.Banner,
    onOpen: (Route) -> Unit,
    ratio: Float,
    modifier: Modifier = Modifier,
    headingStyle: TextStyle = ArgonTheme.type.title,
    shape: Shape = ArgonTheme.radius.l,
    compact: Boolean = false,
    textColor: Color? = null,
) {
    val link = banner.link
    val heading = banner.heading?.takeIf { it.isNotBlank() }
    val text = banner.text?.takeIf { it.isNotBlank() && !compact }
    val button = banner.buttonLabel?.takeIf { it.isNotBlank() && link != null }
    Box(modifier.fillMaxWidth().aspectRatio(ratio).clip(shape).then(if (link != null) Modifier.clickable { onOpen(link) } else Modifier)) {
        StoreImage(banner.image, null, Modifier.matchParentSize())
        if (heading == null && text == null && button == null) return@Box
        // What sits on a photo uses the dark palette in light and dark mode alike: a dark shade, light text, a light button.
        ArgonTheme(darkTheme = true, headingFont = AppGraph.headingFont, bodyFont = AppGraph.bodyFont, corners = AppGraph.look.corners, buttons = AppGraph.look.buttons) {
            val colors = ArgonTheme.colors
            val spacing = ArgonTheme.spacing
            // the shade grows towards the bottom, where the words are; a banner without a picture is all shade. In a short
            // banner the heading reaches the top, so the whole picture is shaded a little for it to stay readable.
            val shade = when {
                banner.image == null -> SolidColor(colors.paper)
                compact -> Brush.verticalGradient(0f to colors.paper.copy(alpha = 0.3f), 1f to colors.paper.copy(alpha = 0.85f))
                else -> Brush.verticalGradient(0.35f to Color.Transparent, 1f to colors.paper.copy(alpha = 0.85f))
            }
            Column(
                Modifier.matchParentSize().background(shade).padding(if (compact) spacing.m else spacing.l),
                verticalArrangement = Arrangement.spacedBy(spacing.s, Alignment.Bottom),
            ) {
                // The heading has the height the text and the button leave, and is cut with an ellipsis to fit it: nothing
                // spills out of the banner, however long the store's words are.
                if (heading != null) {
                    Text(heading, Modifier.weight(1f, fill = false), style = headingStyle, color = textColor ?: colors.ink, maxLines = if (compact) 2 else 3, overflow = TextOverflow.Ellipsis)
                }
                if (text != null) Text(text, style = ArgonTheme.type.body, color = textColor ?: colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (button != null && link != null) ArgonButton(button, size = if (compact) ArgonSize.S else ArgonSize.M) { onOpen(link) }
            }
        }
    }
}

/** A titled row of product cards that scrolls sideways, each card [cardWidth] wide, with "View all" ([viewAll]). */
@Composable
internal fun ProductRail(
    title: String,
    cards: List<ProductCard>,
    viewAll: Route,
    onOpen: (Route) -> Unit,
    style: ProductCardStyle = ProductCardStyle.Standard,
    cardWidth: Dp = 160.dp,
) {
    val spacing = ArgonTheme.spacing
    Column(verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        SectionHeader(title, Modifier.padding(horizontal = spacing.l), actionLabel = "View all") { onOpen(viewAll) }
        ProductCardRow(cards, { onOpen(Route.Product(it.handle)) }, style = style, cardWidth = cardWidth)
    }
}

/**
 * A category's picture: the collection's own image, else its first product's (many stores never give their collections
 * one). Null, and so the quiet placeholder, only when it has neither.
 */
internal val CollectionCard.picture: Img? get() = image ?: products.firstOrNull()?.image

/** [cards] two to a row (a lazy grid can't sit inside the home's list, and these are a handful of cards). */
@Composable
internal fun ProductPairs(cards: List<ProductCard>, onOpen: (Route) -> Unit, modifier: Modifier = Modifier) {
    val spacing = ArgonTheme.spacing
    Column(modifier, verticalArrangement = Arrangement.spacedBy(spacing.l)) {
        for (pair in cards.chunked(2)) {
            Row(horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
                for (card in pair) ProductCardView(card, { onOpen(Route.Product(card.handle)) }, Modifier.weight(1f))
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** A titled list of [cards] as rows (thumbnail, SKU, price, quick add), with "View all" when [viewAll] is given. */
@Composable
internal fun ProductRows(title: String, cards: List<ProductCard>, onOpen: (Route) -> Unit, viewAll: Route? = null) =
    Column(Modifier.padding(horizontal = ArgonTheme.spacing.l)) {
        SectionHeader(title, actionLabel = viewAll?.let { "View all" }, onAction = viewAll?.let { { onOpen(it) } })
        for (card in cards) ProductCardView(card, { onOpen(Route.Product(card.handle)) }, style = ProductCardStyle.Row)
    }

/** What a template shows under its banners when the store has no categories and no products to show. */
@Composable
internal fun EmptyNote() = Text(
    "Nothing to show yet.",
    Modifier.fillMaxWidth().padding(ArgonTheme.spacing.xl),
    style = ArgonTheme.type.body,
    color = ArgonTheme.colors.muted,
    textAlign = TextAlign.Center,
)
