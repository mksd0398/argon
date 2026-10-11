package app.storefront.data

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonContentPolymorphicSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

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

/** A resource by handle, with its title, (an article's) blog and (a product's) featured image where the document selects them. */
@Serializable
data class ResourceRef(val handle: String, val title: String? = null, val blog: ResourceRef? = null, val featuredImage: Img? = null)

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

/** [type]: LIST, PRICE_RANGE or BOOLEAN; [presentation]: how the store wants it shown (IMAGE, SWATCH or TEXT). */
@Serializable
data class Filter(val id: String, val label: String, val type: String, val values: List<FilterValue> = emptyList(), val presentation: String? = null)

/** [input]: the `ProductFilter` JSON that applies this value (send it back in `filters`). */
@Serializable
data class FilterValue(
    val id: String,
    val label: String,
    val count: Int = 0,
    @Serializable(with = JsonTextSerializer::class) val input: String,
    val swatch: Swatch? = null,
)

@Serializable
data class PriceRange(val minVariantPrice: Money, val maxVariantPrice: Money? = null)

// Shopify reports "no compare-at" as null or 0.0; only a higher compare-at is a real discount.
private fun Money?.above(price: Money) = this?.takeIf { it.amount.toBigDecimal() > price.amount.toBigDecimal() }

/** How many of a variant one order may hold. [min] and [step] are the values to use: stores without rules (mock.shop) send 0. */
@Serializable
data class QuantityRule(val minimum: Int = 1, val maximum: Int? = null, val increment: Int = 1) {
    val min: Int get() = maxOf(1, minimum)
    val step: Int get() = maxOf(1, increment)
}

/** Reads the standard `reviews` metafields (Judge.me and other review apps fill them). */
object Ratings {
    /**
     * A `rating` metafield's stars, 0...5: its value is JSON `{"value":"4.6","scale_min":"1.0","scale_max":"5.0"}` (brought
     * to a scale of 5 by `scale_max`) or a plain number. Null when unreadable.
     */
    fun parse(value: String?): Double? {
        val json = runCatching { Json.parseToJsonElement(value?.trim().orEmpty()) }.getOrNull()
        // the JSON's numbers come as strings ("4.6"), or as numbers from an app that writes them so
        fun number(element: JsonElement?) = (element as? JsonPrimitive)?.content?.toDoubleOrNull()?.takeIf { it.isFinite() }
        val (rating, top) = if (json is JsonObject) number(json["value"]) to (number(json["scale_max"]) ?: 5.0) else number(json) to 5.0
        if (rating == null || top <= 0) return null
        // a rating already out of 5 is kept as written (4.6 stays 4.6, with no rounding on the way)
        return (if (top == 5.0) rating else rating * 5 / top).coerceIn(0.0, 5.0)
    }

    /** A `rating_count` metafield's whole number; null when unreadable. */
    fun count(value: String?): Int? = value?.trim()?.toIntOrNull()
}

/** Whether an option (or filter) named [name] chooses a colour: "Colour", "Color" or "Shade", in any case. */
fun isColorName(name: String): Boolean = name.trim().lowercase() in setOf("colour", "color", "shade")

/** The variant a product list shows a product by (`selectedOrFirstAvailableVariant`): what a quick add puts in the cart. */
@Serializable
data class CardVariant(
    val id: String,
    val sku: String? = null,
    @SerialName("availableForSale") val available: Boolean = false,
    val quantityRule: QuantityRule? = null,
)

