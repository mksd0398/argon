package app.storefront.data

import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

private const val PAGE_SIZE = 24

/** The country and language Storefront calls run in (`@inContext`); a null part is the shop's default. */
data class StorefrontContext(val country: String? = null, val language: String? = null) {
    companion object {
        /** [locale]'s country and language where the shop sells in them; each one it doesn't is null. */
        fun pick(locale: Locale, localization: Localization): StorefrontContext {
            val country = localization.availableCountries.firstOrNull { it.isoCode.equals(locale.country, ignoreCase = true) }
            val languages = (country?.availableLanguages ?: localization.availableLanguages).map { it.isoCode }
            // LanguageCode has regional values (PT_BR, ZH_CN) besides the plain ones
            val language = listOf("${locale.language}_${locale.country}", locale.language).map { it.uppercase() }.firstOrNull { it in languages }
            return StorefrontContext(country?.isoCode, language)
        }
    }
}

/**
 * The signed-in buyer Storefront calls run for (`@inContext(buyer:)`), so prices and the catalogue are their company's.
 * [customerAccessToken]: the Customer Account API access token; [companyLocationId]: the location they buy for.
 */
@Serializable
data class Buyer(val customerAccessToken: String, val companyLocationId: String? = null)

// Cart inputs. Null fields are left out of the request.

@Serializable
data class CartInput(
    val lines: List<CartLineInput>? = null,
    val attributes: List<Attribute>? = null,
    val buyerIdentity: CartBuyerIdentityInput? = null,
    val discountCodes: List<String>? = null,
    val giftCardCodes: List<String>? = null,
    val note: String? = null,
)

@Serializable
data class CartLineInput(val merchandiseId: String, val quantity: Int, val sellingPlanId: String? = null, val attributes: List<Attribute>? = null)

@Serializable
data class CartLineUpdateInput(
    val id: String,
    val quantity: Int? = null,
    val merchandiseId: String? = null,
    val sellingPlanId: String? = null,
    val attributes: List<Attribute>? = null,
)

/**
 * [customerAccessToken]: the signed-in customer's Customer Account API access token; [companyLocationId]: with it, the
 * company location they buy for (a B2B cart).
 */
@Serializable
data class CartBuyerIdentityInput(
    val email: String? = null,
    val phone: String? = null,
    val countryCode: String? = null,
    val customerAccessToken: String? = null,
    val companyLocationId: String? = null,
)

/** A new address, or a copy of one of the customer's ([copyFromCustomerAddressId]). */
@Serializable
data class CartAddressInput(val deliveryAddress: CartDeliveryAddress? = null, val copyFromCustomerAddressId: String? = null)

@Serializable
data class CartSelectableAddressInput(val address: CartAddressInput, val selected: Boolean? = null, val oneTimeUse: Boolean? = null)

@Serializable
data class CartSelectableAddressUpdateInput(val id: String, val address: CartAddressInput? = null, val selected: Boolean? = null, val oneTimeUse: Boolean? = null)

@Serializable
data class CartSelectedDeliveryOptionInput(val deliveryGroupId: String, val deliveryOptionHandle: String)

/**
 * Every Storefront API operation of the contract as a typed call. [execute] runs a named document with its variables and
 * returns the response's `data` ([Storefront.query] in the app, canned responses in tests). Lists come [PAGE_SIZE] at a
 * time. Calls run in [context], picked on first use from [locale] (null: the shop's default), and for [buyer]. `shop`,
 * `localization`, `policies` and `menu` are kept for the session. Every failure is an [ArgonApiError]; a cart mutation's
 * `userErrors` are thrown, its `warnings` come back on the cart.
 */
class StorefrontApi(private val execute: suspend (String, JsonObject) -> JsonObject, private val locale: Locale? = null) {
    private val cache = ConcurrentHashMap<String, Any>()
    private val contextLock = Mutex()

