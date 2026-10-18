package app.storefront.ui

import app.storefront.data.Route
import app.storefront.data.StorePage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PageScreenTest {
    @Test
    fun aPageWithoutABodyOpensOnTheWeb() {
        assertEquals(Route.Web("https://shop.test/pages/contact"), webPage(StorePage("1", "contact", "Contact", body = " "), "shop.test"))
        assertEquals(Route.Web("https://shop.test/pages/sections"), webPage(StorePage("2", "sections", "Sections", body = null), "shop.test"))
        assertNull(webPage(StorePage("3", "about", "About", body = "<p>Hello</p>"), "shop.test"))
    }
}
