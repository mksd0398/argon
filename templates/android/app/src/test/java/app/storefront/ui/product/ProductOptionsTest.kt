package app.storefront.ui.product

import app.storefront.data.Img
import app.storefront.data.Money
import app.storefront.data.Product
import app.storefront.data.ProductOption
import app.storefront.data.ProductOptionValue
import app.storefront.data.SelectedOption
import app.storefront.data.Variant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProductOptionsTest {
    private fun option(name: String, vararg values: String) = ProductOption(name = name, optionValues = values.map { ProductOptionValue(name = it) })

    private fun variant(size: String, color: String, available: Boolean = true, compareAt: String? = null, image: Img? = null) = Variant(
        "$size-$color",
        "$size / $color",
        available,
        selectedOptions = listOf(SelectedOption("Size", size), SelectedOption("Color", color)),
        price = Money("80.0", "USD"),
        compareAtPrice = compareAt?.let { Money(it, "USD") },
        image = image,
    )

    private val size = option("Size", "S", "M")
    private val color = option("Color", "Red", "Blue")

    // S/Blue is sold out, M/Blue doesn't exist
    private val variants = listOf(variant("S", "Red"), variant("S", "Blue", available = false), variant("M", "Red"))

    @Test
    fun aProductWithoutOptionsHasNothingToChoose() {
        assertEquals(emptyList<ProductOption>(), visibleOptions(Product("p", "h", "T", options = listOf(option("Title", "Default Title")))))
        assertEquals(listOf(size, color), visibleOptions(Product("p", "h", "T", options = listOf(size, color))))
        val titles = option("Title", "Hardcover", "Paperback")
        assertEquals("a real option named Title stays", listOf(titles), visibleOptions(Product("p", "h", "T", options = listOf(titles))))
    }

    @Test
    fun aValueIsAvailableWhenItGivesABuyableVariantWithTheRestOfTheSelection() {
        val selection = mapOf("Size" to "S", "Color" to "Red")
        assertEquals(setOf("S", "M"), availableValues(variants, selection, size))
        assertEquals("S in Blue is sold out", setOf("Red"), availableValues(variants, selection, color))
    }

    @Test
    fun aCombinationThatDoesNotExistIsNotAvailable() {
        assertEquals(setOf("Red"), availableValues(variants, mapOf("Size" to "M", "Color" to "Red"), color))
        assertEquals("from S/Blue, M would be the missing M/Blue", setOf<String>(), availableValues(variants, mapOf("Size" to "S", "Color" to "Blue"), size))
        assertEquals(emptySet<String>(), availableValues(emptyList(), mapOf("Size" to "S"), size))
    }

    @Test
    fun pastTheLoadedVariantsAnUnlistedCombinationCountsAsAvailable() {
        // 250 variants loaded (the API's page): a combination that isn't among them may still exist
        val many = (1..250).map { variant("$it", "Red", available = it != 2) }
        val sizes = option("Size", "1", "2", "999")
        assertEquals("listed and sold out is still struck", setOf("1", "999"), availableValues(many, mapOf("Size" to "1", "Color" to "Red"), sizes))
        assertEquals(setOf("Red", "Blue"), availableValues(many, mapOf("Size" to "1", "Color" to "Red"), color))
    }

    // Gallery

    @Test
    fun aVariantsImageIsFoundAmongTheProductsWhateverItsSizeParameters() {
        val images = listOf(Img("https://cdn.test/a.jpg"), Img("https://cdn.test/b.jpg?v=1"))
        assertEquals(1, imageIndex(images, Img("https://cdn.test/b.jpg?width=600")))
        assertEquals(0, imageIndex(images, Img("https://cdn.test/a.jpg")))
        assertNull(imageIndex(images, Img("https://cdn.test/c.jpg")))
        assertNull(imageIndex(images, null))
        assertNull(imageIndex(emptyList(), Img("https://cdn.test/a.jpg")))
    }

    @Test
    fun theGallerysTagsSayOnlyWhatIsTrue() {
        assertEquals(emptyList<GalleryTag>(), galleryTags(null))
        assertEquals(emptyList<GalleryTag>(), galleryTags(variant("S", "Red")))
        assertEquals(
            listOf(GalleryTag("Sale −20%", isSale = true), GalleryTag("Sold out")),
            galleryTags(variant("S", "Red", available = false, compareAt = "100.0")),
        )
        assertEquals(listOf(GalleryTag("Bundle")), galleryTags(variant("S", "Red").copy(requiresComponents = true)))
    }
}
