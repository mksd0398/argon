package app.storefront.ui.sections

import androidx.compose.ui.unit.dp
import app.storefront.data.ScreenSection
import app.storefront.data.SectionSettings
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Test

class SectionGapTest {
    private fun section(type: String, vararg settings: Pair<String, String>) =
        ScreenSection(type, type, SectionSettings(JsonObject(settings.associate { (k, v) -> k to JsonPrimitive(v) })))

    private val gap = 24.dp

    @Test
    fun edgeToEdgeSectionsSitFlush() {
        val text = section("rich_text")
        for (bleed in listOf(section("banner"), section("banner", "style" to "hero"), section("slideshow"), section("marquee"), section("video"), section("faq", "background" to "#112233"))) {
            assertEquals("${bleed.type} after an ordinary section", gap, gapBefore(text, bleed, gap))
            assertEquals("an ordinary section after ${bleed.type}", gap, gapBefore(bleed, text, gap))
            assertEquals("${bleed.type} after a hero", 0.dp, gapBefore(section("banner"), bleed, gap))
        }
        assertEquals("hero then marquee", 0.dp, gapBefore(section("banner"), section("marquee"), gap))
    }

    @Test
    fun ordinarySectionsKeepTheGap() {
        assertEquals(gap, gapBefore(section("rich_text"), section("products"), gap))
        assertEquals("a card banner is inset", gap, gapBefore(section("banner", "style" to "card"), section("faq"), gap))
        assertEquals("a malformed background is none", gap, gapBefore(section("faq", "background" to "blue"), section("faq"), gap))
    }

    @Test
    fun theFirstSectionHasNoGapAbove() {
        assertEquals(0.dp, gapBefore(null, section("rich_text"), gap))
    }
}
