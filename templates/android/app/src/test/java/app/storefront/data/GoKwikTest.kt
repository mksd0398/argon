package app.storefront.data

import java.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GoKwikTest {
    private val sandbox = GoKwikConfig.of("gokwik", "kwikpass", "mid-1", "sandbox")
    private val cartId = "gid://shopify/Cart/hWN20nvTkiET80LEjquVKpxU?key=7a1e23034ec76ce3d121035b4510b818"

    private fun decode(value: String) = String(Base64.getDecoder().decode(value))

    /** The URL's query, its values as they are (base64, not URL-encoded). */
    private fun query(url: String) = url.substringAfter('?').split('&').associate { it.substringBefore('=') to it.substringAfter('=') }

    @Test
    fun configIsOffByDefaultAndNeedsAMerchantId() {
        val default = GoKwikConfig.of("shopify", "shopify", "", "")
        assertFalse(default.checkout)
        assertFalse(default.kwikPass)
        assertFalse(default.sandbox)
        assertEquals("production", default.environment)
        assertEquals("https://gkx.gokwik.co/", default.apiBase)

        assertTrue(sandbox.checkout)
        assertTrue(sandbox.kwikPass)
        assertEquals("sandbox", sandbox.environment)
        assertEquals("https://api-gw-v4.dev.gokwik.io/sandbox/", sandbox.apiBase)

        // either alone, case and spaces aside
        val checkoutOnly = GoKwikConfig.of(" GoKwik ", "shopify", " mid ", "production")
        assertTrue(checkoutOnly.checkout)
        assertFalse(checkoutOnly.kwikPass)
        assertEquals("mid", checkoutOnly.merchantId)
        assertEquals("https://pdp.gokwik.co/app/kwik-checkout.html", checkoutOnly.checkoutBase)
        assertTrue(GoKwikConfig.of("shopify", "KWIKPASS", "mid", "").kwikPass)

        // no merchant id: neither runs
        val noMid = GoKwikConfig.of("gokwik", "kwikpass", " ", "sandbox")
        assertFalse(noMid.checkout)
        assertFalse(noMid.kwikPass)
    }

    @Test
    fun checkoutUrlCarriesTheCartForAGuest() {
        val url = goKwikCheckoutUrl(sandbox, cartId, "sf-token", "shop.myshopify.com", upiApps = listOf("googlepay", "phonepe"))
        assertTrue(url.startsWith("https://sandbox.pdp.gokwik.co/app/kwik-checkout.html?storeInfo="))
        val params = query(url)
        assertEquals(setOf("storeInfo", "upi_apps"), params.keys)

        val info = Json.parseToJsonElement(decode(params.getValue("storeInfo"))).jsonObject
        fun text(o: JsonObject, key: String) = o.getValue(key).jsonPrimitive.content
        assertEquals("merchantInfo", text(info, "type"))
        assertEquals("app", text(info, "source"))
        assertEquals("android", text(info, "platform"))
        assertEquals("true", text(info, "appFlow"))
        assertEquals("mobile_app_android", text(info, "tag"))
        assertEquals("true", text(info, "blockExternalEvents"))
        assertEquals("mid-1", text(info, "mid"))
        assertEquals("sandbox", text(info, "environment"))
        val store = info.getValue("storeData").jsonObject
        assertEquals("the gid prefix goes, the key stays", "hWN20nvTkiET80LEjquVKpxU?key=7a1e23034ec76ce3d121035b4510b818", text(store, "cartId"))
        assertEquals("sf-token", text(store, "storefrontAccessToken"))
        assertEquals("shop.myshopify.com", text(store, "shopDomain"))

        val upi = Json.parseToJsonElement(decode(params.getValue("upi_apps"))).jsonArray.map { it.jsonPrimitive.content }
        assertEquals(listOf("googlepay", "phonepe"), upi)
        // it is still a URL the web view can load
        assertEquals("sandbox.pdp.gokwik.co", url.toHttpUrl().host)
    }

    @Test
    fun checkoutUrlSignsInAKwikPassShopper() {
        val production = GoKwikConfig.of("gokwik", "kwikpass", "mid-1", "production")
        val url = goKwikCheckoutUrl(production, cartId, "sf", "shop.test", coreToken = "core-1", email = "a@b.in")
        assertTrue(url.startsWith("https://pdp.gokwik.co/app/kwik-checkout.html?storeInfo="))
        val params = query(url)
        assertEquals(setOf("storeInfo", "gk_token", "kp_email"), params.keys)
        assertEquals("core-1", Json.parseToJsonElement(decode(params.getValue("gk_token"))).jsonObject.getValue("coreToken").jsonPrimitive.content)
        assertEquals("a@b.in", decode(params.getValue("kp_email")))

        // signed out: neither, the email alone included
        val guest = query(goKwikCheckoutUrl(production, cartId, "sf", "shop.test", coreToken = null, email = "a@b.in"))
        assertEquals(setOf("storeInfo"), guest.keys)
    }

    @Test
    fun onlyGoKwikPagesAreHeard() {
        assertTrue(isGoKwikHost("pdp.gokwik.co"))
        assertTrue(isGoKwikHost("sandbox.pdp.gokwik.co"))
        assertTrue(isGoKwikHost("GOKWIK.CO"))
        assertFalse(isGoKwikHost("evilgokwik.co"))
        assertFalse(isGoKwikHost("gokwik.co.evil.com"))
        assertFalse(isGoKwikHost("razorpay.com"))
        assertFalse(isGoKwikHost(null))
    }

    @Test
    fun messagesAreReadLeniently() {
        val order = GoKwikMessage.parse("""{"type":"orderSuccess","data":{"order_id":"123"}}""")!!
        assertEquals("orderSuccess", order.type)
        assertEquals("123", order.data!!.jsonObject.getValue("order_id").jsonPrimitive.content)
        assertEquals("checkout-close", GoKwikMessage.parse("""{"eventname":"checkout-close"}""")?.type)
        assertNull(GoKwikMessage.parse("not json"))
        assertNull(GoKwikMessage.parse("""{"data":1}"""))

        assertEquals("https://a.test", goKwikLink(Json.parseToJsonElement("""{"url":"https://a.test"}""")))
        assertEquals("https://b.test", goKwikLink(Json.parseToJsonElement("\"https://b.test\"")))
        assertNull(goKwikLink(null))
    }

    @Test
    fun aPurchaseIsReportedOnlyWhenTheOrderSaysEnough() {
        val items = listOf(AnalyticsItem(productId = "1", name = "Tee"))
        val full = goKwikPurchase(Json.parseToJsonElement("""{"data":{"order_id":"gid://shopify/Order/55","total_price":"499.00","currency":"INR"}}"""), items)!!
        assertEquals("55", full.orderId)
        assertEquals(499.0, full.value, 0.0)
        assertEquals("INR", full.currency)
        assertEquals(items, full.items)

        assertNull("no currency", goKwikPurchase(Json.parseToJsonElement("""{"orderId":"1","total":"10"}"""), items))
        assertNull("not an object", goKwikPurchase(Json.parseToJsonElement("\"done\""), items))
        assertNull(goKwikPurchase(null, items))
    }

    @Test
    fun theUpiEventIsAJsonStringInTheScript() {
        val script = upiIntentScript("launching", "1-2")
        assertTrue(script.startsWith("document.dispatchEvent(new MessageEvent('message', { data: \""))
        val literal = script.substringAfter("data: ").substringBeforeLast(" }));")
        val inner = Json.parseToJsonElement(Json.parseToJsonElement(literal).jsonPrimitive.content).jsonObject
        assertEquals("upiIntent", inner.getValue("action").jsonPrimitive.content)
        assertEquals("launching", inner.getValue("state").jsonPrimitive.content)
        assertEquals("1-2", inner.getValue("nonce").jsonPrimitive.content)
    }
}
