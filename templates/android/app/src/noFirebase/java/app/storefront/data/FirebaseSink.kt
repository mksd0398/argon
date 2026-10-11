package app.storefront.data

import android.app.Application

/** Google Analytics isn't set up for this app (no `app/google-services.json`): no sink, and no Firebase SDK in the app. */
@Suppress("UNUSED_PARAMETER")
fun firebaseSink(app: Application): AnalyticsSink? = null
