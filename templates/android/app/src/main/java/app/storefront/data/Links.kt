package app.storefront.data

import java.net.URI
import java.net.URLDecoder

/** The one link parser for banner links, menu items, section links and deep links. */
object Links {
    // A leading locale folder such as /fr or /en-in
    private val LOCALE = Regex("^/[a-zA-Z]{2}(-[a-zA-Z]{2})?(?=/)")
    private val WEB = setOf("http", "https")
    private val SCREEN = Regex("^app://screens/([A-Za-z0-9_-]+)/?$")
    private val TABS = setOf("cart", "account", "wishlist")

    /**
     * Maps a store path, or a full URL on one of [hosts], to an in-app route: a product, a collection, a search, a page
     * (`/pages/<h>`), a tab (`/cart`, `/account`, `/wishlist`, and `/` for home), and `app://screens/<h>` to the store's
     * custom page. Any other http(s) URL, and a store path that is none of those (such as `/blogs/news`), becomes
     * [Route.Web]; other schemes give null. [hosts] is ordered: the first is the configured SHOP_DOMAIN, which relative
     * paths are opened against.
     */
    fun resolve(link: String?, hosts: Set<String>): Route? {
        val raw = link?.trim().orEmpty().replace(" ", "%20")
        if (raw.isEmpty()) return null
        SCREEN.find(raw)?.let { return Route.Screen(it.groupValues[1]) }
        val uri = runCatching { URI(raw) }.getOrNull() ?: return null
        val absolute = uri.scheme != null
        if (absolute && uri.scheme.lowercase() !in WEB) return null
        if (absolute && hosts.none { it.equals(uri.host, ignoreCase = true) }) return Route.Web(raw)
        val path = uri.path.orEmpty().replace(LOCALE, "")
        val segments = path.split('/').filter { it.isNotEmpty() }
        return when {
            // also /collections/<c>/products/<h>
            segments.size >= 2 && segments[segments.size - 2] == "products" -> Route.Product(segments.last())
            segments.size == 2 && segments[0] == "collections" -> Route.Collection(segments[1])
            segments.size == 2 && segments[0] == "pages" -> Route.Page(segments[1])
            segments == listOf("search") -> Route.Search(param(uri, "q").orEmpty())
            segments.size == 1 && segments[0] in TABS -> Route.Tab(segments[0])
            // the store's root is home; a link without a path ("#") goes nowhere
            segments.isEmpty() -> if (path.startsWith("/")) Route.Tab("home") else null
            absolute -> Route.Web(raw)
            else -> hosts.firstOrNull()?.let { Route.Web("https://$it/${raw.trimStart('/')}") }
        }
    }

    // URLDecoder's Charset overload needs API 33, so the charset is named.
    private fun param(uri: URI, name: String) = uri.rawQuery.orEmpty().split('&')
        .firstOrNull { it.startsWith("$name=") }
        ?.let { runCatching { URLDecoder.decode(it.substringAfter('='), "UTF-8") }.getOrNull() }
}
