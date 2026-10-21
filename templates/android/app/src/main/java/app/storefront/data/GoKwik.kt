package app.storefront.data

import java.util.Base64
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

// GoKwik: its hosted checkout (CHECKOUT=gokwik) in place of Checkout Kit, and its KwikPass phone sign-in (LOGIN=kwikpass,
// app.storefront.auth.KwikPassStore) in place of the Customer Account one. Either, both or neither; the values here are
// GoKwik's Flutter SDK 1.0.37's, which the app's own code speaks in its place.

/**
 * What the app was built with: [checkout] opens GoKwik's checkout, [kwikPass] signs in with KwikPass, both under the one
 * GoKwik merchant id [merchantId] in [sandbox] or production. Neither without a merchant id: the app then runs as Shopify's.
 */
data class GoKwikConfig(val checkout: Boolean, val kwikPass: Boolean, val merchantId: String, val sandbox: Boolean) {
    companion object {
        /** From `CHECKOUT`, `LOGIN`, `GOKWIK_MERCHANT_ID` and `GOKWIK_ENVIRONMENT` (`sandbox`, else production). */
        fun of(checkout: String, login: String, merchantId: String, environment: String): GoKwikConfig {
            val mid = merchantId.trim()
            return GoKwikConfig(
                checkout = mid.isNotEmpty() && checkout.trim().equals("gokwik", ignoreCase = true),
                kwikPass = mid.isNotEmpty() && login.trim().equals("kwikpass", ignoreCase = true),
                merchantId = mid,
                sandbox = environment.trim().equals("sandbox", ignoreCase = true),
            )
        }
    }

    /** The name GoKwik knows the environment by. */
    val environment: String get() = if (sandbox) "sandbox" else "production"

    /** KwikPass's REST API. */
    val apiBase: String get() = if (sandbox) "https://api-gw-v4.dev.gokwik.io/sandbox/" else "https://gkx.gokwik.co/"

    /** The checkout page, before its `storeInfo`. */
    val checkoutBase: String get() = if (sandbox) "https://sandbox.pdp.gokwik.co/app/kwik-checkout.html" else "https://pdp.gokwik.co/app/kwik-checkout.html"
}

/** The UPI apps checkout can pay with, by the name it knows them by, and their Android packages (the manifest's `<queries>`). */
val UPI_APPS = linkedMapOf(
    "googlepay" to "com.google.android.apps.nbu.paisa.user",
    "phonepe" to "com.phonepe.app",
    "bhim" to "in.org.npci.upiapp",
    "paytm" to "net.one97.paytm",
    "cred" to "com.dreamplug.androidapp",
    "slice" to "indwin.c3.shareapp",
)

private fun b64(text: String): String = Base64.getEncoder().encodeToString(text.toByteArray())

/** The Storefront cart id as checkout takes it: without `gid://shopify/Cart/`, with its `?key=`. */
fun goKwikCartId(cartId: String): String = cartId.removePrefix("gid://shopify/Cart/")

/**
 * GoKwik's checkout for the Storefront cart [cartId]: it reads the cart itself, with the app's [storefrontToken], from
 * [shopDomain]. A KwikPass shopper ([coreToken], [email]) arrives signed in. [upiApps]: the UPI apps on the device. Every
 * value is base64 JSON, left as it is in the URL (as the SDK sends it).
 */
fun goKwikCheckoutUrl(
    config: GoKwikConfig,
    cartId: String,
    storefrontToken: String,
    shopDomain: String,
    coreToken: String? = null,
    email: String? = null,
    upiApps: List<String> = emptyList(),
): String {
    val storeInfo = buildJsonObject {
        put("type", "merchantInfo")
        put("source", "app")
        put("platform", "android")
        put("appFlow", "true")
        put("tag", "mobile_app_android") // becomes an order tag
        put("blockExternalEvents", true)
        put("mid", config.merchantId)
        put("environment", config.environment)
        for (key in listOf("storeId", "fbpixel", "gaTrackingID", "webEngageID", "moEngageID", "sessionId")) put(key, "")
        putJsonObject("utmParams") {}
        put("discountCodes", "")
        putJsonObject("storeData") {
            put("cartId", goKwikCartId(cartId))
            put("storefrontAccessToken", storefrontToken)
            put("shopDomain", shopDomain)
        }
    }
    return buildString {
        append(config.checkoutBase).append("?storeInfo=").append(b64(storeInfo.toString()))
        if (!coreToken.isNullOrEmpty()) {
            append("&gk_token=").append(b64(buildJsonObject { put("coreToken", coreToken) }.toString()))
            if (!email.isNullOrEmpty()) append("&kp_email=").append(b64(email))
        }
        if (upiApps.isNotEmpty()) append("&upi_apps=").append(b64(JsonArray(upiApps.map(::JsonPrimitive)).toString()))
    }
}

