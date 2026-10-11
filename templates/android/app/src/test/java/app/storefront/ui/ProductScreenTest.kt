package app.storefront.ui

import app.storefront.data.MetafieldIdentifier
import app.storefront.data.Money
import app.storefront.data.Product
import app.storefront.data.SelectedOption
import app.storefront.data.Variant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
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

    private fun variant(id: String, available: Boolean, size: String, barcode: String? = null) =
        Variant(id, size, available, selectedOptions = listOf(SelectedOption("Size", size)), price = Money("10.00", "USD"), barcode = barcode)

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

    // Share

    @Test
    fun shareSendsTheWebStorePageElseTheProductsAddressOnTheShopsDomain() {
        val published = Product("p", "men-crewneck", "T", onlineStoreUrl = "https://shop.example/en/products/men-crewneck")
        assertEquals("https://shop.example/en/products/men-crewneck", shareUrl(published, "mock.shop"))
        assertEquals("https://mock.shop/products/men-crewneck", shareUrl(published.copy(onlineStoreUrl = null), "mock.shop"))
        assertEquals("https://mock.shop/products/men-crewneck", shareUrl(published.copy(onlineStoreUrl = " "), "mock.shop"))
    }

    // The selected variant in full: latest selection wins

    private val small = mapOf("Size" to "S")
    private val medium = mapOf("Size" to "M")

    @Test
    fun anAnswerForTheSelectionOnScreenIsKept() {
        val answer = RichVariant(medium, variant("2", true, "M", barcode = "0002"))
        assertSame(answer, latestAnswer(null, answer, selection = medium))
        assertSame("it replaces the answer of an earlier selection", answer, latestAnswer(RichVariant(small, null), answer, selection = medium))
    }

    @Test
    fun aStaleAnswerNeverOverwritesANewerOne() {
        // the shopper went from S to M; M has answered, and now S's answer comes in late
        val current = RichVariant(medium, variant("2", true, "M", barcode = "0002"))
        val late = RichVariant(small, variant("1", true, "S", barcode = "0001"))
        assertSame(current, latestAnswer(current, late, selection = medium))
        assertNull("nor does it show while M is still on its way", latestAnswer(null, late, selection = medium))
    }

    @Test
    fun thePageShowsTheFullVariantOnceItAnswersThisSelection() {
        val product = product(variant("1", true, "S"), variant("2", true, "M"))
        val full = variant("2", true, "M", barcode = "0002")
        assertEquals("until it answers: the product's own", "2", shownVariant(product, medium, null)?.id)
        assertNull(shownVariant(product, medium, null)?.barcode)
        assertSame(full, shownVariant(product, medium, RichVariant(medium, full)))
        assertNull("an answer for another selection isn't shown for this one", shownVariant(product, small, RichVariant(medium, full))?.barcode)
        assertEquals("a failed call leaves the product's own variant", "2", shownVariant(product, medium, RichVariant(medium, null))?.id)
    }

    @Test
    fun aSelectionOutsideTheLoadedVariantsGoesByTheFullVariantAlone() {
        // a product with more than 250 variants: XL isn't in the list
        val product = product(variant("1", true, "S"))
        val extraLarge = mapOf("Size" to "XL")
        assertNull(shownVariant(product, extraLarge, null))
        assertEquals("9", shownVariant(product, extraLarge, RichVariant(extraLarge, variant("9", true, "XL")))?.id)
        assertNull("no such variant: Unavailable", shownVariant(product, extraLarge, RichVariant(extraLarge, null)))
    }
}
