package app.storefront.data

// Money amounts stay Shopify's decimal strings; formatting is the UI's job.
data class Money(val amount: String, val currencyCode: String)

data class Img(val url: String, val alt: String?, val width: Int?, val height: Int?)

data class ProductCard(
    val id: String,
    val handle: String,
    val title: String,
    val available: Boolean,
    val image: Img?,
    val price: Money,
    val compareAt: Money?,
)

data class CollectionCard(val id: String, val handle: String, val title: String, val image: Img?)

data class Variant(
    val id: String,
    val title: String,
    val available: Boolean,
    val options: Map<String, String>,
    val price: Money,
    val compareAt: Money?,
    val image: Img?,
)

data class Product(
    val id: String,
    val handle: String,
    val title: String,
    val vendor: String,
    val descriptionHtml: String,
    val images: List<Img>,
    val options: List<Pair<String, List<String>>>,
    val variants: List<Variant>,
    val metafields: List<Triple<String, String, String>>, // namespace, key, value
)

data class FilterValue(val id: String, val label: String, val count: Int, val input: String)

data class Filter(val id: String, val label: String, val type: String, val values: List<FilterValue>)

data class ProductPage(
    val items: List<ProductCard>,
    val filters: List<Filter>,
    val endCursor: String?,
    val hasNext: Boolean,
)

data class CartLine(
    val id: String,
    val quantity: Int,
    val variantId: String,
    val variantTitle: String,
    val productHandle: String,
    val productTitle: String,
    val image: Img?,
    val price: Money,
    val total: Money,
)

data class Cart(
    val id: String,
    val checkoutUrl: String,
    val totalQuantity: Int,
    val subtotal: Money,
    val total: Money,
    val lines: List<CartLine>,
)

data class MenuItem(val title: String, val route: Route, val children: List<MenuItem>)

data class Brand(val name: String, val logo: Img?, val cover: Img?, val accent: String?, val hosts: Set<String>)

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
