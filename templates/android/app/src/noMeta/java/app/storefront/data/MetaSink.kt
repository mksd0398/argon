package app.storefront.data

import android.app.Application

/** Meta isn't set up for this app (`META_APP_ID` is empty): no sink, and no Facebook SDK in the app. */
@Suppress("UNUSED_PARAMETER")
fun metaSink(app: Application): AnalyticsSink? = null
