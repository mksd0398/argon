package app.storefront.data

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.TimeUnit
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

/** A welcome page's own words from the settings; null (or blank) keeps that page's default. */
data class RemotePage(val heading: String? = null, val text: String? = null)

/**
 * The settings the merchant edits in the Shopify app that connects this app (`SETTINGS_URL`). Every field is optional: a
 * null one keeps the value built into the app (shopify.properties). Analytics ids stay build-time and aren't read here.
 */
data class RemoteSettings(
    /** `brand.accent`, a `#RRGGBB` colour; it replaces the accent taken from the shop's brand colours. */
    val accent: String? = null,
    val homeTemplate: HomeTemplate? = null,
    val collectionTemplate: CollectionTemplate? = null,
    val onboarding: Boolean? = null,
    /** `onboarding.pages`, by position: page i's own words replace welcome page i's. */
    val pages: List<RemotePage> = emptyList(),
    /** `cart.freeShippingThreshold`: above zero, the threshold; zero, no free-shipping progress at all. */
    val freeShippingThreshold: Double? = null,
    val showVendor: Boolean? = null,
    /** `reviews.judgeMePublicToken`, never blank. */
    val judgeMeToken: String? = null,
) {
    /** The free-shipping threshold: the remote one when set (zero: none), else [builtIn]. */
    fun freeShippingThreshold(builtIn: Double?): Double? = when (val remote = freeShippingThreshold) {
        null -> builtIn
        else -> remote.takeIf { it > 0 }
    }

    /** [brand] with the remote accent, when there is one. */
    fun brand(brand: Brand): Brand = accent?.let { brand.copy(accent = it) } ?: brand

    /** [defaults] with each page's heading and text replaced by the remote ones that aren't blank. */
    fun pages(defaults: List<OnboardingPage>): List<OnboardingPage> = defaults.mapIndexed { i, page ->
        val remote = pages.getOrNull(i) ?: return@mapIndexed page
        page.copy(heading = remote.heading ?: page.heading, text = remote.text ?: page.text)
    }

    companion object {
        private val hex = Regex("#[0-9A-Fa-f]{6}")

        /**
         * The settings in [json]; null when it isn't JSON or not an object. Lenient: unknown fields are ignored, and a field
         * of the wrong type or with an invalid value is dropped on its own while the rest still applies.
         */
        fun decode(json: String): RemoteSettings? {
            val root = runCatching { Json.parseToJsonElement(json) }.getOrNull() as? JsonObject ?: return null
            val onboarding = root.obj("onboarding")
            return RemoteSettings(
                accent = root.obj("brand")?.str("accent")?.trim()?.takeIf { hex.matches(it) },
                homeTemplate = root.obj("home")?.str("template")?.let { v -> HomeTemplate.entries.firstOrNull { it.value == v.trim().lowercase() } },
                collectionTemplate = root.obj("collection")?.str("template")?.let { v -> CollectionTemplate.entries.firstOrNull { it.value == v.trim().lowercase() } },
                onboarding = onboarding?.bool("enabled"),
                // a page that isn't an object keeps its place, so the ones after it still line up
                pages = (onboarding?.get("pages") as? JsonArray).orEmpty().map { page ->
                    (page as? JsonObject).let { RemotePage(it?.str("heading")?.trim()?.ifEmpty { null }, it?.str("text")?.trim()?.ifEmpty { null }) }
                },
                freeShippingThreshold = root.obj("cart")?.num("freeShippingThreshold")?.takeIf { it >= 0 && it.isFinite() },
                showVendor = root.obj("product")?.bool("showVendor"),
                judgeMeToken = root.obj("reviews")?.str("judgeMePublicToken")?.trim()?.ifEmpty { null },
            )
        }

        private fun JsonObject.obj(key: String) = this[key] as? JsonObject
        private fun JsonObject.str(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
        private fun JsonObject.bool(key: String) = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
        private fun JsonObject.num(key: String) = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
    }
}

/**
 * The remote settings on the device. [current] is the copy an earlier launch cached in [dir] (`remote-settings.json`),
 * read once when the store is made, so the whole session runs with one set of settings. [refresh] fetches [url] and
 * caches what it gets: fetched values apply at the next launch, never in the middle of a session.
 */
class RemoteSettingsStore(dir: File, private val url: String, http: OkHttpClient) {
    private val file = File(dir, "remote-settings.json")
    private val temp = File(dir, "remote-settings.json.tmp")

    // the app's one client (same connection pool), with a short limit: settings are never worth a long wait
    private val http = http.newBuilder().callTimeout(5, TimeUnit.SECONDS).build()

    private val log = Logger.getLogger("RemoteSettings")

    /** The settings this launch runs with; null without a [url] (a stale copy is ignored), when nothing was cached, or when the copy can't be read. */
    val current: RemoteSettings? = try {
        if (url.isNotBlank() && file.exists()) RemoteSettings.decode(file.readText()) else null
    } catch (e: Exception) {
        log.warning("cached settings unreadable (${e.javaClass.name})")
        null
    }

    /**
     * Fetches [url] (nothing when it is empty) and, on HTTP 200 with a JSON object, replaces the cached copy in one step
     * (a temp file renamed over it). Any failure keeps the copy there is.
     */
    suspend fun refresh() {
        if (url.isBlank()) return
        try {
            withContext(Dispatchers.IO) {
                val body = http.newCall(Request.Builder().url(url).build()).execute().use { response ->
                    if (response.code != 200) return@withContext log.warning("settings fetch: HTTP ${response.code}")
                    response.body.string()
                }
                if (RemoteSettings.decode(body) == null) return@withContext log.warning("settings fetch: not a JSON object")
                temp.writeText(body)
                Files.move(temp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log.warning("settings fetch failed (${e.javaClass.name})")
        }
    }
}