/** [options]: the first three; [rating] (0...5) and [ratingCount]: the standard `reviews` metafields, null without reviews. */
@Serializable
data class ProductCard(
    val id: String,
    val handle: String,
    val title: String,
    @SerialName("availableForSale") val available: Boolean = false,
    @SerialName("featuredImage") val image: Img? = null,
    val priceRange: PriceRange,
    val compareAtPriceRange: PriceRange? = null,
    val vendor: String = "",
    val options: List<ProductOption> = emptyList(),
    val firstVariant: CardVariant? = null,
    @Serializable(with = RatingSerializer::class) val rating: Double? = null,
    @Serializable(with = RatingCountSerializer::class) val ratingCount: Int? = null,
) : Reference, SearchResult {
    val price: Money get() = priceRange.minVariantPrice
    val maxPrice: Money? get() = priceRange.maxVariantPrice
    val compareAt: Money? get() = compareAtPriceRange?.minVariantPrice.above(price)

    /** Its variants don't all cost the same: the price is a "From". */
    val hasPriceRange: Boolean get() = maxPrice.above(price) != null

    /** The values of its colour option ([isColorName]); empty without one. */
    val colors: List<ProductOptionValue> get() = options.firstOrNull { isColorName(it.name) }?.optionValues.orEmpty()

    /** The variant a card can add without asking: the first one, when it is available and no option has a choice. Else null. */
    val quickAddVariantId: String?
        get() = firstVariant?.takeIf { it.available && options.all { option -> option.optionValues.size == 1 } }?.id
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

/**
 * A variant. Everything from [barcode] on is filled only by `variantBySelectedOptions` (the selected variant in full); a
 * product's own variant lists leave it at these defaults. [quantityAvailable] is also null when the token may not read stock.
 */
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
    val barcode: String? = null,
    val quantityAvailable: Int? = null,
    val currentlyNotInStock: Boolean = false,
    val unitPrice: Money? = null,
    val unitPriceMeasurement: UnitPriceMeasurement? = null,
    val quantityRule: QuantityRule? = null,
    /** Volume pricing: from [QuantityPriceBreak.minimumQuantity] up, each costs its price. */
    @Serializable(with = NodesSerializer::class) val quantityPriceBreaks: List<QuantityPriceBreak> = emptyList(),
    /** A bundle: [components] are its parts. */
    val requiresComponents: Boolean = false,
    @Serializable(with = NodesSerializer::class) val components: List<VariantComponent> = emptyList(),
    /** The bundles this variant is a part of. */
    @Serializable(with = NodesSerializer::class) val groupedBy: List<ComponentVariant> = emptyList(),
    @Serializable(with = NodesSerializer::class) val sellingPlanAllocations: List<SellingPlanAllocation> = emptyList(),
) {
    /** Option name to value, e.g. Size to M. */
    val options: Map<String, String> get() = selectedOptions.associate { it.name to it.value }
    val compareAt: Money? get() = compareAtPrice.above(price)
}

/** What a unit price is per: [referenceValue] [referenceUnit] ("$6.00 / 1 ITEM") of the [quantityValue] [quantityUnit] sold. */
@Serializable
data class UnitPriceMeasurement(
    val measuredType: String? = null,
    val quantityUnit: String? = null,
    val quantityValue: Double = 0.0,
    val referenceUnit: String? = null,
    val referenceValue: Int = 0,
)

@Serializable
data class QuantityPriceBreak(val minimumQuantity: Int, val price: Money)

/** One part of a bundle: [quantity] of [variant]. */
@Serializable
data class VariantComponent(val quantity: Int, @SerialName("productVariant") val variant: ComponentVariant)

/** A variant as a bundle's part, or as a bundle the variant belongs to. [image]: its own, else its product's. */
@Serializable
data class ComponentVariant(
    val id: String,
    val title: String,
    @SerialName("image") private val ownImage: Img? = null,
    val price: Money,
    val product: ResourceRef,
) {
    val image: Img? get() = ownImage ?: product.featuredImage
}

/** A selling plan (subscription) the variant can be bought on, with what it then costs. */
@Serializable
data class SellingPlanAllocation(val sellingPlan: SellingPlan, val priceAdjustments: List<PriceAdjustment> = emptyList()) {
    @Serializable
    data class PriceAdjustment(val price: Money, val compareAtPrice: Money? = null, val perDeliveryPrice: Money? = null)
}

@Serializable
data class SellingPlan(val id: String, val name: String)

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
data class Metafield(val namespace: String, val key: String, val type: String? = null, val value: String)

/** The identifier of a metafield to load (`HasMetafieldsIdentifier`). */
@Serializable
data class MetafieldIdentifier(val namespace: String, val key: String)

/**
 * [onlineStoreUrl]: its page on the web store, null when it isn't published there. [rating] (0...5) and [ratingCount]:
 * the standard `reviews` metafields. Its configured metafields come from `productMetafields`, its selling plans from the
 * selected variant ([Variant.sellingPlanAllocations]).
 */
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
    val tags: List<String> = emptyList(),
    val onlineStoreUrl: String? = null,
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
    @Serializable(with = RatingSerializer::class) val rating: Double? = null,
    @Serializable(with = RatingCountSerializer::class) val ratingCount: Int? = null,
) {
    /** The images of its media (MediaImage), in order. */
    val images: List<Img> get() = media.mapNotNull { (it as? Media.Image)?.image }
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
) {
    /** The policies the shop has. */
    val all: List<Policy>
        get() = listOfNotNull(privacyPolicy, refundPolicy, shippingPolicy, termsOfService, termsOfSale, legalNotice, contactInformation, subscriptionPolicy)

    /** The policy with this [handle] (`shipping-policy`, `refund-policy`, ...); null when the shop has none. */
    fun policy(handle: String): Policy? = all.firstOrNull { it.handle == handle }
}

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

    /** The company (and location) the cart is bought for; null for a retail cart. */
    val purchasingCompany: PurchasingCompany? get() = buyerIdentity?.purchasingCompany

    @Serializable
    data class Cost(val subtotalAmount: Money, val totalAmount: Money)

    @Serializable
    data class DiscountCode(val code: String, val applicable: Boolean = false)

    @Serializable
    data class AppliedGiftCard(val id: String, val lastCharacters: String, val amountUsed: Money, val balance: Money)

    @Serializable
    data class BuyerIdentity(
        val email: String? = null,
        val phone: String? = null,
        val countryCode: String? = null,
        val purchasingCompany: PurchasingCompany? = null,
    )

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

