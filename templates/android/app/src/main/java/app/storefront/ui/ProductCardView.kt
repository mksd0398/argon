package app.storefront.ui

import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonQuantityStepper
import app.argon.ui.components.ArgonRating
import app.argon.ui.components.ArgonSwatch
import app.storefront.AppGraph
import app.storefront.data.CartStore
import app.storefront.data.Money
import app.storefront.data.ProductCard
import app.storefront.data.QuantityRule
import java.io.IOException
import java.text.NumberFormat
import java.util.Currency
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** "$25.00": the amount in its currency, in the device's locale. */
fun Money.display(): String = runCatching {
    NumberFormat.getCurrencyInstance().apply { currency = Currency.getInstance(currencyCode) }.format(amount.toBigDecimal())
}.getOrDefault("$amount $currencyCode")

/**
 * Heart toggle for the product with id [productId]: filled while it is in the wishlist. A 36 dp disc inside the 48 dp
 * touch target, so the disc sits 6 dp inside whatever corner the button is aligned to.
 */
@Composable
fun WishlistHeart(productId: String, modifier: Modifier = Modifier) {
    val ids by AppGraph.wishlist.ids.collectAsState()
    val saved = productId in ids
    IconButton(
        onClick = {
            AppGraph.scope.launch {
                // a failed write leaves the heart as it was; it must not crash the app
                try {
                    AppGraph.wishlist.toggle(productId)
                } catch (e: IOException) {
                    Log.w("Wishlist", "toggle failed", e)
                }
            }
        },
        modifier,
    ) {
        Box(Modifier.size(36.dp).background(ArgonTheme.colors.surface.copy(alpha = 0.9f), CircleShape), contentAlignment = Alignment.Center) {
            ArgonIcon(
                if (saved) ArgonIconName.HeartFilled else ArgonIconName.Heart,
                size = 17.dp,
                tint = ArgonTheme.colors.ink,
                contentDescription = if (saved) "Remove from wishlist" else "Save to wishlist",
            )
        }
    }
}

/**
 * Standard: the full card of a grid or carousel. Compact: a small card with a quick add (grocery). Row: a list row with
 * its SKU, quantity rule and a quick add (B2B, dense lists).
 */
enum class ProductCardStyle { Standard, Compact, Row }

/** A product in a list, in one of the [ProductCardStyle]s; [onOpen] opens its page. Give it its width (a row fills it). */
@Composable
fun ProductCardView(card: ProductCard, onOpen: () -> Unit, modifier: Modifier = Modifier, style: ProductCardStyle = ProductCardStyle.Standard) =
    when (style) {
        ProductCardStyle.Standard -> StandardCard(card, onOpen, modifier)
        ProductCardStyle.Compact -> CompactCard(card, onOpen, modifier)
        ProductCardStyle.Row -> RowCard(card, onOpen, modifier)
    }

/**
 * Product cards in a row that scrolls sideways (a rail), each [cardWidth] wide, inset by the page's gutter. Not lazy: a
 * rail is a handful of cards, and a lazy row is only as tall as the cards on screen, so the page under it would jump
 * whenever a taller card (a second title line, colour dots) scrolled in. This row is as tall as its tallest card.
 */
@Composable
fun ProductCardRow(
    cards: List<ProductCard>,
    onOpen: (ProductCard) -> Unit,
    modifier: Modifier = Modifier,
    style: ProductCardStyle = ProductCardStyle.Standard,
    cardWidth: Dp = 160.dp,
) = Row(
    modifier.horizontalScroll(rememberScrollState()).padding(horizontal = ArgonTheme.spacing.l),
    horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m),
) {
    for (card in cards) key(card.id) { ProductCardView(card, { onOpen(card) }, Modifier.width(cardWidth), style) }
}

@Composable
private fun CardTitle(card: ProductCard, minLines: Int = 1) =
    Text(card.title, style = ArgonTheme.type.label, color = ArgonTheme.colors.ink, minLines = minLines, maxLines = 2, overflow = TextOverflow.Ellipsis)

@Composable
private fun CardPrice(card: ProductCard) =
    PriceView(card.price, card.compareAt, size = ArgonSize.S, prefix = if (card.hasPriceRange) "From" else null)

