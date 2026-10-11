package app.storefront.data

import com.shopify.checkoutsheetkit.lifecycleevents.OrderDetails
import com.shopify.checkoutsheetkit.pixelevents.PixelEvent
import com.shopify.checkoutsheetkit.pixelevents.StandardPixelEvent
import java.util.logging.Level
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException

// Analytics: one hub ([Analytics]) that every screen and store reports into, with the providers (Google Analytics, Meta,
// MoEngage) behind it as [AnalyticsSink]s. The events, their names and where each is fired are the same on iOS.

/**
 * A product in an event. Ids are the numeric tail of the Shopify gid ("gid://shopify/Product/123" is "123"): what
 * Google's and Meta's catalogs use. [variant] is the variant's title, [price] one item's.
 */
data class AnalyticsItem(
    val productId: String,
    val variantId: String? = null,
    val name: String,
    val brand: String? = null,
    val category: String? = null,
    val variant: String? = null,
    val price: Double? = null,
    val quantity: Int = 1,
)

/** What the shopper did, one case per event. [name] is Google Analytics 4's name for it. */
sealed class AnalyticsEvent(val name: String) {
    data class ScreenView(val screen: String) : AnalyticsEvent("screen_view")
    data class ViewItemList(val listId: String?, val listName: String, val items: List<AnalyticsItem>) : AnalyticsEvent("view_item_list")
    data class ViewItem(val item: AnalyticsItem, val currency: String) : AnalyticsEvent("view_item")
    data class Search(val term: String) : AnalyticsEvent("search")
    data class AddToWishlist(val item: AnalyticsItem, val currency: String) : AnalyticsEvent("add_to_wishlist")
    data class AddToCart(val item: AnalyticsItem, val currency: String) : AnalyticsEvent("add_to_cart")
    data class RemoveFromCart(val item: AnalyticsItem, val currency: String) : AnalyticsEvent("remove_from_cart")
    data class ViewCart(val items: List<AnalyticsItem>, val value: Double, val currency: String) : AnalyticsEvent("view_cart")
    data class BeginCheckout(val items: List<AnalyticsItem>, val value: Double, val currency: String, val coupon: String? = null) :
        AnalyticsEvent("begin_checkout")
    data class AddShippingInfo(val value: Double, val currency: String) : AnalyticsEvent("add_shipping_info")
    data class AddPaymentInfo(val value: Double, val currency: String) : AnalyticsEvent("add_payment_info")

    /** [orderId]: the order's numeric id, the same in the app and on the server, which is what stops a sale being counted twice. */
    data class Purchase(
        val orderId: String,
        val value: Double,
        val currency: String,
        val tax: Double? = null,
        val shipping: Double? = null,
        val coupon: String? = null,
        val items: List<AnalyticsItem>,
    ) : AnalyticsEvent("purchase")

    data object Login : AnalyticsEvent("login")

    /**
     * The event's values under Google Analytics 4's parameter names, flat, without those it has none of: what the log
     * prints. An item list is one short text per item ("<product id>/<variant id> x<quantity>").
     */
    val params: Map<String, Any>
        get() = when (this) {
            is ScreenView -> values("screen_name" to screen)
            is ViewItemList -> values("item_list_id" to listId, "item_list_name" to listName, "items" to items.labels())
            is ViewItem -> item.values(currency)
            is Search -> values("search_term" to term)
            is AddToWishlist -> item.values(currency)
            is AddToCart -> item.values(currency)
            is RemoveFromCart -> item.values(currency)
            is ViewCart -> values("value" to value, "currency" to currency, "items" to items.labels())
            is BeginCheckout -> values("value" to value, "currency" to currency, "coupon" to coupon, "items" to items.labels())
            is AddShippingInfo -> values("value" to value, "currency" to currency)
            is AddPaymentInfo -> values("value" to value, "currency" to currency)
            is Purchase -> values(
                "transaction_id" to orderId, "value" to value, "currency" to currency, "tax" to tax, "shipping" to shipping,
                "coupon" to coupon, "items" to items.labels(),
            )
            Login -> emptyMap()
        }
}

private fun values(vararg pairs: Pair<String, Any?>): Map<String, Any> = buildMap { for ((key, value) in pairs) if (value != null) put(key, value) }

private fun AnalyticsItem.values(currency: String) = values(
    "item_id" to productId, "variant_id" to variantId, "item_name" to name, "item_brand" to brand, "item_category" to category,
    "item_variant" to variant, "price" to price, "quantity" to quantity, "currency" to currency,
)

