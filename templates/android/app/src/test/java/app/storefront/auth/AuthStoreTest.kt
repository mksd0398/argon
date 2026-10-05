package app.storefront.auth

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import app.storefront.data.StorefrontException
import java.io.File
import java.io.IOException
import java.util.Base64
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AuthStoreTest {
    @get:Rule val tmp = TemporaryFolder()
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @After fun stop() = scope.cancel()

    private var clock = 1_000_000L

    /** Every request the store made, in order. */
    private val requests = mutableListOf<Request>()
    private val paths get() = requests.map { it.url.encodedPath }

    /** The token endpoint's answer to a form: status and JSON body. */
    private var tokenReply: (Map<String, String>) -> Pair<Int, String> = { 200 to tokens("a1", "r1") }

    /** The Customer Account API's answer, by the `Authorization` header it got. */
    private var graphqlReply: (String?) -> Pair<Int, String> = { 200 to """{"data":{"customer":{"firstName":"Ada"}}}""" }

    /** The id_token's nonce; null means "echo the one the store sent". */
    private var idTokenNonce: String? = null
    private var sentNonce = ""

    private fun tokens(access: String, refresh: String?, expiresIn: Int = 3600) =
        """{"access_token":"$access",${refresh?.let { "\"refresh_token\":\"$it\"," }.orEmpty()}"id_token":"${idToken(idTokenNonce ?: sentNonce)}","expires_in":$expiresIn}"""

    private fun idToken(nonce: String): String {
        val b64 = Base64.getUrlEncoder().withoutPadding()
        return b64.encodeToString("""{"alg":"RS256"}""".toByteArray()) + "." +
            b64.encodeToString("""{"nonce":"$nonce","sub":"1"}""".toByteArray()) + ".sig"
    }

    private fun Request.form() = (body as FormBody).let { f -> (0 until f.size).associate { f.name(it) to f.value(it) } }

    // An interceptor answers every request, so nothing touches the network.
    private val http = OkHttpClient.Builder().addInterceptor { chain ->
        val request = chain.request()
        requests += request
        val (code, body) = when (request.url.encodedPath) {
            "/.well-known/openid-configuration" -> 200 to """{"authorization_endpoint":"https://shop.test/authentication/oauth/authorize",""" +
                """"token_endpoint":"https://shop.test/authentication/oauth/token","end_session_endpoint":"https://shop.test/authentication/logout"}"""
            "/.well-known/customer-account-api" -> 200 to """{"graphql_api":"https://shop.test/customer/api/2026-10/graphql"}"""
            "/authentication/oauth/token" -> tokenReply(request.form())
            "/customer/api/2026-10/graphql" -> graphqlReply(request.header("Authorization"))
            "/authentication/logout" -> 200 to ""
            else -> 404 to ""
        }
        Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(code).message("test")
            .body(body.toResponseBody("application/json".toMediaType())).build()
    }.build()

    private fun file() = File(tmp.root, "auth.preferences_pb")
    private fun disk(): DataStore<Preferences> = PreferenceDataStoreFactory.create(scope = scope) { file() }

    /** The process dies: the old DataStore is closed (DataStore allows one per file), then the file is opened again. */
    private suspend fun restart(): DataStore<Preferences> {
        scope.coroutineContext[Job]!!.cancelAndJoin()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        return disk()
    }

    private fun store(prefs: DataStore<Preferences> = disk(), decrypt: (String) -> String = { it.removePrefix("sealed:") }) = AuthStore(
        domain = "shop.test",
        clientId = "client-1",
        redirectUri = "shop.1.app://callback",
        http = http,
        prefs = prefs,
        encrypt = { "sealed:$it" },
        decrypt = decrypt,
        loadDocument = { "query $it { customer { firstName } }" },
        now = { clock },
    )

    /** Starts a sign-in and returns the authorize URL the browser was sent to. */
    private suspend fun AuthStore.start(): okhttp3.HttpUrl {
        var opened: String? = null
        signIn { opened = it }
        return opened!!.toHttpUrl().also { sentNonce = it.queryParameter("nonce")!! }
    }

    private suspend fun AuthStore.signedInStore(): AuthStore {
        val state = start().queryParameter("state")!!
        handleCallback("shop.1.app://callback?code=c1&state=$state")
        return this
    }

    @Test
    fun signInSurvivesProcessDeathAndExchangesTheCode() = runBlocking {
        val authorize = store().start()
        assertEquals("/authentication/oauth/authorize", authorize.encodedPath)
        assertEquals("openid email customer-account-api:full", authorize.queryParameter("scope"))
        assertEquals("client-1", authorize.queryParameter("client_id"))
        assertEquals("code", authorize.queryParameter("response_type"))
        assertEquals("shop.1.app://callback", authorize.queryParameter("redirect_uri"))
        assertEquals("S256", authorize.queryParameter("code_challenge_method"))
        val state = authorize.queryParameter("state")!!

        // the app is killed while the browser is open; the callback starts a new process
        val s = store(restart())
        assertFalse(s.signedIn.value)
        s.handleCallback("shop.1.app://callback?code=c1&state=$state")
        assertTrue(s.signedIn.value)
        assertEquals("a1", s.validAccessToken())

        val form = requests.last { it.url.encodedPath == "/authentication/oauth/token" }.form()
        assertEquals("authorization_code", form["grant_type"])
        assertEquals("client-1", form["client_id"])
        assertEquals("shop.1.app://callback", form["redirect_uri"])
        assertEquals("c1", form["code"])
        assertEquals(authorize.queryParameter("code_challenge"), Pkce.challenge(form.getValue("code_verifier")))

        // the tokens outlive the process, stored only through encrypt(); the pending sign-in is gone
        val saved = restart()
        val values = saved.data.first().asMap().values
        assertEquals(1, values.size)
        assertTrue(values.single().toString().startsWith("sealed:"))
        assertEquals("a1", store(saved).validAccessToken())
    }

    @Test
    fun aStateMismatchThrows() = runBlocking {
        val s = store()
        s.start()
        assertThrows(AuthException::class.java) { runBlocking { s.handleCallback("shop.1.app://callback?code=c1&state=forged") } }
        assertFalse(s.signedIn.value)
        assertFalse("no code is exchanged", "/authentication/oauth/token" in paths)
    }

    @Test
    fun aCallbackWithNoSignInInProgressIsRejected() = runBlocking {
        val s = store()
        assertThrows(AuthException::class.java) { runBlocking { s.handleCallback("shop.1.app://callback?code=c1&state=") } }
        assertEquals(emptyList<String>(), paths)
    }

    @Test
    fun aNonceMismatchIsRejected() = runBlocking {
        idTokenNonce = "replayed"
        val s = store()
        val state = s.start().queryParameter("state")!!
        assertThrows(AuthException::class.java) { runBlocking { s.handleCallback("shop.1.app://callback?code=c1&state=$state") } }
        assertFalse(s.signedIn.value)
        assertNull(s.validAccessToken())
    }

    @Test
    fun anErrorCallbackEndsTheAttemptWithoutACrash() = runBlocking {
        val s = store()
        val state = s.start().queryParameter("state")!!
        assertThrows(AuthException::class.java) {
            runBlocking { s.handleCallback("shop.1.app://callback?error=access_denied&error_description=Cancelled+by+user&state=$state") }
        }
        assertEquals("Cancelled by user", s.signInError.value)
        assertFalse(s.signedIn.value)
        assertFalse("/authentication/oauth/token" in paths)
    }

    @Test
    fun anExpiringTokenIsRefreshed() = runBlocking {
        val s = store().signedInStore()
        tokenReply = { 200 to tokens("a2", "r2") }
        clock += 3_600_000 - 30_000 // 30 s left: inside the 60 s margin
        assertEquals("a2", s.validAccessToken())
        val form = requests.last().form()
        assertEquals(mapOf("grant_type" to "refresh_token", "client_id" to "client-1", "refresh_token" to "r1"), form)
        assertTrue(s.signedIn.value)
    }

    @Test
    fun aRefusedRefreshSignsOut() = runBlocking {
        val s = store().signedInStore()
        tokenReply = { 400 to """{"error":"invalid_grant"}""" }
        clock += 3_600_000
        assertNull(s.validAccessToken())
        assertFalse(s.signedIn.value)
        assertNull("signed out on disk too", store(restart()).validAccessToken())
    }

    @Test
    fun anUnreachableOrFailingTokenEndpointKeepsTheSession() = runBlocking {
        val s = store().signedInStore()
        clock += 3_600_000
        tokenReply = { throw IOException("offline") }
        assertThrows(IOException::class.java) { runBlocking { s.validAccessToken() } }
        assertTrue(s.signedIn.value)
        // a server error isn't a refusal either
        tokenReply = { 503 to "" }
        assertThrows(AuthException::class.java) { runBlocking { s.validAccessToken() } }
        assertTrue(s.signedIn.value)
    }

    @Test
    fun unreadableStoredTokensMeanSignedOut() = runBlocking {
        store().signedInStore()
        // the Keystore key was invalidated: the ciphertext can't be opened any more
        val s = store(restart(), decrypt = { throw javax.crypto.AEADBadTagException("key gone") })
        s.load()
        assertFalse(s.signedIn.value)
        assertNull(s.validAccessToken())
    }

    @Test
    fun customerQuerySendsTheRawTokenAndRetriesOnceAfter401() = runBlocking {
        val s = store().signedInStore()
        graphqlReply = { if (it == "a1") 401 to "" else 200 to """{"data":{"customer":{"firstName":"Ada"}}}""" }
        tokenReply = { 200 to tokens("a2", "r2") }
        val data: JsonObject = s.customerQuery("Customer", JsonObject(emptyMap()))
        assertEquals("""{"customer":{"firstName":"Ada"}}""", data.toString())
        val graphql = requests.filter { it.url.encodedPath == "/customer/api/2026-10/graphql" }
        assertEquals(listOf("a1", "a2"), graphql.map { it.header("Authorization") })
    }

    @Test
    fun a401AfterRefreshSignsOut() = runBlocking {
        val s = store().signedInStore()
        graphqlReply = { 401 to "" }
        tokenReply = { 200 to tokens("a2", "r2") }
        assertThrows(StorefrontException::class.java) { runBlocking { s.customerQuery("Customer", JsonObject(emptyMap())) } }
        assertFalse(s.signedIn.value)
    }

    @Test
    fun signOutCallsLogoutWithTheIdTokenAndForgetsTheTokens() = runBlocking {
        val s = store().signedInStore()
        s.signOut()
        assertFalse(s.signedIn.value)
        val logout = requests.last()
        assertEquals("/authentication/logout", logout.url.encodedPath)
        assertEquals(idToken(sentNonce), logout.url.queryParameter("id_token_hint"))
        assertNull(store(restart()).validAccessToken())
    }
}
