package app.storefront.ui

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.activity.ComponentActivity
import androidx.activity.ComponentDialog
import androidx.activity.addCallback
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import app.storefront.AppGraph
import app.storefront.data.Cart
import app.storefront.data.GOKWIK_BACK_SCRIPT
import app.storefront.data.GOKWIK_LISTENER_SCRIPT
import app.storefront.data.GoKwikMessage
import app.storefront.data.UPI_APPS
import app.storefront.data.analyticsItem
import app.storefront.data.goKwikCheckoutUrl
import app.storefront.data.goKwikLink
import app.storefront.data.goKwikPurchase
import app.storefront.data.isGoKwikHost
import app.storefront.data.upiIntentScript
import kotlin.random.Random
import kotlinx.coroutines.launch

/**
 * GoKwik's checkout (CHECKOUT=gokwik) for [cart], full screen over [host], where Checkout Kit's sheet would open; on the
 * main thread. [checkoutUrl] is Shopify's checkout for the same cart, which GoKwik may hand back to (`gk-checkout-disable`).
 * A placed order spends the cart and is reported as Checkout Kit's is; [onError] is for Shopify's checkout if it takes over.
 */
internal fun presentGoKwikCheckout(cart: Cart, checkoutUrl: String, host: ComponentActivity, onError: (String) -> Unit) {
    val kwikPass = AppGraph.kwikPass
    val url = goKwikCheckoutUrl(
        AppGraph.goKwik,
        cart.id,
        AppGraph.storefrontToken,
        AppGraph.shopDomain,
        coreToken = kwikPass?.coreToken,
        email = kwikPass?.user?.value?.email,
        upiApps = installedUpiApps(host),
    )
    // what the order holds: the cart as it went to checkout (the page's own payload is not documented)
    val items = cart.lines.map { it.analyticsItem() }
    showGoKwikCheckout(host, url) { message, close ->
        when (message.type) {
            "orderSuccess" -> {
                goKwikPurchase(message.data, items)?.let { AppGraph.analytics.track(it) }
                AppGraph.scope.launch { AppGraph.cart.completed() }
                // push: the one offer to turn notifications on comes after a first purchase
                AppGraph.push?.purchased()
                close()
            }
            "modal_closed" -> close()
            "openInBrowserTab" -> goKwikLink(message.data)?.let { link -> openOutside(host, link) }
            // GoKwik's checkout is off for this store: Shopify's takes over
            "gk-checkout-disable" -> {
                close()
                showShopifyCheckout(checkoutUrl, host, onError)
            }
        }
    }
}

/** Which of the UPI apps checkout pays with are on the device (the manifest's `<queries>` lets the app see them). */
private fun installedUpiApps(context: Context): List<String> =
    UPI_APPS.filterValues { runCatching { context.packageManager.getPackageInfo(it, 0) }.isSuccess }.keys.toList()

/** Opens [link] in the app that handles it; false when none does. An `intent:` link is read as one, opening no component directly. */
private fun openOutside(context: Context, link: String): Boolean = try {
    val intent = if (link.startsWith("intent:")) {
        Intent.parseUri(link, Intent.URI_INTENT_SCHEME).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            component = null
            selector = null
        }
    } else {
        Intent(Intent.ACTION_VIEW, Uri.parse(link))
    }
    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    true
} catch (e: Exception) {
    Log.w("GoKwikCheckout", "nothing opens the link (${e.javaClass.name})")
    false
}

/** `Flutter.postMessage`, the bridge checkout's page talks to the app through (the SDK's name for it). Called off the main thread. */
private class Bridge(private val onMessage: (String) -> Unit) {
    @JavascriptInterface
    fun postMessage(message: String) = onMessage(message)
}

/**
 * The checkout page [url] in a full-screen dialog with a spinner until it says it is ready (`gokwikLoaded`). Its messages
 * reach [onMessage] on the main thread, only while the page is GoKwik's own, with the way to close the dialog. Web pages
 * load in place; any other link (a UPI app, `tel:`) goes to the app for it, with the events checkout waits for around
 * it. Back goes back in the page, else asks checkout (or closes before it is up). Closing clears what the page kept
 * (cookies, storage, cache).
 */
@SuppressLint("SetJavaScriptEnabled")
private fun showGoKwikCheckout(host: ComponentActivity, url: String, onMessage: (GoKwikMessage, close: () -> Unit) -> Unit) {
    val dialog = ComponentDialog(host, android.R.style.Theme_DeviceDefault_Light_NoActionBar)
    val main = Handler(Looper.getMainLooper())
    val web = WebView(host)
    val spinner = ProgressBar(host)
    var ready = false
    var listening = false
    var closed = false
    val close = {
        if (!closed) {
            closed = true
            dialog.dismiss()
        }
    }
    fun inject(script: String) = web.evaluateJavascript(script, null)

    web.settings.javaScriptEnabled = true
    web.settings.domStorageEnabled = true
    web.addJavascriptInterface(
        Bridge { raw ->
            main.post {
                // only GoKwik's pages speak for checkout (the SDK checks no origin)
                if (closed || !isGoKwikHost(web.url?.let { Uri.parse(it).host })) return@post
                val message = GoKwikMessage.parse(raw) ?: return@post
                if (message.type == "gokwikLoaded") {
                    ready = true
                    spinner.visibility = View.GONE
                }
                onMessage(message, close)
            }
        },
        "Flutter",
    )
    web.webViewClient = object : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val link = request.url
            if (link.scheme?.lowercase() in setOf("http", "https")) return false
            // a UPI app (or a call, a mail): checkout hears it launch, then whether it did
            val nonce = "${System.nanoTime() / 1000}-${Random.nextInt(1_000_000)}"
            inject(upiIntentScript("launching", nonce))
            inject(upiIntentScript(if (openOutside(host, link.toString())) "launched" else "failed", nonce))
            return true
        }

        // the listeners go in once, when the first page is up (the SDK does the same)
        override fun onPageFinished(view: WebView, url: String) {
            if (listening) return
            listening = true
            inject(GOKWIK_LISTENER_SCRIPT)
        }
    }

    val root = FrameLayout(host).apply {
        setBackgroundColor(Color.WHITE)
        addView(web, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        addView(spinner, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
    }
    // the page keeps clear of the system bars and the keyboard (drawn edge to edge or not)
    ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
        val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.ime())
        view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
        WindowInsetsCompat.CONSUMED
    }
    dialog.setContentView(root)
    dialog.window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    dialog.onBackPressedDispatcher.addCallback(dialog) {
        when {
            web.canGoBack() -> web.goBack()
            ready -> inject(GOKWIK_BACK_SCRIPT)
            else -> close()
        }
    }
    dialog.setOnDismissListener {
        closed = true
        web.stopLoading()
        web.removeJavascriptInterface("Flutter")
        CookieManager.getInstance().removeAllCookies(null)
        WebStorage.getInstance().deleteAllData()
        web.clearCache(true)
        web.destroy()
    }
    dialog.show()
    web.loadUrl(url)
}
