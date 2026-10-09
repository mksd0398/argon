package app.argon.ui.components

import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.carousel.HorizontalMultiBrowseCarousel
import androidx.compose.material3.carousel.rememberCarouselState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import kotlinx.coroutines.delay

/**
 * [count] pages of [itemContent], one at a time: native [HorizontalPager] with page dots. [autoplaySeconds] advances
 * (and wraps) on a timer, paused while dragging and off when the system's animations are off.
 * [multiBrowse] (Android only) is the M3 multi-browse carousel instead: a large item with smaller peeks, no dots or autoplay.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArgonCarousel(
    count: Int,
    modifier: Modifier = Modifier,
    autoplaySeconds: Double? = null,
    showsIndicators: Boolean = true,
    multiBrowse: Boolean = false,
    itemContent: @Composable (Int) -> Unit,
) {
    if (multiBrowse) {
        HorizontalMultiBrowseCarousel(
            rememberCarouselState { count },
            preferredItemWidth = 220.dp,
            modifier = modifier.fillMaxWidth(),
            itemSpacing = ArgonTheme.spacing.s,
        ) { Box(Modifier.maskClip(MaterialTheme.shapes.large)) { itemContent(it) } }
        return
    }
    val pager = rememberPagerState { count }
    val animationsOff = animationsOff()
    val dragging by pager.interactionSource.collectIsDraggedAsState()
    if (autoplaySeconds != null && autoplaySeconds > 0 && count > 1 && !animationsOff) {
        LaunchedEffect(pager, dragging, autoplaySeconds, count) {
            if (dragging) return@LaunchedEffect
            while (true) {
                delay((autoplaySeconds * 1000).toLong())
                pager.animateScrollToPage((pager.currentPage + 1) % count)
            }
        }
    }
    Column(modifier) {
        HorizontalPager(pager, Modifier.fillMaxWidth()) { itemContent(it) }
        if (showsIndicators && count > 1) {
            Row(
                Modifier.fillMaxWidth().padding(top = ArgonTheme.spacing.s)
                    .semantics { stateDescription = "Page ${pager.currentPage + 1} of $count" },
                horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                repeat(count) { i ->
                    val current = i == pager.currentPage
                    Box(Modifier.size(if (current) 8.dp else 6.dp).background(if (current) ArgonTheme.colors.ink else ArgonTheme.colors.border, CircleShape))
                }
            }
        }
    }
}

/** True when the user turned animations off (Settings > Accessibility > Remove animations). */
@Composable
private fun animationsOff(): Boolean {
    val resolver = LocalContext.current.contentResolver
    return remember(resolver) { Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}
