package app.storefront.ui.orders

import app.storefront.data.CustomerAccountApi
import app.storefront.data.Fulfillment
import app.storefront.data.FulfillmentEvent
import app.storefront.data.Money
import app.storefront.data.OrderLine
import app.storefront.data.OrderTransaction
import app.storefront.data.PricingValue
import app.storefront.data.fixture
import app.storefront.ui.display
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OrderLogicTest {
    // the contract fixtures: the sample account's orders
    private val account = CustomerAccountApi({ name, _ -> fixture(name) })
    private val orders = runBlocking { account.orders().items }
    private val order = runBlocking { account.order("gid://shopify/Order/6001004")!! }

    // Status label

    @Test
    fun aCancelledOrderIsCancelledWhateverElseItSays() {
        assertEquals("Cancelled", orderStatus("2026-07-14T16:00:00Z", "DELIVERED", "FULFILLED"))
        assertEquals("Cancelled", orderStatus("2026-07-14T16:00:00Z", null, null))
    }

    @Test
    fun theLatestShipmentStatusComesBeforeTheFulfilmentStatus() {
        assertEquals("Delivered", orderStatus(null, "DELIVERED", "FULFILLED"))
        assertEquals("Out for delivery", orderStatus(null, "OUT_FOR_DELIVERY", "FULFILLED"))
        for (status in listOf("IN_TRANSIT", "CARRIER_PICKED_UP", "CONFIRMED", "LABEL_PRINTED", "LABEL_PURCHASED", "LABEL_VOIDED")) {
            assertEquals(status, "On its way", orderStatus(null, status, "FULFILLED"))
        }
        for (status in listOf("ATTEMPTED_DELIVERY", "DELAYED", "FAILURE")) {
            assertEquals(status, "Delivery issue", orderStatus(null, status, "FULFILLED"))
        }
        assertEquals("Ready for pickup", orderStatus(null, "READY_FOR_PICKUP", "FULFILLED"))
        assertEquals("Picked up", orderStatus(null, "PICKED_UP", "FULFILLED"))
    }

    @Test
    fun withoutShipmentNewsTheFulfilmentStatusDecides() {
        assertEquals("Shipped", orderStatus(null, null, "FULFILLED"))
        assertEquals("Partly shipped", orderStatus(null, null, "PARTIALLY_FULFILLED"))
        assertEquals("On hold", orderStatus(null, null, "ON_HOLD"))
        assertEquals("Confirmed", orderStatus(null, null, "UNFULFILLED"))
        assertEquals("Confirmed", orderStatus(null, null, "IN_PROGRESS"))
        assertEquals("Confirmed", orderStatus(null, null, null))
        assertEquals("a shipment status this app doesn't know", "Shipped", orderStatus(null, "MARKED_AS_FULFILLED", "FULFILLED"))
    }

    @Test
    fun theSampleOrdersReadAsTheyShould() {
        assertEquals(listOf("On its way", "Delivered", "Confirmed", "Cancelled"), orders.map { orderStatus(it) })
        assertEquals("the order page agrees with the list", "Delivered", orderStatus(order))
    }

    // Progress

    private fun shipment(vararg events: String, latest: String? = null, status: String? = "SUCCESS", pickedUp: Boolean = false) =
        Fulfillment("f", status, latestShipmentStatus = latest, isPickedUp = pickedUp, events = events.map { FulfillmentEvent(it) })

    @Test
    fun progressFollowsTheShipmentsEvents() {
        assertEquals("nothing shipped", 0, orderProgressStep(null))
        assertEquals("shipped, no news yet", 1, orderProgressStep(shipment()))
        assertEquals(1, orderProgressStep(shipment("LABEL_PRINTED", "CONFIRMED", "IN_TRANSIT")))
        assertEquals(2, orderProgressStep(shipment("CONFIRMED", "IN_TRANSIT", "OUT_FOR_DELIVERY")))
        assertEquals("an attempted delivery was out for delivery", 2, orderProgressStep(shipment("IN_TRANSIT", "ATTEMPTED_DELIVERY")))
        assertEquals(2, orderProgressStep(shipment("READY_FOR_PICKUP")))
        assertEquals(3, orderProgressStep(shipment("CONFIRMED", "IN_TRANSIT", "OUT_FOR_DELIVERY", "DELIVERED")))
        assertEquals(3, orderProgressStep(shipment("READY_FOR_PICKUP", "PICKED_UP")))
        assertEquals(3, orderProgressStep(shipment(pickedUp = true)))
        assertEquals("the sample order was delivered", 3, orderProgressStep(order.fulfillments.first()))
    }

    @Test
    fun theLatestStatusCountsWithoutEventsAndACancelledShipmentDoesNot() {
        assertEquals(3, orderProgressStep(shipment(latest = "DELIVERED")))
        assertEquals(2, orderProgressStep(shipment(latest = "OUT_FOR_DELIVERY")))
        assertEquals(1, orderProgressStep(shipment(latest = "IN_TRANSIT")))
        assertEquals(0, orderProgressStep(shipment("IN_TRANSIT", status = "CANCELLED")))
        assertEquals(0, orderProgressStep(shipment(status = "FAILURE")))
        assertEquals(ORDER_STEPS.lastIndex, 3)
    }

    @Test
    fun aShipmentsEventsAreReadNewestFirst() {
        assertEquals(listOf("DELIVERED", "OUT_FOR_DELIVERY", "IN_TRANSIT", "CONFIRMED"), newestFirst(order.fulfillments.first()).map { it.status })
        val mixed = Fulfillment("f", events = listOf(FulfillmentEvent("DELIVERED", "2026-09-25T13:05:00Z"), FulfillmentEvent("IN_TRANSIT", "2026-09-23T06:10:00Z")))
        assertEquals("already newest first stays so", listOf("DELIVERED", "IN_TRANSIT"), newestFirst(mixed).map { it.status })
    }

    // The list's card

    @Test
    fun itemCountsAndTheMoreBadge() {
        assertEquals("1 item", itemCountLabel(1))
        assertEquals("4 items", itemCountLabel(4))
        assertEquals("0 items", itemCountLabel(0))
        assertEquals(2, moreItems(itemCount = 4, shown = 2))
        assertEquals(0, moreItems(itemCount = 3, shown = 3))
        assertEquals("fewer items than thumbnails can't be", 0, moreItems(itemCount = 1, shown = 3))
        assertEquals("no count: nothing is claimed", 0, moreItems(itemCount = null, shown = 2))
    }

    @Test
    fun theDeliveryLineSaysArrivesOrDelivered() {
        val notes = orders.map { deliveryNote(it) { iso -> iso } }
        assertEquals("Arrives 2026-10-14T18:00:00Z", notes[0])
        assertEquals("Delivered 2026-09-25T13:05:00Z", notes[1])
        assertNull("nothing shipped", notes[2])
        assertNull("cancelled", notes[3])
        assertNull("a cancelled order says nothing of a delivery", deliveryNote(orders[1].copy(cancelledAt = "2026-09-22T00:00:00Z")) { it })
    }

    // Items

    @Test
    fun anItemsDetailsLeaveOutWhatIsMissing() {
        assertEquals(listOf("Medium / Olive", "SKU MENCREWNECK-MO", "Qty 1"), order.lines[0].let { itemDetails(it.variantTitle, it.sku, it.quantity) })
        assertEquals("a product without options has no variant worth showing", listOf("Qty 2"), itemDetails("Default Title", " ", 2))
        assertEquals(emptyList<String>(), itemDetails(null, null, null))
    }

    // Buy again

    @Test
    fun buyAgainAddsEachVariantWithItsQuantity() {
        val plan = buyAgainPlan(order.lines)
        assertEquals(
            listOf(
                BuyAgainLine("gid://shopify/ProductVariant/43696905224214", 1, "Men's Crewneck"),
                BuyAgainLine("gid://shopify/ProductVariant/43696926949398", 2, "Sweatpants"),
                BuyAgainLine("gid://shopify/ProductVariant/43696932126742", 1, "Men's T-shirt"),
            ),
            plan.lines,
        )
        assertEquals(emptyList<String>(), plan.unavailable)
    }

    @Test
    fun buyAgainMergesAVariantAndNamesWhatIsGone() {
        val plan = buyAgainPlan(
            listOf(
                OrderLine(title = "Hoodie", quantity = 1, variantId = "v1"),
                OrderLine(title = "Hoodie", quantity = 2, variantId = "v1"),
                OrderLine(title = "Retired scarf", quantity = 1, variantId = null),
                OrderLine(title = "Removed by an edit", quantity = 0, variantId = "v2"),
            ),
        )
        assertEquals(listOf(BuyAgainLine("v1", 3, "Hoodie")), plan.lines)
        assertEquals(listOf("Retired scarf"), plan.unavailable)
        assertEquals(BuyAgain(emptyList(), emptyList()), buyAgainPlan(emptyList()))
    }

    @Test
    fun buyAgainTellsWhatHappened() {
        assertEquals("Added to your cart", buyAgainMessage(3, emptyList()))
        assertEquals("Added to your cart. No longer available: Sweatpants, Hoodie", buyAgainMessage(1, listOf("Sweatpants", "Hoodie")))
        assertEquals("No longer available: Sweatpants", buyAgainMessage(0, listOf("Sweatpants")))
    }

    // Payment and totals

    @Test
    fun aPaymentIsNamedByItsCardElseItsType() {
        assertEquals("the refund on the same card isn't a second payment", listOf("Visa ending in 4242"), paymentMethods(order.transactions))
        assertEquals("Bank deposit", paymentLabel(OrderTransaction("t", kind = "SALE", type = "BANK_DEPOSIT")))
        assertNull(paymentLabel(OrderTransaction("t", kind = "SALE")))
        val failed = OrderTransaction("t", kind = "SALE", status = "FAILURE", type = "CARD")
        val manual = OrderTransaction("u", kind = "SALE", status = "SUCCESS", type = "MANUAL")
        assertEquals(listOf("Manual"), paymentMethods(listOf(failed, manual, manual)))
        assertEquals(emptyList<String>(), paymentMethods(emptyList()))
    }

    @Test
    fun aDiscountShowsAsAPercentageOrAnAmount() {
        assertEquals("-10%", discountLabel(order.discountApplications.first().value))
        assertEquals("-12.5%", discountLabel(PricingValue.Percentage(12.5)))
        val five = Money("5.0", "USD")
        assertEquals("-${five.display()}", discountLabel(five))
        assertNull(discountLabel(PricingValue.Other("SomethingNew")))
    }
}
