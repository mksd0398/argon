package app.storefront.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonSkeleton
import app.argon.ui.components.ArgonSkeletonBox
import app.argon.ui.components.ArgonSkeletonCircle
import app.argon.ui.components.ArgonSkeletonGroup
import app.argon.ui.components.ArgonSkeletonLine

// What a screen shows while its first load runs: skeletons shaped like what is coming, on the page's 16 dp gutter and
// spacing, so the content takes their place without a jump. Each is one "Loading" for screen readers.

/** A product card (the grid's and rails' standard one): its 4:5 picture, the title and the price. */
@Composable
private fun ProductCardSkeleton(modifier: Modifier = Modifier) =
    Column(modifier, verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs)) {
        ArgonSkeletonBox(4f / 5f)
        ArgonSkeletonLine(widthFraction = 0.85f, style = ArgonTheme.type.label)
        ArgonSkeletonLine(widthFraction = 0.4f, style = ArgonTheme.type.label)
    }

/** The home (and a custom page's sections): a hero, a row of four collection circles, a heading and a rail of cards. */
@Composable
fun HomeSkeleton() = ArgonSkeletonGroup(Modifier.fillMaxSize()) {
    val spacing = ArgonTheme.spacing
    Column(verticalArrangement = Arrangement.spacedBy(spacing.xl)) {
        ArgonSkeletonBox(4f / 3f, shape = RectangleShape)
        Row(Modifier.fillMaxWidth().padding(horizontal = spacing.l), horizontalArrangement = Arrangement.SpaceBetween) {
            repeat(4) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(spacing.s)) {
                    ArgonSkeletonCircle(64.dp)
                    ArgonSkeletonLine(Modifier.width(48.dp), style = ArgonTheme.type.caption)
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(spacing.m)) {
            ArgonSkeletonLine(Modifier.padding(horizontal = spacing.l), widthFraction = 0.5f, style = ArgonTheme.type.headline)
            // as the rails: 160 dp cards inset by the gutter, the last cut off by the screen's edge
            Row(
                Modifier.horizontalScroll(rememberScrollState(), enabled = false).padding(horizontal = spacing.l),
                horizontalArrangement = Arrangement.spacedBy(spacing.m),
            ) { repeat(3) { ProductCardSkeleton(Modifier.width(160.dp)) } }
        }
    }
}

/** A product grid (a collection, search results, the wishlist): two columns of six cards, as [ProductGrid] lays them. */
@Composable
fun ProductGridSkeleton() = ArgonSkeletonGroup(Modifier.fillMaxSize()) {
    val spacing = ArgonTheme.spacing
    Column(Modifier.padding(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.l)) {
        repeat(3) {
            Row(horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
                ProductCardSkeleton(Modifier.weight(1f))
                ProductCardSkeleton(Modifier.weight(1f))
            }
        }
    }
}

/** The product page: the 4:5 gallery, the title on two lines, the price, a row of option chips and the add button. */
@Composable
fun ProductSkeleton() = ArgonSkeletonGroup(Modifier.fillMaxSize()) {
    val spacing = ArgonTheme.spacing
    Column {
        ArgonSkeletonBox(4f / 5f, shape = RectangleShape)
        Column(Modifier.padding(start = spacing.l, end = spacing.l, top = spacing.xl), verticalArrangement = Arrangement.spacedBy(spacing.s)) {
            ArgonSkeletonLine(widthFraction = 0.9f, style = ArgonTheme.type.title)
            ArgonSkeletonLine(widthFraction = 0.6f, style = ArgonTheme.type.title)
            ArgonSkeletonLine(Modifier.padding(top = spacing.s), widthFraction = 0.3f, style = ArgonTheme.type.headline)
            Row(Modifier.padding(top = spacing.l), horizontalArrangement = Arrangement.spacedBy(spacing.s)) {
                repeat(4) { ArgonSkeleton(Modifier.size(64.dp, 40.dp), ArgonTheme.radius.pill) }
            }
            ArgonSkeleton(Modifier.padding(top = spacing.l).fillMaxWidth().height(48.dp))
        }
    }
}

/**
 * A list of rows (the cart, orders, addresses, the account): a [thumbnail] and two lines each, on the gutter.
 * [thumbnail] 0: rows without one.
 */
@Composable
fun ListSkeleton(rows: Int = 4, thumbnail: Dp = 64.dp) = ArgonSkeletonGroup(Modifier.fillMaxSize()) {
    val spacing = ArgonTheme.spacing
    Column(Modifier.padding(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.l)) {
        repeat(rows) {
            Row(horizontalArrangement = Arrangement.spacedBy(spacing.m), verticalAlignment = Alignment.CenterVertically) {
                if (thumbnail > 0.dp) ArgonSkeleton(Modifier.size(thumbnail))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(spacing.xs)) {
                    ArgonSkeletonLine(widthFraction = 0.7f)
                    ArgonSkeletonLine(widthFraction = 0.4f, style = ArgonTheme.type.label)
                }
            }
        }
    }
}

/** A page of text (a store page, a policy): its title and a few paragraphs' lines. */
@Composable
fun TextSkeleton() = ArgonSkeletonGroup(Modifier.fillMaxSize()) {
    val spacing = ArgonTheme.spacing
    Column(Modifier.padding(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.s)) {
        ArgonSkeletonLine(Modifier.padding(bottom = spacing.s), widthFraction = 0.6f, style = ArgonTheme.type.title)
        listOf(1f, 0.95f, 1f, 0.7f, 1f, 0.9f, 0.5f).forEach { ArgonSkeletonLine(widthFraction = it) }
    }
}
