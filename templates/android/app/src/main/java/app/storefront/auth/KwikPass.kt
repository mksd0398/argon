package app.storefront.auth

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import app.storefront.data.GoKwikConfig
import app.storefront.data.safeData
import java.io.IOException
import java.net.URLEncoder
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** A KwikPass call failed or was refused; the message is GoKwik's (or ours), meant for the shopper. */
class KwikPassException(message: String, val status: Int? = null) : Exception(message)

/** The signed-in KwikPass shopper: the Shopify customer GoKwik found or created for their phone ([phone]: 10 digits). */
data class KwikPassUser(val phone: String, val email: String, val shopifyCustomerId: String) {
    /** The phone as Shopify takes it (E.164). */
    val e164: String get() = "+91$phone"
}

/** Where a step of the sign-in leads. */
sealed interface KwikPassStep {
    data object SignedIn : KwikPassStep

    /** A new number: the shopper gives their email. */
    data object EnterEmail : KwikPassStep

    /** Several customers share the number: the shopper picks their email. */
    data class ChooseEmail(val emails: List<String>) : KwikPassStep

    /** A code went to [email]; the shopper enters it to prove the address is theirs. */
    data class EmailCode(val email: String) : KwikPassStep
}

/** What a verified phone needs next (`kp/api/v2/auth/otp/verify`'s data, the Shopify branch of the SDK). */
internal sealed interface PhoneOutcome {
    /** The number's customer has an email that must be proven first (`authRequired`). */
    data class ProveEmail(val email: String) : PhoneOutcome

    /** The number's customer is known: multipass signs them in. */
    data class Known(val email: String, val customerId: String, val state: String) : PhoneOutcome

    data class Choose(val emails: List<String>) : PhoneOutcome
    data object NewNumber : PhoneOutcome
}

internal fun phoneOutcome(data: JsonObject): PhoneOutcome {
    val email = data.text("email")
    if (data.bool("authRequired") == true && email != null) return PhoneOutcome.ProveEmail(email)
    if (email != null) return PhoneOutcome.Known(email, data.text("shopifyCustomerId").orEmpty(), data.text("state").orEmpty())
    val emails = data.text("multipleEmail")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }.orEmpty()
    return if (emails.isNotEmpty()) PhoneOutcome.Choose(emails) else PhoneOutcome.NewNumber
}

/**
 * A 10-digit Indian mobile number from what the shopper typed (spaces, a +91 or 0 in front are dropped); null when it
 * isn't one (they start 6 to 9).
 */
fun indianMobile(input: String): String? {
    val digits = input.filter(Char::isDigit)
    val number = when {
        digits.length == 12 && digits.startsWith("91") -> digits.drop(2)
        digits.length == 11 && digits.startsWith("0") -> digits.drop(1)
        else -> digits
    }
    return number.takeIf { it.length == 10 && it[0] in '6'..'9' }
}

/**
 * KwikPass, GoKwik's phone sign-in (LOGIN=kwikpass), in place of the Customer Account one: phone and its code, then the
 * Shopify customer GoKwik finds or creates for it (by email, proven by a code when the account already exists). The
 * endpoints, bodies and headers are GoKwik's SDK's (1.0.37). What it gives the app is GoKwik's tokens and the [user]: no
 * Customer Account API token, so orders, addresses and the profile stay out of reach; checkout gets the session
 * (`coreToken`, GoKwik's checkout) or the shopper's email and phone (Shopify's).
 *
 * The session is kept in [prefs] through [encrypt] (TokenCrypto, as the Customer Account tokens); a value [decrypt] can't
 * open reads as signed out. Signing out is local: GoKwik has no call for it.
 */
