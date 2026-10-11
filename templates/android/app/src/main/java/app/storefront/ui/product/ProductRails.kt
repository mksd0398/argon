package app.storefront.ui.product

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import app.storefront.data.ProductCard
import app.storefront.data.Route
import app.storefront.ui.ProductCardRow
import app.storefront.ui.ProductCardStyle
import app.storefront.ui.SectionHeader

/**
 * Blocks 12 to 14 of the product page, each a heading over a row of product cards that scrolls sideways: "Pairs well
 * with" (compact cards with a quick add), "You may also like" and "Recently viewed" (standard cards). Nothing without
 * [cards]. [onOpen] opens a card's product.
 */
@Composable
internal fun ProductRail(title: String, cards: List<ProductCard>, style: ProductCardStyle, modifier: Modifier = Modifier, onOpen: (Route) -> Unit) {
    if (cards.isEmpty()) return
    val spacing = ArgonTheme.spacing
    val width = if (style == ProductCardStyle.Compact) 132.dp else 160.dp
    Column(modifier.fillMaxWidth().padding(top = spacing.xl), verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        SectionHeader(title, Modifier.padding(horizontal = spacing.l))
        ProductCardRow(cards, { onOpen(Route.Product(it.handle)) }, style = style, cardWidth = width)
    }
}
