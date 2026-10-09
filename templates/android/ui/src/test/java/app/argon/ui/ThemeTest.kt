package app.argon.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ThemeTest {
    @Test
    fun parsesSixDigitHexWithOrWithoutHash() {
        assertEquals(0xFF8000, parseHexColor("#FF8000"))
        assertEquals(0x1A2B3C, parseHexColor("1a2b3c"))
        assertEquals(0xFFFFFF, parseHexColor(" #FFFFFF "))
    }

    @Test
    fun rejectsMissingOrMalformedHex() {
        for (bad in listOf(null, "", "#", "#FFF", "#12345", "#1234567", "#GGGGGG", "-12345", "+12345", "brand")) {
            assertNull("$bad", parseHexColor(bad))
        }
    }

    @Test
    fun luminanceAndContrastFollowWcag() {
        assertEquals(0.0, relativeLuminance(BLACK), 1e-9)
        assertEquals(1.0, relativeLuminance(WHITE), 1e-9)
        assertEquals(21.0, contrastRatio(BLACK, WHITE), 1e-9)
        assertEquals(contrastRatio(0x1E88E5, WHITE), contrastRatio(WHITE, 0x1E88E5), 1e-9)
    }

    @Test
    fun onAccentTakesTheHigherContrast() {
        assertEquals("yellow takes black", BLACK, onAccentFor(0xFFEB3B))
        assertEquals("mid blue takes black (5.7:1 vs 3.7:1)", BLACK, onAccentFor(0x1E88E5))
        assertEquals("mid grey takes black", BLACK, onAccentFor(0x808080))
        assertEquals("navy takes white", WHITE, onAccentFor(0x1A237E))
        for (rgb in 0..0xFFFFFF step 0x0F0F0F + 0x2) {
            val ratio = contrastRatio(rgb, onAccentFor(rgb))
            assertTrue("%06X: %.2f".format(rgb, ratio), ratio >= 4.5)
        }
    }

    @Test
    fun textColoursMeetAA() {
        for (p in Palette.entries) {
            for ((name, text) in listOf("ink" to p.ink, "muted" to p.muted, "sale" to p.sale, "success" to p.success)) {
                for ((bgName, bg) in listOf("paper" to p.paper, "surface" to p.surface)) {
                    val ratio = contrastRatio(text, bg)
                    assertTrue("${p.name} $name on $bgName: %.2f".format(ratio), ratio >= 4.5)
                }
            }
            assertTrue("${p.name} paper on sale (badges, destructive buttons)", contrastRatio(p.paper, p.sale) >= 4.5)
            // without a brand colour the accent is ink
            assertTrue("${p.name} onAccent on the default accent", contrastRatio(p.ink, onAccentFor(p.ink)) >= 4.5)
        }
    }

    @Test
    fun accentFallsBackToInk() {
        assertEquals(color(Palette.Light.ink), argonColors(null, dark = false).accent)
        assertEquals(color(Palette.Dark.ink), argonColors("not a colour", dark = true).accent)
        assertEquals("white on light-mode ink", color(WHITE), argonColors(null, dark = false).onAccent)
        assertEquals("black on dark-mode ink", color(BLACK), argonColors(null, dark = true).onAccent)
    }

    @Test
    fun brandAccentAndItsTextColour() {
        val colors = argonColors("#FFEB3B", dark = false)
        assertEquals(color(0xFFEB3B), colors.accent)
        assertEquals(color(BLACK), colors.onAccent)
    }
}
