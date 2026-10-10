package app.storefront.ui

import app.storefront.data.MetafieldIdentifier
import app.storefront.data.Money
import app.storefront.data.Product
import app.storefront.data.SelectedOption
import app.storefront.data.Variant
import org.junit.Assert.assertEquals
import org.junit.Test

class ProductScreenTest {
    @Test
    fun metafieldIdentifiersSplitOnTheFirstDot() {
        assertEquals(
            listOf(MetafieldIdentifier("custom", "material"), MetafieldIdentifier("custom", "care")),
            metafieldIdentifiers("custom.material, custom.care"),
        )
        assertEquals(listOf(MetafieldIdentifier("a", "b.c")), metafieldIdentifiers("a.b.c"))
    }

    @Test
    fun blankAndMalformedEntriesAreSkipped() {
        assertEquals(emptyList<MetafieldIdentifier>(), metafieldIdentifiers(""))
        assertEquals(listOf(MetafieldIdentifier("a", "b")), metafieldIdentifiers("bad, ,.x,y.,a.b,"))
    }

    private fun variant(id: String, available: Boolean, size: String) =
        Variant(id, size, available, selectedOptions = listOf(SelectedOption("Size", size)), price = Money("10.00", "USD"))

    private fun product(vararg variants: Variant) = Product("p", "h", "T", variants = variants.toList())

    @Test
    fun selectionStartsAtTheFirstAvailableVariant() {
        assertEquals(mapOf("Size" to "M"), initialSelection(product(variant("1", false, "S"), variant("2", true, "M"), variant("3", true, "L"))))
    }

    @Test
    fun selectionFallsBackToTheFirstVariantWhenNoneIsAvailable() {
        assertEquals(mapOf("Size" to "S"), initialSelection(product(variant("1", false, "S"), variant("2", false, "M"))))
        assertEquals(emptyMap<String, String>(), initialSelection(product()))
    }
}
