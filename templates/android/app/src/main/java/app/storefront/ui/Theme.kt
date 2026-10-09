package app.storefront.ui

import androidx.compose.runtime.Composable
import app.argon.ui.ArgonTheme

/** The Argon theme with [accent] (`#RRGGBB` from the shop's brand) as the accent; ink when it's absent or unreadable. */
@Composable
fun AppTheme(accent: String?, content: @Composable () -> Unit) = ArgonTheme(accentHex = accent, content = content)
