package app.argon.ui

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import kotlin.math.pow

/** The colour tokens. [accent] is the shop's brand colour (ink when it has none); [onAccent] is text on it; text on
 *  [sale] (badges, destructive buttons) uses [paper]. */
@Immutable
data class ArgonColors(
    val ink: Color,
    val muted: Color,
    val paper: Color,
    val surface: Color,
    val border: Color,
    val accent: Color,
    val onAccent: Color,
    val sale: Color,
    val success: Color,
)

/** Token values as 0xRRGGBB, the same as iOS's ArgonPalette. Dark swaps paper and ink and keeps surfaces close to paper. */
internal enum class Palette(
    val ink: Int,
    val muted: Int,
    val paper: Int,
    val surface: Int,
    val border: Int,
    val sale: Int,
    val success: Int,
) {
    Light(ink = 0x17150F, muted = 0x6E6A63, paper = 0xF6F4F0, surface = 0xFFFFFF, border = 0xE2DED6, sale = 0xB23A2E, success = 0x2E7D4F),
    Dark(ink = 0xF6F4F0, muted = 0xA29E96, paper = 0x17150F, surface = 0x221F19, border = 0x3A362F, sale = 0xE8735F, success = 0x6CC08A),
}

internal const val BLACK = 0x000000
internal const val WHITE = 0xFFFFFF

/** `#RRGGBB` (the `#` optional) as 0xRRGGBB; null when absent or malformed. */
fun parseHexColor(hex: String?): Int? =
    hex?.trim()?.removePrefix("#")?.takeIf { HEX.matches(it) }?.toInt(16)

private val HEX = Regex("[0-9a-fA-F]{6}")

/** WCAG 2 relative luminance of 0xRRGGBB, 0 (black) to 1 (white). */
fun relativeLuminance(rgb: Int): Double {
    fun channel(shift: Int): Double {
        val c = ((rgb shr shift) and 0xFF) / 255.0
        return if (c <= 0.04045) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
    }
    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
}

/** WCAG 2 contrast ratio, 1 to 21. */
fun contrastRatio(a: Int, b: Int): Double {
    val la = relativeLuminance(a)
    val lb = relativeLuminance(b)
    return (maxOf(la, lb) + 0.05) / (minOf(la, lb) + 0.05)
}

/**
 * Black on colours with luminance above 0.5, else white: M3's `onPrimary` rule, and iOS's `onAccentHex`.
 * ponytail: mid-tones (#808080, #3B82F6) get white below 4.5:1; switch both platforms to whichever of black/white
 * contrasts more if brand colours like that turn up.
 */
fun onAccentFor(rgb: Int): Int = if (relativeLuminance(rgb) > 0.5) BLACK else WHITE

internal fun color(rgb: Int) = Color(0xFF000000 or rgb.toLong())

/** The tokens for [dark] or light mode with [accentHex] as the accent (ink when null or malformed). */
fun argonColors(accentHex: String?, dark: Boolean): ArgonColors {
    val p = if (dark) Palette.Dark else Palette.Light
    val accent = parseHexColor(accentHex) ?: p.ink
    return ArgonColors(
        ink = color(p.ink),
        muted = color(p.muted),
        paper = color(p.paper),
        surface = color(p.surface),
        border = color(p.border),
        accent = color(accent),
        onAccent = color(onAccentFor(accent)),
        sale = color(p.sale),
        success = color(p.success),
    )
}
