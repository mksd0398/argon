package app.storefront.ui.orders

import app.storefront.data.Cart
import app.storefront.data.Fulfillment
import app.storefront.data.Money
import app.storefront.data.Order
import app.storefront.data.OrderLine
import app.storefront.data.OrderSummary
import app.storefront.data.OrderTransaction
import app.storefront.data.PricingValue
import app.storefront.ui.display
import app.storefront.ui.displayDate
import app.storefront.ui.displayStatus

// The orders pages' rules, kept free of UI so they can be tested (and read side by side with iOS).

/** The four steps of an order's progress, in order. */
val ORDER_STEPS = listOf("Confirmed", "Shipped", "Out for delivery", "Delivered")

/**
 * An order's status in the shopper's words. A cancelled order is "Cancelled"; else what its latest shipment says
 * ([shipmentStatus]: DELIVERED, IN_TRANSIT, ...); else, with no shipment news, its [fulfillmentStatus].
 */
fun orderStatus(cancelledAt: String?, shipmentStatus: String?, fulfillmentStatus: String?): String = when {
    cancelledAt != null -> "Cancelled"
    shipmentStatus == "DELIVERED" -> "Delivered"
    shipmentStatus == "OUT_FOR_DELIVERY" -> "Out for delivery"
    shipmentStatus == "IN_TRANSIT" || shipmentStatus == "CARRIER_PICKED_UP" || shipmentStatus == "CONFIRMED" -> "On its way"
    shipmentStatus?.startsWith("LABEL_") == true -> "On its way"
    shipmentStatus == "ATTEMPTED_DELIVERY" || shipmentStatus == "DELAYED" || shipmentStatus == "FAILURE" -> "Delivery issue"
    shipmentStatus == "READY_FOR_PICKUP" -> "Ready for pickup"
    shipmentStatus == "PICKED_UP" -> "Picked up"
    fulfillmentStatus == "FULFILLED" -> "Shipped"
    fulfillmentStatus == "PARTIALLY_FULFILLED" -> "Partly shipped"
    fulfillmentStatus == "ON_HOLD" -> "On hold"
    else -> "Confirmed"
}

/** The status of an order in the list. */
fun orderStatus(order: OrderSummary): String = orderStatus(order.cancelledAt, order.latestShipmentStatus, order.fulfillmentStatus)

/** The status of an order on its page: by its first shipment, as the list has it. */
fun orderStatus(order: Order): String =
    orderStatus(order.cancelledAt, order.fulfillments.firstOrNull()?.latestShipmentStatus, order.fulfillmentStatus)

/**
 * How far an order has come, as an index into [ORDER_STEPS], from what its shipment's carrier reported (its events and
 * latest status): 0 Confirmed (nothing shipped, or the shipment was cancelled), 1 Shipped, 2 Out for delivery (also a
 * delivery that was attempted, or an order ready for pickup), 3 Delivered (or picked up).
 */
fun orderProgressStep(fulfillment: Fulfillment?): Int {
    if (fulfillment == null || fulfillment.status == "CANCELLED" || fulfillment.status == "ERROR" || fulfillment.status == "FAILURE") return 0
    val seen = fulfillment.events.map { it.status } + listOfNotNull(fulfillment.latestShipmentStatus)
    return when {
        fulfillment.isPickedUp || "DELIVERED" in seen || "PICKED_UP" in seen -> 3
        "OUT_FOR_DELIVERY" in seen || "ATTEMPTED_DELIVERY" in seen || "READY_FOR_PICKUP" in seen -> 2
        else -> 1
    }
}

/** A variant's title worth showing: not blank, and not Shopify's "Default Title" of a product without options. */
fun variantLabel(title: String?): String? = title?.trim()?.takeIf { it.isNotEmpty() && it != "Default Title" }

/** The lines under an ordered item's title: its variant, "SKU ..." and "Qty N", each only when there is one. */
fun itemDetails(variantTitle: String?, sku: String?, quantity: Int?): List<String> = listOfNotNull(
    variantLabel(variantTitle),
    sku?.trim()?.takeIf { it.isNotEmpty() }?.let { "SKU $it" },
    quantity?.let { "Qty $it" },
)

/** A shipment's events with the newest first. */
fun newestFirst(fulfillment: Fulfillment) = fulfillment.events.sortedByDescending { it.happenedAt.orEmpty() }

