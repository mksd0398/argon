package app.storefront.data

import java.time.Instant
import java.time.OffsetDateTime
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull

// Screens v2 (docs/superpowers/specs/2026-10-19-screens-v2-design.md): a screen is the `app_screen` metaobject with its
// handle, whose `template` is JSON, a list of sections. contract/screens.js is the strict side (what an editor saves);
// this is the app's lenient one: nothing in a template fails a screen, a value that isn't right is its default.

/** The `app_screen` metaobject: [template] is its JSON, decoded with [ScreenTemplate.decode]. */
data class AppScreen(val id: String, val handle: String, val title: String, val template: String?, val updatedAt: String? = null)

/**
 * A screen's sections, as this app shows them: hidden ones, the other platform's and types it doesn't know are already
 * left out. [metafields]: what the template's Liquid reads, as `owner.namespace.key` (owner product, collection or shop).
 * [screen]: the screen's own look (its `screen`).
 */
data class ScreenTemplate(val sections: List<ScreenSection>, val metafields: List<String> = emptyList(), val screen: ScreenLook = ScreenLook()) {
    /** The metafields of [owner] (`product`, `collection` or `shop`) the Liquid reads. */
    fun metafields(owner: String): List<MetafieldIdentifier> = metafields.mapNotNull { ref ->
        val parts = ref.split('.')
        if (parts.size == 3 && parts[0] == owner && parts[1].isNotEmpty() && parts[2].isNotEmpty()) MetafieldIdentifier(parts[1], parts[2]) else null
    }.distinct()

    /** The sections drawn around [screen]'s own content ([Placement]); a screen without one (home, a custom page) has them all above. */
    fun placement(screen: String): Placement {
        val content = sections.filter { it.type != MAIN }
        val index = sections.indexOfFirst { it.type == MAIN }
        val main = sections.getOrNull(index)
        // no main: it goes at the end; collection and search have nothing below their infinite grid
        if (main == null || screen == "collection" || screen == "search" || screen !in SYSTEM_SCREENS) return Placement(content, main, emptyList())
        return Placement(sections.take(index).filter { it.type != MAIN }, main, sections.drop(index + 1).filter { it.type != MAIN })
    }

    companion object {
        /** The platform this app is; a section listing others only isn't shown. */
        const val PLATFORM = "android"
        const val MAIN = "main"

        /** The screens with content of their own (a `main` section): the others are home and custom pages. */
        val SYSTEM_SCREENS = setOf("product", "collection", "search", "cart", "account", "orders", "wishlist")

        /** The section types this app draws; a template's others are skipped (a newer app may know them). */
        val TYPES = setOf("banner", "slideshow", "products", "collections", "rich_text", "image_with_text", "video", "countdown", "spacer", "custom", "marquee", "faq", "features", "image_grid")

        /**
         * [json] (the metaobject's `template`) decoded leniently: not JSON, or without a list of sections, is no template
         * (null). A section without a string id or type, a hidden one, another platform's and one of an unknown type are
         * skipped.
         */
        fun decode(json: String?): ScreenTemplate? {
            val root = runCatching { Json.parseToJsonElement(json.orEmpty()) }.getOrNull() as? JsonObject ?: return null
            val sections = root["sections"] as? JsonArray ?: return null
            val ids = mutableSetOf<String>()
            return ScreenTemplate(
                sections = sections.mapNotNull { (it as? JsonObject)?.let(::section) }.filter { ids.add(it.id) },
                metafields = (root["metafields"] as? JsonArray).orEmpty().mapNotNull { it.string },
                screen = ScreenLook.decode(root["screen"] as? JsonObject),
            )
        }

        private fun section(json: JsonObject): ScreenSection? {
            val id = json["id"]?.string?.takeIf { it.isNotBlank() } ?: return null
            val type = json["type"]?.string ?: return null
            val platforms = (json["platforms"] as? JsonArray)?.mapNotNull { it.string }
            if (json["hidden"]?.boolean == true) return null
            if (platforms != null && platforms.isNotEmpty() && PLATFORM !in platforms) return null
            if (type != MAIN && type !in TYPES) return null
            val blocks = (json["blocks"] as? JsonArray).orEmpty().mapNotNull { block ->
                val obj = block as? JsonObject ?: return@mapNotNull null
                val blockId = obj["id"]?.string ?: return@mapNotNull null
                SectionBlock(blockId, obj["type"]?.string ?: return@mapNotNull null, SectionSettings(obj["settings"] as? JsonObject))
            }
            return ScreenSection(id, type, SectionSettings(json["settings"] as? JsonObject), blocks, platforms, hidden = false, track = json["track"]?.string?.takeIf { it.isNotBlank() })
        }
    }
}

