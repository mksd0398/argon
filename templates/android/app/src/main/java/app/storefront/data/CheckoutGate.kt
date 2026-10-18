package app.storefront.data

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request

/** Why checkout can't open in the app, as the shopper reads it. */
const val PASSWORD_PROTECTED_CHECKOUT = "This store is password protected, so checkout can't open in the app yet."

/**
 * Whether the storefront that [checkoutUrl] belongs to has a password. Behind one, checkout shows the password page and,
 * once the password is entered, the storefront: a Checkout Kit sheet would show the shop's web pages, not checkout.
 * The storefront's home page is asked, without following its redirect (checkout itself refuses requests that aren't a
 * browser's); any failure is false, so a network problem never stops checkout (Checkout Kit reports its own).
 */
suspend fun passwordProtected(checkoutUrl: String, http: OkHttpClient): Boolean = withContext(Dispatchers.IO) {
    runCatching {
        val home = checkoutUrl.toHttpUrl().newBuilder().encodedPath("/").query(null).build()
        val client = http.newBuilder().followRedirects(false).followSslRedirects(false).callTimeout(5, TimeUnit.SECONDS).build()
        client.newCall(Request.Builder().url(home).get().build()).execute().use { response ->
            response.isRedirect && response.header("Location").orEmpty().contains("/password")
        }
    }.getOrDefault(false)
}
