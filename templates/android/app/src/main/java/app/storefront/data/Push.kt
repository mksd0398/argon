package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import java.io.IOException
import java.util.UUID
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

// Push notifications (screens v2 spec, "Push notifications"), only in an app built with `PUSH`: the store's own Firebase
// Cloud Messaging, whose campaigns Krypton sends to the topics `all` and `android` with a `data.link`.

/** What a device reports to `DEVICES_URL`: an anonymous install id, and whether it takes notifications. */
data class DeviceReport(val installId: String, val platform: String, val optedIn: Boolean) {
    fun json(): String = JsonObject(mapOf("installId" to JsonPrimitive(installId), "platform" to JsonPrimitive(platform), "optedIn" to JsonPrimitive(optedIn))).toString()
}

/**
 * The opt-in to push. [enable] subscribes this install to the topics [TOPICS] and reports it, [disable] the reverse; both
 * through the functions given ([topic]: subscribe or unsubscribe one topic; [report]: send the device's state), and each
 * is remembered on the device. The OS permission is the screen's to ask before [enable]; analytics consent doesn't
 * gate push.
 */
class PushStore(
    private val dataStore: DataStore<Preferences>,
    scope: CoroutineScope,
    private val topic: suspend (name: String, subscribe: Boolean) -> Unit,
    private val report: suspend (DeviceReport) -> Unit,
) {
    private val idKey = stringPreferencesKey("push.installId")
    private val optedInKey = booleanPreferencesKey("push.optedIn")
    private val askedKey = booleanPreferencesKey("push.askedAfterPurchase")
    private val lock = Mutex()
    private val state = MutableStateFlow(false)
    private val askedState = MutableStateFlow(true)
    @Volatile private var chosen = false
    @Volatile private var offered = false

    /** Whether this install takes notifications (as last chosen here). */
    val optedIn: StateFlow<Boolean> = state

    /** Whether the one offer after a first purchase was made already (true until the file is read). */
    val askedAfterPurchase: StateFlow<Boolean> = askedState

    init {
        scope.launch {
            val prefs = dataStore.safeData().first()
            // a choice made meanwhile stands
            if (!chosen) state.value = prefs[optedInKey] == true
            if (!offered) askedState.value = prefs[askedKey] == true
        }
    }

    /** The install's anonymous id: made once, then kept on the device. */
    suspend fun installId(): String = lock.withLock {
        dataStore.safeData().first()[idKey] ?: UUID.randomUUID().toString().also { id -> save { it[idKey] = id } }
    }

    /** Subscribes to every topic and reports the opt-in. A topic that fails throws: the switch then stays off. */
    suspend fun enable() {
        for (name in TOPICS) topic(name, true)
        set(true)
    }

    /** Unsubscribes from every topic and reports the opt-out. */
    suspend fun disable() {
        set(false)
        for (name in TOPICS) topic(name, false)
    }

    private val offerState = MutableStateFlow(false)

    /** Whether the offer to turn notifications on is due (after a first purchase): the app's root shows it. */
    val offering: StateFlow<Boolean> = offerState

    /** A purchase was completed: the one offer is due, unless notifications are on or it was made before. */
    fun purchased() {
        if (!state.value && !askedState.value) offerState.value = true
    }

    /** The offer after a first purchase was made (accepted or not): it isn't made again. */
    suspend fun markAsked() {
        offered = true
        offerState.value = false
        askedState.value = true
        save { it[askedKey] = true }
    }

    private suspend fun set(on: Boolean) {
        chosen = true
        state.value = on
        save { it[optedInKey] = on }
        val id = installId()
        // fire and forget: a report that fails is only logged
        try {
            report(DeviceReport(id, PLATFORM, on))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Logger.getLogger("Push").warning("device report failed (${e.javaClass.name})")
        }
    }

    // ponytail: a failed write (IOException) only costs the choice after a restart
    private suspend fun save(change: (MutablePreferences) -> Unit) {
        try {
            dataStore.edit(change)
        } catch (e: IOException) {
            // see above
        }
    }

    companion object {
        const val PLATFORM = "android"

        /** Whether the config value `PUSH` turns push on: `true`, in any case; anything else (empty in an older project) is off. */
        fun enabled(config: String): Boolean = config.trim().equals("true", ignoreCase = true)

        /** The FCM topics Krypton sends campaigns to: everyone's, and this platform's. */
        val TOPICS = listOf("all", PLATFORM)

        /** The `link` of a notification's data (FCM puts it in the launch intent's extras); null without one. */
        fun link(data: Map<String, String?>): String? = data["link"]?.trim()?.takeIf { it.isNotEmpty() }

        /** Sends [report] to [url] (`DEVICES_URL`) as JSON; nothing without a url. */
        suspend fun post(http: OkHttpClient, url: String, report: DeviceReport) {
            if (url.isBlank()) return
            withContext(Dispatchers.IO) {
                val request = Request.Builder().url(url).post(report.json().toRequestBody("application/json".toMediaType())).build()
                http.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) Logger.getLogger("Push").warning("device report: HTTP ${response.code}")
                }
            }
        }
    }
}
