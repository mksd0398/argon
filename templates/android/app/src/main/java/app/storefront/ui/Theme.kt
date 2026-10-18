package app.storefront.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import app.argon.ui.ArgonTheme
import app.storefront.AppGraph
import app.storefront.data.Appearance

/** Whether the app is drawn dark: by the settings' appearance (`light`, `dark`), else as the device is. */
@Composable
fun isAppDark(): Boolean = when (AppGraph.appearance) {
    Appearance.Light -> false
    Appearance.Dark -> true
    Appearance.System -> isSystemInDarkTheme()
}

/**
 * The Argon theme with [accent] (`#RRGGBB` from the shop's brand) as the accent, ink when it's absent or unreadable; light
 * or dark by [isAppDark].
 */
@Composable
fun AppTheme(accent: String?, content: @Composable () -> Unit) = ArgonTheme(accentHex = accent, darkTheme = isAppDark(), content = content)