/**
 * A template's `screen`, the screen's own look. [topBar]: `solid` or `transparent` (the bar over the first section, solid
 * once it scrolls under), null when unset (home then goes by `navigation.topBar.transparentOnHome`); home and custom
 * pages only. [darkTint]: the clear bar's title, icons and status bar are dark (`top_bar_tint` dark, over light
 * pictures). [background]: `#RRGGBB` behind the sections, null for the theme's.
 */
data class ScreenLook(val topBar: String? = null, val darkTint: Boolean = false, val background: String? = null) {
    companion object {
        fun decode(json: JsonObject?): ScreenLook = with(SectionSettings(json)) {
            ScreenLook(
                choice("top_bar", listOf("solid", "transparent"), "").ifEmpty { null },
                choice("top_bar_tint", listOf("light", "dark"), "light") == "dark",
                color("background", "").ifEmpty { null },
            )
        }
    }
}

/** A screen's sections around its own content: [above] it, [below] it, and [main] (its settings), when the template has one. */
data class Placement(val above: List<ScreenSection>, val main: ScreenSection?, val below: List<ScreenSection>)

/** One section of a template. [track]: its name for analytics, else its [type] ([trackName]). */
data class ScreenSection(
    val id: String,
    val type: String,
    val settings: SectionSettings,
    val blocks: List<SectionBlock> = emptyList(),
    val platforms: List<String>? = null,
    val hidden: Boolean = false,
    val track: String? = null,
) {
    val trackName: String get() = track ?: type

    /** The `background` every section type takes: `#RRGGBB` behind the whole section, edge to edge; null: none. */
    val background: String? get() = settings.color("background", "").ifEmpty { null }

    /** The `padding` every section type takes, room above and below inside its [background]: none 0, small 12, medium 24, large 40 (dp). */
    val padding: Int get() = when (settings.choice("padding", listOf("small", "medium", "large"), "none")) {
        "small" -> 12
        "medium" -> 24
        "large" -> 40
        else -> 0
    }
}

data class SectionBlock(val id: String, val type: String, val settings: SectionSettings)

private val GID = Regex("""^gid://shopify/(Product|Collection)/\d+$""")
private val COLOR = Regex("^#[0-9a-fA-F]{6}$")

/**
 * A section's (or block's) settings, read value by value: each reader gives the setting's default when it is missing or
 * isn't a right value for its type (the same lenient decoding as RemoteSettings).
 */
class SectionSettings(val json: JsonObject? = null) {
    private operator fun get(key: String): JsonElement? = json?.get(key)

    /** Text (`text`, `richtext`, `html`): null when missing or blank. May hold Liquid. */
    fun text(key: String): String? = this[key]?.string?.takeIf { it.isNotBlank() }

    /** An `image`: `{ url, alt, width, height }` with an https url; null otherwise. */
    fun image(key: String): Img? {
        val obj = this[key] as? JsonObject ?: return null
        val url = obj["url"]?.string?.takeIf { it.startsWith("https://") } ?: return null
        return Img(url, obj["alt"]?.string?.takeIf { it.isNotBlank() }, obj["width"]?.number?.toInt()?.takeIf { it > 0 }, obj["height"]?.number?.toInt()?.takeIf { it > 0 })
    }

    /** A `link` as written (resolve it with [Links.resolve]); null when missing or blank. */
    fun link(key: String): String? = text(key)

    /** A `product` or `collection` GID; null when it isn't one. */
    fun gid(key: String): String? = this[key]?.string?.takeIf { GID.matches(it) }

    /** `products` or `collections`: the GIDs of the list, each once; empty when it isn't a list. */
    fun gids(key: String): List<String> = (this[key] as? JsonArray).orEmpty().mapNotNull { it.string?.takeIf { id -> GID.matches(id) } }.distinct()

