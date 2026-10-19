package app.argon.ui.components

import android.provider.Settings
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.State
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import app.argon.ui.ArgonTheme

/** How long one sweep of the shimmer takes. */
internal const val SHIMMER_MILLIS = 1200

/** The shimmer of the [ArgonSkeletonGroup] a block is in (0…1 across it), so its blocks sweep together; null: still. */
private val LocalShimmer = compositionLocalOf<State<Float>?> { null }

/** Whether the system plays animations: not with the animator duration scale at 0 ("Remove animations" sets it there). */
@Composable
private fun animationsOn(): Boolean {
    val context = LocalContext.current
    return remember(context) { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) != 0f }
}

/** The shimmer's progress, looping 0…1 linearly every [SHIMMER_MILLIS]; null when animations are off. */
@Composable
private fun rememberShimmer(): State<Float>? {
    if (!animationsOn()) return null
    return rememberInfiniteTransition("skeleton").animateFloat(0f, 1f, infiniteRepeatable(tween(SHIMMER_MILLIS, easing = LinearEasing)), "shimmer")
}

/**
 * Stands in for a screen's content while it loads: [content] is laid out of [ArgonSkeleton] blocks shaped like what is
 * coming. Screen readers hear it once, as "Loading" ([label]); its blocks are silent. Its blocks shimmer together.
 */
@Composable
fun ArgonSkeletonGroup(modifier: Modifier = Modifier, label: String = "Loading", content: @Composable BoxScope.() -> Unit) {
    val shimmer = rememberShimmer()
    CompositionLocalProvider(LocalShimmer provides shimmer) {
        Box(modifier.clearAndSetSemantics { contentDescription = label }, content = content)
    }
}

/**
 * A placeholder block in the theme's subtle surface colour (its border colour), [shape] rounded, with a gentle light
 * sweeping across it every 1.2 s; still when the system's animations are off. Give it its size with [modifier]. Put a
 * screen's blocks in an [ArgonSkeletonGroup] (one "Loading" for screen readers); a block on its own says nothing.
 */
@Composable
fun ArgonSkeleton(modifier: Modifier = Modifier, shape: Shape = ArgonTheme.radius.m) {
    val colors = ArgonTheme.colors
    val shimmer = LocalShimmer.current ?: rememberShimmer()
    // a lighter band over the block: bright on a light theme, faint on a dark one
    val shine = Color.White.copy(alpha = if (colors.paper.luminance() > 0.5f) 0.55f else 0.07f)
    Box(
        modifier.clip(shape).background(colors.border).drawWithContent {
            // read in the draw phase: the sweep redraws the block, it doesn't recompose it
            val progress = shimmer?.value ?: return@drawWithContent
            val band = size.width.coerceAtLeast(1f)
            val x = -band + progress * (size.width + band)
            drawRect(Brush.linearGradient(listOf(Color.Transparent, shine, Color.Transparent), Offset(x, 0f), Offset(x + band, size.height)))
        },
    )
}

/** A line of text in [style] as a skeleton: as tall as the line (no jump when the text comes), the bar a little thinner. */
@Composable
fun ArgonSkeletonLine(modifier: Modifier = Modifier, widthFraction: Float = 1f, style: TextStyle = ArgonTheme.type.body) {
    val density = LocalDensity.current
    val (line, bar) = with(density) { (style.fontSize * 1.35f).toDp() to style.fontSize.toDp() }
    Box(modifier.fillMaxWidth(widthFraction).height(line).padding(vertical = (line - bar) / 2)) {
        ArgonSkeleton(Modifier.matchParentSize(), ArgonTheme.radius.s)
    }
}

/** A round skeleton [size] across (an avatar, a collection circle). */
@Composable
fun ArgonSkeletonCircle(size: Dp, modifier: Modifier = Modifier) = ArgonSkeleton(modifier.size(size), CircleShape)

/** A skeleton the width it is given at [aspectRatio] (width / height): an image, a card's picture. */
@Composable
fun ArgonSkeletonBox(aspectRatio: Float, modifier: Modifier = Modifier, shape: Shape = ArgonTheme.radius.m) =
    ArgonSkeleton(modifier.fillMaxWidth().aspectRatio(aspectRatio), shape)
