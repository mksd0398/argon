package app.storefront.data

import android.app.Application

/** MoEngage isn't set up for this app (`MOENGAGE_WORKSPACE_ID` is empty): no sink, and no MoEngage SDK in the app. */
@Suppress("UNUSED_PARAMETER")
fun moEngageSink(app: Application): AnalyticsSink? = null
