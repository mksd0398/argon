package app.argon.ui

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import kotlin.math.pow

/** The colour tokens. [accent] is the shop's brand colour (ink when it has none); [onAccent] is text on it; [secondary]
 *  the second brand colour (ink unless set), [onSecondary] text on it; text on [sale] (badges, destructive buttons)
 *  uses [paper]. */
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
    val secondary: Color = ink,
    val onSecondary: Color = paper,
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

/** Black or white, whichever contrasts more with [rgb], so text on any accent gets at least 4.58:1. Same rule as iOS's `onAccentHex`. */
fun onAccentFor(rgb: Int): Int = if (contrastRatio(rgb, BLACK) >= contrastRatio(rgb, WHITE)) BLACK else WHITE

internal fun color(rgb: Int) = Color(0xFF000000 or rgb.toLong())

/** [a] at [amount] (0..1) over [b], each channel rounded (contract/theme.js `mix`). */
internal fun mix(a: Int, b: Int, amount: Double): Int = listOf(16, 8, 0).fold(0) { out, shift ->
    val c = ((a shr shift) and 0xFF) * amount + ((b shr shift) and 0xFF) * (1 - amount)
    out or (Math.round(c).toInt() shl shift)
}

/**
 * The tokens for [dark] or light mode with [accentHex] as the accent (ink when null or malformed). In light mode
 * [backgroundHex] and [textHex] replace paper and ink, and muted, border and surface are made from them as
 * contract/theme.js `themeTokens` makes them.
 */
fun argonColors(accentHex: String?, dark: Boolean, backgroundHex: String? = null, textHex: String? = null, secondaryHex: String? = null): ArgonColors {
    val p = if (dark) Palette.Dark else Palette.Light
    val background = if (dark) null else parseHexColor(backgroundHex)
    val text = if (dark) null else parseHexColor(textHex)
    val paper = background ?: p.paper
    val ink = text ?: p.ink
    val own = background != null || text != null
    val accent = parseHexColor(accentHex) ?: ink
    return ArgonColors(
        ink = color(ink),
        muted = color(if (own) mix(ink, paper, 0.62) else p.muted),
        paper = color(paper),
        surface = color(
            when {
                !own -> p.surface
                relativeLuminance(paper) > 0.5 -> mix(WHITE, paper, 0.7)
                else -> mix(ink, paper, 0.08)
            },
        ),
        border = color(if (own) mix(ink, paper, 0.14) else p.border),
        accent = color(accent),
        onAccent = color(onAccentFor(accent)),
        secondary = color(parseHexColor(secondaryHex) ?: ink),
        onSecondary = color(onAccentFor(parseHexColor(secondaryHex) ?: ink)),
        sale = color(p.sale),
        success = color(p.success),
    )
}
