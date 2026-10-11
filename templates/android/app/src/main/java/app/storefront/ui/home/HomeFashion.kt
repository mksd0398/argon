package app.storefront.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonCarousel
import app.storefront.data.CollectionCard
import app.storefront.data.HomeContent
import app.storefront.data.Route
import app.storefront.ui.SectionHeader
import app.storefront.ui.StoreImage
import app.storefront.ui.TrustRow

/**
 * The fashion home (editorial): a full-bleed hero carousel, "Shop by category" as tall image tiles, the first rail as a
 * carousel of cards, the second banner as an inset card, the second rail as a grid of four, the other rails as carousels,
 * then the trust row. Its top bar is the centred logo with search (see HomeScreen).
 */
@Composable
fun HomeFashion(content: HomeContent, onOpen: (Route) -> Unit) {
    val spacing = ArgonTheme.spacing
    val hero = heroBanners(content.banners)
    val editorial = content.banners.getOrNull(1)
    val rails = content.rails
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = spacing.xl), verticalArrangement = Arrangement.spacedBy(spacing.xl)) {
        if (hero.isNotEmpty()) {
            item {
                // edge to edge: no gap between the pages and no neighbour peeking in
                ArgonCarousel(hero.size, autoplaySeconds = 5.0, peekFraction = 0f, itemSpacing = 0.dp) { page ->
                    hero.getOrNull(page)?.let { BannerView(it, onOpen, ratio = 4f / 5f, headingStyle = ArgonTheme.type.display, shape = RectangleShape) }
                }
            }
        }
        if (content.categories.isNotEmpty()) item { CategoryTiles(content.categories, onOpen) }
        rails.getOrNull(0)?.let { rail -> item { ProductRail(rail.title, rail.items, content.routeOf(rail), onOpen) } }
        if (editorial != null) item { BannerView(editorial, onOpen, ratio = 1f, Modifier.padding(horizontal = spacing.l)) }
        rails.getOrNull(1)?.let { rail ->
            item {
                Column(Modifier.padding(horizontal = spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.m)) {
                    SectionHeader(rail.title, actionLabel = "View all") { onOpen(content.routeOf(rail)) }
                    ProductPairs(rail.items.take(4), onOpen)
                }
            }
        }
        items(rails.drop(2)) { rail -> ProductRail(rail.title, rail.items, content.routeOf(rail), onOpen) }
        // nothing to shop yet: the banners above, then the note
        if (content.isEmpty) item { EmptyNote() }
        item { TrustRow(onOpen, Modifier.padding(horizontal = spacing.l)) }
    }
}

/** "Shop by category": 3:4 image tiles that scroll sideways, each with its collection's title under it. */
@Composable
private fun CategoryTiles(categories: List<CollectionCard>, onOpen: (Route) -> Unit) {
    val spacing = ArgonTheme.spacing
    Column(verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        SectionHeader("Shop by category", Modifier.padding(horizontal = spacing.l))
        LazyRow(contentPadding = PaddingValues(horizontal = spacing.l), horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
            items(categories) { category ->
                Column(
                    Modifier.width(132.dp).clickable { onOpen(Route.Collection(category.handle)) },
                    verticalArrangement = Arrangement.spacedBy(spacing.s),
                ) {
                    StoreImage(category.image, null, Modifier.fillMaxWidth().aspectRatio(3f / 4f).clip(ArgonTheme.radius.m))
                    Text(category.title, style = ArgonTheme.type.label, color = ArgonTheme.colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}
