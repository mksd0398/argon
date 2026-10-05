package app.storefront.data

import kotlinx.serialization.json.JsonObject

object Sections {
    /**
     * Sections of the `mobile_screen` metaobject in a `HomeScreen` response. Unknown types, broken references and
     * empty product/collection sections are skipped. [hosts] (`Brand.hosts`) keeps full shop URLs in banner links in-app.
     */
    fun fromHome(data: JsonObject, hosts: Set<String> = emptySet()): List<Section> =
        data.obj("metaobject")?.obj("field")?.nodes("references").orEmpty().mapNotNull { section(it, hosts) }

    private fun section(node: JsonObject, hosts: Set<String>): Section? {
        val fields = node.objects("fields").associateBy { it.str("key") }
        fun text(key: String) = fields[key]?.str("value")?.takeIf { it.isNotBlank() }
        fun reference(key: String) = fields[key]?.obj("reference")
        fun references(key: String) = fields[key]?.nodes("references").orEmpty()

        // Admin field definitions have no defaults, so blank style/limit fall back here.
        return when (node.str("type")) {
            "mobile_banner" -> Section.Banner(
                style = text("style") ?: "hero",
                image = img(reference("image")?.obj("image")),
                heading = text("heading"),
                text = text("text"),
                buttonLabel = text("button_label"),
                link = Links.resolve(text("link"), hosts),
            )
            "mobile_products" -> {
                val limit = text("limit")?.toIntOrNull()?.coerceIn(1, 24) ?: 8
                val items = references("products").cards().ifEmpty { reference("collection")?.nodes("products").orEmpty().cards() }
                Section.Products(text("heading"), text("style") ?: "carousel", items.take(limit)).takeIf { items.isNotEmpty() }
            }
            "mobile_collections" -> references("collections").filter { "id" in it }.map(::parseCollectionCard)
                .takeIf { it.isNotEmpty() }?.let { Section.Collections(text("heading"), it) }
            else -> null
        }
    }

    /** The home screen built from a `FallbackHome` response when the store has no usable `mobile_screen`. */
    fun fallback(brand: Brand, data: JsonObject): List<Section> {
        val collections = data.nodes("collections").filter { it.nodes("products").isNotEmpty() }
        return listOfNotNull(
            brand.cover?.let { Section.Banner("hero", it, null, null, null, null) },
            collections.map(::parseCollectionCard).takeIf { it.isNotEmpty() }?.let { Section.Collections(null, it) },
            collections.firstOrNull()?.let { Section.Products(it.str("title"), "carousel", it.nodes("products").cards()) },
        )
    }
}
