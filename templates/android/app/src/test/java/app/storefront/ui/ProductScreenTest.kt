package app.storefront.ui

import app.storefront.data.Money
import app.storefront.data.Product
import app.storefront.data.Variant
import org.junit.Assert.assertEquals
import org.junit.Test

class ProductScreenTest {
    @Test
    fun metafieldIdentifiersSplitOnTheFirstDot() {
        assertEquals(
            """[{"namespace":"custom","key":"material"},{"namespace":"custom","key":"care"}]""",
            metafieldIdentifiers("custom.material, custom.care").toString(),
        )
        assertEquals("""[{"namespace":"a","key":"b.c"}]""", metafieldIdentifiers("a.b.c").toString())
    }

    @Test
    fun blankAndMalformedEntriesAreSkipped() {
        assertEquals("[]", metafieldIdentifiers("").toString())
        assertEquals("""[{"namespace":"a","key":"b"}]""", metafieldIdentifiers("bad, ,.x,y.,a.b,").toString())
    }

    private fun variant(id: String, available: Boolean, size: String) =
        Variant(id, size, available, mapOf("Size" to size), Money("10.00", "USD"), null, null)

    private fun product(vararg variants: Variant) =
        Product("p", "h", "T", "V", "", emptyList(), listOf("Size" to variants.map { it.title }), variants.toList(), emptyList())

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
