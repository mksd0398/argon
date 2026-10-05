package app.storefront.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull

// Lenient accessors: a missing or null field reads as null / empty. `string` is for fields the query guarantees.
internal fun JsonObject.obj(key: String) = this[key] as? JsonObject
internal fun JsonObject.str(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
internal fun JsonObject.string(key: String) = str(key) ?: throw IllegalStateException("Missing \"$key\" in response")
internal fun JsonObject.int(key: String) = (this[key] as? JsonPrimitive)?.intOrNull
internal fun JsonObject.bool(key: String) = (this[key] as? JsonPrimitive)?.booleanOrNull == true
internal fun JsonObject.objects(key: String) = (this[key] as? JsonArray).orEmpty().filterIsInstance<JsonObject>()
internal fun JsonObject.nodes(key: String) = obj(key)?.objects("nodes").orEmpty()

private fun money(m: JsonObject?) =
    checkNotNull(m) { "Missing money in response" }.let { Money(it.string("amount"), it.string("currencyCode")) }

internal fun img(i: JsonObject?) = i?.str("url")?.let { Img(it, i.str("altText"), i.int("width"), i.int("height")) }

// Shopify reports "no compare-at" as null or 0.0; only a higher compare-at is a real discount.
private fun compareAt(price: Money, compare: Money?) =
    compare?.takeIf { it.amount.toBigDecimal() > price.amount.toBigDecimal() }

// Broken references (null, or a `... on Product` that didn't match) arrive without an id and are skipped.
internal fun List<JsonObject>.cards() = filter { "id" in it }.map(::parseProductCard)

fun parseProductCard(p: JsonObject): ProductCard {
    val price = money(p.obj("priceRange")?.obj("minVariantPrice"))
    return ProductCard(
        id = p.string("id"),
        handle = p.string("handle"),
        title = p.string("title"),
        available = p.bool("availableForSale"),
        image = img(p.obj("featuredImage")),
        price = price,
        compareAt = compareAt(price, p.obj("compareAtPriceRange")?.obj("minVariantPrice")?.let(::money)),
    )
}

fun parseCollectionCard(c: JsonObject) =
    CollectionCard(c.string("id"), c.string("handle"), c.string("title"), img(c.obj("image")))

fun parseProduct(p: JsonObject) = Product(
    id = p.string("id"),
    handle = p.string("handle"),
    title = p.string("title"),
    vendor = p.str("vendor").orEmpty(),
    descriptionHtml = p.str("descriptionHtml").orEmpty(),
    images = p.nodes("media").mapNotNull { img(it.obj("image")) },
    options = p.objects("options").map { o -> o.string("name") to o.objects("optionValues").map { it.string("name") } },
    variants = p.nodes("variants").map { v ->
        val price = money(v.obj("price"))
        Variant(
            id = v.string("id"),
            title = v.string("title"),
            available = v.bool("availableForSale"),
            options = v.objects("selectedOptions").associate { it.string("name") to it.string("value") },
            price = price,
            compareAt = compareAt(price, v.obj("compareAtPrice")?.let(::money)),
            image = img(v.obj("image")),
        )
    },
    // identifiers with no value on this product come back as null entries
    metafields = p.objects("metafields").mapNotNull { m ->
        m.str("value")?.let { Triple(m.string("namespace"), m.string("key"), it) }
    },
)

/** [connection] is a product connection; [filtersKey] is `filters` (collection) or `productFilters` (search). */
fun parseProductPage(connection: JsonObject, filtersKey: String) = ProductPage(
    items = connection.objects("nodes").cards(),
    filters = connection.objects(filtersKey).map { f ->
        Filter(
            id = f.string("id"),
            label = f.string("label"),
            type = f.string("type"),
            values = f.objects("values").map { v ->
                // `input` is a JSON scalar; Shopify sends it as a string of JSON
                FilterValue(v.string("id"), v.string("label"), v.int("count") ?: 0, v.str("input") ?: v["input"].toString())
            },
        )
    },
    endCursor = connection.obj("pageInfo")?.str("endCursor"),
    hasNext = connection.obj("pageInfo")?.bool("hasNextPage") == true,
)

fun parseCart(cart: JsonObject) = Cart(
    id = cart.string("id"),
    checkoutUrl = cart.string("checkoutUrl"),
    totalQuantity = cart.int("totalQuantity") ?: 0,
    subtotal = money(cart.obj("cost")?.obj("subtotalAmount")),
    total = money(cart.obj("cost")?.obj("totalAmount")),
    lines = cart.nodes("lines").mapNotNull { line ->
        val variant = line.obj("merchandise")?.takeIf { "id" in it } ?: return@mapNotNull null
        val product = variant.obj("product")
        CartLine(
            id = line.string("id"),
            quantity = line.int("quantity") ?: 0,
            variantId = variant.string("id"),
            variantTitle = variant.string("title"),
            productHandle = product?.str("handle").orEmpty(),
            productTitle = product?.str("title").orEmpty(),
            image = img(variant.obj("image")),
            price = money(variant.obj("price")),
            total = money(line.obj("cost")?.obj("totalAmount")),
        )
    },
)

/** Menu items route through their linked resource, else through [Links]. Unroutable leaves are dropped. */
fun parseMenu(menu: JsonObject, hosts: Set<String>): List<MenuItem> = menu.objects("items").mapNotNull { item ->
    val children = parseMenu(item, hosts)
    val handle = item.obj("resource")?.str("handle")
    val route = when {
        handle != null && item.str("type") == "PRODUCT" -> Route.Product(handle)
        handle != null && item.str("type") == "COLLECTION" -> Route.Collection(handle)
        else -> Links.resolve(item.str("url"), hosts)
    }
    // ponytail: a pure header item (url "#") keeps its children behind a placeholder Web route; the UI expands it
    val target = route ?: if (children.isEmpty()) return@mapNotNull null else Route.Web(item.str("url").orEmpty())
    MenuItem(item.string("title"), target, children)
}

/** [configDomain] is SHOP_DOMAIN; together with the primary domain it decides which links stay in the app. */
fun parseBrand(shop: JsonObject, configDomain: String): Brand {
    val brand = shop.obj("brand")
    return Brand(
        name = shop.string("name"),
        logo = img(brand?.obj("logo")?.obj("image")),
        cover = img(brand?.obj("coverImage")?.obj("image")),
        accent = brand?.obj("colors")?.objects("primary")?.firstOrNull()?.str("background"),
        hosts = setOfNotNull(configDomain, shop.obj("primaryDomain")?.str("host")),
    )
}
