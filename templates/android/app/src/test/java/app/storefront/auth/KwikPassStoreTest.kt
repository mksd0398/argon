package app.storefront.auth

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import app.storefront.data.GoKwikConfig
import java.io.File
import java.io.IOException
import java.util.Collections
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.Rule
import org.junit.rules.TemporaryFolder

class KwikPassStoreTest {
    @get:Rule val tmp = TemporaryFolder()
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @After fun stop() = scope.cancel()

    private val config = GoKwikConfig.of("shopify", "kwikpass", "mid-1", "sandbox")

    /** Every request the store made, in order, with its JSON body (requests arrive on IO threads). */
    private val requests: MutableList<Pair<Request, JsonObject?>> = Collections.synchronizedList(mutableListOf())
    private val paths get() = synchronized(requests) { requests.map { it.first.path } }
    private val Request.path get() = url.pathSegments.drop(1).joinToString("/") // after the environment's base, decoded
    private fun body(path: String) = synchronized(requests) { requests.last { it.first.path.endsWith(path) }.second!! }

    /** GoKwik's answers by path (after the environment's base): status and JSON. */
    private val replies = mutableMapOf(
        "kp/api/v1/auth/browser" to (200 to """{"success":true,"data":{"requestId":"req-1","token":"browser-1"}}"""),
        "kp/api/v1/auth/otp/send" to (200 to """{"success":true,"data":{"interval":45,"otp_required":true}}"""),
        "kp/api/v1/auth/email-otp/send" to (200 to """{"success":true,"data":{}}"""),
        "kp/api/v1/disposable-email/validate/new@b.in" to (200 to """{"success":true,"data":{"valid":true}}"""),
        "kp/api/v1/auth/validate-token" to (200 to """{"success":true,"data":{"token":{"isValid":true,"isExpired":false}}}"""),
    )
    private var offline = false

    // An interceptor answers every request, so nothing touches the network.
    private val http = OkHttpClient.Builder().addInterceptor { chain ->
        val request = chain.request()
        if (offline) throw IOException("offline")
        val sent = request.body?.let { b -> Buffer().also(b::writeTo).readUtf8() }?.let { Json.parseToJsonElement(it).jsonObject }
        requests += request to sent
        val (code, body) = replies[request.path] ?: (404 to "")
        Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(code).message("test")
            .body(body.toResponseBody("application/json".toMediaType())).build()
    }.build()

    private fun file() = File(tmp.root, "kwikpass.preferences_pb")
    private fun disk(): DataStore<Preferences> = PreferenceDataStoreFactory.create(scope = scope) { file() }

    /** The process dies: the old DataStore is closed (DataStore allows one per file), then the file is opened again. */
    private suspend fun restart(): DataStore<Preferences> {
        scope.coroutineContext[Job]!!.cancelAndJoin()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        return disk()
    }

    private fun store(prefs: DataStore<Preferences> = disk()) = KwikPassStore(
        config, http, prefs, encrypt = { "sealed:$it" }, decrypt = { it.removePrefix("sealed:") }, appVersion = "1.0", deviceId = { "device-1" },
    )

    private fun verifyReply(data: String) {
        replies["kp/api/v2/auth/otp/verify"] = 200 to """{"success":true,"data":{"token":"gk-1","coreToken":"core-1","kpToken":"kp-1",$data}}"""
    }

    @Test
    fun sendCodeGetsTheBrowserTokenFirstAndSendsTheSdkHeaders() = runBlocking {
        val s = store()
        assertEquals(45, s.sendCode("9876543210"))
        assertEquals(listOf("kp/api/v1/auth/browser", "kp/api/v1/auth/otp/send"), paths)
        val send = requests[1].first
        assertEquals("https://api-gw-v4.dev.gokwik.io/sandbox/kp/api/v1/auth/otp/send", send.url.toString())
        assertEquals("9876543210", body("otp/send").getValue("phone").jsonPrimitive.content)
        assertEquals("mid-1", send.header("gk-merchant-id"))
        assertEquals("shopify", send.header("gk-platform"))
        assertEquals("argon-android", send.header("sdk-platform"))
        assertEquals("1.0.37", send.header("sdk-version"))
        assertEquals("APP_MAKER", send.header("kp-integration-type"))
        assertEquals("android", send.header("appplatform"))
        assertEquals("1.0", send.header("appversion"))
        assertEquals("the bare browser token", "browser-1", send.header("Authorization"))
        assertEquals("req-1", send.header("gk-request-id"))
        assertEquals("req-1", send.header("kp-request-id"))
        assertNull("no session yet", send.header("gk-access-token"))
    }