    @Volatile private var picked: StorefrontContext? = null

    @Volatile private var currentBuyer: Buyer? = null

    /** The context of every call but [localization]; null until picked. Setting it (a country picker) drops the session cache. */
    var context: StorefrontContext?
        get() = picked
        set(value) {
            picked = value
            cache.clear()
        }

    /**
     * The company buyer every call runs for (`$buyer`), so prices and products are their catalogue's; null: retail.
     * Setting it drops the session cache, like [context].
     */
    var buyer: Buyer?
        get() = currentBuyer
        set(value) {
            currentBuyer = value
            cache.clear()
        }

    private suspend fun currentContext(): StorefrontContext = picked ?: contextLock.withLock {
        picked ?: (locale?.let { StorefrontContext.pick(it, localization()) } ?: StorefrontContext()).also { picked = it }
    }

    private fun buyerVariable() = listOfNotNull(currentBuyer?.let { "buyer" to encode(it) })

    /** Runs [operation] in the context, for the buyer, and returns its `data`. */
    private suspend fun send(operation: String, variables: JsonObject): JsonObject {
        val context = currentContext()
        val inContext = listOfNotNull(context.country?.let { "country" to JsonPrimitive(it) }, context.language?.let { "language" to JsonPrimitive(it) })
        return execute(operation, JsonObject(variables + inContext + buyerVariable()))
    }

    private suspend inline fun <reified T> run(operation: String, variables: JsonObject, vararg path: String): T =
        decode(operation, send(operation, variables), *path)

    @Suppress("UNCHECKED_CAST")
    private suspend fun <T> cached(key: String, load: suspend () -> T): T =
        cache[key] as T? ?: load().also { if (it != null) cache[key] = it }

    suspend fun shop(): Shop = cached("shop") { run("Shop", vars(), "shop") }

    /** The countries and languages the shop sells in. Always in the shop's default context. */
    suspend fun localization(): Localization = cached("localization") {
        decode("Localization", execute("Localization", JsonObject(buyerVariable().toMap())), "localization")
    }

    suspend fun policies(): ShopPolicies = cached("policies") { run("ShopPolicies", vars(), "shop") }

    suspend fun menu(handle: String): Menu? = cached("menu:$handle") { run("Menu", vars("handle" to handle), "menu") }

    /** [selectedOptions] (option name to value) picks `selectedOrFirstAvailableVariant`. */
    suspend fun product(handle: String, selectedOptions: Map<String, String> = emptyMap()): Product? =
        run("Product", vars("handle" to handle, "selectedOptions" to selectedOptions.ifEmpty { null }?.let { encode(it.selected()) }), "product")

    /**
     * The metafields among [identifiers] the product has a value for; none (and no request) without identifiers, or
     * without the product. Its own query, not part of [product]: a token that may not read metafields is refused the
     * whole product they are selected on.
     */
    suspend fun productMetafields(handle: String, identifiers: List<MetafieldIdentifier>): List<Metafield> {
        if (identifiers.isEmpty()) return emptyList()
        return run<List<Metafield?>?>("ProductMetafields", vars("handle" to handle, "metafields" to encode(identifiers)), "product", "metafields")
            .orEmpty().filterNotNull()
    }

    /** The selected variant in full: stock, unit price, quantity rule and price breaks, bundle parts, selling plans. */
    suspend fun variantBySelectedOptions(productHandle: String, options: Map<String, String>): Variant? =
        run("VariantBySelectedOptions", vars("handle" to productHandle, "selectedOptions" to encode(options.selected())), "product", "variantBySelectedOptions")

    /** The catalogue (`Catalog`): [query] is Shopify search syntax, [sortKey] a `ProductSortKeys` value. */
    suspend fun products(query: String? = null, sortKey: String? = null, reverse: Boolean = false, after: String? = null): Page<ProductCard> =
        run("Catalog", vars("first" to PAGE_SIZE, "after" to after, "query" to query, "sortKey" to sortKey, "reverse" to reverse), "products")

