package app.storefront.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LinksTest {
    private val hosts = linkedSetOf("nalli.com", "nalli.myshopify.com")

    @Test
    fun shopUrlWithLocaleOpensProduct() {
        assertEquals(
            Route.Product("silk-saree"),
            Links.resolve("https://nalli.com/en-in/products/silk-saree?variant=1", setOf("nalli.com", "nalli.myshopify.com")),
        )
    }

    @Test
    fun collectionPath() {
        assertEquals(Route.Collection("all"), Links.resolve("/collections/all/", hosts))
    }

    @Test
    fun searchQueryIsDecoded() {
        assertEquals(Route.Search("red saree"), Links.resolve("/search?q=red+saree", hosts))
    }

    @Test
    fun otherHostOpensInBrowser() {
        assertEquals(Route.Web("https://instagram.com/x"), Links.resolve("https://instagram.com/x", hosts))
    }

    @Test
    fun blankOrRootIsNull() {
        assertNull(Links.resolve("", hosts))
        assertNull(Links.resolve(null, hosts))
        assertNull(Links.resolve("/", hosts))
    }

    @Test
    fun myshopifyHostStaysInApp() {
        assertEquals(Route.Product("x"), Links.resolve("https://nalli.myshopify.com/products/x", hosts))
    }

    @Test
    fun otherStorePathOpensInBrowserOnShopDomain() {
        assertEquals(Route.Web("https://nalli.com/pages/shipping"), Links.resolve("/pages/shipping", hosts))
    }

    @Test
    fun onlyHttpSchemesOpenInBrowser() {
        assertNull(Links.resolve("javascript:alert(1)", hosts))
        assertNull(Links.resolve("mailto:hi@nalli.com", hosts))
        assertEquals(Route.Web("http://instagram.com/x"), Links.resolve("http://instagram.com/x", hosts))
    }

    @Test
    fun rawSpaceInQueryIsEncoded() {
        assertEquals(Route.Search("red saree"), Links.resolve("/search?q=red saree", hosts))
    }
}
