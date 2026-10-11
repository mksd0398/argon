package app.storefront.data

import android.app.Application
import app.storefront.BuildConfig
import com.moengage.core.DataCenter
import com.moengage.core.MoECoreHelper
import com.moengage.core.MoEngage
import com.moengage.core.Properties
import com.moengage.core.analytics.MoEAnalyticsHelper
import com.moengage.core.config.FcmConfig
import org.json.JSONArray

/**
 * MoEngage: compiled in because `MOENGAGE_WORKSPACE_ID` is set. Its SDK is started here, which is the place it asks for
 * (`Application.onCreate`, on the main thread), in the workspace's data center (`MOENGAGE_DATA_CENTER`, 1 when unset).
 */
fun moEngageSink(app: Application): AnalyticsSink? {
    val dataCenter = when (BuildConfig.MOENGAGE_DATA_CENTER.trim()) {
        "2" -> DataCenter.DATA_CENTER_2
        "3" -> DataCenter.DATA_CENTER_3
        "4" -> DataCenter.DATA_CENTER_4
        "5" -> DataCenter.DATA_CENTER_5
        "6" -> DataCenter.DATA_CENTER_6
        else -> DataCenter.DATA_CENTER_1 // the build refuses anything but 1...6
    }
    // No push in this app yet (it has no Firebase Messaging), so the SDK is told not to go looking for a push token.
    val moEngage = MoEngage.Builder(app, BuildConfig.MOENGAGE_WORKSPACE_ID.trim(), dataCenter).configureFcm(FcmConfig(false)).build()
    MoEngage.initialiseDefaultInstance(moEngage)
    return MoEngageSink(app)
}

private class MoEngageSink(private val app: Application) : AnalyticsSink {
    override fun track(event: AnalyticsEvent) {
        val (name, attributes) = moEngageEvent(event)
        val properties = Properties()
        for ((key, value) in attributes) properties.addAttribute(key, if (value is List<*>) JSONArray(value) else value)
        MoEAnalyticsHelper.trackEvent(app, name, properties)
    }

    override fun identify(user: AnalyticsUser?) {
        // a sign-out: what follows on this phone is no longer this customer's
        if (user == null) return MoECoreHelper.logoutUser(app)
        MoEAnalyticsHelper.identifyUser(app, user.id)
        user.email?.let { MoEAnalyticsHelper.setEmailId(app, it) }
        user.phone?.let { MoEAnalyticsHelper.setMobileNumber(app, it) }
        user.firstName?.let { MoEAnalyticsHelper.setFirstName(app, it) }
        user.lastName?.let { MoEAnalyticsHelper.setLastName(app, it) }
    }
}
