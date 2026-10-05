package app.storefront.auth

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import app.storefront.data.StorefrontException
import app.storefront.data.graphQL
import app.storefront.data.graphQLBody
import app.storefront.data.int
import app.storefront.data.safeData
import app.storefront.data.str
import app.storefront.data.string
import java.net.URI
import java.net.URLDecoder
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import okhttp3.FormBody
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

/** Sign-in failed or was refused. [status] is set when a Shopify endpoint answered with an HTTP error. */
class AuthException(message: String, val status: Int? = null) : Exception(message)

/**
 * The customer's Customer Account API session: the OAuth 2.0 authorization code flow for a public client with PKCE (S256),
 * as in shopify.dev/docs/api/customer. Endpoints come from the shop's discovery documents. Everything this store writes to
 * [prefs] goes through [encrypt] (an Android Keystore key, see TokenCrypto); a value [decrypt] can't open reads as signed out.
 */
class AuthStore(
    private val domain: String,
    private val clientId: String,
    private val redirectUri: String,
    private val http: OkHttpClient,
    private val prefs: DataStore<Preferences>,
    private val encrypt: (String) -> String,
    private val decrypt: (String) -> String,
    private val loadDocument: (String) -> String,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private class Tokens(val access: String, val refresh: String?, val idToken: String?, val expiresAt: Long)

    private val tokensKey = stringPreferencesKey("tokens")

    // The sign-in in progress (verifier, state, nonce) is kept on disk: the process may die while the browser is open.
    private val pendingKey = stringPreferencesKey("pending")

    // One change at a time: two refreshes with the same refresh token would get the second one refused (and sign out).
    private val lock = Mutex()
    private var loaded = false
    private var tokens: Tokens? = null
    private var pending: JsonObject? = null

    @Volatile private var openId: JsonObject? = null

    @Volatile private var graphqlUrl: HttpUrl? = null
    private val documents = ConcurrentHashMap<String, String>()

    // java.util.logging: it reaches logcat on Android and also runs in JVM tests. Only exception classes are logged, never values.
    private val log = Logger.getLogger("AuthStore")

    private val signedInState = MutableStateFlow(false)
    private val signInErrorState = MutableStateFlow<String?>(null)

    /** False until [load] (or any other call) has read the stored session. */
    val signedIn: StateFlow<Boolean> = signedInState

    /** Why the last sign-in failed once the browser came back (cancelled, refused); cleared by the next [signIn]. */
    val signInError: StateFlow<String?> = signInErrorState

    /** Reads the stored session, once. */
    suspend fun load() = lock.withLock { ensureLoaded() }

    /** Starts a sign-in: remembers a new verifier, state and nonce, then hands the authorize URL to [open] (a browser). */
    suspend fun signIn(open: (String) -> Unit) {
        val url = lock.withLock {
            ensureLoaded()
            signInErrorState.value = null
            val verifier = Pkce.verifier()
            val state = Pkce.verifier()
            val nonce = Pkce.verifier()
            // the code goes back to the token endpoint: one that isn't https stops the sign-in before the browser opens
            openId().endpoint("token_endpoint")
            val url = openId().endpoint("authorization_endpoint").newBuilder()
                .addQueryParameter("scope", "openid email customer-account-api:full")
                .addQueryParameter("client_id", clientId)
                .addQueryParameter("response_type", "code")
                .addQueryParameter("redirect_uri", redirectUri)
                .addQueryParameter("state", state)
                .addQueryParameter("nonce", nonce)
                .addQueryParameter("code_challenge", Pkce.challenge(verifier))
                .addQueryParameter("code_challenge_method", "S256")
                .build()
            setPending(buildJsonObject { put("verifier", verifier); put("state", state); put("nonce", nonce) })
            url
        }
        open(url.toString())
    }

    /**
     * The browser came back to [redirectUri] with [uri]. A callback that isn't for the sign-in in progress (none, or another
     * `state`) throws and changes nothing. Otherwise that attempt ends here: an `error` answer or a failed exchange throws and
     * sets [signInError]; a `code` is exchanged for tokens once the id_token's nonce matches.
     */
    suspend fun handleCallback(uri: String) {
        lock.withLock {
            ensureLoaded()
            val callback = URI(uri)
            val expected = URI(redirectUri)
            val params = callback.rawQuery.orEmpty().split('&').mapNotNull { pair ->
                pair.split('=', limit = 2).takeIf { it.size == 2 }?.let { (k, v) -> URLDecoder.decode(k, "UTF-8") to URLDecoder.decode(v, "UTF-8") }
            }.toMap()
            val attempt = pending
            if (callback.scheme != expected.scheme || callback.host != expected.host || attempt == null || params["state"] != attempt.str("state")) {
                throw AuthException("This sign-in link isn't for this app")
            }
            setPending(null)
            try {
                params["error"]?.let { throw AuthException(params["error_description"] ?: "Sign-in was cancelled") }
                val json = fetch(
                    tokenRequest(
                        "grant_type" to "authorization_code",
                        "client_id" to clientId,
                        "redirect_uri" to redirectUri,
                        "code" to (params["code"] ?: throw AuthException("Sign-in failed")),
                        "code_verifier" to attempt.string("verifier"),
                    ),
                )
                if (nonceOf(json.str("id_token")) != attempt.string("nonce")) throw AuthException("Sign-in couldn't be verified")
                setTokens(parseTokens(json, previous = null))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                signInErrorState.value = e.message ?: "Sign-in failed"
                throw e
            }
        }
    }

    /**
     * The access token, refreshed first when it expires within 60 s. Null when signed out, or when Shopify refuses the
     * refresh (400/401: that signs out). Any other refresh failure throws and keeps the session.
     */
    suspend fun validAccessToken(): String? = lock.withLock {
        ensureLoaded()
        val current = tokens ?: return null
        if (current.expiresAt - now() > 60_000) current.access else refresh(current)
    }

    /** Runs Customer Account API operation [name] and returns its `data`. A 401 refreshes and retries once; a second signs out. */
    suspend fun customerQuery(name: String, variables: JsonObject): JsonObject {
        val url = graphqlUrl ?: get("https://$domain/.well-known/customer-account-api").endpoint("graphql_api").also { graphqlUrl = it }
        val body = graphQLBody(withContext(Dispatchers.IO) { documents.getOrPut(name) { loadDocument(name) } }, variables)
        // The header is the bare access token, with no "Bearer" (shopify.dev/docs/api/customer, "Endpoints and queries").
        fun request(token: String) = Request.Builder().url(url).header("Authorization", token).post(body).build()

        val first = validAccessToken() ?: throw AuthException("You're signed out")
        try {
            return http.graphQL(request(first))
        } catch (e: StorefrontException) {
            if (e.status != 401) throw e
        }
        // revoked or expired early; a concurrent caller may already have refreshed it
        val second = lock.withLock { tokens?.let { if (it.access == first) refresh(it) else it.access } }
            ?: throw AuthException("You're signed out")
        try {
            return http.graphQL(request(second))
        } catch (e: StorefrontException) {
            if (e.status == 401) lock.withLock { setTokens(null) }
            throw e
        }
    }

    /**
     * Forgets the session on the device, then ends it at Shopify: a mobile client calls the logout endpoint as an API with
     * `id_token_hint` (it answers 200 instead of redirecting). That call is best-effort.
     */
    suspend fun signOut() {
        val idToken = lock.withLock {
            ensureLoaded()
            tokens?.idToken.also { setTokens(null) }
        } ?: return
        try {
            val url = openId().endpoint("end_session_endpoint").newBuilder().addQueryParameter("id_token_hint", idToken).build()
            withContext(Dispatchers.IO) { http.newCall(Request.Builder().url(url).build()).execute().close() }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // signed out on the device already; Shopify's session then simply runs out
            log.warning("logout call failed (${e.javaClass.name})")
        }
    }

    /**
     * With the lock held. Shopify refusing the refresh (400 or 401, RFC 6749 §5.2) signs out and returns null; anything else
     * (offline, 408, 429, 5xx) throws and keeps the session.
     */
    private suspend fun refresh(current: Tokens): String? {
        val refreshToken = current.refresh ?: return setTokens(null)
        val request = tokenRequest("grant_type" to "refresh_token", "client_id" to clientId, "refresh_token" to refreshToken)
        // Not cancellable: once Shopify has rotated the refresh token, the caller going away mustn't lose the new one.
        return withContext(NonCancellable) {
            val json = try {
                fetch(request)
            } catch (e: AuthException) {
                if (e.status == 400 || e.status == 401) return@withContext setTokens(null) else throw e
            }
            setTokens(parseTokens(json, previous = current))
        }
    }

    // Keystore and disk work runs on IO: callers include the main thread (the Account screen's scope).
    private suspend fun ensureLoaded() {
        if (loaded) return
        val (storedTokens, storedPending) = withContext(Dispatchers.IO) {
            val stored = prefs.safeData().first()
            open(stored[tokensKey]) to open(stored[pendingKey])
        }
        tokens = storedTokens?.let { t ->
            t.str("access")?.let { Tokens(it, t.str("refresh"), t.str("idToken"), (t["expiresAt"] as? JsonPrimitive)?.longOrNull ?: 0) }
        }
        pending = storedPending
        signedInState.value = tokens != null
        loaded = true
    }

    /** A stored value; null when there is none, or it can't be decrypted (the Keystore key is gone) or parsed. */
    private fun open(sealed: String?): JsonObject? = sealed?.let {
        try {
            Json.parseToJsonElement(decrypt(it)) as? JsonObject
        } catch (e: Exception) {
            log.warning("stored session unreadable (${e.javaClass.name})")
            null
        }
    }

    /** Sets the session and returns its access token (null: signed out). */
    private suspend fun setTokens(value: Tokens?): String? {
        tokens = value
        signedInState.value = value != null
        save(
            tokensKey,
            value?.let {
                buildJsonObject { put("access", it.access); put("refresh", it.refresh); put("idToken", it.idToken); put("expiresAt", it.expiresAt) }
            },
        )
        return value?.access
    }

    private suspend fun setPending(value: JsonObject?) {
        pending = value
        save(pendingKey, value)
    }

    // ponytail: a failed write (disk full, Keystore unavailable) only costs the session across a restart: memory stays right.
    private suspend fun save(key: Preferences.Key<String>, value: JsonObject?) {
        try {
            withContext(Dispatchers.IO) {
                val sealed = value?.let { encrypt(it.toString()) }
                prefs.edit { if (sealed == null) it.remove(key) else it[key] = sealed }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log.warning("session not saved (${e.javaClass.name})")
        }
    }

    /** A token response. A refresh answer may leave out the refresh and id tokens; the previous ones then carry on. */
    private fun parseTokens(json: JsonObject, previous: Tokens?) = Tokens(
        access = json.str("access_token") ?: throw AuthException("Sign-in failed"),
        refresh = json.str("refresh_token") ?: previous?.refresh,
        idToken = json.str("id_token") ?: previous?.idToken,
        expiresAt = now() + (json.int("expires_in") ?: 0) * 1000L,
    )

    private suspend fun tokenRequest(vararg form: Pair<String, String>) = Request.Builder()
        .url(openId().endpoint("token_endpoint"))
        .post(FormBody.Builder().apply { for ((k, v) in form) add(k, v) }.build())
        .build()

    private suspend fun openId(): JsonObject =
        openId ?: get("https://$domain/.well-known/openid-configuration").also { openId = it }

    private suspend fun get(url: String) = fetch(Request.Builder().url(url).build())

    /** The JSON a Shopify auth endpoint answered; an HTTP error is an [AuthException] with its status. */
    private suspend fun fetch(request: Request): JsonObject = withContext(Dispatchers.IO) {
        http.newCall(request).execute().use { response ->
            val json = runCatching { Json.parseToJsonElement(response.body.string()) }.getOrNull() as? JsonObject
            if (!response.isSuccessful || json == null) {
                throw AuthException(json?.str("error_description") ?: "Sign-in isn't available right now (HTTP ${response.code})", response.code)
            }
            json
        }
    }

    /** A discovered endpoint. Tokens only ever go to https. */
    private fun JsonObject.endpoint(key: String): HttpUrl =
        str(key)?.toHttpUrlOrNull()?.takeIf { it.isHttps } ?: throw AuthException("Sign-in isn't set up for this store")

    // ponytail: reads the id_token's nonce without verifying the token's signature (it came straight from the token endpoint
    // over TLS). To verify it, check the RS256 signature against the keys at the discovery document's `jwks_uri`, then iss/aud/exp.
    private fun nonceOf(idToken: String?): String? = idToken?.split('.')?.getOrNull(1)?.let { payload ->
        runCatching { (Json.parseToJsonElement(String(Base64.getUrlDecoder().decode(payload))) as? JsonObject)?.str("nonce") }.getOrNull()
    }
}
