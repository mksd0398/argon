package app.storefront.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.storefront.data.ProductCard

/**
 * Two-column grid of product cards. While [hasNext], a footer spinner calls [onLoadMore] as it scrolls into view;
 * if loading failed ([error]) the footer is a Retry button instead. [loadKey] must change whenever a page arrives, even
 * one that adds no items, or the footer would stall (the default, the item count, is enough for a list that only grows).
 */
@Composable
fun ProductGrid(
    items: List<ProductCard>,
    hasNext: Boolean,
    onLoadMore: () -> Unit,
    onOpen: (ProductCard) -> Unit,
    modifier: Modifier = Modifier,
    error: String? = null,
    loadKey: Any = items.size,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = modifier,
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        items(items, key = { it.id }) { ProductCardView(it, onClick = { onOpen(it) }) }
        if (hasNext) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Box(Modifier.fillMaxWidth().padding(8.dp), Alignment.Center) {
                    if (error == null) {
                        LaunchedEffect(loadKey) { onLoadMore() }
                        CircularProgressIndicator()
                    } else {
                        TextButton(onClick = onLoadMore) { Text("$error. Retry") }
                    }
                }
            }
        }
    }
}
