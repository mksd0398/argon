package app.storefront.data

import java.io.File
import java.io.IOException
import kotlinx.coroutines.runBlocking
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RemoteSettingsTest {
    @get:Rule val tmp = TemporaryFolder()

    private val full = """
        {
          "version": 1,
          "brand": { "accent": "#1F6FEB" },
          "home": { "template": "beauty" },
          "collection": { "template": "bottom" },
          "onboarding": { "enabled": false, "pages": [ { "heading": "Hello", "text": "" }, { "heading": " ", "text": "Fast" } ] },
          "cart": { "freeShippingThreshold": 50 },
          "product": { "showVendor": true },
          "reviews": { "judgeMePublicToken": "jm-1" },
          "analytics": { "metaAppId": "123", "serverPurchase": true }
        }
    """.trimIndent()

    // Decoding

    @Test
    fun decodesEveryField() {
        val s = RemoteSettings.decode(full)!!
        assertEquals("#1F6FEB", s.accent)
        assertEquals(HomeTemplate.Beauty, s.homeTemplate)
        assertEquals(CollectionTemplate.Bottom, s.collectionTemplate)
        assertEquals(false, s.onboarding)
        assertEquals(listOf(RemotePage("Hello", null), RemotePage(null, "Fast")), s.pages)
        assertEquals(50.0, s.freeShippingThreshold)
        assertEquals(true, s.showVendor)
        assertEquals("jm-1", s.judgeMeToken)
    }

    @Test
    fun aWrongTypeOrInvalidValueIsDroppedOnItsOwn() {
        val s = RemoteSettings.decode(
            """
            {
              "brand": { "accent": "blue" },
              "home": { "template": "furniture" },
              "collection": { "template": 3 },
              "onboarding": { "enabled": "yes", "pages": [ "nope", { "heading": 5, "text": "Second" } ] },
              "cart": { "freeShippingThreshold": "50" },
              "product": { "showVendor": 1 },
              "reviews": { "judgeMePublicToken": "" },
              "extra": { "anything": [1, 2] }
            }
            """.trimIndent(),
        )!!
        assertEquals(RemoteSettings(pages = listOf(RemotePage(), RemotePage(null, "Second"))), s)
        assertNull("a negative threshold", RemoteSettings.decode("""{"cart":{"freeShippingThreshold":-1}}""")!!.freeShippingThreshold)
        assertEquals(RemoteSettings(), RemoteSettings.decode("""{"brand":"#000000","home":[],"cart":null}"""))
    }

    @Test
    fun garbageIsNoSettings() {
        for (json in listOf("", "not json", "[1,2]", "\"text\"", "42", "null", "{\"brand\":")) assertNull(json, RemoteSettings.decode(json))
    }

    // Overrides

    private val brand = Brand("Maison", logo = null, cover = null, accent = "#AA0000", hosts = emptySet())

    @Test
    fun theFreeShippingThresholdIsTheRemoteOneZeroMeansNone() {
        assertEquals(50.0, RemoteSettings(freeShippingThreshold = 50.0).freeShippingThreshold(builtIn = 80.0))
        assertNull(RemoteSettings(freeShippingThreshold = 0.0).freeShippingThreshold(builtIn = 80.0))
        assertEquals(80.0, RemoteSettings().freeShippingThreshold(builtIn = 80.0))
        assertNull(RemoteSettings().freeShippingThreshold(builtIn = null))
    }

    @Test
    fun theRemoteAccentReplacesTheBrands() {
        assertEquals("#1F6FEB", RemoteSettings(accent = "#1F6FEB").brand(brand).accent)
        assertEquals(brand, RemoteSettings().brand(brand))
    }

    @Test
    fun remoteWordsReplaceTheWelcomePagesByPosition() {
        val defaults = Onboarding.pages(brand, HomeTemplate.Fashion)
        val pages = RemoteSettings.decode(full)!!.pages(defaults)
        assertEquals(listOf("Hello", "Find it fast", "Checkout in a few taps"), pages.map { it.heading })
        assertEquals(listOf(defaults[0].text, "Fast", defaults[2].text), pages.map { it.text })
        assertEquals(defaults.map { it.image }, pages.map { it.image })
        assertEquals(defaults, RemoteSettings().pages(defaults))
    }

    // The cache

    /** The answer to every fetch: status and body, or a failure. */
    private var reply: () -> Pair<Int, String> = { 200 to """{"home":{"template":"grocery"}}""" }
    private var fetches = 0

    private val http = OkHttpClient.Builder().addInterceptor { chain ->
        fetches++
        val (code, body) = reply()
        Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(code).message("test")
            .body(body.toResponseBody("application/json".toMediaType())).build()
    }.build()

    private fun store(url: String = "https://settings.test/v1/settings/shop.test") = RemoteSettingsStore(tmp.root, url, http)
    private fun cached() = File(tmp.root, "remote-settings.json")

    @Test
    fun aFetchAppliesAtTheNextLaunch() = runBlocking {
        val first = store()
        assertNull("nothing cached yet", first.current)
        first.refresh()
        assertNull("not in the middle of a session", first.current)
        assertEquals(HomeTemplate.Grocery, store().current?.homeTemplate)
        assertFalse("no temp file left", File(tmp.root, "remote-settings.json.tmp").exists())
    }

    @Test
    fun aFailedFetchKeepsTheCache() = runBlocking {
        store().refresh()
        val saved = cached().readText()
        for (failure in listOf<() -> Pair<Int, String>>({ 500 to "{}" }, { 404 to "" }, { 200 to "<html>" }, { 200 to "[]" }, { throw IOException("offline") })) {
            reply = failure
            store().refresh()
            assertEquals(saved, cached().readText())
        }
        assertEquals(HomeTemplate.Grocery, store().current?.homeTemplate)
    }

    @Test
    fun noUrlNoFetchAndAnUnreadableCacheIsNoSettings() = runBlocking {
        store(url = "").refresh()
        assertEquals(0, fetches)
        assertFalse(cached().exists())
        cached().writeText("{ broken")
        assertNull(store().current)
        // a copy left from a build that had a settings URL means nothing to one without
        store().refresh()
        assertNotNull(store().current)
        assertNull(store(url = "").current)
    }
}