private fun List<AnalyticsItem>.labels() = map { listOfNotNull(it.productId, it.variantId).joinToString("/") + " x${it.quantity}" }

/** The signed-in customer ([id]: their numeric id). */
data class AnalyticsUser(
    val id: String,
    val email: String? = null,
    val phone: String? = null,
    val firstName: String? = null,
    val lastName: String? = null,
)

/**
 * One destination of the events: a provider's SDK, or the debug log. A sink takes what it has a use for and leaves the
 * rest at these defaults. Its calls come from any thread, the main one too, and must not block.
 */
interface AnalyticsSink {
    fun track(event: AnalyticsEvent) {}

    /** The signed-in customer; null after a sign-out. */
    fun identify(user: AnalyticsUser?) {}

    /** What a new cart carries for the store's server to tie the order to this app install (the provider's own ids). */
    suspend fun cartAttributes(): Map<String, String> = emptyMap()
}

/**
 * The hub: screens and stores report here (`AppGraph.analytics`), and every sink gets what they report while the shopper
 * allows it ([allowed], see [AnalyticsConsentStore]). It never throws into its caller: a sink that fails is logged and
 * skipped.
 */
class Analytics(private val sinks: List<AnalyticsSink>, private val allowed: () -> Boolean) {
    // java.util.logging, as in the stores: it reaches logcat and also runs in JVM tests
    private val log = Logger.getLogger("Analytics")

    fun track(event: AnalyticsEvent) = each { it.track(event) }

    /** The signed-in customer; null after a sign-out. */
    fun identify(user: AnalyticsUser?) = each { it.identify(user) }

    /**
     * The attributes of a new cart: the sinks' together, and `_argon_platform`, by which the store's server knows an
     * order of the app's (they become the order's note attributes). Empty without a sink, and when not allowed.
     */
    suspend fun cartAttributes(): Map<String, String> {
        if (sinks.isEmpty() || !allowed()) return emptyMap()
        return buildMap {
            for (sink in sinks) {
                try {
                    putAll(sink.cartAttributes())
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    skipped(sink, e)
                }
            }
            put("_argon_platform", "android")
        }
    }

    private inline fun each(action: (AnalyticsSink) -> Unit) {
        if (!allowed()) return
        for (sink in sinks) {
            try {
                action(sink)
            } catch (e: Exception) {
                skipped(sink, e)
            }
        }
    }

    private fun skipped(sink: AnalyticsSink, e: Exception) = log.log(Level.WARNING, "${sink.javaClass.simpleName} failed and was skipped", e)
}

/**
 * Debug builds only: one line per event in logcat, `Analytics: add_to_cart {…}` (the logger's name is the tag), so the
 * events can be checked without any provider account. Of the customer it logs the id alone.
 */
class LogSink : AnalyticsSink {
    private val log = Logger.getLogger("Analytics")

    override fun track(event: AnalyticsEvent) = log.info("${event.name} ${event.params}")

    override fun identify(user: AnalyticsUser?) = log.info("identify ${user?.id}")
}

// The mappers: the app's own models, and Checkout Kit's, as items and events.

/** "gid://shopify/Product/123" is "123". */
fun gidTail(gid: String): String = gid.substringBefore('?').substringAfterLast('/')

private fun Money.toDouble(): Double? = amount.toDoubleOrNull()

/** [title] unless it is the "Default Title" of a product without options. */
private fun variantName(title: String?): String? = title?.takeIf { it != "Default Title" }

/** A cart line as an item; [quantity] is how many of it the event is about (a change of two is 2). */
fun CartLine.analyticsItem(quantity: Int = this.quantity) = AnalyticsItem(
    productId = gidTail(productId),
    variantId = gidTail(merchandise.id),
    name = productTitle,
    variant = variantName(variantTitle),
    price = unitPrice.toDouble(),
    quantity = quantity,
)

/** A product in a list as an item, by the variant the list shows it by. */
fun ProductCard.analyticsItem() = AnalyticsItem(
    productId = gidTail(id),
    variantId = firstVariant?.let { gidTail(it.id) },
    name = title,
    brand = vendor.ifBlank { null },
    price = price.toDouble(),
)

// the variant a product's page opens on (ProductScreen's initialSelection)
private fun Product.openingVariant(): Variant? = variants.firstOrNull { it.available } ?: variants.firstOrNull()

