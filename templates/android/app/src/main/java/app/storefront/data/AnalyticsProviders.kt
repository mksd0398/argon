package app.storefront.data

import android.os.Bundle
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.put

// What each provider is sent for an event: the hub's events under the provider's own names. Pure and always compiled, so
// they are tested without any SDK; a provider's sink (src/firebase, src/meta, src/moengage: compiled in only when the
// store set the provider up, see app/build.gradle.kts) only hands the result to its SDK.

// amounts are decimal: 19.99 x 3 is 59.97, not the 59.969999999999995 of doubles
private fun AnalyticsItem.total(): Double? = price?.let { (it.toBigDecimal() * quantity.toBigDecimal()).toDouble() }

// Google Analytics 4 (Firebase)

private fun AnalyticsItem.ga4() = values(
    "item_id" to productId, "item_name" to name, "item_brand" to brand, "item_category" to category, "item_variant" to variant,
    "price" to price, "quantity" to quantity,
)

private fun ga4(item: AnalyticsItem, currency: String) = values("currency" to currency, "value" to item.total(), "items" to listOf(item.ga4()))

/**
 * [event]'s parameters for Google Analytics 4, where its name is [AnalyticsEvent.name]: the flat ones, with `items` as one
 * map per item. A purchase is worth the order's total without tax and shipping, which are parameters of their own (the
 * store's server reports the same number). Null: not sent, which is the purchase when the server reports it
 * ([serverPurchase], see FirebaseSink).
 */
fun ga4Params(event: AnalyticsEvent, serverPurchase: Boolean = false): Map<String, Any>? = when (event) {
    is AnalyticsEvent.ViewItem -> ga4(event.item, event.currency)
    is AnalyticsEvent.AddToWishlist -> ga4(event.item, event.currency)
    is AnalyticsEvent.AddToCart -> ga4(event.item, event.currency)
    is AnalyticsEvent.RemoveFromCart -> ga4(event.item, event.currency)
    is AnalyticsEvent.ViewItemList -> event.params + ("items" to event.items.map { it.ga4() })
    is AnalyticsEvent.ViewCart -> event.params + ("items" to event.items.map { it.ga4() })
    is AnalyticsEvent.BeginCheckout -> event.params + ("items" to event.items.map { it.ga4() })
    is AnalyticsEvent.Purchase -> if (serverPurchase) null else {
        val net = event.value.toBigDecimal() - (event.tax ?: 0.0).toBigDecimal() - (event.shipping ?: 0.0).toBigDecimal()
        event.params + mapOf("value" to net.toDouble(), "items" to event.items.map { it.ga4() })
    }
    else -> event.params // a screen, a search, the two checkout steps, a sign-in: flat already
}

// Meta (the Facebook SDK's App Events)

/** An App Event as the Facebook SDK logs it: a standard event's [name], the [value] it sums (none: null) and its [params]. */
data class MetaEvent(val name: String, val value: Double?, val params: Map<String, Any>)

// The id Meta's catalog knows a product by. A catalog synced from Shopify lists variants, so it is the variant's.
private fun AnalyticsItem.metaId() = variantId ?: productId

/** [items] under Meta's parameter names: `fb_content_id` is the one id, or a JSON list of them; `fb_content` adds the quantities. */
private fun metaContents(items: List<AnalyticsItem>, currency: String): Map<String, Any> = mapOf(
    "fb_content_id" to (items.singleOrNull()?.metaId() ?: JsonArray(items.map { JsonPrimitive(it.metaId()) }).toString()),
    "fb_content" to buildJsonArray {
        for (item in items) addJsonObject {
            put("id", item.metaId())
            put("quantity", item.quantity)
        }
    }.toString(),
    "fb_content_type" to "product",
    "fb_currency" to currency,
    "fb_num_items" to items.sumOf { it.quantity },
)

private fun meta(name: String, item: AnalyticsItem, currency: String) = MetaEvent(name, item.total(), metaContents(listOf(item), currency))

/**
 * [event] as Meta's standard App Event; null for those Meta has no standard event for (a list, a removal, the cart,
 * shipping details, a screen, a sign-in): they are not sent. The purchase is worth the order's total, and its `event_id`
 * is the one the store's server sends the same purchase under, by which Meta counts the two once.
 */
fun metaEvent(event: AnalyticsEvent): MetaEvent? = when (event) {
    is AnalyticsEvent.ViewItem -> meta("fb_mobile_content_view", event.item, event.currency)
    is AnalyticsEvent.Search -> MetaEvent("fb_mobile_search", null, mapOf("fb_search_string" to event.term))
    is AnalyticsEvent.AddToWishlist -> meta("fb_mobile_add_to_wishlist", event.item, event.currency)
    is AnalyticsEvent.AddToCart -> meta("fb_mobile_add_to_cart", event.item, event.currency)
    is AnalyticsEvent.BeginCheckout -> MetaEvent("fb_mobile_initiated_checkout", event.value, metaContents(event.items, event.currency))
    is AnalyticsEvent.AddPaymentInfo -> MetaEvent("fb_mobile_add_payment_info", null, mapOf("fb_success" to 1))
    is AnalyticsEvent.Purchase ->
        MetaEvent("fb_mobile_purchase", event.value, metaContents(event.items, event.currency) + ("event_id" to "purchase-${event.orderId}"))
    // no standard event for a promotion: a custom one, under GA4's name and parameters
    is AnalyticsEvent.ViewPromotion, is AnalyticsEvent.SelectPromotion -> MetaEvent(event.name, null, event.params)
    else -> null
}

