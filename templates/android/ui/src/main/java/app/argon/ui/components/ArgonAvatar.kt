package app.argon.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import coil3.compose.AsyncImage

/**
 * A round picture: [imageUrl] over [initials] over [icon] (a person by default), so a missing or failed image
 * shows the next one. Sizes 32, 40, 56 dp. Custom on both platforms.
 */
@Composable
fun ArgonAvatar(
    modifier: Modifier = Modifier,
    imageUrl: String? = null,
    initials: String? = null,
    icon: ArgonIconName? = null,
    size: ArgonSize = ArgonSize.M,
    contentDescription: String? = null,
) {
    val side = when (size) {
        ArgonSize.S -> 32.dp
        ArgonSize.M -> 40.dp
        ArgonSize.L -> 56.dp
    }
    // initials are sized to the circle, not to the font scale
    val type = ArgonTheme.type.headline.copy(fontSize = with(LocalDensity.current) { (side * 0.38f).toSp() })
    Box(
        modifier.size(side).clip(CircleShape).background(ArgonTheme.colors.border).border(1.dp, ArgonTheme.colors.border, CircleShape)
            .let { m -> contentDescription?.let { d -> m.semantics { this.contentDescription = d } } ?: m },
        contentAlignment = Alignment.Center,
    ) {
        if (!initials.isNullOrBlank()) {
            Text(initials.take(2).uppercase(), style = type, color = ArgonTheme.colors.ink)
        } else {
            ArgonIcon(icon ?: ArgonIconName.Person, size = side * 0.5f, tint = ArgonTheme.colors.muted)
        }
        if (imageUrl != null) AsyncImage(imageUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
    }
}
