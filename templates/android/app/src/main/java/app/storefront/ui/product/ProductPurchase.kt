package app.storefront.ui.product

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonDivider
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonQuantityStepper
import app.argon.ui.components.ArgonRadioGroup
import app.argon.ui.components.steppedQuantity
import app.storefront.data.Money
import app.storefront.data.QuantityRule
import app.storefront.data.SellingPlanAllocation
import app.storefront.data.UnitPriceMeasurement
import app.storefront.data.Variant
import app.storefront.ui.LabelTag
import app.storefront.ui.PriceView
import app.storefront.ui.discountPercent
import app.storefront.ui.display

// The buying blocks of the product page: price (unit price, company tag, volume pricing, quantity rule), availability,
// purchase options, quantity with Buy now, and the sticky add-to-cart bar. The rules are the plain functions on top.

/** [quantity] brought onto [rule]: no less than its minimum, no more than its maximum, on its increments (5 in twos is 4). */
internal fun clampedQuantity(quantity: Int, rule: QuantityRule?): Int {
    val r = rule ?: QuantityRule()
    return steppedQuantity(quantity, 0, r.min, r.maximum, r.step)
}

/** A row of the volume pricing table: from [from] items up, each costs [price]. */
internal data class VolumeRow(val from: Int, val price: Money) {
    /** "10+" */
    val label: String get() = "$from+"
}

/**
 * The volume pricing table of [variant]: its own price from the smallest quantity that can be bought, then one row per
 * price break, by quantity. Empty for a variant without price breaks.
 */
internal fun volumeRows(variant: Variant): List<VolumeRow> {
    if (variant.quantityPriceBreaks.isEmpty()) return emptyList()
    val first = VolumeRow((variant.quantityRule ?: QuantityRule()).min, variant.price)
    val breaks = variant.quantityPriceBreaks.sortedBy { it.minimumQuantity }.filter { it.minimumQuantity > first.from }
    return listOf(first) + breaks.map { VolumeRow(it.minimumQuantity, it.price) }
}

/** The row [quantity] buys at (the one to highlight): the last one it reaches. */
internal fun volumeRow(rows: List<VolumeRow>, quantity: Int): VolumeRow? = rows.lastOrNull { it.from <= quantity }

private val UNIT_NAMES = mapOf("ITEM" to "item", "FLOZ" to "fl oz", "FT2" to "ft²", "M2" to "m²", "M3" to "m³")

/**
 * "$6.00 / item", "$2.50 / 100 g": [price] per the [measurement]'s reference amount. Null without a unit price.
 * Shopify's unit names are shown in lower case ("KG" is "kg"), the few that don't read that way by [UNIT_NAMES].
 */
internal fun unitPriceLabel(price: Money?, measurement: UnitPriceMeasurement?): String? {
    val unit = measurement?.referenceUnit?.takeIf { it.isNotBlank() } ?: return null
    if (price == null) return null
    val name = UNIT_NAMES[unit] ?: unit.lowercase()
    val per = if (measurement.referenceValue > 1) "${measurement.referenceValue} $name" else name
    return "${price.display()} / $per"
}

/** "Minimum 2 · Maximum 40 · Sold in multiples of 2": the parts of [rule] that limit an order; null when none does. */
internal fun quantityRuleSentence(rule: QuantityRule?): String? = listOfNotNull(
    rule?.min?.takeIf { it > 1 }?.let { "Minimum $it" },
    rule?.maximum?.let { "Maximum $it" },
    rule?.step?.takeIf { it > 1 }?.let { "Sold in multiples of $it" },
).joinToString(" · ").ifEmpty { null }

/** Good: in stock. Low: nearly gone (the warning colour). Later: sold now, shipped when it is back. */
internal enum class AvailabilityTone { Good, Low, Later }

internal data class AvailabilityLine(val text: String, val tone: AvailabilityTone)

/**
 * What the page says about [variant]'s stock: "Only 3 left" for 1 to 5, "Ships when back in stock" for one sold while
 * out of stock, else "In stock". Null for a variant that can't be bought (the button says "Sold out") or isn't there.
 */
internal fun availabilityLine(variant: Variant?): AvailabilityLine? = when {
    variant == null || !variant.available -> null
    (variant.quantityAvailable ?: 0) in 1..5 -> AvailabilityLine("Only ${variant.quantityAvailable} left", AvailabilityTone.Low)
    variant.currentlyNotInStock -> AvailabilityLine("Ships when back in stock", AvailabilityTone.Later)
    else -> AvailabilityLine("In stock", AvailabilityTone.Good)
}

/** "Sale −20%": the gallery's tag for a price below its compare-at price; null when it is no discount. */
internal fun saleTag(price: Money, compareAt: Money?): String? = discountPercent(price, compareAt)?.let { "Sale −$it%" }

