package app.storefront.ui

import app.storefront.data.Cart
import app.storefront.data.CartDiscount
import app.storefront.data.CartLine
import app.storefront.data.CartLineComponent
import app.storefront.data.Money
import app.storefront.data.ResourceRef
import app.storefront.data.fixtureStorefront
import java.util.Locale
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CartScreenTest {
    private fun part(product: String?, variant: String, quantity: Int) =
        CartLineComponent("c", quantity, CartLineComponent.Merchandise("v", variant, product = ResourceRef("handle", product)))

    private fun usd(amount: String) = Money(amount, "USD")

    /** A line of [quantity] at [price] each, [compareAt] each before, with [discounts] taken off it. */
    private fun line(id: String, price: String, quantity: Int = 1, compareAt: String? = null, discounts: List<Pair<String, String>> = emptyList(), productId: String = id): CartLine {
        val subtotal = price.toBigDecimal() * quantity.toBigDecimal()
        val total = subtotal - discounts.sumOf { it.second.toBigDecimal() }
        return CartLine(
            id,
            quantity,
            cost = CartLine.Cost(usd(total.toPlainString()), usd(subtotal.toPlainString()), usd(price), compareAt?.let(::usd)),
            discountAllocations = discounts.map { (code, amount) -> CartLine.DiscountAllocation(usd(amount), code = code) },
            merchandise = CartLine.Merchandise("v-$id", "Default Title", price = usd(price), product = ResourceRef("handle-$id", "Product $id", id = productId)),
        )
    }

    private fun cart(vararg lines: CartLine): Cart {
        val total = lines.sumOf { it.total.amount.toBigDecimal() }.toPlainString()
        return Cart("c", "https://shop.test/checkout", cost = Cart.Cost(usd(total), usd(total)), lines = lines.toList())
    }

    /** [expected] as an amount: "360.00" is "360.0". */
    private fun assertAmount(expected: String, actual: Money) =
        assertEquals("${actual.amount} ${actual.currencyCode}", 0, expected.toBigDecimal().compareTo(actual.amount.toBigDecimal()))

    @Test
    fun aBundlesPartReadsAsItsProductItsVariantAndHowMany() {
        assertEquals("Men's T-shirt · Small / Olive × 1", componentLabel(part("Men's T-shirt", "Small / Olive", 1)))
        assertEquals("a product without options has no variant worth naming", "Gift card × 2", componentLabel(part("Gift card", "Default Title", 2)))
        assertEquals("Small × 3", componentLabel(part(null, "Small", 3)))
    }

    // Free shipping

    @Test
    fun freeShippingSaysWhatIsLeftAndHowFarTheCartIs() {
        val below = freeShipping(usd("120.0"), 150.0, "USD")!!
        assertAmount("30.00", below.remaining)
        assertEquals("USD", below.remaining.currencyCode)
        assertEquals(0.8f, below.progress, 1e-6f)
        assertFalse(below.reached)

        val empty = freeShipping(usd("0.0"), 150.0, "USD")!!
        assertAmount("150.00", empty.remaining)
        assertEquals(0f, empty.progress, 0f)

        val cents = freeShipping(usd("149.99"), 150.0, "USD")!!
        assertAmount("0.01", cents.remaining)
        assertFalse("a cent short is not there yet", cents.reached)
    }

    @Test
    fun freeShippingIsReachedAtTheThresholdAndStaysReachedAboveIt() {
        for (amount in listOf("150.0", "150.00", "324.0")) {
            val reached = freeShipping(usd(amount), 150.0, "USD")!!
            assertTrue(amount, reached.reached)
            assertAmount("0", reached.remaining)
            assertEquals(amount, 1f, reached.progress, 0f)
        }
    }

    @Test
    fun aStoreWithoutAThresholdShowsNoFreeShipping() {
        assertNull(freeShipping(usd("120.0"), null, "USD"))
        assertNull("zero is no threshold", freeShipping(usd("120.0"), 0.0, "USD"))
        assertNull(freeShipping(usd("120.0"), -5.0, "USD"))
        assertNull(freeShipping(usd("120.0"), Double.NaN, "USD"))
        assertNull("an amount that can't be read", freeShipping(usd("lots"), 150.0, "USD"))
    }

    @Test
    fun freeShippingIsOnlyForACartInTheShopsOwnCurrency() {
        assertNotNull("the threshold is a number in the shop's currency", freeShipping(usd("120.0"), 150.0, "USD"))
        assertNull("120 USD says nothing of 150 CAD", freeShipping(usd("120.0"), 150.0, "CAD"))
        assertNull("the same holds above the number", freeShipping(usd("324.0"), 150.0, "CAD"))
        assertNull("the shop's currency isn't known yet", freeShipping(usd("120.0"), 150.0, null))
    }

    // Lines

    @Test
    fun aLinesCompareAtIsForAllItsItemsAndOnlyWhenItIsHigher() {
        assertEquals(usd("450.0"), compareAtTotal(line("a", "120.0", quantity = 3, compareAt = "150.0")))
        assertNull(compareAtTotal(line("a", "120.0", quantity = 3)))
        assertNull("Shopify may send the price itself, or 0", compareAtTotal(line("a", "120.0", compareAt = "120.0")))
        assertNull(compareAtTotal(line("a", "120.0", compareAt = "0.0")))
    }

    @Test
    fun aLinesDiscountsAreNamedByTheirCodeElseTheirTitle() {
        val allocations = listOf(
            CartLine.DiscountAllocation(usd("10.0"), code = "WELCOME10"),
            CartLine.DiscountAllocation(usd("5.0"), title = "Buy 3, save 10%"),
            CartLine.DiscountAllocation(usd("1.0")),
        )
        assertEquals(
            listOf(CartDiscount(usd("10.0"), "WELCOME10"), CartDiscount(usd("5.0"), "Buy 3, save 10%"), CartDiscount(usd("1.0"), "Discount")),
            line("a", "50.0").copy(discountAllocations = allocations).discounts,
        )
    }

    @Test
    fun aDiscountReadsAsItsLabelAndWhatItTakesOff() {
        Locale.setDefault(Locale.US)
        assertEquals("WELCOME10 −$12.00", discountLabel(CartDiscount(usd("12.0"), "WELCOME10")))
        assertEquals("Buy 3, save 10% −$36.00", discountLabel(CartDiscount(usd("36.0"), "Buy 3, save 10%")))
    }

    // Summary

    @Test
    fun theSummaryOfTheFixtureCart() = runBlocking {
        // 3 × 120.00 (150.00 before), with an automatic discount of 36.00
        val summary = cartSummary(fixtureStorefront().cart("gid://shopify/Cart/c1")!!)
        assertAmount("360.00", summary.subtotal)
        assertAmount("36.00", summary.discounts)
        assertAmount("126.00", summary.savings)
        assertAmount("324.00", summary.total)
        assertEquals(listOf("CAD", "CAD", "CAD", "CAD"), listOf(summary.subtotal, summary.discounts, summary.savings, summary.total).map { it.currencyCode })
    }

    @Test
    fun theSummaryAddsUpEveryLineAndEveryDiscount() {
        val summary = cartSummary(
            cart(
                line("a", "50.0", quantity = 2, compareAt = "80.0", discounts = listOf("WELCOME10" to "10.0", "VIP" to "5.0")),
                line("b", "20.0", discounts = listOf("WELCOME10" to "2.0")),
                line("c", "9.5"),
            ),
        )
        assertAmount("129.50", summary.subtotal)
        assertAmount("17.00", summary.discounts)
        assertAmount("77.00", summary.savings) // 2 × 30 off the compare-at price, and the discounts
        assertAmount("112.50", summary.total)
    }

    @Test
    fun aCartWithoutDiscountsOrCompareAtPricesSavesNothing() {
        val summary = cartSummary(cart(line("a", "50.0", quantity = 2), line("b", "20.0")))
        assertAmount("120.00", summary.subtotal)
        assertAmount("0", summary.discounts)
        assertAmount("0", summary.savings)
        assertAmount("0", cartSummary(cart()).subtotal)
    }

    // You may also like

    @Test
    fun suggestionsLeaveOutWhatIsInTheCart() = runBlocking {
        val api = fixtureStorefront()
        val recommended = api.recommendations("gid://shopify/Product/1")
        assertTrue(recommended.size > 1)
        val inCart = recommended[0]
        val cart = cart(line("a", "50.0", productId = inCart.id))
        assertEquals(recommended.drop(1), suggestions(recommended, cart))
        assertEquals("no cart: all of them", recommended, suggestions(recommended, null))
    }
}
