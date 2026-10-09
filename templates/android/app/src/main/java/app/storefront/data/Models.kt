package app.storefront.data

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonContentPolymorphicSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

// Storefront API models, decoded from the responses of contract/queries (fragments in contract/fragments.graphql).
// Property names are the GraphQL field names, except where screens already used another name (@SerialName). Enums stay
// Shopify's strings, money its decimal strings and dates ISO-8601 strings: formatting is the UI's job.

@Serializable
data class Money(val amount: String, val currencyCode: String) : PricingValue

@Serializable
data class Img(val url: String, @SerialName("altText") val alt: String? = null, val width: Int? = null, val height: Int? = null)

@Serializable
data class Seo(val title: String? = null, val description: String? = null)

/** A cart or line attribute; also the `AttributeInput` (whose `value` is required). */
@Serializable
data class Attribute(val key: String, val value: String? = null)

/** A resource by handle, with its title and (an article's) blog where the document selects them. */
@Serializable
data class ResourceRef(val handle: String, val title: String? = null, val blog: ResourceRef? = null)

/** One of a mutation's `userErrors`: [field] is the input path it is about, [code] Shopify's error code (may be null). */
@Serializable
data class UserError(val field: List<String>? = null, val message: String, val code: String? = null)

/**
 * One page of a list. Pass [endCursor] as `after` for the next page while [hasNextPage]. [filters]: the facets Shopify
 * offers for a product list (collection products, search results); empty for every other list.
 */
@Serializable(with = PageSerializer::class)
data class Page<T>(
    val items: List<T>,
    val endCursor: String? = null,
    val hasNextPage: Boolean = false,
    val filters: List<Filter> = emptyList(),
)

@Serializable
data class Filter(val id: String, val label: String, val type: String, val values: List<FilterValue> = emptyList())

/** [input]: the `ProductFilter` JSON that applies this value (send it back in `filters`). */
@Serializable
data class FilterValue(val id: String, val label: String, val count: Int = 0, @Serializable(with = JsonTextSerializer::class) val input: String)

@Serializable
data class PriceRange(val minVariantPrice: Money, val maxVariantPrice: Money? = null)

// Shopify reports "no compare-at" as null or 0.0; only a higher compare-at is a real discount.
private fun Money?.above(price: Money) = this?.takeIf { it.amount.toBigDecimal() > price.amount.toBigDecimal() }

@Serializable
data class ProductCard(
    val id: String,
    val handle: String,
    val title: String,
    @SerialName("availableForSale") val available: Boolean = false,
    @SerialName("featuredImage") val image: Img? = null,
    val priceRange: PriceRange,
    val compareAtPriceRange: PriceRange? = null,
) : Reference, SearchResult {
    val price: Money get() = priceRange.minVariantPrice
    val compareAt: Money? get() = compareAtPriceRange?.minVariantPrice.above(price)
}

/** [products]: the first products, where the document selects them (home sections, the fallback home). */
@Serializable
data class CollectionCard(
    val id: String,
    val handle: String,
    val title: String,
    val image: Img? = null,
    val description: String? = null,
    @Serializable(with = NodesSerializer::class) val products: List<ProductCard> = emptyList(),
) : Reference

/** A collection with a page of its products and their filters. */
@Serializable
data class CollectionDetail(
    val id: String,
    val handle: String,
    val title: String,
    val description: String = "",
    val seo: Seo? = null,
    val image: Img? = null,
    val products: Page<ProductCard>,
)

@Serializable
data class SelectedOption(val name: String, val value: String)

@Serializable
data class Variant(
    val id: String,
    val title: String,
    @SerialName("availableForSale") val available: Boolean = false,
    val sku: String? = null,
    val selectedOptions: List<SelectedOption> = emptyList(),
    val price: Money,
    val compareAtPrice: Money? = null,
    val image: Img? = null,
) {
    /** Option name to value, e.g. Size to M. */
    val options: Map<String, String> get() = selectedOptions.associate { it.name to it.value }
    val compareAt: Money? get() = compareAtPrice.above(price)
}

@Serializable
data class ProductOption(val id: String? = null, val name: String, val optionValues: List<ProductOptionValue> = emptyList()) {
    val values: List<String> get() = optionValues.map { it.name }
}

@Serializable
data class ProductOptionValue(val id: String? = null, val name: String, val swatch: Swatch? = null, val firstSelectableVariant: Variant? = null)