/** "1 item", "4 items". */
fun itemCountLabel(count: Int): String = if (count == 1) "1 item" else "$count items"

/** The "+N" after an order's thumbnails: how many of its [itemCount] items the [shown] thumbnails leave out. */
fun moreItems(itemCount: Int?, shown: Int): Int = ((itemCount ?: shown) - shown).coerceAtLeast(0)

/**
 * An order's delivery line in the list: "Delivered <date>" once it was, "Arrives <date>" while its shipment has a date;
 * null for a cancelled order and for one with no shipment news. [date] formats an ISO date.
 */
fun deliveryNote(order: OrderSummary, date: (String) -> String = ::displayDate): String? {
    if (order.cancelledAt != null) return null
    order.latestFulfillmentDeliveryDate?.let { return "Delivered ${date(it)}" }
    return order.estimatedDeliveryAt?.let { "Arrives ${date(it)}" }
}

/** One thing "Buy again" adds to the cart; [title] names it if it turns out to be unavailable. */
data class BuyAgainLine(val variantId: String, val quantity: Int, val title: String)

/** What "Buy again" does with an order: the [lines] to add, and the titles of the items that can't be bought any more. */
data class BuyAgain(val lines: List<BuyAgainLine>, val unavailable: List<String>)

/**
 * The cart lines that buy [lines] again: each variant once, with the quantity ordered (two lines of one variant add up).
 * A line whose variant no longer exists (no variant id) is [BuyAgain.unavailable]; a line with no quantity is skipped.
 */
fun buyAgainPlan(lines: List<OrderLine>): BuyAgain {
    val wanted = lines.filter { it.quantity > 0 }
    val add = wanted.filter { it.variantId != null }.groupBy { it.variantId!! }
        .map { (variantId, same) -> BuyAgainLine(variantId, same.sumOf { it.quantity }, same.first().title) }
    return BuyAgain(add, wanted.filter { it.variantId == null }.map { it.title }.distinct())
}

/** What "Buy again" tells the shopper: [added] lines went in the cart, the [unavailable] titles couldn't. */
fun buyAgainMessage(added: Int, unavailable: List<String>): String = when {
    unavailable.isEmpty() -> "Added to your cart"
    added == 0 -> "No longer available: ${unavailable.joinToString(", ")}"
    else -> "Added to your cart. No longer available: ${unavailable.joinToString(", ")}"
}

/** How many of the variant are in [cart]. */
fun quantityIn(cart: Cart?, variantId: String): Int = cart?.lines.orEmpty().filter { it.merchandise.id == variantId }.sumOf { it.quantity }

/**
 * How a payment was made: "Visa ending in 4242", "Gift card ending in 1234", else its type ("Bank deposit"); null when
 * the transaction says none of it.
 */
fun paymentLabel(transaction: OrderTransaction): String? {
    val brand = transaction.cardBrand?.takeIf { it.isNotBlank() }?.let(::displayStatus)
    val last4 = transaction.last4?.takeIf { it.isNotBlank() }
    val giftCard = transaction.giftCardLast4?.takeIf { it.isNotBlank() }
    return when {
        brand != null && last4 != null -> "$brand ending in $last4"
        brand != null -> brand
        giftCard != null -> "Gift card ending in $giftCard"
        else -> transaction.type?.takeIf { it.isNotBlank() }?.let(::displayStatus)
    }
}

/** The ways an order was paid, each once: its payments (not its refunds), leaving out the ones that failed. */
fun paymentMethods(transactions: List<OrderTransaction>): List<String> = transactions
    .filter { it.kind == "SALE" || it.kind == "CAPTURE" || it.kind == "AUTHORIZATION" }
    .filter { it.status != "FAILURE" && it.status != "ERROR" }
    .mapNotNull(::paymentLabel)
    .distinct()

/** A discount on an order as its totals show it: "-10%" or "-$5.00"; null for a kind of discount this app doesn't know. */
fun discountLabel(value: PricingValue): String? = when (value) {
    is Money -> "-${value.display()}"
    is PricingValue.Percentage -> "-${value.percentage.toBigDecimal().stripTrailingZeros().toPlainString()}%"
    is PricingValue.Other -> null
}
