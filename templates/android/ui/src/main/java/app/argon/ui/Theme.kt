package app.argon.ui

import android.content.Context
import androidx.annotation.FontRes
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.argon.ui.components.ArgonIconStyle
import app.argon.ui.components.LocalArgonIconStyle

/** Text roles. Display and title use Instrument Serif, the rest Hanken Grotesk; all in sp, so they follow font scale. */
@Immutable
data class ArgonType(
    val display: TextStyle,
    val title: TextStyle,
    val headline: TextStyle,
    val body: TextStyle,
    val label: TextStyle,
    val caption: TextStyle,
)

/** Spacing tokens: 2, 4, 8, 12, 16, 24, 32. */
object ArgonSpacing {
    val xxs = 2.dp
    val xs = 4.dp
    val s = 8.dp
    val m = 12.dp
    val l = 16.dp
    val xl = 24.dp
    val xxl = 32.dp
}

/** Corner tokens, s/m/l by [corners] (rounded: 4, 8, 16), and pill; [button] is the buttons' shape. */
@Immutable
class ArgonRadius(corners: ArgonCorners = ArgonCorners.Rounded, buttons: ArgonButtonShape = ArgonButtonShape.Pill) {
    val s = RoundedCornerShape(corners.dp[0].dp)
    val m = RoundedCornerShape(corners.dp[1].dp)
    val l = RoundedCornerShape(corners.dp[2].dp)
    val pill = RoundedCornerShape(percent = 50)
    val button = if (buttons == ArgonButtonShape.Pill) pill else RoundedCornerShape(buttons.dp.dp)
}

/** The theme's corners (contract/theme.js CORNERS): s, m and l in dp. */
enum class ArgonCorners(val dp: List<Int>) { Square(listOf(0, 0, 0)), Rounded(listOf(4, 8, 16)), Round(listOf(8, 16, 24)) }

/** The buttons' shape (contract/theme.js BUTTONS). */
enum class ArgonButtonShape(val dp: Int) { Pill(999), Rounded(8), Square(0) }

/** Small, medium, large (iOS `.s/.m/.l`): avatars, buttons, spinners. */
enum class ArgonSize { S, M, L }

private val LocalArgonColors = staticCompositionLocalOf { argonColors(null, dark = false) }
private val LocalArgonType = staticCompositionLocalOf { argonType(FontFamily.Default, FontFamily.Default) }
private val LocalArgonRadius = staticCompositionLocalOf { ArgonRadius() }

/** The tokens of the nearest [ArgonTheme]. */
object ArgonTheme {
    val colors: ArgonColors
        @Composable @ReadOnlyComposable get() = LocalArgonColors.current
    val type: ArgonType
        @Composable @ReadOnlyComposable get() = LocalArgonType.current
    val spacing = ArgonSpacing
    val radius: ArgonRadius
        @Composable @ReadOnlyComposable get() = LocalArgonRadius.current
}

/**
 * Argon's tokens for [content], also mapped onto Material 3 (colour scheme, typography, shapes), so native
 * controls follow them: primary is the accent. [accentHex] is the shop's `#RRGGBB` brand colour; ink when absent.
 * [headingFont] replaces the serif (display, title), [bodyFont] the sans (the other roles); null keeps Argon's.
 * [backgroundHex] and [textHex] replace paper and ink in light mode, [secondaryHex] is the second brand colour
 * ([argonColors]); [corners] and [buttons] shape it, [scale] sizes every text role and [icons] draws every icon.
 */
@Composable
fun ArgonTheme(
    accentHex: String? = null,
    darkTheme: Boolean = isSystemInDarkTheme(),
    headingFont: FontFamily? = null,
    bodyFont: FontFamily? = null,
    backgroundHex: String? = null,
    textHex: String? = null,
    corners: ArgonCorners = ArgonCorners.Rounded,
    buttons: ArgonButtonShape = ArgonButtonShape.Pill,
    secondaryHex: String? = null,
    scale: Float = 1f,
    icons: ArgonIconStyle = ArgonIconStyle.Outline,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val type = remember(context, headingFont, bodyFont, scale) {
        argonType(
            serif = headingFont ?: family(context, R.font.instrument_serif_regular) { FontFamily(Font(R.font.instrument_serif_regular)) },
            sans = bodyFont ?: family(context, R.font.hanken_grotesk) { FontFamily(listOf(400, 500, 600, 700).map(::hanken)) },
            scale = scale,
        )
    }
    val colors = remember(accentHex, darkTheme, backgroundHex, textHex, secondaryHex) { argonColors(accentHex, darkTheme, backgroundHex, textHex, secondaryHex) }
    val radius = remember(corners, buttons) { ArgonRadius(corners, buttons) }
    CompositionLocalProvider(
        LocalArgonColors provides colors,
        LocalArgonType provides type,
        LocalArgonRadius provides radius,
        LocalArgonIconStyle provides icons,
    ) {
        MaterialTheme(colorScheme = colors.material(darkTheme), typography = type.material(), shapes = radius.material(), content = content)
    }
}

