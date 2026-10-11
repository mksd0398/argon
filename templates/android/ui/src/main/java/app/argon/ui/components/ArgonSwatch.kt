package app.argon.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.color
import app.argon.ui.parseHexColor
import coil3.compose.AsyncImage

/**
 * A colour to choose: a circle in the colour ([colorHex], `#RRGGBB`) or showing the image ([imageUrl], a pattern), with
 * a ring when selected and a diagonal strike when unavailable (it can still be tapped). [label] is its accessibility
 * name, shown under the circle at size L. Without a colour or an image the circle shows the label's first letter.
 * Circles are 16/32/44 dp by [size], with room for the ring around them. Custom on both platforms.
 */
@Composable
fun ArgonSwatch(
    colorHex: String?,
    imageUrl: String?,
    label: String,
    modifier: Modifier = Modifier,
    isSelected: Boolean = false,
    isAvailable: Boolean = true,
    size: ArgonSize = ArgonSize.M,
    onClick: (() -> Unit)? = null,
) {
    val diameter = when (size) {
        ArgonSize.S -> 16.dp
        ArgonSize.M -> 32.dp
        ArgonSize.L -> 44.dp
    }
    // room for the selection ring, kept when unselected so a row of swatches doesn't shift
    val ring = if (size == ArgonSize.S) 2.dp else 4.dp
    val colors = ArgonTheme.colors
    val fill = parseHexColor(colorHex)?.let(::color)
    Column(
        (if (onClick != null) modifier.selectable(isSelected, role = Role.RadioButton, onClick = onClick) else modifier)
            // one node named by the label: the letter and the text under a large swatch would only repeat it
            .clearAndSetSemantics {
                contentDescription = label
                if (onClick == null && isSelected) selected = true
                if (!isAvailable) stateDescription = "Unavailable"
            },
        verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.border(if (size == ArgonSize.S) 1.dp else 2.dp, if (isSelected) colors.ink else Color.Transparent, CircleShape).padding(ring)
                .size(diameter)
                .drawWithContent {
                    drawContent()
                    // bottom-start to top-end, over the faded colour
                    if (!isAvailable) {
                        val (w, h) = this.size
                        drawLine(colors.ink, Offset(w * 0.15f, h * 0.85f), Offset(w * 0.85f, h * 0.15f), strokeWidth = 1.5.dp.toPx())
                    }
                }
                // a hairline, so white and near-paper colours keep an edge
                .border(1.dp, colors.border, CircleShape)
                .alpha(if (isAvailable) 1f else 0.45f)
                .clip(CircleShape)
                .background(fill ?: colors.surface),
            contentAlignment = Alignment.Center,
        ) {
            if (fill == null && imageUrl == null && size != ArgonSize.S) {
                // sized to the circle, not to the font scale
                val letter = ArgonTheme.type.label.copy(fontSize = with(LocalDensity.current) { (diameter * 0.4f).toSp() })
                Text(label.take(1).uppercase(), style = letter, color = colors.muted)
            }
            if (imageUrl != null) AsyncImage(imageUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        }
        if (size == ArgonSize.L) {
            Text(
                label,
                Modifier.width(diameter + 24.dp),
                style = ArgonTheme.type.caption,
                color = if (isAvailable) colors.ink else colors.muted,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
