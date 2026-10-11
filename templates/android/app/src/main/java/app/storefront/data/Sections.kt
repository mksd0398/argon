package app.storefront.data

/**
 * What a home template shows, whatever the store has set up: [banners] (the hero and the cards between the rails),
 * [categories] (the collections to shop by) and [rails] (titled product rows).
 */
data class HomeContent(val banners: List<Section.Banner>, val categories: List<CollectionCard>, val rails: List<Section.Products>) {
    /** Nothing to shop yet: a template keeps its banners and says so under them. */
    val isEmpty: Boolean get() = categories.isEmpty() && rails.isEmpty()
}

/** The placeholder banners bundled with the app (`assets/home/`, see templates/images/CREDITS.md), shown until the store has its own. */
object StockImages {
    /** The URL of [template]'s banner [index] (1...3); the app's image view loads it from the APK. */
    fun url(template: HomeTemplate, index: Int): String = "file:///android_asset/home/home-${template.value}-$index.jpg"
}

object Sections {
    /**
     * The home screen's content for [template]. Each part is the store's own when its `mobile_screen` has it ([sections],
     * from [fromHome]), else made from the fallback home's [collections] (the stocked ones):
     * - banners: the store's banners, else the template's three stock banners, each linking to the first stocked collection
     *   (nowhere when there is none);
     * - categories: the collections of the store's collection sections, else the stocked collections;
     * - rails: the store's product sections, else one per stocked collection, titled with it.
     */
    @Suppress("UNUSED_PARAMETER") // brand: part of the signature both platforms share; nothing reads it yet
    fun content(template: HomeTemplate, brand: Brand, sections: List<Section>, collections: List<CollectionCard>): HomeContent {
        val stocked = collections.filter { it.products.isNotEmpty() }
        val link = stocked.firstOrNull()?.let { Route.Collection(it.handle) }
        return HomeContent(
            banners = sections.filterIsInstance<Section.Banner>().ifEmpty {
                template.bannerCopy.mapIndexed { i, (heading, button) ->
                    Section.Banner("hero", Img(StockImages.url(template, i + 1)), heading, null, button, link)
                }
            },
            // each collection once: a list keyed by id must not get one twice
            categories = sections.filterIsInstance<Section.Collections>().flatMap { it.items }.distinctBy { it.id }.ifEmpty { stocked },
            rails = sections.filterIsInstance<Section.Products>().ifEmpty { stocked.map { Section.Products(it.title, "carousel", it.products) } },
        )
    }

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