@Serializable
data class Swatch(val color: String? = null, val image: Image? = null) {
    @Serializable
    data class Image(val previewImage: Img? = null)
}

@Serializable
data class SellingPlanGroup(
    val name: String,
    val appName: String? = null,
    val options: List<Option> = emptyList(),
    @Serializable(with = NodesSerializer::class) val sellingPlans: List<SellingPlan> = emptyList(),
) {
    @Serializable
    data class Option(val name: String, val values: List<String> = emptyList())
}

@Serializable
data class SellingPlan(val id: String, val name: String, val description: String? = null, val recurringDeliveries: Boolean = false)

@Serializable
data class Metafield(val namespace: String, val key: String, val type: String? = null, val value: String)

/** The identifier of a metafield to load (`HasMetafieldsIdentifier`). */
@Serializable
data class MetafieldIdentifier(val namespace: String, val key: String)

@Serializable
data class Product(
    val id: String,
    val handle: String,
    val title: String,
    val vendor: String = "",
    val productType: String = "",
    val descriptionHtml: String = "",
    val availableForSale: Boolean = false,
    val isGiftCard: Boolean = false,
    val requiresSellingPlan: Boolean = false,
    val encodedVariantExistence: String? = null,
    val encodedVariantAvailability: String? = null,
    val seo: Seo? = null,
    val priceRange: PriceRange? = null,
    @Serializable(with = NodesSerializer::class) val media: List<Media> = emptyList(),
    val options: List<ProductOption> = emptyList(),
    val selectedOrFirstAvailableVariant: Variant? = null,
    val adjacentVariants: List<Variant> = emptyList(),
    @Serializable(with = NodesSerializer::class) val variants: List<Variant> = emptyList(),
    @Serializable(with = NodesSerializer::class) val sellingPlanGroups: List<SellingPlanGroup> = emptyList(),
    // one entry per requested identifier; the ones this product has no value for come back null
    @SerialName("metafields") private val requestedMetafields: List<Metafield?> = emptyList(),
) {
    /** The images of its media (MediaImage), in order. */
    val images: List<Img> get() = media.mapNotNull { (it as? Media.Image)?.image }

    /** The requested metafields this product has a value for. */
    val metafields: List<Metafield> get() = requestedMetafields.filterNotNull()
}

/** Product media by `__typename`; [Other] is a media type this app doesn't know yet. */
@Serializable(with = MediaSerializer::class)
sealed interface Media {
    val id: String
    val alt: String?
    val previewImage: Img?

    @Serializable
    data class Image(override val id: String, override val alt: String? = null, override val previewImage: Img? = null, val image: Img? = null) : Media

    @Serializable
    data class Video(override val id: String, override val alt: String? = null, override val previewImage: Img? = null, val sources: List<Source> = emptyList()) : Media

    @Serializable
    data class ExternalVideo(
        override val id: String,
        override val alt: String? = null,
        override val previewImage: Img? = null,
        val host: String? = null,
        val embedUrl: String? = null,
        val originUrl: String? = null,
    ) : Media

    /** Decoded, not rendered: the app has no 3D viewer. */
    @Serializable
    data class Model3d(override val id: String, override val alt: String? = null, override val previewImage: Img? = null, val sources: List<Source> = emptyList()) : Media

    @Serializable
    data class Other(
        @SerialName("__typename") val typename: String? = null,
        override val id: String = "",
        override val alt: String? = null,
        override val previewImage: Img? = null,
    ) : Media

    /** A video or 3D model file: [width] and [height] for videos, [filesize] for models. */
    @Serializable
    data class Source(val url: String, val mimeType: String? = null, val format: String? = null, val width: Int? = null, val height: Int? = null, val filesize: Int? = null)
}

internal object MediaSerializer : JsonContentPolymorphicSerializer<Media>(Media::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<Media> = when (element.typename) {
        "MediaImage" -> Media.Image.serializer()
        "Video" -> Media.Video.serializer()
        "ExternalVideo" -> Media.ExternalVideo.serializer()
        "Model3d" -> Media.Model3d.serializer()
        else -> Media.Other.serializer()
    }
}

/**
 * A metaobject field's reference by `__typename`: products and collections as their cards, an image, a metaobject.
 * [Other] is any type the document selects nothing of but `__typename`, or a broken reference.
 */
