package app.storefront.ui

import app.argon.ui.components.ArgonTopBarVariant.CenteredLogo
import app.argon.ui.components.ArgonTopBarVariant.Search
import app.argon.ui.components.ArgonTopBarVariant.Standard
import app.storefront.data.HomeTemplate
import org.junit.Assert.assertEquals
import org.junit.Test

class HomeBarTest {
    @Test
    fun theClearBarFollowsTheMerchantsStyle() {
        for (template in HomeTemplate.entries) {
            assertEquals("search over the hero, $template", Search, homeBarVariant(template, "search", overlay = true))
            assertEquals(CenteredLogo, homeBarVariant(template, "centered_logo", overlay = true))
            assertEquals(Standard, homeBarVariant(template, "standard", overlay = true))
            assertEquals("no style: the centred logo, as ever", CenteredLogo, homeBarVariant(template, null, overlay = true))
        }
    }

    @Test
    fun withoutAStyleTheSolidBarIsTheTemplates() {
        assertEquals(CenteredLogo, homeBarVariant(HomeTemplate.Fashion, null, overlay = false))
        assertEquals(Standard, homeBarVariant(HomeTemplate.Beauty, null, overlay = false))
        assertEquals(Search, homeBarVariant(HomeTemplate.Grocery, null, overlay = false))
        assertEquals(Search, homeBarVariant(HomeTemplate.B2B, null, overlay = false))
        assertEquals("the merchant's style wins", Standard, homeBarVariant(HomeTemplate.Grocery, "standard", overlay = false))
    }
}
