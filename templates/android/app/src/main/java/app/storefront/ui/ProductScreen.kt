package app.storefront.ui

import android.text.method.LinkMovementMethod
import android.widget.TextView
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.text.HtmlCompat
import androidx.navigation.NavController
import app.storefront.AppGraph
import app.storefront.data.Product
import app.storefront.data.StorefrontException
import app.storefront.data.Variants
import app.storefront.data.obj
import app.storefront.data.parseProduct
import coil3.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * `PDP_METAFIELDS` ("custom.material, custom.care") as the Storefront `metafields` identifiers. Each entry splits on its
 * first dot; blank entries and ones without a namespace and a key are skipped.
 */
internal fun metafieldIdentifiers(config: String): JsonArray = JsonArray(
    config.split(",").map { it.trim() }.mapNotNull { entry ->
        val namespace = entry.substringBefore(".", "")
        val key = entry.substringAfter(".", "")
        if (namespace.isEmpty() || key.isEmpty()) null else buildJsonObject { put("namespace", namespace); put("key", key) }
    },
)

/** The options of the first available variant, else of the first variant (a sold-out product still shows its options). */
internal fun initialSelection(product: Product): Map<String, String> =
    (product.variants.firstOrNull { it.available } ?: product.variants.firstOrNull())?.options.orEmpty()

private suspend fun loadProduct(handle: String): Product {
    // ponytail: the Product query loads variants(first: 250), the Storefront API's page ceiling: a product with more
    // variants shows "Unavailable" for the combinations that didn't load. Upgrade: paginate the variants, or query
    // variantBySelectedOptions for each selection.
    val data = AppGraph.storefront.query(
        "Product",
        buildJsonObject { put("handle", handle); put("metafields", metafieldIdentifiers(AppGraph.pdpMetafields)) },
    )
    return parseProduct(data.obj("product") ?: throw StorefrontException(listOf("Product not found"), null))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProductScreen(handle: String, nav: NavController) {
    Scaffold(topBar = { TopAppBar(title = {}, navigationIcon = { BackButton(nav) }) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Loader({ loadProduct(handle) }) { ProductContent(it) }
        }
    }
}

@Composable
private fun ProductContent(product: Product) {
    var selection by remember { mutableStateOf(initialSelection(product)) }
    var adding by remember { mutableStateOf(false) }
    var addError by remember { mutableStateOf<String?>(null) }
    val variant = Variants.match(product.variants, selection)

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Gallery(product)
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(product.title, style = MaterialTheme.typography.headlineSmall)
                    if (product.vendor.isNotBlank()) {
                        Text(product.vendor, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                WishlistHeart(product.id)
            }

            if (variant == null) {
                Text("Unavailable", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
                    Text(variant.price.display(), style = MaterialTheme.typography.titleLarge)
                    variant.compareAt?.let {
                        Text(
                            it.display(),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textDecoration = TextDecoration.LineThrough,
                        )
                    }
                }
            }

            // a product without options still has Shopify's one "Title: Default Title" option; nothing to choose there
            for ((name, values) in product.options.filterNot { it.first == "Title" && it.second == listOf("Default Title") }) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(name, style = MaterialTheme.typography.labelLarge)
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (value in values) {
                            FilterChip(selected = selection[name] == value, onClick = { selection = selection + (name to value) }, label = { Text(value) })
                        }
                    }
                }
            }

            Button(
                onClick = {
                    val id = variant?.id ?: return@Button
                    adding = true
                    addError = null
                    // AppGraph's scope, not the screen's: leaving right after the tap must not drop the add
                    AppGraph.scope.launch {
                        try {
                            AppGraph.addToCart(id, 1)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            addError = e.message ?: e.toString()
                        } finally {
                            adding = false
                        }
                    }
                },
                enabled = variant?.available == true && !adding,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    when {
                        variant == null -> "Unavailable"
                        !variant.available -> "Sold out"
                        adding -> "Adding…"
                        else -> "Add to cart"
                    },
                )
            }
            addError?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }

            Description(product.descriptionHtml)

            if (product.metafields.isNotEmpty()) {
                HorizontalDivider()
                Text("Details", style = MaterialTheme.typography.titleMedium)
                // ponytail: values are shown as the store sends them (a rich-text or JSON metafield shows its raw text)
                for ((_, key, value) in product.metafields) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text(
                            key.replace('_', ' ').replaceFirstChar { it.uppercase() },
                            Modifier.weight(1f),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(value, Modifier.weight(2f))
                    }
                }
            }
        }
    }
}

/** Swipeable images with a "2 / 5" counter; a grey box when the product has none. */
@Composable
private fun Gallery(product: Product) {
    val box = Modifier.fillMaxWidth().aspectRatio(1f).background(MaterialTheme.colorScheme.surfaceVariant)
    if (product.images.isEmpty()) {
        Box(box)
        return
    }
    val pager = rememberPagerState { product.images.size }
    Box(box) {
        HorizontalPager(pager, Modifier.matchParentSize()) { page ->
            val image = product.images[page]
            AsyncImage(image.url, image.alt ?: product.title, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        }
        if (product.images.size > 1) {
            Text(
                "${pager.currentPage + 1} / ${product.images.size}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.align(Alignment.BottomEnd).padding(12.dp)
                    .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.8f), RoundedCornerShape(12.dp)).padding(horizontal = 8.dp, vertical = 2.dp),
            )
        }
    }
}

/** The merchant's HTML description through the platform's HTML renderer (paragraphs, lists, bold, links). */
@Composable
private fun Description(html: String) {
    if (html.isBlank()) return
    val color = MaterialTheme.colorScheme.onSurface.toArgb()
    val linkColor = MaterialTheme.colorScheme.primary.toArgb()
    AndroidView(
        factory = { TextView(it).apply { movementMethod = LinkMovementMethod.getInstance(); textSize = 15f } },
        update = {
            it.setTextColor(color)
            it.setLinkTextColor(linkColor)
            it.text = HtmlCompat.fromHtml(html, HtmlCompat.FROM_HTML_MODE_COMPACT).trimEnd()
        },
        modifier = Modifier.fillMaxWidth(),
    )
}
