package app.storefront.ui

import app.storefront.data.Filter
import app.storefront.data.FilterValue
import app.storefront.data.Money
import app.storefront.data.Swatch
import app.storefront.data.fixtureStorefront
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The filter sheet's logic, on the filters of the Collection fixture: availability, price, colour (swatches) and size. */
class FiltersTest {
    private val filters = runBlocking { fixtureStorefront().collection("men")!!.products.filters }
    private val availability = filters.first { it.id == "filter.v.availability" }
    private val price = filters.first { it.id == "filter.v.price" }
    private val color = filters.first { it.id == "filter.v.option.color" }
    private val size = filters.first { it.id == "filter.v.option.size" }
    private val green = color.values[0].input
    private val small = size.values[0].input

    private fun priceFilter(input: String) = Filter("filter.v.price", "Price", "PRICE_RANGE", listOf(FilterValue("filter.v.price", "Price", 14, input)))

    @Test
    fun eachFilterGetsItsControl() {
        assertEquals(
            listOf(FilterControl.Checkboxes, FilterControl.Slider, FilterControl.Swatches, FilterControl.Checkboxes),
            listOf(availability, price, color, size).map(::filterControl),
        )
    }

    @Test
    fun aColourFilterIsKnownByItsPresentationItsSwatchesOrItsName() {
        assertEquals(FilterControl.Checkboxes, filterControl(size))
        assertEquals(FilterControl.Swatches, filterControl(size.copy(presentation = "SWATCH")))
        assertEquals(FilterControl.Swatches, filterControl(size.copy(label = "Colour")))
        assertEquals(FilterControl.Swatches, filterControl(size.copy(label = " shade ")))
        val oneSwatch = size.values.mapIndexed { i, value -> if (i == 0) value.copy(swatch = Swatch(color = "#FFFFFF")) else value }
        assertEquals("the store set a swatch on a value", FilterControl.Swatches, filterControl(size.copy(values = oneSwatch)))
        assertEquals("a name that only mentions colour is not a colour filter", FilterControl.Checkboxes, filterControl(size.copy(label = "Colour family")))
    }

    @Test
    fun aFilterWithNothingToChooseHasNoControl() {
        assertNull(filterControl(size.copy(values = emptyList())))
        assertNull("a price filter without a value has no bounds", filterControl(Filter("filter.v.price", "Price", "PRICE_RANGE")))
        assertNull("every product costs the same", filterControl(priceFilter("""{"price":{"min":40,"max":40}}""")))
    }

    @Test
    fun aBooleanFilterIsASwitchOnItsTrueValue() {
        fun value(id: String, flag: String) = FilterValue(id, flag, 2, """{"productMetafield":{"namespace":"custom","key":"vegan","value":"$flag"}}""")
        val vegan = Filter("filter.p.m.custom.vegan", "Vegan", "BOOLEAN", listOf(value("no", "false"), value("yes", "true")))
        assertEquals(FilterControl.Switch, filterControl(vegan))
        assertEquals("yes", booleanValue(vegan)?.id)
        assertEquals("without a true value: the first", "no", booleanValue(vegan.copy(values = vegan.values.take(1)))?.id)
    }

    @Test
    fun aTapAddsAValueAndASecondTapTakesItOut() {
        val one = toggled(emptyList(), green)
        assertEquals(listOf(green), one)
        val two = toggled(one, small)
        assertEquals("in the order selected", listOf(green, small), two)
        assertEquals(listOf(small), toggled(two, green))
    }

    @Test
    fun thePriceSliderTakesItsBoundsFromTheFilterValuesOwnInput() {
        assertEquals("""{"price":{"min":0,"max":120}}""", price.values.single().input)
        assertEquals(PriceSlider(0f..120f, 2f), priceSlider(price))
        assertEquals("widened to whole steps, so 119.99 stays inside", PriceSlider(12f..120f, 2f), priceSlider(priceFilter("""{"price":{"min":12.5,"max":119.99}}""")))
        assertEquals("a currency with large amounts", PriceSlider(0f..48000f, 500f), priceSlider(priceFilter("""{"price":{"min":0,"max":48000}}""")))
        assertEquals("no min: from 0", PriceSlider(0f..80f, 1f), priceSlider(priceFilter("""{"price":{"max":80}}""")))
        assertNull(priceSlider(size))
    }