class KwikPassStore(
    private val config: GoKwikConfig,
    private val http: OkHttpClient,
    private val prefs: DataStore<Preferences>,
    private val encrypt: (String) -> String,
    private val decrypt: (String) -> String,
    private val appVersion: String,
    private val deviceId: () -> String,
) {
    private val sessionKey = stringPreferencesKey("session")

    // java.util.logging: it reaches logcat on Android and also runs in JVM tests. Only exception classes are logged, never values.
    private val log = Logger.getLogger("KwikPassStore")
    private val lock = Mutex()
    private val userState = MutableStateFlow<KwikPassUser?>(null)
    private var loaded = false

    // GoKwik's tokens: `token` (gk-access-token), `coreToken` (checkout-access-token), `kpToken`; the browser token's
    // request id and `Authorization`. Also held mid sign-in, before there is a user.
    private var tokens = emptyMap<String, String>()

    // the sign-in in progress: the phone, and the customer GoKwik named for it so far
    private var phone: String? = null
    private var pending: JsonObject = JsonObject(emptyMap())

    /** The signed-in shopper; null when signed out, and until [load] has read the stored session. */
    val user: StateFlow<KwikPassUser?> = userState

    /** The `coreToken` checkout takes to know the shopper; null when signed out. */
    val coreToken: String? get() = tokens["coreToken"].takeIf { userState.value != null }

    /** Reads the stored session, then asks GoKwik whether it is still good: one it refuses signs out; no answer keeps it. */
    suspend fun load() {
        lock.withLock { ensureLoaded() }
        if (userState.value == null) return
        val valid = try {
            val data = call("GET", "kp/api/v1/auth/validate-token").data()
            val token = data["token"] as? JsonObject
            token?.bool("isValid") != false && token?.bool("isExpired") != true
        } catch (e: KwikPassException) {
            e.status != 401 && e.status != 403
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log.warning("session not checked (${e.javaClass.name})")
            true
        }
        if (!valid) signOut()
    }

    /** Sends a code to [phone] (10 digits); returns how many seconds until another may be asked for. */
    suspend fun sendCode(phone: String): Int {
        lock.withLock { ensureLoaded() }
        // the browser token: the request id and `Authorization` every call after this one carries
        val browser = call("GET", "kp/api/v1/auth/browser").data()
        tokens = tokens + listOfNotNull(
            browser.text("requestId")?.let { "requestId" to it },
            browser.text("token")?.let { "authorization" to it },
        )
        val sent = call("POST", "kp/api/v1/auth/otp/send", buildJsonObject { put("phone", phone) }).data()
        this.phone = phone
        return sent.int("interval")?.takeIf { it > 0 } ?: 30
    }

    /** Checks the phone's [code]: signed in, or the email step next. */
    suspend fun verifyCode(code: String): KwikPassStep {
        val phone = phone ?: throw KwikPassException("Enter your phone number first")
        val body = buildJsonObject {
            put("phone", phone)
            put("otp", code.toIntOrNull() ?: throw KwikPassException("Enter the code you received"))
            put("deviceId", deviceId())
        }
        val data = call("POST", "kp/api/v2/auth/otp/verify", body).data()
        tokens = tokens + listOf("token", "coreToken", "kpToken").mapNotNull { key -> data.text(key)?.let { key to it } }
        pending = data
        return when (val outcome = phoneOutcome(data)) {
            is PhoneOutcome.ProveEmail -> sendEmailCode(outcome.email)
            is PhoneOutcome.Known -> {
                val body = buildJsonObject {
                    put("id", outcome.customerId)
                    put("email", outcome.email)
                    put("redirectUrl", "/")
                    put("isMarketingEventSubscribed", true)
                    put("state", outcome.state)
                }
                // Not /account/activate after it, as the SDK does when it names an activation URL: that is classic accounts' only.
                finish(call("POST", "kp/api/v2/customer/shopify/multipass", body).data())
            }
            is PhoneOutcome.Choose -> KwikPassStep.ChooseEmail(outcome.emails)
            PhoneOutcome.NewNumber -> KwikPassStep.EnterEmail
        }
    }

    /**
     * The email of a new number (or the one chosen): a throwaway address is refused; GoKwik then finds or creates the
     * Shopify customer. A new one is signed in; an existing one proves the address with a code first.
     */
    suspend fun submitEmail(email: String): KwikPassStep {
        val address = email.trim()
        val check = try {
            call("GET", "kp/api/v1/disposable-email/validate/" + URLEncoder.encode(address, "UTF-8").replace("+", "%20"))
        } catch (e: KwikPassException) {
            if (e.status == null) throw e else null // refused: not valid
        }
        if (check?.bool("success") != true || check["data"] == null || check["data"] is JsonNull) throw KwikPassException("Entered email is not valid")
        val body = buildJsonObject {
            put("email", address)
            put("redirectUrl", "/")
            put("isMarketingEventSubscribed", true)
            pending.text("shopifyCustomerId")?.let { put("id", it) }
        }
        val session = call("POST", "kp/api/v1/customer/shopify-session", body).data()
        return if (session.bool("isNewUser") == true) finish(session, email = address) else sendEmailCode(address)
    }

    /** Sends the code that proves [email] again. */
    suspend fun sendEmailCode(email: String): KwikPassStep.EmailCode {
        call("POST", "kp/api/v1/auth/email-otp/send", buildJsonObject { put("email", email) })
        return KwikPassStep.EmailCode(email)
    }

    /** Checks the code sent to [email]: signed in. */
    suspend fun verifyEmailCode(email: String, code: String): KwikPassStep {
        val body = buildJsonObject {
            put("email", email)
            put("otp", code)
            put("redirectUrl", "/")
            put("isMarketingEventSubscribed", true)
        }
        return finish(call("POST", "kp/api/v1/auth/email-otp/verify", body).data(), email = email)
    }

    /** Forgets the session on the device. */
    suspend fun signOut() = lock.withLock {
        ensureLoaded()
        tokens = emptyMap()
        phone = null
        pending = JsonObject(emptyMap())
        userState.value = null
        save(null)
    }

    /** The shopper GoKwik answered with ([data], over what the phone step said): signed in once it names all three. */
    private suspend fun finish(data: JsonObject, email: String? = null): KwikPassStep = lock.withLock {
        val user = KwikPassUser(
            phone = phone ?: throw KwikPassException("Sign-in couldn't be completed"),
            email = data.text("email") ?: email ?: pending.text("email") ?: throw KwikPassException("Sign-in couldn't be completed"),
            shopifyCustomerId = data.text("shopifyCustomerId") ?: pending.text("shopifyCustomerId") ?: throw KwikPassException("Sign-in couldn't be completed"),
        )
        userState.value = user
        save(buildJsonObject {
            for ((key, value) in tokens) put(key, value)
            put("phone", user.phone)
            put("email", user.email)
            put("shopifyCustomerId", user.shopifyCustomerId)
        })
        KwikPassStep.SignedIn
    }

    private suspend fun ensureLoaded() {
        if (loaded) return
        val stored = withContext(Dispatchers.IO) {
            prefs.safeData().first()[sessionKey]?.let { sealed ->
                try {
                    Json.parseToJsonElement(decrypt(sealed)) as? JsonObject
                } catch (e: Exception) {
                    log.warning("stored session unreadable (${e.javaClass.name})")
                    null
                }
            }
        }
        if (stored != null) {
            val phone = stored.text("phone")
            val email = stored.text("email")
            val id = stored.text("shopifyCustomerId")
            if (phone != null && email != null && id != null) {
                tokens = listOf("token", "coreToken", "kpToken", "requestId", "authorization").mapNotNull { key -> stored.text(key)?.let { key to it } }.toMap()
                this.phone = phone
                userState.value = KwikPassUser(phone, email, id)
            }
        }
        loaded = true
    }

    // ponytail: a failed write (disk full, Keystore unavailable) only costs the session across a restart: memory stays right.
    private suspend fun save(value: JsonObject?) {
        try {
            withContext(Dispatchers.IO) {
                val sealed = value?.let { encrypt(it.toString()) }
                prefs.edit { if (sealed == null) it.remove(sessionKey) else it[sessionKey] = sealed }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log.warning("session not saved (${e.javaClass.name})")
        }
    }

    /**
     * Calls GoKwik and returns its envelope (`{data, success, ...}`). An HTTP error, or an envelope that says it failed, is
     * a [KwikPassException] with GoKwik's message; one without an answer (offline) has no status.
     */
    private suspend fun call(method: String, path: String, body: JsonObject? = null): JsonObject = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(config.apiBase + path).apply {
            // the SDK's headers on every call, then what the session has so far
            header("accept", "*/*")
            header("gk-source", "kp")
            header("appplatform", "android")
            header("appversion", appVersion)
            header("source", "android-app")
            header("gk-platform", "shopify")
            header("gk-merchant-id", config.merchantId)
            header("sdk-platform", "argon-android")
            header("sdk-version", "1.0.37")
            header("kp-integration-type", "APP_MAKER")
            tokens["token"]?.let { header("gk-access-token", it) }
            tokens["coreToken"]?.let { header("checkout-access-token", it) }
            tokens["requestId"]?.let { header("gk-request-id", it); header("kp-request-id", it) }
            tokens["authorization"]?.let { header("Authorization", it) } // the bare token, no "Bearer"
            method(method, body?.toString()?.toRequestBody("application/json".toMediaType()))
        }.build()
        val (status, json) = try {
            http.newCall(request).execute().use { response ->
                response.code to (runCatching { Json.parseToJsonElement(response.body.string()) }.getOrNull() as? JsonObject)
            }
        } catch (e: IOException) {
            throw KwikPassException("Couldn't reach the sign-in service. Check your connection and try again.")
        }
        val failed = status !in 200..299 || json == null || json.bool("success") == false || json.bool("isSuccess") == false
        if (failed) throw KwikPassException(json?.errorMessage() ?: "Sign-in isn't available right now (HTTP $status)", status)
        json!!
    }
}

/** GoKwik's message for a failure: `error.message`, `error`, `error_msg`, then `message`. */
private fun JsonObject.errorMessage(): String? =
    (this["error"] as? JsonObject)?.text("message") ?: text("error") ?: text("error_msg") ?: text("message")

private fun JsonObject.data(): JsonObject = this["data"] as? JsonObject ?: JsonObject(emptyMap())

// Lenient reads of GoKwik's JSON: a missing, null or blank field reads as null; a number reads as its text.
private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }
private fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.let { it.booleanOrNull ?: it.contentOrNull?.toBooleanStrictOrNull() }
private fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.let { it.intOrNull ?: it.contentOrNull?.toDoubleOrNull()?.toInt() }
