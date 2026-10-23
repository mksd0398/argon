package app.storefront.data

import com.google.firebase.crashlytics.FirebaseCrashlytics

/** Crashlytics, compiled in because `app/google-services.json` exists; its SDK starts with Firebase and catches crashes. */
fun crashBackend(): CrashBackend? = CrashlyticsBackend(FirebaseCrashlytics.getInstance())

private class CrashlyticsBackend(private val crashlytics: FirebaseCrashlytics) : CrashBackend {
    override fun setKey(key: String, value: String) = crashlytics.setCustomKey(key, value)

    override fun log(message: String) = crashlytics.log(message)

    override fun record(error: Throwable) = crashlytics.recordException(error)
}
