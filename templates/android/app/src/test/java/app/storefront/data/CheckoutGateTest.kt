package app.storefront.data

import java.io.IOException
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CheckoutGateTest {
    private val checkout = "https://shop.test/cart/c/abc?key=k"
    private val requests = mutableListOf<Request>()

    /** A client whose every call answers [code] with a Location of [location] (or fails with [offline]). */
    private fun answering(code: Int, location: String? = null, offline: Boolean = false) = OkHttpClient.Builder().addInterceptor { chain ->
        requests += chain.request()
        if (offline) throw IOException("offline")
        Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(code).message("test")
            .apply { location?.let { header("Location", it) } }
            .body("".toResponseBody()).build()
    }.build()

    @Test
    fun aStorefrontSentToThePasswordPageIsProtected() = runBlocking {
        assertTrue(passwordProtected(checkout, answering(302, "https://shop.test/password")))
        assertEquals("the storefront's home page is asked", "https://shop.test/", requests.single().url.toString())
    }

    @Test
    fun aStorefrontWithoutAPasswordIsNot() = runBlocking {
        assertFalse(passwordProtected(checkout, answering(301, "https://www.shop.test/")))
        assertFalse(passwordProtected(checkout, answering(200)))
    }

    private val hosts = setOf("shop.myshopify.com", "www.shop.com")

    @Test
    fun theStoresOwnPagesAreStorePages() {
        for (page in listOf(
            "https://shop.myshopify.com/", "https://www.shop.com", "https://www.shop.com/products/pants?variant=1",
            "https://shop.myshopify.com/cart", "https://shop.myshopify.com/password", "https://WWW.SHOP.COM/collections/all",
        )) assertTrue(page, isStorePage(page, hosts))
    }

    @Test
    fun checkoutAndOtherDomainsAreNot() {
        for (page in listOf(
            "https://shop.myshopify.com/checkouts/cn/abc/en-us", "https://shop.myshopify.com/checkouts/cn/abc/thank-you",
            "https://shop.myshopify.com/cart/c/abc?key=k", "https://shop.myshopify.com/123456/checkouts/cn/abc",
            "https://www.shop.com/policies/refund-policy", "https://www.paypal.com/checkoutnow", "https://shop.app/pay",
            "https://help.shopify.com/en/manual", "mailto:help@shop.com", "not a url",
        )) assertFalse(page, isStorePage(page, hosts))
    }

    @Test
    fun aNetworkFailureNeverStopsCheckout() = runBlocking {
        assertFalse(passwordProtected(checkout, answering(0, offline = true)))
    }
}