    /** The products with these ids (`Products`, at most 250); ids that aren't products (any more) are left out. */
    suspend fun productsByIds(ids: List<String>): List<ProductCard> =
        run<List<Reference?>>("Products", vars("ids" to encode(ids)), "nodes").filterIsInstance<ProductCard>()

    /** [intent]: RELATED or COMPLEMENTARY. */
    suspend fun recommendations(productId: String, intent: String = "RELATED"): List<ProductCard> =
        run<List<ProductCard>?>("ProductRecommendations", vars("productId" to productId, "intent" to intent), "productRecommendations").orEmpty()

    /** [filters]: `FilterValue.input`s to apply; [sortKey]: a `ProductCollectionSortKeys` value. */
    suspend fun collection(
        handle: String,
        filters: List<String> = emptyList(),
        sortKey: String? = null,
        reverse: Boolean = false,
        after: String? = null,
    ): CollectionDetail? = run(
        "Collection",
        vars("handle" to handle, "first" to PAGE_SIZE, "after" to after, "sortKey" to sortKey, "reverse" to reverse, "filters" to filterInput(filters)),
        "collection",
    )

    suspend fun collections(after: String? = null): Page<CollectionCard> =
        run("Collections", vars("first" to PAGE_SIZE, "after" to after), "collections")

    /** [filters]: `FilterValue.input`s; [sortKey]: RELEVANCE or PRICE; [types]: `SearchType`s (the document's default: products). */
    suspend fun search(
        query: String,
        filters: List<String> = emptyList(),
        sortKey: String? = null,
        reverse: Boolean = false,
        after: String? = null,
        types: List<String>? = null,
    ): Page<SearchResult> = run(
        "Search",
        vars(
            "query" to query, "first" to PAGE_SIZE, "after" to after, "sortKey" to sortKey, "reverse" to reverse,
            "filters" to filterInput(filters), "types" to types?.let { encode(it) },
        ),
        "search",
    )

    /** Suggestions as the shopper types: [limit] of each kind. */
    suspend fun predictiveSearch(query: String, limit: Int = 8): PredictiveSearch =
        run<PredictiveSearch?>("PredictiveSearch", vars("query" to query, "limit" to limit), "predictiveSearch") ?: PredictiveSearch()

    /** Where the variant can be picked up; empty when it can't (or [variantId] isn't a variant). */
    suspend fun storeAvailability(variantId: String): List<StoreAvailability> =
        run<List<StoreAvailability>?>("StoreAvailability", vars("variantId" to variantId, "first" to PAGE_SIZE), "node", "storeAvailability", "nodes").orEmpty()

    suspend fun locations(after: String? = null): Page<Location> = run("Locations", vars("first" to PAGE_SIZE, "after" to after), "locations")

    suspend fun page(handle: String): StorePage? = run("Page", vars("handle" to handle), "page")

    suspend fun pages(after: String? = null): Page<StorePage> = run("Pages", vars("first" to PAGE_SIZE, "after" to after), "pages")

    suspend fun blogs(after: String? = null): Page<Blog> = run("Blogs", vars("first" to PAGE_SIZE, "after" to after), "blogs")

    /** The blog with a page of its articles. */
    suspend fun blog(handle: String, after: String? = null): Blog? =
        run("Blog", vars("handle" to handle, "first" to PAGE_SIZE, "after" to after), "blog")

    suspend fun article(blogHandle: String, articleHandle: String): Article? =
        run("Article", vars("blogHandle" to blogHandle, "articleHandle" to articleHandle), "blog", "articleByHandle")

    suspend fun articles(query: String? = null, after: String? = null): Page<Article> =
        run("Articles", vars("first" to PAGE_SIZE, "after" to after, "query" to query), "articles")

