package app.storefront.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonBarColors
import app.argon.ui.components.LocalArgonBarColors
import app.storefront.AppGraph
import app.storefront.data.Appearance
import app.storefront.ui.sections.color

/** Whether the app is drawn dark: by the settings' appearance (`light`, `dark`), else as the device is. */
@Composable
fun isAppDark(): Boolean = when (AppGraph.appearance) {
    Appearance.Light -> false
    Appearance.Dark -> true
    Appearance.System -> isSystemInDarkTheme()
}

/**
 * The Argon theme with [accent] (`#RRGGBB` from the shop's brand) as the accent, ink when it's absent or unreadable; light
 * or dark by [isAppDark]. The top bars take the settings' `navigation.topBar` colours.
 */
@Composable
fun AppTheme(accent: String?, content: @Composable () -> Unit) = ArgonTheme(accentHex = accent, darkTheme = isAppDark()) {
    val navigation = AppGraph.navigation
    val bar = ArgonBarColors(navigation.topBarBackground.toColor(), navigation.topBarForeground.toColor())
    CompositionLocalProvider(LocalArgonBarColors provides bar, content = content)
}

/** A settings colour (`#RRGGBB`) as a colour; Unspecified (the theme's) when unset. */
internal fun String?.toColor(): Color = this?.let(::color) ?: Color.Unspecified