/** 4:5 image with the wishlist heart and a "Sold out" or "Sale" tag, vendor, title, rating, price, colour dots. */
@Composable
private fun StandardCard(card: ProductCard, onOpen: () -> Unit, modifier: Modifier) {
    val spacing = ArgonTheme.spacing
    Column(modifier.clickable(onClick = onOpen), verticalArrangement = Arrangement.spacedBy(spacing.xs)) {
        Box(Modifier.fillMaxWidth().aspectRatio(4f / 5f).clip(ArgonTheme.radius.m)) {
            StoreImage(card.image, card.title, Modifier.matchParentSize())
            WishlistHeart(card.id, Modifier.align(Alignment.TopEnd))
            val tag = Modifier.align(Alignment.TopStart).padding(spacing.s)
            if (!card.available) LabelTag("Sold out", tag) else if (card.compareAt != null) LabelTag("Sale", tag, isSale = true)
        }
        if (AppGraph.showVendor && card.vendor.isNotBlank()) {
            Text(card.vendor, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        CardTitle(card)
        // a product nobody has reviewed yet has no stars to show
        val rating = card.rating
        if (rating != null && card.ratingCount != 0) ArgonRating(rating, count = card.ratingCount)
        CardPrice(card)
        ColorDots(card)
    }
}

/** Up to four of the product's colours as dots, then "+N" for the rest. */
@Composable
private fun ColorDots(card: ProductCard) {
    val colors = card.colors
    if (colors.isEmpty()) return
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xxs), verticalAlignment = Alignment.CenterVertically) {
        for (value in colors.take(4)) {
            val fill = swatch(value)
            ArgonSwatch(fill.colorHex, fill.imageUrl, value.name, size = ArgonSize.S)
        }
        if (colors.size > 4) Text("+${colors.size - 4}", style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
    }
}

/** Square image, title, price and a quick add. */
@Composable
private fun CompactCard(card: ProductCard, onOpen: () -> Unit, modifier: Modifier) =
    Column(modifier.clickable(onClick = onOpen), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs)) {
        StoreImage(card.image, card.title, Modifier.fillMaxWidth().aspectRatio(1f).clip(ArgonTheme.radius.m))
        // two lines always, so the quick adds of a row of cards line up
        CardTitle(card, minLines = 2)
        CardPrice(card)
        QuickAdd(card, onOpen)
    }

/** "Min. 2 · Multiples of 2": the parts of [rule] a buyer has to know; null when any quantity can be bought. */
internal fun quantityRuleLabel(rule: QuantityRule?): String? = listOfNotNull(
    rule?.min?.takeIf { it > 1 }?.let { "Min. $it" },
    rule?.step?.takeIf { it > 1 }?.let { "Multiples of $it" },
).joinToString(" · ").ifEmpty { null }

/** Thumbnail, title, SKU, price, the quantity rule, and a quick add at the end. */
@Composable
private fun RowCard(card: ProductCard, onOpen: () -> Unit, modifier: Modifier) = Row(
    modifier.fillMaxWidth().clickable(onClick = onOpen).padding(vertical = ArgonTheme.spacing.s),
    horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m),
    verticalAlignment = Alignment.Top,
) {
    StoreImage(card.image, card.title, Modifier.size(72.dp).clip(ArgonTheme.radius.s))
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xxs)) {
        CardTitle(card)
        card.firstVariant?.sku?.takeIf { it.isNotBlank() }?.let { Text("SKU $it", style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted, maxLines = 1) }
        CardPrice(card)
        quantityRuleLabel(card.firstVariant?.quantityRule)?.let { Text(it, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted) }
    }
    QuickAdd(card, onOpen)
}

/**
 * A card's shortcut to the cart. A product with a choice to make ([ProductCard.quickAddVariantId] is null) gets
 * "Options", which opens it ([onOpen]). Any other gets "Add"; once its variant is in the cart that becomes a stepper on
 * the cart line's quantity, moving by the variant's quantity rule (under the rule's minimum the line is removed). Writes
 * run on the app's scope (scrolling the card away doesn't drop them); a change Shopify refuses shows its message for a
 * moment (`AppGraph.toast`) and leaves the quantity as it was.
 */
@Composable
fun QuickAdd(card: ProductCard, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    // as tall as the button in all three states, so a card doesn't jump when "Add" becomes the stepper
    Box(modifier.heightIn(min = 44.dp), contentAlignment = Alignment.CenterStart) {
        val variantId = card.quickAddVariantId
        if (variantId == null) {
            ArgonButton("Options", style = ArgonButtonStyle.Secondary, size = ArgonSize.S, action = onOpen)
            return@Box
        }
        val cart by AppGraph.cart.cart.collectAsState()
        val line = cart?.lines?.firstOrNull { it.merchandise.id == variantId }
        val rule = card.firstVariant?.quantityRule ?: QuantityRule()
        var busy by remember { mutableStateOf(false) }

        fun write(change: suspend CartStore.() -> Unit) {
            busy = true
            AppGraph.scope.launch {
                try {
                    AppGraph.cart.change()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    AppGraph.toast.show(e.message ?: "Couldn't update the cart")
                } finally {
                    busy = false
                }
            }
        }

        if (line == null) {
            ArgonButton("Add", style = ArgonButtonStyle.Secondary, size = ArgonSize.S, isLoading = busy) { write { add(variantId, rule.min) } }
        } else {
            ArgonQuantityStepper(
                line.quantity,
                onChange = { quantity -> write { update(line.id, if (quantity < rule.min) 0 else quantity) } },
                min = 0,
                max = rule.maximum,
                step = rule.step,
                size = ArgonSize.S,
                isEnabled = !busy,
            )
        }
    }
}