    suspend fun metaobject(type: String, handle: String): Metaobject? =
        run("Metaobject", vars("type" to type, "handle" to handle), "metaobject")

    suspend fun metaobjects(type: String, after: String? = null): Page<Metaobject> =
        run("Metaobjects", vars("type" to type, "first" to PAGE_SIZE, "after" to after), "metaobjects")

    /** The section entries of the `mobile_screen` metaobject [handle]; none when there is no such screen. Broken references are left out. */
    suspend fun homeScreen(handle: String = "home"): List<Metaobject> =
        run<List<Reference>?>("HomeScreen", vars("handle" to handle), "metaobject", "field", "references", "nodes").orEmpty().filterIsInstance<Metaobject>()

    /** The first collections, each with its first products: the home of a store without a `mobile_screen`. */
    suspend fun fallbackHome(): List<CollectionCard> = run<List<CollectionCard>?>("FallbackHome", vars(), "collections", "nodes").orEmpty()

    // Screens v2

    /** The `app_screen` metaobject [handle] (a screen: `home`, `product`, ..., or a custom page's); null when there is none. */
    suspend fun appScreen(handle: String): AppScreen? =
        run<AppScreenNode?>("AppScreen", vars("handle" to handle), "metaobject")?.let { AppScreen(it.id, it.handle ?: handle, it.title?.value.orEmpty(), it.template?.value, it.updatedAt) }

    /**
     * The products and collections with these GIDs (a screen's sections, [sectionNodeIds]), by id; ids that are neither
     * (any more) are left out. No request without ids.
     */
    suspend fun sectionNodes(ids: List<String>): SectionNodes {
        if (ids.isEmpty()) return SectionNodes()
        // ponytail: one request of up to 250 ids (the API's ceiling); a screen with more drops the rest
        val nodes = run<List<Reference?>>("SectionNodes", vars("ids" to encode(ids.take(250))), "nodes").filterNotNull()
        return SectionNodes(nodes.filterIsInstance<ProductCard>().associateBy { it.id }, nodes.filterIsInstance<CollectionCard>().associateBy { it.id })
    }

    /** The metafields among [identifiers] the collection has a value for; none (and no request) without identifiers. */
    suspend fun collectionMetafields(handle: String, identifiers: List<MetafieldIdentifier>): List<Metafield> {
        if (identifiers.isEmpty()) return emptyList()
        return run<List<Metafield?>?>("CollectionMetafields", vars("handle" to handle, "metafields" to encode(identifiers)), "collection", "metafields")
            .orEmpty().filterNotNull()
    }

    /** The metafields among [identifiers] the shop has a value for; none (and no request) without identifiers. */
    suspend fun shopMetafields(identifiers: List<MetafieldIdentifier>): List<Metafield> {
        if (identifiers.isEmpty()) return emptyList()
        return run<List<Metafield?>?>("ShopMetafields", vars("metafields" to encode(identifiers)), "shop", "metafields").orEmpty().filterNotNull()
    }

    // Cart

    /** Null when Shopify no longer has the cart (expired, or checked out). */
    suspend fun cart(id: String): Cart? = run("Cart", vars("id" to id), "cart")

    suspend fun cartCreate(input: CartInput = CartInput()): Cart = cartMutation("CartCreate", vars("input" to encode(input)))

    suspend fun addLines(cartId: String, lines: List<CartLineInput>): Cart =
        cartMutation("CartLinesAdd", vars("cartId" to cartId, "lines" to encode(lines)))

    suspend fun updateLines(cartId: String, lines: List<CartLineUpdateInput>): Cart =
        cartMutation("CartLinesUpdate", vars("cartId" to cartId, "lines" to encode(lines)))

    suspend fun removeLines(cartId: String, lineIds: List<String>): Cart =
        cartMutation("CartLinesRemove", vars("cartId" to cartId, "lineIds" to encode(lineIds)))

