package app.storefront.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class VariantsTest {
    private fun variant(id: String, size: String, color: String) =
        Variant(id, "$size / $color", available = true, selectedOptions = listOf(SelectedOption("Size", size), SelectedOption("Color", color)), price = Money("10.0", "USD"))

    private val variants = listOf(variant("1", "S", "Red"), variant("2", "S", "Blue"), variant("3", "M", "Red"))

    @Test
    fun exactSelectionMatches() {
        assertEquals("2", Variants.match(variants, mapOf("Size" to "S", "Color" to "Blue"))?.id)
    }

    @Test
    fun combinationWithoutVariantIsNull() {
        assertNull(Variants.match(variants, mapOf("Size" to "M", "Color" to "Blue")))
    }

    @Test
    fun noVariantsIsNull() {
        assertNull(Variants.match(emptyList(), mapOf("Size" to "S")))
    }
}