@Serializable(with = ReferenceSerializer::class)
sealed interface Reference {
    @Serializable
    data class Image(val image: Img? = null) : Reference

    @Serializable
    data class Other(@SerialName("__typename") val typename: String? = null) : Reference
}

internal object ReferenceSerializer : JsonContentPolymorphicSerializer<Reference>(Reference::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<Reference> {
        // a document that selects only `__typename` of a type (Metaobject.graphql's collection references) sends no id
        val selected = (element as? JsonObject)?.containsKey("id") == true
        return when (element.typename) {
            "MediaImage" -> Reference.Image.serializer()
            "Product" -> if (selected) ProductCard.serializer() else Reference.Other.serializer()
            "Collection" -> if (selected) CollectionCard.serializer() else Reference.Other.serializer()
            "Metaobject" -> if (selected) Metaobject.serializer() else Reference.Other.serializer()
            else -> Reference.Other.serializer()
        }
    }
}

@Serializable
data class Metaobject(
    val id: String,
    val handle: String? = null,
    val type: String,
    val updatedAt: String? = null,
    val fields: List<MetaobjectField> = emptyList(),
) : Reference {
    fun field(key: String): MetaobjectField? = fields.firstOrNull { it.key == key }
}

@Serializable
data class MetaobjectField(
    val key: String,
    val type: String? = null,
    val value: String? = null,
    val reference: Reference? = null,
    @Serializable(with = NodesSerializer::class) val references: List<Reference> = emptyList(),
)

/** A search result by `__typename`; [Other] is a type the document doesn't select. */
@Serializable(with = SearchResultSerializer::class)
sealed interface SearchResult {
    @Serializable
    data class Other(@SerialName("__typename") val typename: String? = null) : SearchResult
}

internal object SearchResultSerializer : JsonContentPolymorphicSerializer<SearchResult>(SearchResult::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<SearchResult> = when (element.typename) {
        "Product" -> ProductCard.serializer()
        "Page" -> StorePage.serializer()
        "Article" -> Article.serializer()
        else -> SearchResult.Other.serializer()
    }
}

@Serializable
data class PredictiveSearch(
    val queries: List<Query> = emptyList(),
    val products: List<ProductCard> = emptyList(),
    val collections: List<ResourceRef> = emptyList(),
    val pages: List<ResourceRef> = emptyList(),
    val articles: List<ResourceRef> = emptyList(),
) {
    @Serializable
    data class Query(val text: String, val styledText: String? = null)
}

/** An online store page (the API's `Page`). */
@Serializable
data class StorePage(
    val id: String,
    val handle: String,
    val title: String,
    val body: String? = null,
    val bodySummary: String? = null,
    val seo: Seo? = null,
    val updatedAt: String? = null,
) : SearchResult

/** [articles]: where the document selects them (Blog). */
@Serializable
data class Blog(val id: String, val handle: String, val title: String, val seo: Seo? = null, val articles: Page<Article>? = null)

/** [contentHtml], [tags] and [seo]: where the document selects them (Article). */
@Serializable
data class Article(
    val id: String,
    val handle: String,
    val title: String,
    val excerpt: String? = null,
    val publishedAt: String? = null,
    val image: Img? = null,
    val authorV2: Author? = null,
    val blog: ResourceRef? = null,
    val contentHtml: String? = null,
    val tags: List<String> = emptyList(),
    val seo: Seo? = null,
) : SearchResult {
    @Serializable
    data class Author(val name: String)
}

@Serializable
data class Shop(
    val id: String,
    val name: String,
    val description: String? = null,
    val moneyFormat: String? = null,
    val shipsToCountries: List<String> = emptyList(),
    val primaryDomain: Domain? = null,
    val brand: ShopBrand? = null,
    val paymentSettings: PaymentSettings? = null,
) {
    @Serializable
    data class Domain(val host: String, val url: String)

    @Serializable
    data class PaymentSettings(
        val currencyCode: String,
        val countryCode: String,
        val acceptedCardBrands: List<String> = emptyList(),
        val supportedDigitalWallets: List<String> = emptyList(),
        val enabledPresentmentCurrencies: List<String> = emptyList(),
    )
}