private fun Product.openingPrice(): Money? = openingVariant()?.price ?: priceRange?.minVariantPrice

/** A product as an item, by the variant its page opens on: the first available one, else the first. */
fun Product.analyticsItem(): AnalyticsItem {
    val variant = openingVariant()
    return AnalyticsItem(
        productId = gidTail(id),
        variantId = variant?.let { gidTail(it.id) },
        name = title,
        brand = vendor.ifBlank { null },
        category = productType.ifBlank { null },
        variant = variantName(variant?.title),
        price = openingPrice()?.toDouble(),
    )
}

/** The currency of [analyticsItem]'s price; empty for a product without one. */
val Product.analyticsCurrency: String get() = openingPrice()?.currencyCode.orEmpty()

fun Customer.analyticsUser() = AnalyticsUser(gidTail(id), email, phoneNumber?.phoneNumber, firstName, lastName)

/**
 * What a change of a cart's lines put in and took out, as events: each line's quantity [after] against the one [before].
 * A line with more is an `add_to_cart` of the difference, one with less (or gone) a `remove_from_cart` of it.
 */
fun cartLineEvents(before: List<CartLine>, after: List<CartLine>): List<AnalyticsEvent> {
    val was = before.associateBy { it.id }
    val now = after.associateBy { it.id }
    return (after + before.filter { it.id !in now }).mapNotNull { line ->
        val change = (now[line.id]?.quantity ?: 0) - (was[line.id]?.quantity ?: 0)
        val currency = line.unitPrice.currencyCode
        when {
            change > 0 -> AnalyticsEvent.AddToCart(line.analyticsItem(change), currency)
            change < 0 -> AnalyticsEvent.RemoveFromCart(line.analyticsItem(-change), currency)
            else -> null
        }
    }
}

/** The cart as the cart screen shows it: its lines, worth its total (after discounts). */
fun viewCart(cart: Cart) = AnalyticsEvent.ViewCart(cart.lines.map { it.analyticsItem() }, cart.total.toDouble() ?: 0.0, cart.total.currencyCode)

/** The cart going to checkout; [AnalyticsEvent.BeginCheckout.coupon] is its discount codes that count ("A,B"). */
fun beginCheckout(cart: Cart) = AnalyticsEvent.BeginCheckout(
    cart.lines.map { it.analyticsItem() },
    cart.total.toDouble() ?: 0.0,
    cart.total.currencyCode,
    coupon = cart.discountCodes.filter { it.applicable }.joinToString(",") { it.code }.ifEmpty { null },
)

/**
 * The order Checkout Kit says was placed (`CheckoutCompletedEvent.orderDetails`) as the purchase. Its coupon is the
 * titles of the order's discounts: a code's is the code.
 */
fun purchase(order: OrderDetails): AnalyticsEvent.Purchase {
    val price = order.cart.price
    return AnalyticsEvent.Purchase(
        orderId = gidTail(order.id),
        value = price.total?.amount ?: 0.0,
        currency = price.total?.currencyCode.orEmpty(),
        tax = price.taxes?.amount,
        shipping = price.shipping?.amount,
        coupon = price.discounts.orEmpty().mapNotNull { it.title }.joinToString(",").ifEmpty { null },
        items = order.cart.lines.map { line ->
            AnalyticsItem(
                productId = gidTail(line.productId.orEmpty()),
                variantId = line.merchandiseId?.let(::gidTail),
                name = line.title,
                price = line.price.amount,
                quantity = line.quantity,
            )
        },
    )
}

/**
 * The checkout step a Checkout Kit web pixel event stands for: shipping or payment details submitted, worth the
 * checkout's total. Null for every other standard event (the app reports those itself, where it has the whole cart), for
 * a store's custom events, and for an event without a total.
 */
fun checkoutStep(event: PixelEvent): AnalyticsEvent? {
    val checkout = (event as? StandardPixelEvent)?.data?.checkout ?: return null
    val value = checkout.totalPrice?.amount ?: return null
    val currency = checkout.currencyCode ?: checkout.totalPrice?.currencyCode ?: return null
    return when (event.name) {
        "checkout_shipping_info_submitted" -> AnalyticsEvent.AddShippingInfo(value, currency)
        "payment_info_submitted" -> AnalyticsEvent.AddPaymentInfo(value, currency)
        else -> null
    }
}
