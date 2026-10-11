package app.storefront.ui

import app.storefront.data.CartLineComponent
import app.storefront.data.ResourceRef
import org.junit.Assert.assertEquals
import org.junit.Test

class CartScreenTest {
    private fun part(product: String?, variant: String, quantity: Int) =
        CartLineComponent("c", quantity, CartLineComponent.Merchandise("v", variant, product = ResourceRef("handle", product)))

    @Test
    fun aBundlesPartReadsAsItsProductItsVariantAndHowMany() {
        assertEquals("Men's T-shirt · Small / Olive × 1", componentLabel(part("Men's T-shirt", "Small / Olive", 1)))
        assertEquals("a product without options has no variant worth naming", "Gift card × 2", componentLabel(part("Gift card", "Default Title", 2)))
        assertEquals("Small × 3", componentLabel(part(null, "Small", 3)))
    }
}