    @Test
    fun theStepKeepsTheSliderAtAHundredStopsOrFewer() {
        assertEquals(
            listOf(1f, 1f, 2f, 5f, 10f, 20f, 50f),
            listOf(0.5f, 100f, 101f, 250f, 1000f, 2000f, 4999f).map(::priceStep),
        )
    }

    @Test
    fun thePriceInputIsShopifysProductFilter() {
        assertEquals("""{"price":{"min":10.0,"max":50.0}}""", priceInput(10f, 50f))
        assertEquals(10f to 50f, priceRange(priceInput(10f, 50f)))
        assertEquals(0f to 120f, priceRange("""{"price":{"min":0,"max":120}}"""))
        assertEquals(null to 20f, priceRange("""{"price":{"max":20}}"""))
        assertNull("another filter", priceRange(green))
        assertNull(priceRange("not json"))
    }

    @Test
    fun thePriceRangeIsOneEntryOfTheSelection() {
        val bounds = 0f..120f
        val one = withPrice(listOf(green), 20f, 60f, bounds)
        assertEquals(listOf(green, """{"price":{"min":20.0,"max":60.0}}"""), one)
        assertEquals(20f to 60f, priceSelection(one))
        assertEquals("moved: replaced, not added", listOf(green, """{"price":{"min":20.0,"max":80.0}}"""), withPrice(one, 20f, 80f, bounds))
        assertEquals("the whole range is no filter", listOf(green), withPrice(one, 0f, 120f, bounds))
        assertNull(priceSelection(listOf(green)))
    }

    @Test
    fun aFilterIsActiveWhenTheSelectionHasOneOfItsValues() {
        assertTrue(isActive(color, listOf(green)))
        assertFalse(isActive(size, listOf(green)))
        assertFalse("the price filter's own input is its bounds, not a selection", isActive(price, listOf(green)))
        assertTrue(isActive(price, listOf(priceInput(20f, 60f))))
    }

    @Test
    fun selectedFiltersAreNamedForTheirTags() {
        val inStock = availability.values[0].input
        val gone = """{"variantOption":{"name":"color","value":"Teal"}}"""
        val applied = listOf(green, inStock, priceInput(20f, 60f), gone)
        val active = activeFilters(applied, filters)
        assertEquals(applied, active.map { it.input })
        assertEquals(listOf("Green", "In stock", "20 – 60", "Teal"), active.map { it.label })
        assertEquals(
            "in the list's currency once it is known",
            "${Money("20.0", "USD").display()} – ${Money("60.0", "USD").display()}",
            activeFilters(listOf(priceInput(20f, 60f)), filters, "USD").single().label,
        )
        val vegan = Filter("b", "Vegan", "BOOLEAN", listOf(FilterValue("yes", "true", 2, """{"productMetafield":{"key":"vegan","value":"true"}}""")))
        assertEquals("a switch is named by its filter", "Vegan", activeFilters(listOf(vegan.values[0].input), listOf(vegan)).single().label)
        assertEquals("unreadable: itself, so it can still be removed", "?", activeFilters(listOf("?"), filters).single().label)
    }

    @Test
    fun countsReadNaturally() {
        assertEquals("14 products", resultCount(14, hasNext = false))
        assertEquals("1 product", resultCount(1, hasNext = false))
        assertEquals("0 products", resultCount(0, hasNext = false))
        assertEquals("more pages to come", "24+ products", resultCount(24, hasNext = true))
        assertEquals("Filters", countLabel("Filters", 0))
        assertEquals("Filter (2)", countLabel("Filter", 2))
    }
}
