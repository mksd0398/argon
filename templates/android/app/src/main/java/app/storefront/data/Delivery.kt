package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import java.io.IOException
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

/** Where the customer wants things delivered: a six-digit Indian pincode and, when known, its city. */
data class DeliveryLocation(val pincode: String, val city: String? = null) {
    /** "560001 · Bengaluru", or the pincode alone. */
    val label: String get() = listOfNotNull(pincode, city?.takeIf { it.isNotBlank() }).joinToString(" · ")

    companion object {
        private val pincode = Regex("[1-9][0-9]{5}")

        fun isPincode(text: String): Boolean = pincode.matches(text)

        /** [address]'s pincode and city when it is an Indian address with a valid pincode; else null. */
        fun of(address: CustomerAddress?): DeliveryLocation? {
            val zip = address?.zip?.filter { !it.isWhitespace() } ?: return null
            if (address.countryCode?.uppercase()?.let { it != "IN" } == true || !isPincode(zip)) return null
            return DeliveryLocation(zip, address.city?.trim()?.ifEmpty { null })
        }
    }
}

/**
 * Krypton's answer for a pincode (`GET /v1/delivery/{shop}?pincode=`): [date] the order would arrive, null when the store
 * doesn't deliver there ([serviceable] false); [cod] whether it can be paid on delivery, null when not known.
 */
data class DeliveryEstimate(val pincode: String, val serviceable: Boolean, val cod: Boolean?, val date: LocalDate?, val city: String?) {
    companion object {
        /** The answer in [json]; null when it isn't one. */
        fun decode(json: String): DeliveryEstimate? {
            val root = runCatching { Json.parseToJsonElement(json) }.getOrNull() as? JsonObject ?: return null
            val str = { key: String -> (root[key] as? JsonPrimitive)?.takeIf { it.isString }?.content }
            val bool = { key: String -> (root[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull }
            val pincode = str("pincode") ?: return null
            val serviceable = bool("serviceable") ?: return null
            return DeliveryEstimate(
                pincode = pincode,
                serviceable = serviceable,
                cod = bool("cod"),
                date = str("date")?.let { runCatching { LocalDate.parse(it) }.getOrNull() }?.takeIf { serviceable },
                city = str("city")?.trim()?.ifEmpty { null },
            )
        }
    }
}

enum class DeliveryTone { Good, Muted, Bad }

/** One line of the delivery block. */
data class DeliveryLine(val text: String, val tone: DeliveryTone)

/** What the product page says for [estimate]: the date ("Delivery by Thu, 24 Oct") and COD, or that it doesn't deliver there. */
fun deliveryLines(estimate: DeliveryEstimate, locale: Locale = Locale.getDefault()): List<DeliveryLine> {
    if (!estimate.serviceable) return listOf(DeliveryLine("Not delivering to ${estimate.pincode} yet", DeliveryTone.Bad))
    return listOfNotNull(
        estimate.date?.let { DeliveryLine("Delivery by ${it.format(DateTimeFormatter.ofPattern("EEE, d MMM", locale))}", DeliveryTone.Good) },
        when (estimate.cod) {
            true -> DeliveryLine("Cash on delivery available", DeliveryTone.Muted)
            false -> DeliveryLine("Cash on delivery not available", DeliveryTone.Muted)
            null -> null
        },
    )
}

/** Krypton's delivery endpoint next to the settings one (`…/v1/settings/{shop}` → `…/v1/delivery/{shop}`); empty without one. */
fun deliveryEndpoint(settingsUrl: String): String =
    if ("/v1/settings/" in settingsUrl) settingsUrl.replace("/v1/settings/", "/v1/delivery/") else ""

/**
 * The customer's delivery location, kept on the device (`delivery.pincode`, `delivery.city`), and the estimates for it from
 * [url]. Only the pincode leaves the device. Estimates are kept for the session: every product page asks for the same one.
 */
class DeliveryStore(private val dataStore: DataStore<Preferences>, scope: CoroutineScope, private val url: String, http: OkHttpClient) {
    private val pincodeKey = stringPreferencesKey("delivery.pincode")
    private val cityKey = stringPreferencesKey("delivery.city")
    private val state = MutableStateFlow<DeliveryLocation?>(null)
    private val estimates = ConcurrentHashMap<String, DeliveryEstimate>()
    private val http = http.newBuilder().callTimeout(8, TimeUnit.SECONDS).build()
    private val log = Logger.getLogger("Delivery")

    /** Null until the customer has one (or the file is read). */
    val location: StateFlow<DeliveryLocation?> = state

    init {
        scope.launch {
            val saved = dataStore.safeData().first()
            val pin = saved[pincodeKey]
            if (pin != null && DeliveryLocation.isPincode(pin)) state.compareAndSet(null, DeliveryLocation(pin, saved[cityKey]))
        }
    }

    // ponytail: a failed write only costs entering the pincode again after a restart
    suspend fun set(location: DeliveryLocation) {
        state.value = location
        try {
            dataStore.edit {
                it[pincodeKey] = location.pincode
                if (location.city != null) it[cityKey] = location.city else it.remove(cityKey)
            }
        } catch (e: IOException) {
            // see above
        }
    }

    /** The signed-in customer's default address, when the customer has set no location yet. */
    suspend fun prefill(address: CustomerAddress?) {
        val location = DeliveryLocation.of(address) ?: return
        if (state.value == null && dataStore.safeData().first()[pincodeKey] == null) set(location)
    }

    /** The estimate for [pincode]; null when it can't be had (no endpoint, offline, the store turned it off). */
    suspend fun estimate(pincode: String): DeliveryEstimate? {
        estimates[pincode]?.let { return it }
        val endpoint = url.toHttpUrlOrNull()?.newBuilder()?.addQueryParameter("pincode", pincode)?.build() ?: return null
        return try {
            withContext(Dispatchers.IO) {
                http.newCall(Request.Builder().url(endpoint).build()).execute().use { response ->
                    if (response.code != 200) return@withContext null.also { log.warning("delivery: HTTP ${response.code}") }
                    DeliveryEstimate.decode(response.body.string())
                }
            }?.also { estimates[pincode] = it }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log.warning("delivery fetch failed (${e.javaClass.name})")
            null
        }
    }
}
