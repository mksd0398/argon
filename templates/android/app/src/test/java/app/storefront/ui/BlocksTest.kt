package app.storefront.ui

import app.storefront.data.FilterValue
import app.storefront.data.Img
import app.storefront.data.Money
import app.storefront.data.ProductOptionValue
import app.storefront.data.QuantityRule
import app.storefront.data.Swatch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BlocksTest {
    // Swatch colours

    @Test
    fun aColourIsFoundByItsWholeNameThenItsLastWordThenAnyWord() {
        assertEquals("#000000", SwatchColors.hex("Black"))
        assertEquals("#1F2A5C", SwatchColors.hex("navy"))
        assertEquals("a blue, whatever kind", SwatchColors.hex("blue"), SwatchColors.hex("Peacock Blue"))
        assertEquals(SwatchColors.hex("white"), SwatchColors.hex("Off White"))
        assertEquals(SwatchColors.hex("white"), SwatchColors.hex("off-white"))
        assertEquals("the last word wins over an earlier one", SwatchColors.hex("green"), SwatchColors.hex("Olive Green"))
        assertEquals("no last-word match: any word", SwatchColors.hex("grey"), SwatchColors.hex("Light Grey Melange"))
        assertEquals("grey and gray are one colour", SwatchColors.hex("grey"), SwatchColors.hex("GRAY"))
    }

    @Test
    fun anUnknownNameAndMultiHaveNoColour() {
        assertNull(SwatchColors.hex("Ocean"))
        assertNull(SwatchColors.hex(""))
        assertNull(SwatchColors.hex("42"))
        assertNull("a word inside another isn't a match", SwatchColors.hex("Reddish"))
        assertNull(SwatchColors.hex("Multi"))
        assertNull("multi says there is no single colour", SwatchColors.hex("Blue Multi"))
    }

    @Test
    fun everyNamedColourIsAHexColour() {
        val names = listOf(
            "black", "white", "grey", "gray", "silver", "red", "maroon", "pink", "rose", "orange", "peach", "yellow", "gold",
            "mustard", "green", "olive", "teal", "turquoise", "blue", "navy", "sky", "purple", "violet", "lavender", "magenta",
            "brown", "tan", "beige", "cream", "ivory", "khaki", "coral", "mint", "lime", "burgundy", "wine", "charcoal", "copper",
            "bronze",
        )
        for (name in names) assertEquals(name, true, SwatchColors.hex(name)?.matches(Regex("#[0-9A-F]{6}")))
    }

    @Test
    fun aSwatchIsShopifysColourOrImageElseTheNamesColour() {
        assertEquals(SwatchFill("#3F6B4F", null), swatch(ProductOptionValue(name = "Green", swatch = Swatch(color = "#3F6B4F"))))
        assertEquals("no swatch data: by name", SwatchFill(SwatchColors.hex("green"), null), swatch(ProductOptionValue(name = "Forest Green")))
        assertEquals(SwatchFill(null, null), swatch(ProductOptionValue(name = "Ocean")))
        val pattern = Swatch(image = Swatch.Image(Img("https://cdn.test/floral.jpg")))
        assertEquals("an image swatch isn't given a guessed colour", SwatchFill(null, "https://cdn.test/floral.jpg"), swatch(ProductOptionValue(name = "Red Floral", swatch = pattern)))
        // a filter value goes by its label
        assertEquals(SwatchFill(SwatchColors.hex("olive"), null), swatch(FilterValue("f", "Olive", 9, "{}")))
        assertEquals(SwatchFill("#3F6B4F", null), swatch(FilterValue("f", "Green", 9, "{}", Swatch(color = "#3F6B4F"))))
    }

    // Prices

    private fun usd(amount: String) = Money(amount, "USD")

    @Test
    fun theDiscountIsAWholePercentOfTheCompareAtPrice() {
        assertEquals(20, discountPercent(usd("80.0"), usd("100.0")))
        assertEquals(33, discountPercent(usd("20.00"), usd("30.00")))
        assertEquals("rounded, not cut", 67, discountPercent(usd("10.0"), usd("30.0")))
        assertEquals(1, discountPercent(usd("99.4"), usd("100.0")))
        assertEquals(100, discountPercent(usd("0.0"), usd("5.0")))
    }

    @Test
    fun noDiscountWithoutAHigherCompareAtOrUnderOnePercent() {
        assertNull(discountPercent(usd("80.0"), null))
        assertNull("Shopify's 0.0 is no compare-at", discountPercent(usd("80.0"), usd("0.0")))
        assertNull(discountPercent(usd("80.0"), usd("80.00")))
        assertNull(discountPercent(usd("80.0"), usd("70.0")))
        assertNull("0.4% rounds to nothing", discountPercent(usd("99.6"), usd("100.0")))
        assertNull(discountPercent(usd("n/a"), usd("100.0")))
        assertNull(discountPercent(usd("80.0"), usd("")))
    }

    // Quantity rules

    @Test
    fun aQuantityRuleIsSaidOnlyWhereItLimits() {
        assertEquals("Min. 2 · Multiples of 2", quantityRuleLabel(QuantityRule(2, 40, 2)))
        assertEquals("Min. 6", quantityRuleLabel(QuantityRule(6, null, 1)))
        assertEquals("Multiples of 12", quantityRuleLabel(QuantityRule(1, null, 12)))
        assertNull("a store without rules sends 0", quantityRuleLabel(QuantityRule(0, null, 0)))
        assertNull(quantityRuleLabel(QuantityRule()))
        assertNull(quantityRuleLabel(null))
    }
}
