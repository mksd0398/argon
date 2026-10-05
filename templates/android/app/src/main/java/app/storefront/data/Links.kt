package app.storefront.data

import java.net.URI
import java.net.URLDecoder

/** The one link parser for banner links, menu items and deep links. */
object Links {
    // A leading locale folder such as /fr or /en-in
    private val LOCALE = Regex("^/[a-zA-Z]{2}(-[a-zA-Z]{2})?(?=/)")
    private val WEB = setOf("http", "https")

    /**
     * Maps a store path, or a full URL on one of [hosts], to an in-app route. Any other http(s) URL, and a store path
     * that isn't a product, collection or search (such as `/pages/shipping`), becomes [Route.Web]; other schemes give null.
     * [hosts] is ordered: the first is the configured SHOP_DOMAIN, which relative paths are opened against.
     */
    fun resolve(link: String?, hosts: Set<String>): Route? {
        val raw = link?.trim().orEmpty().replace(" ", "%20")
        val uri = runCatching { URI(raw) }.getOrNull() ?: return null
        val absolute = uri.scheme != null
        if (absolute && uri.scheme.lowercase() !in WEB) return null
        if (absolute && hosts.none { it.equals(uri.host, ignoreCase = true) }) return Route.Web(raw)
        val segments = uri.path.orEmpty().replace(LOCALE, "").split('/').filter { it.isNotEmpty() }
        return when {
            // also /collections/<c>/products/<h>
            segments.size >= 2 && segments[segments.size - 2] == "products" -> Route.Product(segments.last())
            segments.size == 2 && segments[0] == "collections" -> Route.Collection(segments[1])
            segments == listOf("search") -> Route.Search(param(uri, "q").orEmpty())
            segments.isEmpty() -> null
            absolute -> Route.Web(raw)
            else -> hosts.firstOrNull()?.let { Route.Web("https://$it/${raw.trimStart('/')}") }
        }
    }

    // URLDecoder's Charset overload needs API 33, so the charset is named.
    private fun param(uri: URI, name: String) = uri.rawQuery.orEmpty().split('&')
        .firstOrNull { it.startsWith("$name=") }
        ?.let { runCatching { URLDecoder.decode(it.substringAfter('='), "UTF-8") }.getOrNull() }
}
