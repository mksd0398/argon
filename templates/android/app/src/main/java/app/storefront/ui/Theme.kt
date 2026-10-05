package app.storefront.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance

/** Material 3 with [accent] (`#RRGGBB` from the shop's brand) as the primary colour; the default scheme when it's absent or unreadable. */
@Composable
fun AppTheme(accent: String?, content: @Composable () -> Unit) {
    val primary = accent?.removePrefix("#")?.takeIf { it.length == 6 }?.toLongOrNull(16)?.let { Color(0xFF000000 or it) }
    val base = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()
    val scheme = primary?.let { base.copy(primary = it, onPrimary = if (it.luminance() > 0.5f) Color.Black else Color.White) } ?: base
    MaterialTheme(colorScheme = scheme, content = content)
}