/** What the variant costs on the plan of [allocation]; null when the store sends no price for it. */
internal fun planPrice(allocation: SellingPlanAllocation): Money? = allocation.priceAdjustments.firstOrNull()?.price

/** "Deliver every month · $108.00": a plan's row among the purchase options. */
internal fun planLabel(allocation: SellingPlanAllocation): String =
    listOfNotNull(allocation.sellingPlan.name, planPrice(allocation)?.display()).joinToString(" · ")

/**
 * The plan [variant] is bought on: the one with [planId]; without one, a one-time purchase (null), or the variant's
 * first plan when the product is sold by plan only ([requiresSellingPlan]).
 */
internal fun chosenPlan(variant: Variant?, requiresSellingPlan: Boolean, planId: String?): SellingPlanAllocation? {
    val plans = variant?.sellingPlanAllocations.orEmpty()
    return plans.firstOrNull { it.sellingPlan.id == planId } ?: plans.firstOrNull().takeIf { requiresSellingPlan }
}

/** What one item costs as chosen, and the higher price to strike beside it (null: none). */
internal data class ChosenPrice(val price: Money, val compareAt: Money?)

/**
 * The price of one [variant] as the shopper has set it up: on [plan], the plan's price; else the volume price
 * [quantity] reaches ([volumeRow]); else the variant's own. The struck price is the plan's or the variant's compare-at,
 * else the variant's own price when the chosen one is lower.
 */
internal fun chosenPrice(variant: Variant, quantity: Int, plan: SellingPlanAllocation?): ChosenPrice {
    val price = plan?.let(::planPrice) ?: volumeRow(volumeRows(variant), quantity)?.price ?: variant.price
    val compareAt = plan?.priceAdjustments?.firstOrNull()?.compareAtPrice ?: variant.compareAt ?: variant.price.takeIf { it != price }
    return ChosenPrice(price, compareAt)
}

/** Where an add to the cart stands: nothing running, running, or just done (shown for two seconds). */
internal enum class AddPhase { Idle, Adding, Added }

/** The main button's words: "Unavailable" without a variant, "Sold out" for one that can't be bought, else by [phase]. */
internal fun addButtonLabel(variant: Variant?, phase: AddPhase): String = when {
    variant == null -> "Unavailable"
    !variant.available -> "Sold out"
    phase == AddPhase.Adding -> "Adding…"
    phase == AddPhase.Added -> "Added"
    else -> "Add to cart"
}

/**
 * Block 3. The price as chosen ([price]), the unit price, "Your price for <company>" in a company context
 * ([companyName]), the volume pricing table with the row [quantity] reaches highlighted, and the quantity rule.
 */
