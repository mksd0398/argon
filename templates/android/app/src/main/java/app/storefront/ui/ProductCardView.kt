package app.storefront.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storefront.AppGraph
import app.storefront.data.Money
import app.storefront.data.ProductCard
import coil3.compose.AsyncImage
import java.text.NumberFormat
import java.util.Currency
import kotlinx.coroutines.launch

/** "$25.00": the amount in its currency, in the device's locale. */
fun Money.display(): String = runCatching {
    NumberFormat.getCurrencyInstance().apply { currency = Currency.getInstance(currencyCode) }.format(amount.toBigDecimal())
}.getOrDefault("$amount $currencyCode")

/** Heart toggle for the product with id [productId]: filled while it is in the wishlist. */
@Composable
fun WishlistHeart(productId: String, modifier: Modifier = Modifier) {
    val ids by AppGraph.wishlist.ids.collectAsState()
    val saved = productId in ids
    IconButton(onClick = { AppGraph.scope.launch { AppGraph.wishlist.toggle(productId) } }, modifier) {
        Icon(
            if (saved) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            contentDescription = if (saved) "Remove from wishlist" else "Save to wishlist",
            tint = if (saved) MaterialTheme.colorScheme.primary else LocalContentColor.current,
        )
    }
}

@Composable
fun ProductCardView(card: ProductCard, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.clickable(onClick = onClick), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(4f / 5f).clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surfaceVariant)) {
            AsyncImage(
                model = card.image?.url,
                contentDescription = card.image?.alt ?: card.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
            )
            WishlistHeart(
                card.id,
                Modifier.align(Alignment.TopEnd).padding(4.dp).size(36.dp)
                    .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.8f), CircleShape),
            )
            if (!card.available) {
                Text(
                    "Sold out",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.align(Alignment.TopStart).padding(8.dp)
                        .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
        }
        Text(card.title, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(card.price.display(), style = MaterialTheme.typography.bodyMedium)
            card.compareAt?.let {
                Text(
                    it.display(),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textDecoration = TextDecoration.LineThrough,
                )
            }
        }
    }
}
