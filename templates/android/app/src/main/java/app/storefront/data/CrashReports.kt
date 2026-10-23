package app.storefront.data

/** What [CrashReports] hands its reports to: Crashlytics (src/firebase), in an app built with the store's Firebase file. */
interface CrashBackend {
    fun setKey(key: String, value: String)

    fun log(message: String)

    fun record(error: Throwable)
}

/**
 * Crash reporting: the keys a crash is reported with, the breadcrumbs before it, and the caught failures worth fixing
 * (non-fatal reports). Always compiled, so every call site is unconditional: without Firebase, and in JVM tests,
 * [backend] is null and every call does nothing. It never throws into its caller.
 *
 * Crash reports are not behind the analytics switch: they carry no personal data (the keys below, no user id). The
 * breadcrumbs are, as a sink of the analytics hub ([CrashSink]).
 */
object CrashReports {
    @Volatile var backend: CrashBackend? = null

    fun setKey(key: String, value: String) = quietly { it.setKey(key, value) }

    fun log(message: String) = quietly { it.log(message) }

    /** A caught failure that is a bug somewhere (the app's, or the store's content): reported, the app carries on. */
    fun record(error: Throwable, where: String) = quietly {
        it.log("non-fatal: $where")
        it.record(error)
    }

    private inline fun quietly(action: (CrashBackend) -> Unit) {
        val backend = backend ?: return
        try {
            action(backend)
        } catch (_: Exception) {
            // reporting must never be what breaks the app
        }
    }
}

/** The breadcrumbs: every analytics event the shopper allows, as one line before a crash. */
class CrashSink : AnalyticsSink {
    override fun track(event: AnalyticsEvent) = CrashReports.log(breadcrumb(event))
}

/** One event as a breadcrumb: `add_to_cart {currency=INR, value=499.0, items=[…]}`, at most 300 characters. */
fun breadcrumb(event: AnalyticsEvent): String = "${event.name} ${event.params}".take(300)

/** Thrown by a debug build launched with the `argon_test_crash` extra: proves crash reports reach the store's Firebase. */
class ArgonTestCrash : RuntimeException("Argon test crash (debug builds only)")
