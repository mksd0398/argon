package app.storefront.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonCarousel
import app.storefront.AppGraph
import app.storefront.data.CollectionCard
import app.storefront.data.HomeContent
import app.storefront.data.Route
import app.storefront.ui.AppTab
import app.storefront.ui.ProductCardStyle
import app.storefront.ui.SectionHeader
import app.storefront.ui.StoreImage

/**
 * The grocery home (dense): a short banner carousel, a grid of eight categories with "See all", every rail as small
 * cards with a quick add, and after the second rail the first rail's products again as a list under "Popular". Its top
 * bar is a search field (see HomeScreen).
 */
@Composable
fun HomeGrocery(content: HomeContent, onOpen: (Route) -> Unit) {
    val spacing = ArgonTheme.spacing
    val rails = content.rails
    // "Popular" follows the second rail, or the only one
    val popularAfter = minOf(1, rails.lastIndex)
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = spacing.s, bottom = spacing.xl),
        verticalArrangement = Arrangement.spacedBy(spacing.xl),
    ) {
        if (content.banners.isNotEmpty()) {
            item {
                ArgonCarousel(content.banners.size, showsIndicators = false) { page ->
                    content.banners.getOrNull(page)?.let { BannerView(it, onOpen, ratio = 21f / 9f, compact = true) }
                }
            }
        }
        if (content.isEmpty) item { EmptyNote() }
        if (content.categories.isNotEmpty()) item { CategoryGrid(content.categories.take(8), onOpen) }
        rails.forEachIndexed { index, rail ->
            item { ProductRail(rail.title, rail.items, content.routeOf(rail), onOpen, ProductCardStyle.Compact, cardWidth = 132.dp) }
            if (index == popularAfter) item { ProductRows("Popular", rails[0].items.take(5), onOpen) }
        }
    }
}

/** "Shop by category": [categories] four to a row as small square pictures with their titles; "See all" opens the Shop tab. */
@Composable
private fun CategoryGrid(categories: List<CollectionCard>, onOpen: (Route) -> Unit) {
    val spacing = ArgonTheme.spacing
    Column(Modifier.padding(horizontal = spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        SectionHeader("Shop by category", actionLabel = "See all") { AppGraph.tabs.select(AppTab.Shop) }
        for (row in categories.chunked(4)) {
            Row(horizontalArrangement = Arrangement.spacedBy(spacing.s)) {
                for (category in row) {
                    Column(
                        Modifier.weight(1f).clickable { onOpen(Route.Collection(category.handle)) },
                        verticalArrangement = Arrangement.spacedBy(spacing.xs),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        StoreImage(category.picture, null, Modifier.fillMaxWidth().aspectRatio(1f).clip(ArgonTheme.radius.m))
                        Text(
                            category.title,
                            style = ArgonTheme.type.caption,
                            color = ArgonTheme.colors.ink,
                            textAlign = TextAlign.Center,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                // a short last row keeps its tiles the size of the others
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}