    /** A `number`, clamped to [min]...[max]; [default] when it isn't a number. */
    fun number(key: String, default: Double, min: Double, max: Double): Double = this[key]?.number?.coerceIn(min, max) ?: default

    fun boolean(key: String, default: Boolean): Boolean = this[key]?.boolean ?: default

    /** A `color` as `#RRGGBB` (upper case); [default] otherwise. */
    fun color(key: String, default: String): String = this[key]?.string?.takeIf { COLOR.matches(it) }?.uppercase() ?: default

    /** A `choice`: one of [choices]; [default] otherwise. */
    fun choice(key: String, choices: List<String>, default: String): String = this[key]?.string?.takeIf { it in choices } ?: default

    /** A `datetime` (ISO 8601); null when it can't be read. */
    fun datetime(key: String): Instant? = this[key]?.string?.let { value ->
        runCatching { Instant.parse(value) }.getOrNull() ?: runCatching { OffsetDateTime.parse(value).toInstant() }.getOrNull()
    }

    /** The settings as Liquid values: a section's `section.settings`, a block's `block.settings`. */
    @Suppress("UNCHECKED_CAST")
    val liquid: Map<String, Any?> get() = json?.let { Liquid.value(it) as Map<String, Any?> }.orEmpty()

    override fun equals(other: Any?) = other is SectionSettings && other.json == json
    override fun hashCode() = json.hashCode()
    override fun toString() = json.toString()
}

