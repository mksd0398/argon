package app.storefront.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonSpinner
import app.storefront.data.ProductCard

/**
 * Two-column grid of product cards, with [header] (when given) across both columns above them, scrolling with them.
 * While [hasNext], a footer spinner calls [onLoadMore] as it scrolls into view; if loading failed ([error]) the footer
 * is the message and a Retry button instead. [loadKey] must change whenever a page arrives, even one that adds no items,
 * or the footer would stall (the default, the item count, is enough for a list that only grows). [above] and [below]: more
 * items over the header and under the footer (a screen's sections, screens v2).
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
    contentPadding: PaddingValues = PaddingValues(ArgonTheme.spacing.l),
    header: (@Composable () -> Unit)? = null,
    above: LazyGridScope.() -> Unit = {},
    below: LazyGridScope.() -> Unit = {},
) {
    val spacing = ArgonTheme.spacing
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = modifier,
        contentPadding = contentPadding,
        horizontalArrangement = Arrangement.spacedBy(spacing.m),
        verticalArrangement = Arrangement.spacedBy(spacing.l),
    ) {
        above()
        if (header != null) item(key = "header", span = { GridItemSpan(maxLineSpan) }) { header() }
        items(items, key = { it.id }) { ProductCardView(it, onOpen = { onOpen(it) }) }
        if (hasNext) {
            item(key = "footer", span = { GridItemSpan(maxLineSpan) }) {
                Column(
                    Modifier.fillMaxWidth().padding(spacing.s),
                    verticalArrangement = Arrangement.spacedBy(spacing.s),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    if (error == null) {
                        LaunchedEffect(loadKey) { onLoadMore() }
                        ArgonSpinner()
                    } else {
                        Text(error, style = ArgonTheme.type.label, color = ArgonTheme.colors.muted, textAlign = TextAlign.Center)
                        ArgonButton("Retry", style = ArgonButtonStyle.Secondary, size = ArgonSize.S, action = onLoadMore)
                    }
                }
            }
        }
        below()
    }
}
