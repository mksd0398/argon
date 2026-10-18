package app.storefront.ui

import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.webkit.ClientCertRequest
import android.webkit.HttpAuthHandler
import android.webkit.RenderProcessGoneDetail
import android.webkit.SafeBrowsingResponse
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * Keeps the checkout sheet on checkout: a page of the store's own website ([isStorePage]) that it is about to show,
 * a link the shopper followed or a redirect (the password page, "Continue shopping" on the confirmation), is stopped
 * and [leave] runs (it closes the sheet and opens the app's cart). Checkout Kit offers no hook for this, so its
 * WebView's client is wrapped, every call handed on to it.
 */
internal class CheckoutGuardClient(
    private val inner: WebViewClient,
    private val isStorePage: (String) -> Boolean,
    private val leave: () -> Unit,
) : WebViewClient() {
    private var left = false

    private fun stop(view: WebView?, url: String?): Boolean {
        if (left || url == null || !isStorePage(url)) return left
        left = true
        view?.stopLoading()
        leave()
        return true
    }

    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
        (request.isForMainFrame && stop(view, request.url.toString())) || inner.shouldOverrideUrlLoading(view, request)

    @Deprecated("Deprecated in Java")
    override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
        stop(view, url) || @Suppress("DEPRECATION") inner.shouldOverrideUrlLoading(view, url)

    // A redirect doesn't always ask shouldOverrideUrlLoading: it is caught as its page starts
    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
        if (!stop(view, url)) inner.onPageStarted(view, url, favicon)
    }

    override fun onPageFinished(view: WebView, url: String) = inner.onPageFinished(view, url)
    override fun onLoadResource(view: WebView, url: String) = inner.onLoadResource(view, url)
    override fun onPageCommitVisible(view: WebView, url: String) = inner.onPageCommitVisible(view, url)
    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
        inner.shouldInterceptRequest(view, request)
    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) =
        inner.onReceivedError(view, request, error)
    override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse) =
        inner.onReceivedHttpError(view, request, errorResponse)
    override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) = inner.onReceivedSslError(view, handler, error)
    override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest) = inner.onReceivedClientCertRequest(view, request)
    override fun onReceivedHttpAuthRequest(view: WebView, handler: HttpAuthHandler, host: String, realm: String) =
        inner.onReceivedHttpAuthRequest(view, handler, host, realm)
    override fun onFormResubmission(view: WebView, dontResend: Message, resend: Message) = inner.onFormResubmission(view, dontResend, resend)
    override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) = inner.doUpdateVisitedHistory(view, url, isReload)
    override fun shouldOverrideKeyEvent(view: WebView, event: KeyEvent): Boolean = inner.shouldOverrideKeyEvent(view, event)
    override fun onUnhandledKeyEvent(view: WebView, event: KeyEvent) = inner.onUnhandledKeyEvent(view, event)
    override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) = inner.onScaleChanged(view, oldScale, newScale)
    override fun onReceivedLoginRequest(view: WebView, realm: String, account: String?, args: String) =
        inner.onReceivedLoginRequest(view, realm, account, args)
    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean = inner.onRenderProcessGone(view, detail)
    override fun onSafeBrowsingHit(view: WebView, request: WebResourceRequest, threatType: Int, callback: SafeBrowsingResponse) =
        inner.onSafeBrowsingHit(view, request, threatType, callback)
}

/**
 * Puts [CheckoutGuardClient] on the checkout sheet that was just presented. The sheet is Checkout Kit's own dialog, found
 * among the app's windows (WindowInspector, Android 10 and later; earlier versions go without the guard). Tried now
 * and on the next frame, as the dialog may still be laying out.
 */
internal fun guardCheckoutSheet(isStorePage: (String) -> Boolean, leave: () -> Unit) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
    fun attach(): Boolean {
        val webView = WindowInspector.getGlobalWindowViews().firstNotNullOfOrNull { it.checkoutWebView() } ?: return false
        val client = webView.webViewClient
        if (client !is CheckoutGuardClient) webView.webViewClient = CheckoutGuardClient(client, isStorePage, leave)
        return true
    }
    if (!attach()) Handler(Looper.getMainLooper()).post { attach() }
}

/** The kit's checkout WebView under this view, if there is one. */
private fun View.checkoutWebView(): WebView? = when {
    this is WebView && javaClass.name.startsWith("com.shopify.checkoutsheetkit") -> this
    this is ViewGroup -> (0 until childCount).firstNotNullOfOrNull { getChildAt(it).checkoutWebView() }
    else -> null
}