/** A B2B company with the locations the document selects ([CustomerAccountApi.companies]; none on a cart or an order). */
@Serializable
data class Company(val id: String, val name: String, @Serializable(with = NodesSerializer::class) val locations: List<CompanyLocation> = emptyList())

@Serializable
data class CompanyLocation(val id: String, val name: String)

/** The company and the location of it a cart or an order is bought for. */
@Serializable
data class PurchasingCompany(val company: Company, val location: CompanyLocation)

/** [components]: a bundle's parts; [sellingPlanAllocation]: the subscription the line is bought on. */
@Serializable
data class CartLine(
    val id: String,
    val quantity: Int,
    val attributes: List<Attribute> = emptyList(),
    val cost: Cost,
    val discountAllocations: List<DiscountAllocation> = emptyList(),
    val sellingPlanAllocation: SellingPlanAllocation? = null,
    val merchandise: Merchandise,
    @SerialName("lineComponents") val components: List<CartLineComponent> = emptyList(),
) {
    val variantTitle: String get() = merchandise.title
    val productTitle: String get() = merchandise.product.title.orEmpty()
    val image: Img? get() = merchandise.image
    val total: Money get() = cost.totalAmount
    val sellingPlanName: String? get() = sellingPlanAllocation?.sellingPlan?.name

    @Serializable
    data class Cost(val totalAmount: Money)

    @Serializable
    data class DiscountAllocation(val discountedAmount: Money)

    /** The variant on the line ([product]: its product's handle and title). */
    @Serializable
    data class Merchandise(
        val id: String,
        val title: String,
        val sku: String? = null,
        val image: Img? = null,
        val price: Money,
        val quantityRule: QuantityRule? = null,
        val product: ResourceRef,
    )
}

/** One part of a bundle on a cart line: [quantity] of a variant. */
@Serializable
data class CartLineComponent(val id: String, val quantity: Int, private val merchandise: Merchandise) {
    val variantId: String get() = merchandise.id
    val variantTitle: String get() = merchandise.title
    val productHandle: String get() = merchandise.product.handle
    val productTitle: String get() = merchandise.product.title.orEmpty()
    val image: Img? get() = merchandise.image

    @Serializable
    data class Merchandise(val id: String, val title: String, val image: Img? = null, val product: ResourceRef)
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

/** Where a tap leads: a pushed screen, or a web page ([Web], in the in-app browser). */
sealed interface Route {
    data class Product(val handle: String) : Route
    data class Collection(val handle: String) : Route
    data class Search(val query: String) : Route

    /** A shop policy's page by its handle (`shipping-policy`, `refund-policy`, ...): the route `policy/{handle}`. */
    data class Policy(val handle: String) : Route
    data class Web(val url: String) : Route
}

/** The home screen's layout by kind of store (`HOME_TEMPLATE`). */
enum class HomeTemplate(val value: String) {
    Fashion("fashion"), Beauty("beauty"), Grocery("grocery"), B2B("b2b");

    /** The heading and button of the template's three stock banners, shown until the store has banners of its own. */
    val bannerCopy: List<Pair<String, String>>
        get() = when (this) {
            Fashion -> listOf("The new season" to "Shop now", "Everyday essentials" to "Explore", "Made to last" to "Discover")
            Beauty -> listOf("Your daily ritual" to "Shop now", "Skin first" to "Explore", "Colour that stays" to "Discover")
            Grocery -> listOf("Fresh today" to "Shop now", "Fill your basket" to "Start shopping", "Baked this morning" to "Order now")
            B2B -> listOf("Stocked and ready to ship" to "Browse the catalogue", "Tools for the trade" to "Shop now", "Order by the pallet" to "View bulk pricing")
        }

    companion object {
        /** The template configured as [value]; the first (fashion) for anything else. */
        fun of(value: String): HomeTemplate = entries.firstOrNull { it.value == value.trim().lowercase() } ?: Fashion
    }
}

/** Where a product list keeps its sort and filter controls (`COLLECTION_TEMPLATE`): a sticky bar at the top, or a floating one at the bottom. */
enum class CollectionTemplate(val value: String) {
    Top("top"), Bottom("bottom");

    companion object {
        /** The template configured as [value]; the first (top) for anything else. */
        fun of(value: String): CollectionTemplate = entries.firstOrNull { it.value == value.trim().lowercase() } ?: Top
    }
}
