package app.storefront.data

import android.app.Application
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.telephony.TelephonyManager
import app.storefront.BuildConfig
import com.facebook.FacebookSdk
import com.facebook.appevents.AppEventsLogger
import java.math.BigDecimal
import java.util.Currency
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Meta, through the Facebook SDK's App Events: compiled in because `META_APP_ID` is set. The SDK starts itself, with the
 * app id and client token it reads in the manifest.
 */
fun metaSink(app: Application): AnalyticsSink? = MetaSink(app, AppEventsLogger.newLogger(app))

private class MetaSink(private val app: Application, private val logger: AppEventsLogger) : AnalyticsSink {
    override fun track(event: AnalyticsEvent) {
        val (name, value, params) = metaEvent(event) ?: return
        val bundle = params.toBundle()
        when {
            // the SDK's own call for a purchase: it doesn't wait for its next batch to send it
            event is AnalyticsEvent.Purchase -> logger.logPurchase(BigDecimal.valueOf(event.value), Currency.getInstance(event.currency), bundle)
            value != null -> logger.logEvent(name, value, bundle)
            else -> logger.logEvent(name, bundle)
        }
    }

    // the SDK hashes the customer's details before they leave the phone
    override fun identify(user: AnalyticsUser?) {
        if (user == null) {
            AppEventsLogger.clearUserID()
            AppEventsLogger.clearUserData()
        } else {
            AppEventsLogger.setUserID(user.id)
            AppEventsLogger.setUserData(user.email, user.firstName, user.lastName, user.phone, null, null, null, null, null, null)
        }
    }

    // What the SDK does on its own: its automatic events (installs, sessions) and reading the phone's advertising id.
    // Both are off in the manifest until this turns them on, and the SDK keeps what it was last told across launches.
    // One thing wins over this: the "Automatic event logging for the Facebook SDK" switch in Meta's own dashboard, once
    // someone has set it there. A store that wants the shopper's choice to rule leaves that switch alone.
    override fun setEnabled(allowed: Boolean) {
        FacebookSdk.setAutoLogAppEventsEnabled(allowed)
        FacebookSdk.setAdvertiserIDCollectionEnabled(allowed)
    }

    /** What the store's server needs to send Meta the purchase as this app install's: the SDK's id for it, and the device. */
    override suspend fun cartAttributes(): Map<String, String> {
        val screen = app.resources.displayMetrics
        val timezone = TimeZone.getDefault()
        val storage = StatFs(Environment.getDataDirectory().path)
        return mapOf(
            "_meta_anon_id" to AppEventsLogger.getAnonymousAppDeviceGUID(app),
            "_meta_extinfo" to metaExtinfo(
                packageName = app.packageName,
                versionCode = BuildConfig.VERSION_CODE,
                versionName = BuildConfig.VERSION_NAME,
                osVersion = Build.VERSION.RELEASE,
                model = Build.MODEL,
                locale = Locale.getDefault().run { "${language}_$country" },
                timezoneAbbreviation = timezone.getDisplayName(timezone.inDaylightTime(Date()), TimeZone.SHORT),
                carrier = app.getSystemService(TelephonyManager::class.java)?.networkOperatorName.orEmpty(),
                screenWidth = screen.widthPixels,
                screenHeight = screen.heightPixels,
                screenDensity = screen.density,
                cores = Runtime.getRuntime().availableProcessors(),
                storageGb = storage.totalBytes shr 30,
                freeStorageGb = storage.availableBytes shr 30,
                timezone = timezone.id,
            ),
            // ponytail: always "tracking allowed". These attributes exist only while the shopper shares usage data; the
            // phone's own "limit ad tracking" setting is the Facebook SDK's to read, and isn't passed on here.
            "_meta_tracking" to "1",
        )
    }
}