    suspend fun updateBuyerIdentity(cartId: String, buyerIdentity: CartBuyerIdentityInput): Cart =
        cartMutation("CartBuyerIdentityUpdate", vars("cartId" to cartId, "buyerIdentity" to encode(buyerIdentity)))

    /** Replaces the cart's discount codes; an empty list clears them. */
    suspend fun updateDiscountCodes(cartId: String, codes: List<String>): Cart =
        cartMutation("CartDiscountCodesUpdate", vars("cartId" to cartId, "discountCodes" to encode(codes)))

    suspend fun addGiftCards(cartId: String, codes: List<String>): Cart =
        cartMutation("CartGiftCardCodesAdd", vars("cartId" to cartId, "giftCardCodes" to encode(codes)))

    /** [appliedGiftCardIds]: `Cart.AppliedGiftCard.id`s (not the codes). */
    suspend fun removeGiftCards(cartId: String, appliedGiftCardIds: List<String>): Cart =
        cartMutation("CartGiftCardCodesRemove", vars("cartId" to cartId, "appliedGiftCardIds" to encode(appliedGiftCardIds)))

    suspend fun updateNote(cartId: String, note: String): Cart = cartMutation("CartNoteUpdate", vars("cartId" to cartId, "note" to note))

    suspend fun updateAttributes(cartId: String, attributes: List<Attribute>): Cart =
        cartMutation("CartAttributesUpdate", vars("cartId" to cartId, "attributes" to encode(attributes)))

    suspend fun addDeliveryAddresses(cartId: String, addresses: List<CartSelectableAddressInput>): Cart =
        cartMutation("CartDeliveryAddressesAdd", vars("cartId" to cartId, "addresses" to encode(addresses)))

    suspend fun updateDeliveryAddresses(cartId: String, addresses: List<CartSelectableAddressUpdateInput>): Cart =
        cartMutation("CartDeliveryAddressesUpdate", vars("cartId" to cartId, "addresses" to encode(addresses)))

    suspend fun removeDeliveryAddresses(cartId: String, addressIds: List<String>): Cart =
        cartMutation("CartDeliveryAddressesRemove", vars("cartId" to cartId, "addressIds" to encode(addressIds)))

    suspend fun selectDeliveryOptions(cartId: String, options: List<CartSelectedDeliveryOptionInput>): Cart =
        cartMutation("CartSelectedDeliveryOptionsUpdate", vars("cartId" to cartId, "selectedDeliveryOptions" to encode(options)))

    /** The cart with the payload's warnings. `userErrors`, or no cart, throw [ArgonApiError.UserErrors] (with the cart, if any). */
    private suspend fun cartMutation(operation: String, variables: JsonObject): Cart {
        val data = send(operation, variables)
        val root = operation.replaceFirstChar { it.lowercase() }
        if (data[root] !is JsonObject) throw ArgonApiError.Decoding(operation, "no $root")
        val warnings = decode<List<CartWarning>?>(operation, data, root, "warnings").orEmpty()
        val cart = decode<Cart?>(operation, data, root, "cart")?.copy(warnings = warnings)
        val errors = decode<List<UserError>?>(operation, data, root, "userErrors").orEmpty()
        if (cart == null || errors.isNotEmpty()) {
            throw ArgonApiError.UserErrors(errors.ifEmpty { listOf(UserError(message = "The cart is unavailable")) }, cart)
        }
        return cart
    }
}

// AppScreen's metaobject: its two fields by alias
@Serializable
private class AppScreenNode(val id: String, val handle: String? = null, val updatedAt: String? = null, val title: FieldValue? = null, val template: FieldValue? = null)

@Serializable
private class FieldValue(val value: String? = null)

private fun Map<String, String>.selected() = map { (name, value) -> SelectedOption(name, value) }

private fun filterInput(filters: List<String>) = filters.ifEmpty { null }?.let { list -> JsonArray(list.map { Json.parseToJsonElement(it) }) }
