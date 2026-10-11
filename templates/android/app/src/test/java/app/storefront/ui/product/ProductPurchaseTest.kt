package app.storefront.ui.product

import app.storefront.data.Money
import app.storefront.data.QuantityPriceBreak
import app.storefront.data.QuantityRule
import app.storefront.data.SellingPlan
import app.storefront.data.SellingPlanAllocation
import app.storefront.data.UnitPriceMeasurement
import app.storefront.data.Variant
import app.storefront.data.fixtureStorefront
import app.storefront.ui.display
import java.util.Locale
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProductPurchaseTest {
    private fun usd(amount: String) = Money(amount, "USD")
    private fun cad(amount: String) = Money(amount, "CAD")

    /** A plain variant, as a product's own list has it. */
    private val basic = Variant("v", "Small", available = true, price = usd("80.0"))

    /**
     * The contract's selected variant in full: $120.00, 4 in stock, sold in twos from 2 to 40, cheaper from 10 and from
     * 20, a bundle, with a monthly plan at $108.00.
     */
    private val rich: Variant = runBlocking { fixtureStorefront().variantBySelectedOptions("men-crewneck", mapOf("Size" to "Small", "Color" to "Olive"))!! }
    private val monthly = rich.sellingPlanAllocations.single()

    // Quantity

    @Test
    fun theQuantityIsKeptOnTheRule() {
        val pairs = QuantityRule(minimum = 2, maximum = 40, increment = 2)
        assertEquals("up to the minimum", 2, clampedQuantity(1, pairs))
        assertEquals(2, clampedQuantity(2, pairs))
        assertEquals("down onto the increments", 4, clampedQuantity(5, pairs))
        assertEquals("down to the maximum", 40, clampedQuantity(99, pairs))
        assertEquals("the top of a range that doesn't end on an increment", 9, clampedQuantity(50, QuantityRule(minimum = 3, maximum = 10, increment = 3)))
    }

    @Test
    fun withoutARuleAnyQuantityFromOneGoes() {
        assertEquals(7, clampedQuantity(7, null))
        assertEquals(1, clampedQuantity(0, null))
        assertEquals("mock.shop sends 0 for no rule", 3, clampedQuantity(3, QuantityRule(minimum = 0, maximum = null, increment = 0)))
    }

    // Volume pricing

    @Test
    fun theVolumeTableStartsAtTheVariantsPriceThenListsEachBreak() {
        val rows = volumeRows(rich)
        assertEquals(listOf(VolumeRow(2, cad("120.0")), VolumeRow(10, cad("108.0")), VolumeRow(20, cad("96.0"))), rows)
        assertEquals(listOf("2+", "10+", "20+"), rows.map { it.label })
        assertEquals("no breaks, no table", emptyList<VolumeRow>(), volumeRows(basic))
    }

    @Test
    fun theBreaksAreOrderedAndStartFromOneWithoutARule() {
        val variant = basic.copy(quantityPriceBreaks = listOf(QuantityPriceBreak(50, usd("60.0")), QuantityPriceBreak(10, usd("70.0"))))
        assertEquals(listOf(VolumeRow(1, usd("80.0")), VolumeRow(10, usd("70.0")), VolumeRow(50, usd("60.0"))), volumeRows(variant))
    }

    @Test
    fun theRowForAQuantityIsTheLastOneItReaches() {
        val rows = volumeRows(rich)
        assertEquals(rows[0], volumeRow(rows, 2))
        assertEquals(rows[0], volumeRow(rows, 9))
        assertEquals(rows[1], volumeRow(rows, 10))
        assertEquals(rows[1], volumeRow(rows, 19))
        assertEquals(rows[2], volumeRow(rows, 20))
        assertEquals(rows[2], volumeRow(rows, 40))
        assertNull("under the first row", volumeRow(rows, 1))
        assertNull(volumeRow(emptyList(), 5))
    }

    @Test
    fun thePriceOfOneFollowsTheQuantityAndThePlan() {
        assertEquals(ChosenPrice(cad("120.0"), null), chosenPrice(rich, 2, null))
        assertEquals("ten or more cost less each, with the full price struck", ChosenPrice(cad("108.0"), cad("120.0")), chosenPrice(rich, 10, null))
        assertEquals(ChosenPrice(cad("96.0"), cad("120.0")), chosenPrice(rich, 20, null))
        assertEquals("the plan's price, whatever the quantity", ChosenPrice(cad("108.0"), cad("120.0")), chosenPrice(rich, 20, monthly))
    }

    @Test
    fun aVariantOnSaleKeepsItsCompareAtPrice() {
        val onSale = basic.copy(compareAtPrice = usd("100.0"))
        assertEquals(ChosenPrice(usd("80.0"), usd("100.0")), chosenPrice(onSale, 1, null))
        assertEquals(ChosenPrice(usd("80.0"), null), chosenPrice(basic, 3, null))
        val planWithoutPrices = SellingPlanAllocation(SellingPlan("p", "Monthly"))
        assertEquals("a plan that sends no price costs the variant's", ChosenPrice(usd("80.0"), null), chosenPrice(basic, 1, planWithoutPrices))
    }

    // Unit price

    @Test
    fun theUnitPriceReadsPerItsReferenceAmount() {
        Locale.setDefault(Locale.US)
        assertEquals("$6.00 / item", unitPriceLabel(usd("6.0"), UnitPriceMeasurement("COUNT", "ITEM", 2.0, "ITEM", 1)))
        assertEquals("$2.50 / 100 g", unitPriceLabel(usd("2.5"), UnitPriceMeasurement("WEIGHT", "G", 250.0, "G", 100)))
        assertEquals("$4.00 / kg", unitPriceLabel(usd("4.0"), UnitPriceMeasurement("WEIGHT", "G", 500.0, "KG", 1)))
        assertEquals("$1.20 / fl oz", unitPriceLabel(usd("1.2"), UnitPriceMeasurement("VOLUME", "FLOZ", 12.0, "FLOZ", 1)))
        assertEquals("$9.00 / m²", unitPriceLabel(usd("9.0"), UnitPriceMeasurement("AREA", "M2", 3.0, "M2", 1)))
        assertEquals("${cad("60.0").display()} / item", unitPriceLabel(rich.unitPrice, rich.unitPriceMeasurement))
    }

    @Test
    fun noUnitPriceWithoutAPriceAndAUnit() {
        assertNull(unitPriceLabel(null, UnitPriceMeasurement("COUNT", "ITEM", 2.0, "ITEM", 1)))
        assertNull(unitPriceLabel(usd("6.0"), null))
        assertNull(unitPriceLabel(usd("6.0"), UnitPriceMeasurement()))
        assertNull(unitPriceLabel(basic.unitPrice, basic.unitPriceMeasurement))
    }

    // Quantity rule

    @Test
    fun theRuleSentenceNamesOnlyThePartsThatLimitAnOrder() {
        assertEquals("Minimum 2 · Maximum 40 · Sold in multiples of 2", quantityRuleSentence(rich.quantityRule))
        assertEquals("Maximum 10", quantityRuleSentence(QuantityRule(minimum = 1, maximum = 10, increment = 1)))
        assertEquals("Minimum 6 · Sold in multiples of 6", quantityRuleSentence(QuantityRule(minimum = 6, increment = 6)))
        assertNull(quantityRuleSentence(QuantityRule()))
        assertNull("mock.shop's zeros are no rule", quantityRuleSentence(QuantityRule(minimum = 0, maximum = null, increment = 0)))
        assertNull(quantityRuleSentence(null))
    }

    // Availability

    @Test
    fun theAvailabilityLineGoesByStock() {
        assertEquals(AvailabilityLine("Only 4 left", AvailabilityTone.Low), availabilityLine(rich))
        assertEquals(AvailabilityLine("Only 1 left", AvailabilityTone.Low), availabilityLine(rich.copy(quantityAvailable = 1)))
        assertEquals(AvailabilityLine("In stock", AvailabilityTone.Good), availabilityLine(rich.copy(quantityAvailable = 6)))
        assertEquals("a token that may not read stock", AvailabilityLine("In stock", AvailabilityTone.Good), availabilityLine(basic))
        assertEquals(
            AvailabilityLine("Ships when back in stock", AvailabilityTone.Later),
            availabilityLine(rich.copy(quantityAvailable = 0, currentlyNotInStock = true)),
        )
    }

    @Test
    fun aVariantThatCantBeBoughtHasNoAvailabilityLine() {
        assertNull(availabilityLine(null))
        assertNull(availabilityLine(basic.copy(available = false)))
        assertNull("sold out with a stale count", availabilityLine(rich.copy(available = false)))
    }

    // Sale tag

    @Test
    fun theSaleTagIsThePercentOffTheCompareAtPrice() {
        assertEquals("Sale −20%", saleTag(usd("80.0"), usd("100.0")))
        assertEquals("Sale −33%", saleTag(usd("20.0"), usd("30.0")))
        assertNull(saleTag(usd("80.0"), null))
        assertNull(saleTag(usd("80.0"), usd("80.0")))
        assertNull("Shopify's 0.0 is no compare-at", saleTag(usd("80.0"), usd("0.0")))
    }

    // Selling plans

    @Test
    fun aPlanCostsItsFirstPriceAdjustment() {
        assertEquals(cad("108.0"), planPrice(monthly))
        assertNull(planPrice(SellingPlanAllocation(SellingPlan("p", "Monthly"))))
        assertEquals("Deliver every month · ${cad("108.0").display()}", planLabel(monthly))
        assertEquals("Monthly", planLabel(SellingPlanAllocation(SellingPlan("p", "Monthly"))))
    }

    @Test
    fun thePlanIsTheChosenOneElseOneTimeElseTheFirstWhenAPlanIsRequired() {
        assertNull("nothing chosen: a one-time purchase", chosenPlan(rich, requiresSellingPlan = false, planId = null))
        assertEquals(monthly, chosenPlan(rich, requiresSellingPlan = false, planId = monthly.sellingPlan.id))
        assertNull("a plan this variant doesn't have", chosenPlan(rich, requiresSellingPlan = false, planId = "gid://shopify/SellingPlan/1"))
        assertEquals("sold by plan only", monthly, chosenPlan(rich, requiresSellingPlan = true, planId = null))
        assertNull(chosenPlan(basic, requiresSellingPlan = true, planId = null))
        assertNull(chosenPlan(null, requiresSellingPlan = true, planId = monthly.sellingPlan.id))
    }

    // The main button

    @Test
    fun theMainButtonSaysWhatATapWouldDo() {
        assertEquals("Add to cart", addButtonLabel(basic, AddPhase.Idle))
        assertEquals("Adding…", addButtonLabel(basic, AddPhase.Adding))
        assertEquals("Added", addButtonLabel(basic, AddPhase.Added))
        assertEquals("Sold out", addButtonLabel(basic.copy(available = false), AddPhase.Idle))
        assertEquals("Unavailable", addButtonLabel(null, AddPhase.Idle))
    }
}
