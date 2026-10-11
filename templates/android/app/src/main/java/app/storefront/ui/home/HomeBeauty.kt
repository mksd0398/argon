package app.storefront.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonAvatar
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonCarousel
import app.argon.ui.components.ArgonTabs
import app.storefront.data.CollectionCard
import app.storefront.data.HomeContent
import app.storefront.data.Route
import app.storefront.ui.SectionHeader
import app.storefront.ui.TrustRow

/**
 * The beauty home (soft): an inset, rounded hero carousel, "Shop by category" as circles, the first rail as
 * "Bestsellers", "Shop by routine" (tabs of the first four categories over four of the selected one's products), the
 * second banner as a card, the other rails, then the trust row. Its top bar is the logo at the start with search (see
 * HomeScreen).
 */
@Composable
fun HomeBeauty(content: HomeContent, onOpen: (Route) -> Unit) {
    val spacing = ArgonTheme.spacing
    val hero = heroBanners(content.banners)
    val card = content.banners.getOrNull(1)
    val rails = content.rails
    // a routine needs products to show: the store's own category sections come without them
    val routines = content.categories.filter { it.products.isNotEmpty() }.take(4)
    var routine by rememberSaveable { mutableIntStateOf(0) }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = spacing.s, bottom = spacing.xl),
        verticalArrangement = Arrangement.spacedBy(spacing.xl),
    ) {
        if (hero.isNotEmpty()) {
            item {
                // the carousel's own margins inset the banners and let the next one peek in
                ArgonCarousel(hero.size) { page -> hero.getOrNull(page)?.let { BannerView(it, onOpen, ratio = 16f / 10f) } }
            }
        }
        if (content.categories.isNotEmpty()) item { CategoryCircles(content.categories, onOpen) }
        rails.firstOrNull()?.let { rail -> item { ProductRail("Bestsellers", rail.items, content.routeOf(rail), onOpen) } }
        if (routines.isNotEmpty()) {
            item { Routines(routines, routine.coerceIn(routines.indices), { routine = it }, onOpen) }
        }
        if (card != null) item { BannerView(card, onOpen, ratio = 16f / 10f, Modifier.padding(horizontal = spacing.l)) }
        items(rails.drop(1)) { rail -> ProductRail(rail.title, rail.items, content.routeOf(rail), onOpen) }
        // nothing to shop yet: the banners above, then the note
        if (content.isEmpty) item { EmptyNote() }
        item { TrustRow(onOpen, Modifier.padding(horizontal = spacing.l)) }
    }
}

/** "Shop by category": each collection as a round picture with its title under it, in a row that scrolls sideways. */
@Composable
private fun CategoryCircles(categories: List<CollectionCard>, onOpen: (Route) -> Unit) {
    val spacing = ArgonTheme.spacing
    Column(verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        SectionHeader("Shop by category", Modifier.padding(horizontal = spacing.l))
        LazyRow(contentPadding = PaddingValues(horizontal = spacing.l), horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
            items(categories) { category ->
                Column(
                    Modifier.width(72.dp).clickable { onOpen(Route.Collection(category.handle)) },
                    verticalArrangement = Arrangement.spacedBy(spacing.xs),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    ArgonAvatar(imageUrl = category.picture?.url, initials = category.title, size = ArgonSize.L)
                    Text(
                        category.title,
                        style = ArgonTheme.type.caption,
                        color = ArgonTheme.colors.ink,
                        textAlign = TextAlign.Center,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

/** "Shop by routine": a tab per category in [routines]; under them the [selected] one's first four products and "View all". */
@Composable
private fun Routines(routines: List<CollectionCard>, selected: Int, onSelect: (Int) -> Unit, onOpen: (Route) -> Unit) {
    val spacing = ArgonTheme.spacing
    val current = routines[selected]
    Column(verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        SectionHeader("Shop by routine", Modifier.padding(horizontal = spacing.l))
        // one category has nothing to switch between
        if (routines.size > 1) ArgonTabs(routines.map { it.title }, selected, onSelect)
        ProductPairs(current.products.take(4), onOpen, Modifier.padding(horizontal = spacing.l))
        ArgonButton("View all", Modifier.padding(horizontal = spacing.l), style = ArgonButtonStyle.Secondary, fullWidth = true) {
            onOpen(Route.Collection(current.handle))
        }
    }
}
