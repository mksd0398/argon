package app.storefront.ui.orders

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonCard
import app.argon.ui.components.ArgonCardStyle
import app.argon.ui.components.ArgonTag
import app.argon.ui.components.ArgonTagStyle
import app.storefront.data.Img
import app.storefront.data.OrderSummary
import app.storefront.ui.StoreImage
import app.storefront.ui.display
import app.storefront.ui.displayDate

// The blocks the orders list, the order page, the account page and the returns flow share.

/**
 * An order in a list: its name, date and status tag, up to three thumbnails (then "+N"), how many items, the total, and
 * "Arrives <date>" or "Delivered <date>" once it ships. [onOpen] opens the order.
 */
@Composable
fun OrderCard(order: OrderSummary, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val spacing = ArgonTheme.spacing
    val type = ArgonTheme.type
    val colors = ArgonTheme.colors
    ArgonCard(modifier.fillMaxWidth(), style = ArgonCardStyle.Elevated, onClick = onOpen) {
        Column(Modifier.fillMaxWidth().padding(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.m)) {
            Row(horizontalArrangement = Arrangement.spacedBy(spacing.s), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(order.name, style = type.headline, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(displayDate(order.processedAt), style = type.caption, color = colors.muted, maxLines = 1)
                }
                // the tag is a chip: a tap on it opens the order like the rest of the card
                ArgonTag(orderStatus(order), style = ArgonTagStyle.Info, onClick = onOpen)
            }
            val shown = order.lineItems.take(3)
            if (shown.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(spacing.s), verticalAlignment = Alignment.CenterVertically) {
                    for (line in shown) StoreImage(line.image, line.title, Modifier.size(56.dp).clip(ArgonTheme.radius.m))
                    val more = moreItems(order.itemCount, shown.size)
                    if (more > 0) Text("+$more", style = type.label, color = colors.muted, maxLines = 1)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(spacing.s), verticalAlignment = Alignment.CenterVertically) {
                Text(order.itemCount?.let(::itemCountLabel).orEmpty(), Modifier.weight(1f), style = type.label, color = colors.muted, maxLines = 1)
                Text(order.total.display(), style = type.headline, color = colors.ink, maxLines = 1)
            }
            deliveryNote(order)?.let { Text(it, style = type.label, color = colors.ink) }
        }
    }
}

/**
 * An item of an order or a return: its thumbnail, [title], the [details] under it (variant, SKU, quantity, ...), and
 * [trailing] at the end of the line (a price).
 */
@Composable
fun ItemRow(image: Img?, title: String, details: List<String>, modifier: Modifier = Modifier, trailing: String? = null) {
    val type = ArgonTheme.type
    val colors = ArgonTheme.colors
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m), verticalAlignment = Alignment.Top) {
        // decorative: the title beside it says what it is
        StoreImage(image?.url, null, Modifier.size(64.dp).clip(ArgonTheme.radius.m))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xxs)) {
            Text(title, style = type.label, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
            for (detail in details) Text(detail, style = type.caption, color = colors.muted)
        }
        if (trailing != null) Text(trailing, style = type.label, color = colors.ink, maxLines = 1)
    }
}
