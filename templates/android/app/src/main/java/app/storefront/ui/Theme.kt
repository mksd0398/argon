package app.storefront.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.isSpecified
import androidx.compose.ui.graphics.luminance
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

/** Whether the status bar lies on a dark colour: the settings' `navigation.topBar.background` when set, else the theme's. */
@Composable
fun isBarDark(): Boolean {
    // the merchant's bar colour, else (light mode) the theme's own background, which the bar takes
    val bar = AppGraph.navigation.topBarBackground.toColor().takeIf { it.isSpecified }
        ?: if (isAppDark()) Color.Unspecified else AppGraph.look.background.toColor()
    return if (bar.isSpecified) bar.luminance() < 0.5f else isAppDark()
}

/**
 * The Argon theme with [accent] (`#RRGGBB` from the shop's brand) as the accent, ink when it's absent or unreadable; light
 * or dark by [isAppDark]; the settings' background, text, corners and buttons ([AppGraph.look]). The top bars take the
 * settings' `navigation.topBar` colours.
 */
@Composable
fun AppTheme(accent: String?, content: @Composable () -> Unit) {
    val look = AppGraph.look
    ArgonTheme(
        accent, isAppDark(), AppGraph.headingFont, AppGraph.bodyFont, look.background, look.text, look.corners, look.buttons,
        look.secondary, look.scale, look.icons,
    ) {
        val navigation = AppGraph.navigation
        val bar = ArgonBarColors(navigation.topBarBackground.toColor(), navigation.topBarForeground.toColor())
        // the status bar icons over a merchant's own bar colour (the theme's are set by MainActivity)
        if (bar.container.isSpecified) StatusBarIcons(light = false)
        CompositionLocalProvider(LocalArgonBarColors provides bar, content = content)
    }
}

/**
 * A colour setting as a colour in the current theme: one of its colours by name ([app.storefront.data.COLOR_NAMES],
 * following the theme and light or dark) or a `#RRGGBB` of its own; Unspecified (the theme's) when unset or neither.
 */
@Composable
@ReadOnlyComposable
internal fun String?.toColor(): Color {
    val c = ArgonTheme.colors
    return when (this) {
        null -> Color.Unspecified
        "accent" -> c.accent
        "secondary" -> c.secondary
        "background" -> c.paper
        "surface" -> c.surface
        "text" -> c.ink
        "muted" -> c.muted
        "border" -> c.border
        "sale" -> c.sale
        else -> color(this) ?: Color.Unspecified
    }
}