/** The shop's brand settings (the API's `Brand`); the app's theme reads them as a [Brand]. */
@Serializable
data class ShopBrand(
    val slogan: String? = null,
    val shortDescription: String? = null,
    val logo: Image? = null,
    val squareLogo: Image? = null,
    val coverImage: Image? = null,
    val colors: Colors? = null,
) {
    @Serializable
    data class Image(val image: Img? = null)

    @Serializable
    data class Colors(val primary: List<ColorGroup> = emptyList(), val secondary: List<ColorGroup> = emptyList())

    @Serializable
    data class ColorGroup(val background: String? = null, val foreground: String? = null)
}

@Serializable
data class Policy(val id: String? = null, val handle: String, val title: String, val body: String, val url: String)

@Serializable
data class ShopPolicies(
    val privacyPolicy: Policy? = null,
    val refundPolicy: Policy? = null,
    val shippingPolicy: Policy? = null,
    val termsOfService: Policy? = null,
    val termsOfSale: Policy? = null,
    val legalNotice: Policy? = null,
    val contactInformation: Policy? = null,
    val subscriptionPolicy: Policy? = null,
)

@Serializable
data class Localization(
    val country: Country,
    val language: Language,
    val availableCountries: List<Country> = emptyList(),
    val availableLanguages: List<Language> = emptyList(),
) {
    @Serializable
    data class Country(
        val isoCode: String,
        val name: String = "",
        val currency: Currency? = null,
        val unitSystem: String? = null,
        val defaultLanguage: Language? = null,
        val availableLanguages: List<Language> = emptyList(),
    )

    @Serializable
    data class Language(val isoCode: String, val endonymName: String? = null, val name: String? = null)

    @Serializable
    data class Currency(val isoCode: String, val name: String? = null, val symbol: String? = null)
}

@Serializable
data class Menu(val id: String, val handle: String, val title: String, val items: List<Item> = emptyList()) {
    @Serializable
    data class Item(
        val id: String,
        val title: String,
        val url: String? = null,
        val type: String,
        val resourceId: String? = null,
        val resource: Resource? = null,
        val items: List<Item> = emptyList(),
    )

    /** The linked resource; [typename] says which (Collection, Product, Page, Blog, Article, ShopPolicy, Metaobject). [blog]: an article's; [type]: a metaobject's. */
    @Serializable
    data class Resource(@SerialName("__typename") val typename: String, val handle: String? = null, val blog: ResourceRef? = null, val type: String? = null)
}

@Serializable
data class LocationAddress(
    val address1: String? = null,
    val address2: String? = null,
    val city: String? = null,
    val province: String? = null,
    val provinceCode: String? = null,
    val zip: String? = null,
    val country: String? = null,
    val countryCode: String? = null,
    val phone: String? = null,
    val formatted: List<String> = emptyList(),
    val latitude: Double? = null,
    val longitude: Double? = null,
)

@Serializable
data class Location(val id: String, val name: String, val address: LocationAddress)

@Serializable
data class StoreAvailability(val available: Boolean, val pickUpTime: String, val quantityAvailable: Int = 0, val location: Location)

// Cart

@Serializable
data class CartWarning(val code: String, val message: String, val target: String? = null)

/** A cart's delivery address; also the `deliveryAddress` of a [CartAddressInput]. */
@Serializable
data class CartDeliveryAddress(
    val firstName: String? = null,
    val lastName: String? = null,
    val company: String? = null,
    val address1: String? = null,
    val address2: String? = null,
    val city: String? = null,
    val provinceCode: String? = null,
    val zip: String? = null,
    val countryCode: String? = null,
    val phone: String? = null,
)

