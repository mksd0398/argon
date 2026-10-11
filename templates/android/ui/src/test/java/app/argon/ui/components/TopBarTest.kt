package app.argon.ui.components

import app.argon.ui.argonColors
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TopBarTest {
    private val onPhoto = argonColors(null, dark = true)

    @Test
    fun overThePictureTheBarIsClearWithLightContentOnADarkShade() {
        for (dark in listOf(false, true)) {
            val bar = overlayBarColors(0f, argonColors(null, dark))
            assertEquals("no background", 0f, bar.container.alpha, 0f)
            assertEquals("light content, whatever the theme", onPhoto.ink, bar.content)
            assertEquals(onPhoto.paper.copy(alpha = SHADE), bar.shade)
        }
    }

    @Test
    fun solidItIsTheThemesBar() {
        for (dark in listOf(false, true)) {
            val theme = argonColors(null, dark)
            val bar = overlayBarColors(1f, theme)
            assertEquals(theme.paper, bar.container)
            assertEquals(theme.ink, bar.content)
            assertEquals("no shade left", 0f, bar.shade.alpha, 0f)
        }
    }

    @Test
    fun inBetweenTheBarFadesIn() {
        val theme = argonColors(null, dark = false)
        val bar = overlayBarColors(0.5f, theme)
        assertEquals(0.5f, bar.container.alpha, 0.01f)
        assertEquals(SHADE / 2, bar.shade.alpha, 0.01f)
        // the content is on its way from light to the theme's dark ink
        assertTrue(bar.content.red < onPhoto.ink.red && bar.content.red > theme.ink.red)
    }

    @Test
    fun solidIsClampedToItsRange() {
        val theme = argonColors(null, dark = false)
        assertEquals(overlayBarColors(0f, theme), overlayBarColors(-2f, theme))
        assertEquals(overlayBarColors(1f, theme), overlayBarColors(7f, theme))
    }
}