    @Test
    fun aKnownEmailSignsInThroughMultipassAndSurvivesARestart() = runBlocking {
        verifyReply(""""email":"a@b.in","shopifyCustomerId":"777","state":"ENABLED"""")
        replies["kp/api/v2/customer/shopify/multipass"] = 200 to """{"success":true,"data":{"email":"a@b.in","shopifyCustomerId":777}}"""
        val s = store()
        s.sendCode("9876543210")
        assertEquals(KwikPassStep.SignedIn, s.verifyCode("1234"))

        val verify = body("otp/verify")
        assertEquals("the code goes as a number", "1234", verify.getValue("otp").toString())
        assertEquals("device-1", verify.getValue("deviceId").jsonPrimitive.content)
        val multipass = body("shopify/multipass")
        assertEquals("777", multipass.getValue("id").jsonPrimitive.content)
        assertEquals("ENABLED", multipass.getValue("state").jsonPrimitive.content)
        assertEquals("/", multipass.getValue("redirectUrl").jsonPrimitive.content)
        val last = requests.last().first
        assertEquals("gk-1", last.header("gk-access-token"))
        assertEquals("core-1", last.header("checkout-access-token"))

        assertEquals(KwikPassUser("9876543210", "a@b.in", "777"), s.user.value)
        assertEquals("+919876543210", s.user.value?.e164)
        assertEquals("core-1", s.coreToken)
        assertEquals(listOf("kp/api/v1/auth/browser", "kp/api/v1/auth/otp/send", "kp/api/v2/auth/otp/verify", "kp/api/v2/customer/shopify/multipass"), paths)

        // a new process: the session is read back, and GoKwik is asked whether it still holds
        requests.clear()
        val again = store(restart())
        again.load()
        assertEquals(KwikPassUser("9876543210", "a@b.in", "777"), again.user.value)
        assertEquals("core-1", again.coreToken)
        assertEquals(listOf("kp/api/v1/auth/validate-token"), paths)
        assertEquals("gk-1", requests.single().first.header("gk-access-token"))
    }

    @Test
    fun anEmailThatMustBeProvenGetsACodeFirst() = runBlocking {
        verifyReply(""""email":"a@b.in","shopifyCustomerId":"777","authRequired":true""")
        replies["kp/api/v1/auth/email-otp/verify"] = 200 to """{"success":true,"data":{"shopifyCustomerId":"777"}}"""
        val s = store()
        s.sendCode("9876543210")
        assertEquals(KwikPassStep.EmailCode("a@b.in"), s.verifyCode("1234"))
        assertEquals("a@b.in", body("email-otp/send").getValue("email").jsonPrimitive.content)
        assertNull("not signed in until the email is proven", s.user.value)

        assertEquals(KwikPassStep.SignedIn, s.verifyEmailCode("a@b.in", "5678"))
        assertEquals("the email code goes as text", "\"5678\"", body("email-otp/verify").getValue("otp").toString())
        assertEquals(KwikPassUser("9876543210", "a@b.in", "777"), s.user.value)
    }

    @Test
    fun aNewNumberGivesAnEmailThatGoKwikMakesACustomerFor() = runBlocking {
        verifyReply(""""emailRequired":true""")
        replies["kp/api/v1/customer/shopify-session"] = 200 to """{"success":true,"data":{"isNewUser":true,"shopifyCustomerId":"888"}}"""
        val s = store()
        s.sendCode("9876543210")
        assertEquals(KwikPassStep.EnterEmail, s.verifyCode("1234"))

        // a throwaway address is refused before anything is created
        replies["kp/api/v1/disposable-email/validate/temp@trash.in"] = 200 to """{"success":false,"data":null}"""
        assertEquals("Entered email is not valid", assertThrows(KwikPassException::class.java) { runBlocking { s.submitEmail("temp@trash.in") } }.message)

        assertEquals(KwikPassStep.SignedIn, s.submitEmail(" new@b.in "))
        assertEquals("new@b.in", body("shopify-session").getValue("email").jsonPrimitive.content)
        assertEquals(KwikPassUser("9876543210", "new@b.in", "888"), s.user.value)
    }

    @Test
    fun anEmailOfAnExistingCustomerIsProvenWithACode() = runBlocking {
        verifyReply(""""emailRequired":true""")
        replies["kp/api/v1/customer/shopify-session"] = 200 to """{"success":true,"data":{"isNewUser":false}}"""
        val s = store()
        s.sendCode("9876543210")
        s.verifyCode("1234")
        assertEquals(KwikPassStep.EmailCode("new@b.in"), s.submitEmail("new@b.in"))
        assertEquals("new@b.in", body("email-otp/send").getValue("email").jsonPrimitive.content)
    }

    @Test
    fun aNumberSeveralCustomersShareOffersTheirEmails() = runBlocking {
        verifyReply(""""multipleEmail":"a@b.in, c@d.in"""")
        val s = store()
        s.sendCode("9876543210")
        assertEquals(KwikPassStep.ChooseEmail(listOf("a@b.in", "c@d.in")), s.verifyCode("1234"))
    }

    @Test
    fun goKwiksMessageIsTheFailure() = runBlocking {
        replies["kp/api/v1/auth/otp/send"] = 400 to """{"success":false,"error":{"message":"Too many attempts"},"error_msg":"other"}"""
        val s = store()
        val e = assertThrows(KwikPassException::class.java) { runBlocking { s.sendCode("9876543210") } }
        assertEquals("Too many attempts", e.message)
        assertEquals(400, e.status)

        // a 200 that says it failed is a failure too
        replies["kp/api/v1/auth/otp/send"] = 200 to """{"success":false,"error_msg":"Invalid phone"}"""
        assertEquals("Invalid phone", assertThrows(KwikPassException::class.java) { runBlocking { s.sendCode("9876543210") } }.message)
    }

    private suspend fun signedIn(prefs: DataStore<Preferences> = disk()): KwikPassStore {
        verifyReply(""""email":"a@b.in","shopifyCustomerId":"777"""")
        replies["kp/api/v2/customer/shopify/multipass"] = 200 to """{"success":true,"data":{}}"""
        return store(prefs).also { it.sendCode("9876543210"); it.verifyCode("1234") }
    }

    @Test
    fun aSessionGoKwikRefusesSignsOutAndNoAnswerKeepsIt() = runBlocking<Unit> {
        signedIn()
        offline = true
        store(restart()).also { it.load(); assertNotNull("offline: kept", it.user.value) }
        offline = false

        replies["kp/api/v1/auth/validate-token"] = 200 to """{"success":true,"data":{"token":{"isValid":true,"isExpired":true}}}"""
        store(restart()).also { it.load(); assertNull("expired: signed out", it.user.value); assertNull(it.coreToken) }
        // and it stays signed out
        store(restart()).also { it.load(); assertNull(it.user.value) }
    }

    @Test
    fun aRefusedTokenSignsOutAndSignOutIsLocal() = runBlocking {
        signedIn()
        replies["kp/api/v1/auth/validate-token"] = 401 to """{"success":false,"error":"Unauthorized"}"""
        store(restart()).also { it.load(); assertNull(it.user.value) }

        val s = signedIn(restart())
        requests.clear()
        s.signOut()
        assertNull(s.user.value)
        assertEquals("no call for it", emptyList<String>(), paths)
        assertNull(store(restart()).also { it.load() }.user.value)
    }

    @Test
    fun indianMobileNumbers() {
        assertEquals("9876543210", indianMobile("98765 43210"))
        assertEquals("9876543210", indianMobile("+91 98765-43210"))
        assertEquals("9876543210", indianMobile("09876543210"))
        assertNull("starts 6 to 9", indianMobile("1234567890"))
        assertNull(indianMobile("987654321"))
        assertNull(indianMobile(""))
    }
}
