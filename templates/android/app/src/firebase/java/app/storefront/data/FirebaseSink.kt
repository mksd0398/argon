package app.storefront.data

import android.app.Application
import app.storefront.BuildConfig
import com.google.firebase.analytics.FirebaseAnalytics
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/** Google Analytics 4, through Firebase: compiled in because `app/google-services.json` exists, which also starts the SDK. */
fun firebaseSink(app: Application): AnalyticsSink? =
    FirebaseSink(FirebaseAnalytics.getInstance(app), serverPurchase = BuildConfig.SERVER_PURCHASE.trim().equals("true", ignoreCase = true))

/**
 * The purchase must reach Google Analytics from one side only: it counts an app's purchase every time it is sent (its
 * `transaction_id` check is for websites). So without the store's server ([serverPurchase] off, `SERVER_PURCHASE`) the app
 * sends the purchase and a cart carries no `_ga_app_instance_id`; with it the app leaves the purchase out and the cart
 * carries the id, which on an order is what tells the server to report it. Whatever versions of the app are in use,
 * no order is counted twice.
 */
private class FirebaseSink(private val analytics: FirebaseAnalytics, private val serverPurchase: Boolean) : AnalyticsSink {
    override fun track(event: AnalyticsEvent) {
        val params = ga4Params(event, serverPurchase) ?: return
        analytics.logEvent(event.name, params.toBundle())
    }

    override fun identify(user: AnalyticsUser?) = analytics.setUserId(user?.id)

    // The SDK collects nothing until this turns it on (the manifest's firebase_analytics_collection_enabled is false),
    // and it keeps what it was last told across launches.
    override fun setEnabled(allowed: Boolean) = analytics.setAnalyticsCollectionEnabled(allowed)

    override suspend fun cartAttributes(): Map<String, String> {
        if (!serverPurchase) return emptyMap()
        // The SDK's Task, awaited by hand (no coroutines-play-services library), and not for long: a first cart must not
        // wait on the SDK, which can take minutes to give up. No id: an order the server leaves alone.
        val id = withTimeoutOrNull(3_000) {
            suspendCancellableCoroutine { continuation ->
                analytics.appInstanceId.addOnCompleteListener { continuation.resume(if (it.isSuccessful) it.result else null) }
            }
        }
        return if (id == null) emptyMap() else mapOf("_ga_app_instance_id" to id)
    }
}
