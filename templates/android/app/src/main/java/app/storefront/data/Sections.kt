package app.storefront.data

object Sections {
    /**
     * The home [sections] (the `mobile_screen` metaobject's entries) the app can show. Unknown types and empty
     * product/collection sections are skipped. [hosts] (`Brand.hosts`) keeps full shop URLs in banner links in-app.
     */
    fun fromHome(sections: List<Metaobject>, hosts: Set<String> = emptySet()): List<Section> = sections.mapNotNull { section(it, hosts) }

    private fun section(node: Metaobject, hosts: Set<String>): Section? {
        fun text(key: String) = node.field(key)?.value?.takeIf { it.isNotBlank() }
        fun reference(key: String) = node.field(key)?.reference
        fun references(key: String) = node.field(key)?.references.orEmpty()

        // Admin field definitions have no defaults, so blank style/limit fall back here.
        return when (node.type) {
            "mobile_banner" -> Section.Banner(
                style = text("style") ?: "hero",
                image = (reference("image") as? Reference.Image)?.image,
                heading = text("heading"),
                text = text("text"),
                buttonLabel = text("button_label"),
                link = Links.resolve(text("link"), hosts),
            )
            "mobile_products" -> {
                val limit = text("limit")?.toIntOrNull()?.coerceIn(1, 24) ?: 8
                val items = references("products").filterIsInstance<ProductCard>()
                    .ifEmpty { (reference("collection") as? CollectionCard)?.products.orEmpty() }
                Section.Products(text("heading"), text("style") ?: "carousel", items.take(limit)).takeIf { items.isNotEmpty() }
            }
            "mobile_collections" -> references("collections").filterIsInstance<CollectionCard>()
                .takeIf { it.isNotEmpty() }?.let { Section.Collections(text("heading"), it) }
            else -> null
        }
    }

    /** The home screen built from the fallback home's [collections] when the store has no usable `mobile_screen`. */
    fun fallback(brand: Brand, collections: List<CollectionCard>): List<Section> {
        val stocked = collections.filter { it.products.isNotEmpty() }
        return listOfNotNull(
            brand.cover?.let { Section.Banner("hero", it, null, null, null, null) },
            stocked.takeIf { it.isNotEmpty() }?.let { Section.Collections(null, it) },
            stocked.firstOrNull()?.let { Section.Products(it.title, "carousel", it.products) },
        )
    }
}