/**
 * Meta's `extinfo`: what its Conversions API wants to know of the device behind an app's event, as the JSON list (16
 * texts in this order, "a2" first: the Android layout) that a cart carries to the store's server. Sizes are in pixels,
 * storage in GB.
 */
fun metaExtinfo(
    packageName: String,
    versionCode: Int,
    versionName: String,
    osVersion: String,
    model: String,
    locale: String,
    timezoneAbbreviation: String,
    carrier: String,
    screenWidth: Int,
    screenHeight: Int,
    screenDensity: Float,
    cores: Int,
    storageGb: Long,
    freeStorageGb: Long,
    timezone: String,
): String = JsonArray(
    listOf(
        "a2", packageName, versionCode, versionName, osVersion, model, locale, timezoneAbbreviation, carrier, screenWidth, screenHeight,
        screenDensity, cores, storageGb, freeStorageGb, timezone,
    ).map { JsonPrimitive(it.toString()) },
).toString()

// MoEngage

// One product's attributes, and a list's: the names MoEngage's Shopify integration tracks the same things under.
private fun moEngage(item: AnalyticsItem, currency: String) = values(
    "Product ID" to item.productId, "Product Title" to item.name, "Variation ID" to item.variantId, "Variation Title" to item.variant,
    "Vendor Name" to item.brand, "Price" to item.price, "Currency" to currency, "Quantity" to item.quantity,
)

// a list an item has nothing for is shorter than the others; one no item has anything for is left out
private fun moEngage(items: List<AnalyticsItem>) = mapOf(
    "Product IDs" to items.map { it.productId }, "Product Titles" to items.map { it.name },
    "Variation IDs" to items.mapNotNull { it.variantId }, "Product Prices" to items.mapNotNull { it.price },
    "Product Quantities" to items.map { it.quantity }, "Vendor Names" to items.mapNotNull { it.brand },
).filterValues { it.isNotEmpty() }

/**
 * [event] as MoEngage's event: its name and attributes. The names are those MoEngage's Shopify integration (its Web SDK)
 * tracks the same action under, so a store's web and app events are one; where it has none, the same style. Never its
 * "Shopify - ..." names: those come from the store's webhooks, for the app's orders too.
 */
fun moEngageEvent(event: AnalyticsEvent): Pair<String, Map<String, Any>> = when (event) {
    is AnalyticsEvent.ScreenView -> "Screen Viewed" to mapOf("Screen Name" to event.screen)
    is AnalyticsEvent.ViewItemList -> "Product List Viewed" to values("List ID" to event.listId, "List Name" to event.listName) + moEngage(event.items)
    is AnalyticsEvent.ViewItem -> "Product Viewed" to moEngage(event.item, event.currency)
    is AnalyticsEvent.Search -> "Product Searched" to mapOf("Search String" to event.term)
    is AnalyticsEvent.AddToWishlist -> "Wishlist Added" to moEngage(event.item, event.currency)
    is AnalyticsEvent.AddToCart -> "Add to Cart" to moEngage(event.item, event.currency)
    is AnalyticsEvent.RemoveFromCart -> "Removed From Cart" to moEngage(event.item, event.currency)
    is AnalyticsEvent.ViewCart -> "Cart Viewed" to mapOf("Total Price" to event.value, "Currency" to event.currency) + moEngage(event.items)
    // "currency": the integration's own spelling on this one event
    is AnalyticsEvent.BeginCheckout ->
        "Checkout Started" to values("Total Price" to event.value, "currency" to event.currency, "Coupon" to event.coupon) + moEngage(event.items)
    is AnalyticsEvent.AddShippingInfo -> "Shipping Info Added" to mapOf("Total Price" to event.value, "Currency" to event.currency)
    is AnalyticsEvent.AddPaymentInfo -> "Payment Info Added" to mapOf("Total Price" to event.value, "Currency" to event.currency)
    is AnalyticsEvent.Purchase -> "Order Placed" to values(
        "Order ID" to event.orderId, "Total Price" to event.value, "Currency" to event.currency, "Tax" to event.tax, "Shipping" to event.shipping,
        "Coupon" to event.coupon,
    ) + moEngage(event.items)
    AnalyticsEvent.Login -> "Customer Logged In" to emptyMap()
    // promotions: no name of the integration's own, so GA4's, with its parameters
    is AnalyticsEvent.ViewPromotion, is AnalyticsEvent.SelectPromotion -> event.name to event.params
}

/**
 * A mapped event's parameters as the Bundle Firebase's and Facebook's SDKs take: texts, whole numbers (as longs), amounts,
 * and a list of maps (Google Analytics' `items`) as an array of Bundles.
 */
internal fun Map<String, Any>.toBundle(): Bundle = Bundle().also { bundle ->
    for ((key, value) in this) when (value) {
        is String -> bundle.putString(key, value)
        is Int -> bundle.putLong(key, value.toLong())
        is Double -> bundle.putDouble(key, value)
        is List<*> -> bundle.putParcelableArray(key, value.filterIsInstance<Map<String, Any>>().map { it.toBundle() }.toTypedArray())
    }
}