@Composable
internal fun ProductPrice(variant: Variant?, price: ChosenPrice?, quantity: Int, companyName: String?, modifier: Modifier = Modifier) {
    if (variant == null || price == null) return
    val spacing = ArgonTheme.spacing
    Column(
        modifier.fillMaxWidth().padding(start = spacing.l, end = spacing.l, top = spacing.m),
        verticalArrangement = Arrangement.spacedBy(spacing.s),
    ) {
        PriceView(price.price, price.compareAt, size = ArgonSize.L)
        unitPriceLabel(variant.unitPrice, variant.unitPriceMeasurement)?.let {
            Text(it, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
        }
        if (companyName != null) LabelTag("Your price for $companyName")
        VolumePricing(volumeRows(variant), quantity)
        quantityRuleSentence(variant.quantityRule)?.let {
            Text(it, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
        }
    }
}

/** "Volume pricing", then a row per step ("10+", "$108.00 each"); the row [quantity] reaches is on the surface colour. */
@Composable
private fun VolumePricing(rows: List<VolumeRow>, quantity: Int) {
    if (rows.isEmpty()) return
    val spacing = ArgonTheme.spacing
    val colors = ArgonTheme.colors
    val current = volumeRow(rows, quantity)
    Column(Modifier.fillMaxWidth().clip(ArgonTheme.radius.m).border(1.dp, colors.border, ArgonTheme.radius.m)) {
        Text("Volume pricing", Modifier.padding(horizontal = spacing.m, vertical = spacing.s), style = ArgonTheme.type.label, color = colors.muted)
        for (row in rows) {
            val isCurrent = row == current
            Row(
                Modifier.fillMaxWidth()
                    .then(if (isCurrent) Modifier.background(colors.surface) else Modifier)
                    .semantics(mergeDescendants = true) { selected = isCurrent }
                    .padding(horizontal = spacing.m, vertical = spacing.s),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(row.label, style = ArgonTheme.type.label, color = if (isCurrent) colors.ink else colors.muted)
                Text("${row.price.display()} each", style = ArgonTheme.type.label, color = if (isCurrent) colors.ink else colors.muted)
            }
        }
    }
}

/** Block 5. The stock line ([availabilityLine]) and "Pickup available at <location>" ([pickup], the location's name). */
@Composable
internal fun ProductAvailability(variant: Variant?, pickup: String?, modifier: Modifier = Modifier) {
    val line = availabilityLine(variant)
    if (line == null && pickup == null) return
    val spacing = ArgonTheme.spacing
    val colors = ArgonTheme.colors
    Column(
        modifier.fillMaxWidth().padding(start = spacing.l, end = spacing.l, top = spacing.l),
        verticalArrangement = Arrangement.spacedBy(spacing.xs),
    ) {
        if (line != null) {
            val color = when (line.tone) {
                AvailabilityTone.Good -> colors.success
                AvailabilityTone.Low -> colors.sale
                AvailabilityTone.Later -> colors.muted
            }
            val icon = if (line.tone == AvailabilityTone.Good) ArgonIconName.Check else ArgonIconName.Clock
            IconLine(icon, line.text, color)
        }
        if (pickup != null) IconLine(ArgonIconName.Location, "Pickup available at $pickup", colors.muted)
    }
}

@Composable
private fun IconLine(icon: ArgonIconName, text: String, color: Color) =
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs), verticalAlignment = Alignment.CenterVertically) {
        ArgonIcon(icon, size = 16.dp, tint = color)
        Text(text, style = ArgonTheme.type.label, color = color, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }

/**
 * Block 6, for a variant with selling plans. "One-time purchase" (left out when the product is sold by plan only,
 * [requiresSellingPlan]) and each plan with its price; [plan] is the chosen one, [onSelect] gets a plan's id, or null
 * for the one-time purchase.
 */
@Composable
internal fun ProductPurchaseOptions(
    variant: Variant?,
    requiresSellingPlan: Boolean,
    plan: SellingPlanAllocation?,
    modifier: Modifier = Modifier,
    onSelect: (planId: String?) -> Unit,
) {
    val plans = variant?.sellingPlanAllocations.orEmpty()
    if (plans.isEmpty()) return
    val spacing = ArgonTheme.spacing
    val oneTime = if (requiresSellingPlan) emptyList() else listOf("One-time purchase")
    // the rows are the one-time purchase (when there is one), then the plans
    val chosen = plans.indexOfFirst { it.sellingPlan.id == plan?.sellingPlan?.id }
    val selected = if (chosen >= 0) chosen + oneTime.size else if (requiresSellingPlan) null else 0
    Column(modifier.fillMaxWidth().padding(start = spacing.l, end = spacing.l, top = spacing.xl)) {
        Text("Purchase options", style = ArgonTheme.type.label, color = ArgonTheme.colors.muted)
        ArgonRadioGroup(oneTime + plans.map(::planLabel), selected, { row -> onSelect(plans.getOrNull(row - oneTime.size)?.sellingPlan?.id) })
    }
}

/**
 * Block 7. The quantity on the variant's [rule], and "Buy now" (adds, then opens checkout; [isBuying] while it does).
 * [canBuyNow] is off while another add is running.
 */
@Composable
internal fun ProductQuantity(
    quantity: Int,
    rule: QuantityRule?,
    canBuyNow: Boolean,
    isBuying: Boolean,
    modifier: Modifier = Modifier,
    onQuantity: (Int) -> Unit,
    onBuyNow: () -> Unit,
) {
    val spacing = ArgonTheme.spacing
    val r = rule ?: QuantityRule()
    Column(
        modifier.fillMaxWidth().padding(start = spacing.l, end = spacing.l, top = spacing.xl),
        verticalArrangement = Arrangement.spacedBy(spacing.l),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Quantity", Modifier.weight(1f), style = ArgonTheme.type.label, color = ArgonTheme.colors.muted)
            ArgonQuantityStepper(quantity, onQuantity, min = r.min, max = r.maximum, step = r.step)
        }
        ArgonButton("Buy now", style = ArgonButtonStyle.Secondary, isLoading = isBuying, isEnabled = canBuyNow, fullWidth = true, action = onBuyNow)
    }
}

/**
 * The bar pinned under the page, above the system's navigation: the price as chosen on the left, the main button on the
 * right ([label], see [addButtonLabel]). It goes in the scaffold's bottom slot.
 */
@Composable
internal fun StickyAddBar(price: ChosenPrice?, label: String, isEnabled: Boolean, isLoading: Boolean, onAdd: () -> Unit) {
    val spacing = ArgonTheme.spacing
    // the surface runs under the system's navigation; the content stays above it
    Column(Modifier.fillMaxWidth().background(ArgonTheme.colors.surface)) {
        ArgonDivider()
        Row(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = spacing.l, vertical = spacing.m),
            horizontalArrangement = Arrangement.spacedBy(spacing.m),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.weight(1f)) { if (price != null) PriceView(price.price, price.compareAt) }
            // as wide for "Added" as for "Add to cart": the price beside it doesn't jump
            ArgonButton(label, Modifier.widthIn(min = 160.dp), isLoading = isLoading, isEnabled = isEnabled, action = onAdd)
        }
    }
}