// Hanken Grotesk ships as one variable font: each weight is a `wght` axis setting.
@OptIn(ExperimentalTextApi::class)
private fun hanken(weight: Int) =
    Font(R.font.hanken_grotesk, FontWeight(weight), variationSettings = FontVariation.Settings(FontVariation.weight(weight)))

/** [bundled], or the system font when the file can't be loaded. */
private fun family(context: Context, @FontRes res: Int, bundled: () -> FontFamily): FontFamily =
    runCatching { context.resources.getFont(res) }.fold({ bundled() }, { FontFamily.Default })

// Sizes and weights as on iOS, times the theme's [scale]; line heights are the fonts' own.
internal fun argonType(serif: FontFamily, sans: FontFamily, scale: Float = 1f) = ArgonType(
    display = TextStyle(fontFamily = serif, fontSize = 40.sp * scale),
    title = TextStyle(fontFamily = serif, fontSize = 28.sp * scale),
    headline = TextStyle(fontFamily = sans, fontWeight = FontWeight.SemiBold, fontSize = 17.sp * scale),
    body = TextStyle(fontFamily = sans, fontWeight = FontWeight.Normal, fontSize = 16.sp * scale),
    label = TextStyle(fontFamily = sans, fontWeight = FontWeight.Medium, fontSize = 14.sp * scale),
    caption = TextStyle(fontFamily = sans, fontWeight = FontWeight.Normal, fontSize = 12.sp * scale),
)

private fun ArgonColors.material(dark: Boolean): ColorScheme {
    val tint = accent.copy(alpha = 0.12f).compositeOver(surface)
    return (if (dark) darkColorScheme() else lightColorScheme()).copy(
        primary = accent,
        onPrimary = onAccent,
        primaryContainer = tint,
        onPrimaryContainer = ink,
        inversePrimary = paper,
        secondary = ink,
        onSecondary = paper,
        secondaryContainer = tint,
        onSecondaryContainer = ink,
        tertiary = accent,
        onTertiary = onAccent,
        tertiaryContainer = tint,
        onTertiaryContainer = ink,
        background = paper,
        onBackground = ink,
        surface = paper,
        onSurface = ink,
        surfaceVariant = border,
        onSurfaceVariant = muted,
        surfaceTint = Color.Transparent, // no accent wash on elevated surfaces
        inverseSurface = ink,
        inverseOnSurface = paper,
        error = sale,
        onError = paper,
        errorContainer = sale.copy(alpha = 0.12f).compositeOver(surface),
        onErrorContainer = ink,
        outline = muted,
        outlineVariant = border,
        surfaceBright = surface,
        surfaceDim = paper,
        surfaceContainerLowest = surface,
        surfaceContainerLow = surface,
        surfaceContainer = surface,
        surfaceContainerHigh = surface,
        surfaceContainerHighest = surface,
    )
}

/** Serif for display and headline roles, Hanken for text; titleLarge, titleSmall and labelMedium (app bar titles,
 *  tab and navigation bar labels) stay on the system font, as system chrome does on iOS. */
private fun ArgonType.material(): Typography {
    val serif = display.fontFamily
    val sans = body.fontFamily
    val d = Typography()
    return d.copy(
        displayLarge = d.displayLarge.copy(fontFamily = serif),
        displayMedium = d.displayMedium.copy(fontFamily = serif),
        displaySmall = d.displaySmall.copy(fontFamily = serif),
        headlineLarge = d.headlineLarge.copy(fontFamily = serif),
        headlineMedium = d.headlineMedium.copy(fontFamily = serif),
        headlineSmall = d.headlineSmall.copy(fontFamily = serif),
        titleMedium = d.titleMedium.copy(fontFamily = sans),
        bodyLarge = d.bodyLarge.copy(fontFamily = sans),
        bodyMedium = d.bodyMedium.copy(fontFamily = sans),
        bodySmall = d.bodySmall.copy(fontFamily = sans),
        labelLarge = d.labelLarge.copy(fontFamily = sans),
        labelSmall = d.labelSmall.copy(fontFamily = sans),
    )
}

private fun ArgonRadius.material() = Shapes(extraSmall = s, small = m, medium = m, large = l, extraLarge = l)