private val JsonElement.string: String? get() = (this as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
private val JsonElement.boolean: Boolean? get() = (this as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
private val JsonElement.number: Double? get() = (this as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull?.takeIf { it.isFinite() }

// ─── The catalogue: each type's settings with their defaults and limits (contract/screens.js) ─────

/** A slideshow's slide, or a banner: its picture, words and link (still Liquid, as written). */
data class Slide(val id: String?, val image: Img?, val heading: String?, val text: String?, val buttonLabel: String?, val link: String?)

/** A section's settings, read by its type. Text fields are as written (Liquid not yet evaluated). */
sealed interface SectionContent {
    data class Banner(val slide: Slide, val style: String, val height: String, val textColor: String) : SectionContent
    data class Slideshow(val autoplay: Boolean, val interval: Int, val height: String, val slides: List<Slide>) : SectionContent
    data class Products(val heading: String?, val collection: String?, val products: List<String>, val style: String, val limit: Int, val showAll: Boolean) : SectionContent
    data class Collections(val heading: String?, val collections: List<String>, val style: String) : SectionContent
    data class RichText(val heading: String?, val text: String?, val alignment: String) : SectionContent
    data class ImageWithText(val image: Img?, val heading: String?, val text: String?, val buttonLabel: String?, val link: String?, val imagePosition: String) :
        SectionContent
    data class Video(val url: String?, val poster: Img?, val autoplay: Boolean, val loop: Boolean, val muted: Boolean, val aspect: String) : SectionContent {
        /** Width over height of [aspect] ("16:9" is 1.78). */
        val ratio: Float get() = aspect.split(':').let { (w, h) -> w.toFloat() / h.toFloat() }
    }
    data class Countdown(val heading: String?, val text: String?, val endsAt: Instant?, val link: String?, val hideWhenOver: Boolean) : SectionContent
    data class Spacer(val height: Int, val divider: Boolean) : SectionContent

    /** [nodes]: Krypton's compiled tree; drawn natively only when [render] is native and there are some, else [html] in a web view. */
    data class Custom(val html: String?, val render: String, val nodes: List<CustomNode>, val height: Int) : SectionContent {
        val isNative: Boolean get() = render == "native" && nodes.isNotEmpty()
    }

    /** One line of [text] scrolling without end at [speed] dp a second (slow 30, medium 60, fast 90); the strip opens [link]. */
    data class Marquee(val text: String?, val link: String?, val speed: Int, val textColor: String) : SectionContent

    /** An accordion of [questions], all closed; a block without its question is skipped. */
    data class Faq(val heading: String?, val questions: List<Question>) : SectionContent
    data class Question(val block: SectionBlock, val question: String, val answer: String?)

    /** [features] (up to 8) in a sideways `row` or a two-column `grid` ([layout]). */
    data class Features(val heading: String?, val layout: String, val features: List<Feature>) : SectionContent

    /** [icon]: one of [FEATURE_ICONS]. */
    data class Feature(val block: SectionBlock, val icon: String, val heading: String?, val text: String?)

    /** [tiles] (up to 12; one without an image is skipped) in [columns] columns, each [ratio] wide over high by its [aspect]. */
    data class ImageGrid(val heading: String?, val columns: Int, val aspect: String, val tiles: List<Tile>) : SectionContent {
        val ratio: Float get() = when (aspect) {
            "portrait" -> 4f / 5f
            "landscape" -> 4f / 3f
            else -> 1f
        }
    }
    data class Tile(val block: SectionBlock, val image: Img, val heading: String?, val link: String?)
}

/** The icons a feature block can show (contract/screens.js FEATURE_ICONS): Argon's icon set, snake_case. */
val FEATURE_ICONS = listOf("truck", "returns", "lock", "leaf", "gift", "clock", "star", "heart", "globe", "check", "tag", "phone", "mail", "location", "info")

private val HEIGHTS = listOf("small", "medium", "large")

private fun SectionSettings.slide(id: String?) = Slide(id, image("image"), text("heading"), text("text"), text("button_label"), link("link"))

/** The section's settings read by its type ([SectionContent]); null for `main` and for a type this app doesn't know. */
val ScreenSection.content: SectionContent?
    get() = with(settings) {
        when (type) {
            "banner" -> SectionContent.Banner(slide(null), choice("style", listOf("hero", "card"), "hero"), choice("height", HEIGHTS, "large"), color("text_color", "#FFFFFF"))
            "slideshow" -> SectionContent.Slideshow(
                boolean("autoplay", true),
                number("interval", 5.0, 3.0, 15.0).toInt(),
                choice("height", HEIGHTS, "large"),
                blocks.filter { it.type == "slide" }.take(10).map { it.settings.slide(it.id) },
            )
            "products" -> SectionContent.Products(
                text("heading"), gid("collection")?.takeIf { "/Collection/" in it }, gids("products").filter { "/Product/" in it },
                choice("style", listOf("carousel", "grid"), "carousel"), number("limit", 8.0, 1.0, 24.0).toInt(), boolean("show_all", true),
            )
            "collections" -> SectionContent.Collections(text("heading"), gids("collections").filter { "/Collection/" in it }, choice("style", listOf("circles", "grid", "list"), "circles"))
            "rich_text" -> SectionContent.RichText(text("heading"), text("text"), choice("alignment", listOf("start", "center"), "start"))
            "image_with_text" -> SectionContent.ImageWithText(
                image("image"), text("heading"), text("text"), text("button_label"), link("link"), choice("image_position", listOf("start", "end"), "start"),
            )
            "video" -> SectionContent.Video(
                text("url")?.takeIf { it.startsWith("https://") }, image("poster"), boolean("autoplay", true), boolean("loop", true), boolean("muted", true),
                choice("aspect", listOf("16:9", "9:16", "1:1", "4:5"), "16:9"),
            )
            "countdown" -> SectionContent.Countdown(text("heading"), text("text"), datetime("ends_at"), link("link"), boolean("hide_when_over", true))
            "spacer" -> SectionContent.Spacer(number("height", 24.0, 4.0, 120.0).toInt(), boolean("divider", false))
            "custom" -> SectionContent.Custom(
                text("html"), choice("render", listOf("native", "web"), "web"), CustomNode.decode(json?.get("nodes")), number("height", 0.0, 0.0, 2000.0).toInt(),
            )
            "marquee" -> SectionContent.Marquee(
                text("text"), link("link"), when (choice("speed", listOf("slow", "medium", "fast"), "medium")) { "slow" -> 30; "fast" -> 90; else -> 60 },
                color("text_color", "#FFFFFF"),
            )
            "faq" -> SectionContent.Faq(
                text("heading"),
                blocksOf("question", 20).mapNotNull { b -> b.settings.text("question")?.let { SectionContent.Question(b, it, b.settings.text("answer")) } },
            )
            "features" -> SectionContent.Features(
                text("heading"), choice("layout", listOf("row", "grid"), "row"),
                blocksOf("feature", 8).map { SectionContent.Feature(it, it.settings.choice("icon", FEATURE_ICONS, "check"), it.settings.text("heading"), it.settings.text("text")) },
            )
            "image_grid" -> SectionContent.ImageGrid(
                text("heading"), choice("columns", listOf("2", "3"), "2").toInt(), choice("aspect", listOf("square", "portrait", "landscape"), "square"),
                blocksOf("tile", 12).mapNotNull { b -> b.settings.image("image")?.let { SectionContent.Tile(b, it, b.settings.text("heading"), b.settings.link("link")) } },
            )
            else -> null
        }
    }

/** The section's blocks of [type], the first [max]. */
private fun ScreenSection.blocksOf(type: String, max: Int) = blocks.filter { it.type == type }.take(max)

/** The PDP blocks of the product screen's `main.blocks` (contract/screens.js PRODUCT_BLOCKS), in their default order. */
val PRODUCT_BLOCKS = listOf("gallery", "title", "price", "options", "purchase", "bundle", "details", "reviews", "rails")

/**
 * The product page's blocks to show, in order, by [main]'s `blocks`: the listed ones in their order (unknown names
 * ignored, each once), then those it doesn't list in their default order; hidden ones left out. No main, or no list:
 * all of them as usual.
 */
fun productBlocks(main: ScreenSection?): List<String> {
    val listed = (main?.settings?.json?.get("blocks") as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
        .mapNotNull { block -> block["type"]?.string?.takeIf { it in PRODUCT_BLOCKS }?.let { it to (block["hidden"]?.boolean == true) } }
        .distinctBy { it.first }
    val order = listed.map { it.first } + PRODUCT_BLOCKS.filter { name -> listed.none { it.first == name } }
    val hidden = listed.filter { it.second }.map { it.first }.toSet()
    return order.filter { it !in hidden }
}

/** The collection screen's `main.filters` (`top` or `bottom`), which overrides the collection template; null when unset. */
fun collectionFilters(main: ScreenSection?): CollectionTemplate? =
    main?.settings?.choice("filters", listOf("top", "bottom"), "")?.takeIf { it.isNotEmpty() }?.let(CollectionTemplate::of)

// ─── The custom section's nodes ───────────────────────────────────────────

/** A run of a paragraph or list item: [text] (may hold Liquid), with its emphasis and an optional [link]. */
data class TextRun(val text: String, val bold: Boolean = false, val italic: Boolean = false, val link: String? = null)

/** One node of a custom section's compiled tree (spec: Custom section). Unknown node types are skipped. */
sealed interface CustomNode {
    data class Heading(val level: Int, val text: String) : CustomNode
    data class Paragraph(val runs: List<TextRun>) : CustomNode
    data class Bullets(val ordered: Boolean, val items: List<List<TextRun>>) : CustomNode
    data class Image(val url: String, val alt: String?, val link: String?) : CustomNode
    data class Button(val label: String, val link: String?) : CustomNode
    data object Divider : CustomNode
    data class Product(val id: String) : CustomNode
    data class Collection(val id: String, val limit: Int) : CustomNode

    companion object {
        /** [json] (the `nodes` setting) as nodes; anything that isn't a node this app knows is skipped. */
        fun decode(json: JsonElement?): List<CustomNode> = (json as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(::node) }

        private fun runs(json: JsonElement?): List<TextRun> = (json as? JsonArray).orEmpty().mapNotNull { element ->
            val run = element as? JsonObject ?: return@mapNotNull null
            TextRun(run["text"]?.string ?: return@mapNotNull null, run["bold"]?.boolean == true, run["italic"]?.boolean == true, run["link"]?.string?.takeIf { it.isNotBlank() })
        }

        private fun node(json: JsonObject): CustomNode? {
            fun s(key: String) = json[key]?.string
            return when (s("type")) {
                "heading" -> Heading(json["level"]?.number?.toInt()?.coerceIn(1, 3) ?: 2, s("text") ?: return null)
                "paragraph" -> Paragraph(runs(json["runs"]))
                "list" -> Bullets(json["ordered"]?.boolean == true, (json["items"] as? JsonArray).orEmpty().map(::runs))
                "image" -> Image(s("url")?.takeIf { it.startsWith("https://") } ?: return null, s("alt")?.takeIf { it.isNotBlank() }, s("link")?.takeIf { it.isNotBlank() })
                "button" -> Button(s("label") ?: return null, s("link")?.takeIf { it.isNotBlank() })
                "divider" -> Divider
                "product" -> Product(s("id")?.takeIf { GID.matches(it) && "/Product/" in it } ?: return null)
                "collection" -> Collection(s("id")?.takeIf { GID.matches(it) && "/Collection/" in it } ?: return null, json["limit"]?.number?.toInt()?.coerceIn(1, 24) ?: 8)
                else -> null
            }
        }
    }
}

/**
 * Every product and collection GID the [sections] show (their settings and their custom sections' nodes), each once:
 * what one `SectionNodes` query loads for the whole screen.
 */
fun sectionNodeIds(sections: List<ScreenSection>): List<String> = sections.flatMap { section ->
    when (val content = section.content) {
        is SectionContent.Products -> listOfNotNull(content.collection) + content.products
        is SectionContent.Collections -> content.collections
        is SectionContent.Custom -> if (!content.isNative) emptyList() else content.nodes.mapNotNull {
            when (it) {
                is CustomNode.Product -> it.id
                is CustomNode.Collection -> it.id
                else -> null
            }
        }
        else -> emptyList()
    }
}.distinct()

/** What `SectionNodes` loaded, by GID: a section whose ids aren't here draws what it can, or nothing. */
data class SectionNodes(val products: Map<String, ProductCard> = emptyMap(), val collections: Map<String, CollectionCard> = emptyMap())

// ─── Liquid's objects (spec: Liquid, Objects) ─────────────────────────────

object ScreenContext {
    /**
     * `metafields.<namespace>.<key>`: each value as text, or parsed when its type is JSON (lists, numbers, booleans,
     * json).
     */
    fun metafields(metafields: List<Metafield>): Map<String, Any?> =
        metafields.groupBy { it.namespace }.mapValues { (_, list) -> list.associate { it.key to value(it) } }

    private fun value(metafield: Metafield): Any? {
        val type = metafield.type.orEmpty()
        val parsed = type == "json" || type == "boolean" || type.startsWith("number_") || type.startsWith("list.") || type == "rating" || type == "dimension"
        if (!parsed) return metafield.value
        return runCatching { Liquid.value(Json.parseToJsonElement(metafield.value)) }.getOrDefault(metafield.value)
    }

    fun shop(shop: Shop?, metafields: List<Metafield>): Map<String, Any?> =
        mapOf("name" to shop?.name, "currency" to shop?.paymentSettings?.currencyCode, "metafields" to metafields(metafields))

    fun product(product: Product, metafields: List<Metafield>): Map<String, Any?> {
        val variant = product.selectedOrFirstAvailableVariant ?: product.variants.firstOrNull()
        return mapOf(
            "title" to product.title, "handle" to product.handle, "vendor" to product.vendor, "type" to product.productType, "tags" to product.tags,
            "price" to (variant?.price?.amount ?: product.priceRange?.minVariantPrice?.amount), "compare_at_price" to variant?.compareAt?.amount,
            "available" to product.availableForSale, "url" to "/products/${product.handle}", "metafields" to metafields(metafields),
        )
    }

    fun collection(handle: String, title: String, description: String, metafields: List<Metafield>): Map<String, Any?> = mapOf(
        "title" to title, "handle" to handle, "description" to description, "url" to "/collections/$handle", "metafields" to metafields(metafields),
    )

    fun customer(customer: Customer): Map<String, Any?> =
        mapOf("first_name" to customer.firstName, "last_name" to customer.lastName, "email" to customer.email)

    fun cart(cart: Cart?): Map<String, Any?> = mapOf("item_count" to (cart?.totalQuantity ?: 0).toLong(), "total_price" to (cart?.total?.amount ?: "0.0"))

    /** [context] with a section's `section` (and a block's `block`) added: what a section's text is evaluated with. */
    fun forSection(context: Map<String, Any?>, section: ScreenSection, block: SectionBlock? = null): Map<String, Any?> =
        context + ("section" to mapOf("id" to section.id, "settings" to section.settings.liquid)) +
            (if (block != null) mapOf("block" to mapOf("id" to block.id, "settings" to block.settings.liquid)) else emptyMap())
}