/** Whether a page on [host] may talk to the app: GoKwik's own (`gokwik.co` and under it). */
fun isGoKwikHost(host: String?): Boolean = host != null && host.lowercase().let { it == "gokwik.co" || it.endsWith(".gokwik.co") }

/** A message from the checkout page (`Flutter.postMessage`): `{"type": ..., "data": ...}`; null when it isn't one. */
data class GoKwikMessage(val type: String, val data: JsonElement?) {
    companion object {
        fun parse(message: String): GoKwikMessage? {
            val json = runCatching { ArgonJson.parseToJsonElement(message) }.getOrNull() as? JsonObject ?: return null
            val type = ((json["type"] ?: json["eventname"]) as? JsonPrimitive)?.contentOrNull ?: return null
            return GoKwikMessage(type, json["data"])
        }
    }
}

/** The link `openInBrowserTab` asks for: its `url`, or the data itself when it is the link. */
fun goKwikLink(data: JsonElement?): String? =
    ((data as? JsonObject)?.get("url") as? JsonPrimitive ?: data as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }

/**
 * The purchase in checkout's `orderSuccess` [data], for the [items] the cart held: when it names the order, its total and
 * its currency (at its top level, or in its `data` or `order`). Else null: the shape isn't GoKwik's documented, so a
 * purchase is only reported when it can be told right.
 */
fun goKwikPurchase(data: JsonElement?, items: List<AnalyticsItem>): AnalyticsEvent.Purchase? {
    val root = data as? JsonObject ?: return null
    val objects = listOfNotNull(root, root["data"] as? JsonObject, root["order"] as? JsonObject)
    fun find(vararg keys: String): String? = objects.firstNotNullOfOrNull { o ->
        keys.firstNotNullOfOrNull { (o[it] as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank) }
    }
    val orderId = find("order_id", "orderId", "shopify_order_id", "id") ?: return null
    val value = find("total_price", "totalPrice", "total", "amount")?.toDoubleOrNull() ?: return null
    val currency = find("currency", "currencyCode", "currency_code") ?: return null
    return AnalyticsEvent.Purchase(orderId = gidTail(orderId), value = value, currency = currency, items = items)
}

/** The UPI app event checkout waits for around a launch: `launching`, then `launched` or `failed`. */
fun upiIntentScript(state: String, nonce: String): String {
    val message = buildJsonObject { put("action", "upiIntent"); put("state", state); put("newArch", true); put("nonce", nonce) }.toString()
    return "document.dispatchEvent(new MessageEvent('message', { data: ${JsonPrimitive(message)} }));"
}

/** Back with nowhere to go back to in the page: checkout decides (it may ask, then close). */
const val GOKWIK_BACK_SCRIPT = "document.dispatchEvent(new MessageEvent('message',{data: JSON.stringify({action:'hardwareBackPress'})}));"

/** Hands checkout's events to the app (`Flutter.postMessage`), once its page is up; the SDK's own script. */
const val GOKWIK_LISTENER_SCRIPT = """
(function checkGoKwikSdk() {
  if (typeof gokwikSdk !== 'undefined' && typeof gokwikSdk.on === 'function') {
    gokwikSdk.on('modal_closed', d => Flutter.postMessage(JSON.stringify({ type: 'modal_closed', data: d })));
    gokwikSdk.on('orderSuccess', d => Flutter.postMessage(JSON.stringify({ type: 'orderSuccess', data: d })));
    gokwikSdk.on('openInBrowserTab', d => Flutter.postMessage(JSON.stringify({ type: 'openInBrowserTab', data: d })));
  } else { setTimeout(checkGoKwikSdk, 500); }
})();
document.addEventListener("gk-checkout-disable", e => Flutter.postMessage(JSON.stringify({ type: 'gk-checkout-disable', data: e })));
window.addEventListener('message', e => { if (e.data && e.data.type === "gokwik_events") Flutter.postMessage(JSON.stringify({ type: 'gokwik_events', data: e?.data?.data })); });
window.addEventListener("gokwikLoaded", e => Flutter.postMessage(JSON.stringify({ type: 'gokwikLoaded', data: e })));
"""