@Serializable
data class Cart(
    val id: String,
    val checkoutUrl: String,
    val totalQuantity: Int = 0,
    val note: String? = null,
    val attributes: List<Attribute> = emptyList(),
    val discountCodes: List<DiscountCode> = emptyList(),
    val appliedGiftCards: List<AppliedGiftCard> = emptyList(),
    val buyerIdentity: BuyerIdentity? = null,
    val delivery: Delivery? = null,
    val cost: Cost,
    @Serializable(with = NodesSerializer::class) val lines: List<CartLine> = emptyList(),
    /** Where the document selects them (Cart, CartSelectedDeliveryOptionsUpdate). */
    @Serializable(with = NodesSerializer::class) val deliveryGroups: List<DeliveryGroup> = emptyList(),
    /** The mutation's `warnings` (a discount code that doesn't apply, stock that ran short); none from the Cart query. */
    val warnings: List<CartWarning> = emptyList(),
) {
    val subtotal: Money get() = cost.subtotalAmount
    val total: Money get() = cost.totalAmount

    @Serializable
    data class Cost(val subtotalAmount: Money, val totalAmount: Money)

    @Serializable
    data class DiscountCode(val code: String, val applicable: Boolean = false)

    @Serializable
    data class AppliedGiftCard(val id: String, val lastCharacters: String, val amountUsed: Money, val balance: Money)

    @Serializable
    data class BuyerIdentity(val email: String? = null, val phone: String? = null, val countryCode: String? = null)

    @Serializable
    data class Delivery(val addresses: List<SelectableAddress> = emptyList())

    @Serializable
    data class SelectableAddress(val id: String, val selected: Boolean = false, val oneTimeUse: Boolean = false, val address: CartDeliveryAddress)

    @Serializable
    data class DeliveryGroup(
        val id: String,
        val deliveryAddress: FormattedAddress? = null,
        val selectedDeliveryOption: DeliveryOption? = null,
        val deliveryOptions: List<DeliveryOption> = emptyList(),
    )

    @Serializable
    data class FormattedAddress(val formatted: List<String> = emptyList())

    @Serializable
    data class DeliveryOption(
        val handle: String,
        val title: String? = null,
        val description: String? = null,
        val deliveryMethodType: String? = null,
        val estimatedCost: Money? = null,
    )
}

@Serializable
data class CartLine(
    val id: String,
    val quantity: Int,
    val attributes: List<Attribute> = emptyList(),
    val cost: Cost,
    val discountAllocations: List<DiscountAllocation> = emptyList(),
    val merchandise: Merchandise,
) {
    val variantTitle: String get() = merchandise.title
    val productTitle: String get() = merchandise.product.title.orEmpty()
    val image: Img? get() = merchandise.image
    val total: Money get() = cost.totalAmount

    @Serializable
    data class Cost(val totalAmount: Money)

    @Serializable
    data class DiscountAllocation(val discountedAmount: Money)

    /** The variant on the line ([product]: its product's handle and title). */
    @Serializable
    data class Merchandise(val id: String, val title: String, val image: Img? = null, val price: Money, val product: ResourceRef)
}

// The app's own models, built from the API's for the screens.

data class MenuItem(val title: String, val route: Route, val children: List<MenuItem>)

/** Menu items route through their linked product or collection, else through [Links]. Unroutable leaves are dropped. */
fun menuTree(items: List<Menu.Item>, hosts: Set<String>): List<MenuItem> = items.mapNotNull { item ->
    val children = menuTree(item.items, hosts)
    val handle = item.resource?.handle
    val route = when {
        handle != null && item.resource.typename == "Product" -> Route.Product(handle)
        handle != null && item.resource.typename == "Collection" -> Route.Collection(handle)
        else -> Links.resolve(item.url, hosts)
    }
    // ponytail: a pure header item (url "#") keeps its children behind a placeholder Web route; the UI expands it
    val target = route ?: if (children.isEmpty()) return@mapNotNull null else Route.Web(item.url.orEmpty())
    MenuItem(item.title, target, children)
}

data class Brand(val name: String, val logo: Img?, val cover: Img?, val accent: String?, val hosts: Set<String>)

/** [configDomain] is SHOP_DOMAIN; together with the primary domain it decides which links stay in the app. */
fun Shop.toBrand(configDomain: String) = Brand(
    name = name,
    logo = brand?.logo?.image,
    cover = brand?.coverImage?.image,
    accent = brand?.colors?.primary?.firstOrNull()?.background,
    hosts = setOfNotNull(configDomain, primaryDomain?.host),
)

sealed interface Section {
    data class Banner(
        val style: String,
        val image: Img?,
        val heading: String?,
        val text: String?,
        val buttonLabel: String?,
        val link: Route?,
    ) : Section

    data class Products(val heading: String?, val style: String, val items: List<ProductCard>) : Section

    data class Collections(val heading: String?, val items: List<CollectionCard>) : Section
}

sealed interface Route {
    data class Product(val handle: String) : Route
    data class Collection(val handle: String) : Route
    data class Search(val query: String) : Route
    data class Web(val url: String) : Route
}
