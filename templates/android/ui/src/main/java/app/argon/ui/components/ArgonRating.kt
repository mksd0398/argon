package app.argon.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import java.util.Locale

/** How much of star [index] (0...4) a rating of [value] fills, 0 to 1. As iOS. */
fun starFill(value: Double, index: Int): Float = (value - index).coerceIn(0.0, 1.0).toFloat()

/** What a screen reader says for a rating: "4.6 out of 5, 128 reviews" (just the first part without a [count]). As iOS. */
fun ratingLabel(value: Double, count: Int? = null): String {
    val stars = String.format(Locale.US, "%.1f out of 5", value.coerceIn(0.0, 5.0))
    return when (count) {
        null -> stars
        1 -> "$stars, 1 review"
        else -> "$stars, $count reviews"
    }
}

/**
 * A rating out of five: five stars, the last one filled partly (4.6 fills 60% of the fifth), then the number of reviews
 * as "(128)". Stars are 12/16/22 dp by [size]. Read as one label ([ratingLabel]). Custom on both platforms.
 */
@Composable
fun ArgonRating(value: Double, modifier: Modifier = Modifier, count: Int? = null, size: ArgonSize = ArgonSize.S) {
    val side = when (size) {
        ArgonSize.S -> 12.dp
        ArgonSize.M -> 16.dp
        ArgonSize.L -> 22.dp
    }
    Row(
        modifier.clearAndSetSemantics { contentDescription = ratingLabel(value, count) },
        horizontalArrangement = Arrangement.spacedBy(side / 8),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(5) { index ->
            val fill = starFill(value, index)
            Box {
                ArgonIcon(ArgonIconName.StarFilled, size = side, tint = ArgonTheme.colors.border)
                // the same star in ink, cut at the fill: from the start edge, so from the right in RTL
                if (fill > 0f) {
                    ArgonIcon(
                        ArgonIconName.StarFilled,
                        Modifier.drawWithContent {
                            val cut = this.size.width * fill
                            if (layoutDirection == LayoutDirection.Rtl) {
                                clipRect(left = this.size.width - cut) { this@drawWithContent.drawContent() }
                            } else {
                                clipRect(right = cut) { this@drawWithContent.drawContent() }
                            }
                        },
                        size = side,
                        tint = ArgonTheme.colors.ink,
                    )
                }
            }
        }
        if (count != null) {
            Text(
                "($count)",
                Modifier.padding(start = ArgonTheme.spacing.xs - side / 8),
                style = if (size == ArgonSize.L) ArgonTheme.type.label else ArgonTheme.type.caption,
                color = ArgonTheme.colors.muted,
            )
        }
    }
}
