import XCTest
@testable import ArgonStorefront

/// The orders pages' rules (Android's OrderLogicTest, case for case).
final class OrderLogicTests: XCTestCase {
    // the contract fixtures: the sample account's orders
    @MainActor
    private func sampleOrders() async throws -> [OrderSummary] {
        try await StubServer().customerAccount().orders().items
    }

    @MainActor
    private func sampleOrder() async throws -> Order {
        let found = try await StubServer().customerAccount().order("gid://shopify/Order/6001004")
        return try XCTUnwrap(found)
    }

    private func status(_ cancelledAt: String?, _ shipment: String?, _ fulfillment: String?) -> String {
        orderStatus(cancelledAt: cancelledAt, shipmentStatus: shipment, fulfillmentStatus: fulfillment)
    }

    // MARK: Status label

    func testACancelledOrderIsCancelledWhateverElseItSays() {
        XCTAssertEqual(status("2026-07-14T16:00:00Z", "DELIVERED", "FULFILLED"), "Cancelled")
        XCTAssertEqual(status("2026-07-14T16:00:00Z", nil, nil), "Cancelled")
    }

    func testTheLatestShipmentStatusComesBeforeTheFulfilmentStatus() {
        XCTAssertEqual(status(nil, "DELIVERED", "FULFILLED"), "Delivered")
        XCTAssertEqual(status(nil, "OUT_FOR_DELIVERY", "FULFILLED"), "Out for delivery")
        for code in ["IN_TRANSIT", "CARRIER_PICKED_UP", "CONFIRMED", "LABEL_PRINTED", "LABEL_PURCHASED", "LABEL_VOIDED"] {
            XCTAssertEqual(status(nil, code, "FULFILLED"), "On its way", code)
        }
        for code in ["ATTEMPTED_DELIVERY", "DELAYED", "FAILURE"] {
            XCTAssertEqual(status(nil, code, "FULFILLED"), "Delivery issue", code)
        }
        XCTAssertEqual(status(nil, "READY_FOR_PICKUP", "FULFILLED"), "Ready for pickup")
        XCTAssertEqual(status(nil, "PICKED_UP", "FULFILLED"), "Picked up")
    }

    func testWithoutShipmentNewsTheFulfilmentStatusDecides() {
        XCTAssertEqual(status(nil, nil, "FULFILLED"), "Shipped")
        XCTAssertEqual(status(nil, nil, "PARTIALLY_FULFILLED"), "Partly shipped")
        XCTAssertEqual(status(nil, nil, "ON_HOLD"), "On hold")
        XCTAssertEqual(status(nil, nil, "UNFULFILLED"), "Confirmed")
        XCTAssertEqual(status(nil, nil, "IN_PROGRESS"), "Confirmed")
        XCTAssertEqual(status(nil, nil, nil), "Confirmed")
        XCTAssertEqual(status(nil, "MARKED_AS_FULFILLED", "FULFILLED"), "Shipped", "a shipment status this app doesn't know")
    }

    @MainActor
    func testTheSampleOrdersReadAsTheyShould() async throws {
        let orders = try await sampleOrders()
        let order = try await sampleOrder()
        XCTAssertEqual(orders.map { orderStatus($0) }, ["On its way", "Delivered", "Confirmed", "Cancelled"])
        XCTAssertEqual(orderStatus(order), "Delivered", "the order page agrees with the list")
    }

    // MARK: Progress

    private func shipment(_ events: String..., latest: String? = nil, status: String? = "SUCCESS", pickedUp: Bool = false) -> Fulfillment {
        Fulfillment(
            id: "f", status: status, createdAt: nil, estimatedDeliveryAt: nil, latestShipmentStatus: latest, tracking: [], lines: [],
            isPickedUp: pickedUp, events: events.map { FulfillmentEvent(status: $0, happenedAt: nil) }
        )
    }

    @MainActor
    func testProgressFollowsTheShipmentsEvents() async throws {
        XCTAssertEqual(orderProgressStep(nil), 0, "nothing shipped")
        XCTAssertEqual(orderProgressStep(shipment()), 1, "shipped, no news yet")
        XCTAssertEqual(orderProgressStep(shipment("LABEL_PRINTED", "CONFIRMED", "IN_TRANSIT")), 1)
        XCTAssertEqual(orderProgressStep(shipment("CONFIRMED", "IN_TRANSIT", "OUT_FOR_DELIVERY")), 2)
        XCTAssertEqual(orderProgressStep(shipment("IN_TRANSIT", "ATTEMPTED_DELIVERY")), 2, "an attempted delivery was out for delivery")
        XCTAssertEqual(orderProgressStep(shipment("READY_FOR_PICKUP")), 2)
        XCTAssertEqual(orderProgressStep(shipment("CONFIRMED", "IN_TRANSIT", "OUT_FOR_DELIVERY", "DELIVERED")), 3)
        XCTAssertEqual(orderProgressStep(shipment("READY_FOR_PICKUP", "PICKED_UP")), 3)
        XCTAssertEqual(orderProgressStep(shipment(pickedUp: true)), 3)
        let order = try await sampleOrder()
        XCTAssertEqual(orderProgressStep(order.fulfillments.first), 3, "the sample order was delivered")
    }

    func testTheLatestStatusCountsWithoutEventsAndACancelledShipmentDoesNot() {
        XCTAssertEqual(orderProgressStep(shipment(latest: "DELIVERED")), 3)
        XCTAssertEqual(orderProgressStep(shipment(latest: "OUT_FOR_DELIVERY")), 2)
        XCTAssertEqual(orderProgressStep(shipment(latest: "IN_TRANSIT")), 1)
        XCTAssertEqual(orderProgressStep(shipment("IN_TRANSIT", status: "CANCELLED")), 0)
        XCTAssertEqual(orderProgressStep(shipment(status: "FAILURE")), 0)
        XCTAssertEqual(orderSteps.count - 1, 3)
    }

    @MainActor
    func testAShipmentsEventsAreReadNewestFirst() async throws {
        let order = try await sampleOrder()
        let delivered = try XCTUnwrap(order.fulfillments.first)
        XCTAssertEqual(newestFirst(delivered).map { $0.status }, ["DELIVERED", "OUT_FOR_DELIVERY", "IN_TRANSIT", "CONFIRMED"])
        let mixed = Fulfillment(
            id: "f", status: nil, createdAt: nil, estimatedDeliveryAt: nil, latestShipmentStatus: nil, tracking: [], lines: [],
            events: [
                FulfillmentEvent(status: "DELIVERED", happenedAt: "2026-09-25T13:05:00Z"),
                FulfillmentEvent(status: "IN_TRANSIT", happenedAt: "2026-09-23T06:10:00Z"),
            ]
        )
        XCTAssertEqual(newestFirst(mixed).map { $0.status }, ["DELIVERED", "IN_TRANSIT"], "already newest first stays so")
    }

    // MARK: The list's card

    func testItemCountsAndTheMoreBadge() {
        XCTAssertEqual(itemCountLabel(1), "1 item")
        XCTAssertEqual(itemCountLabel(4), "4 items")
        XCTAssertEqual(itemCountLabel(0), "0 items")
        XCTAssertEqual(moreItems(itemCount: 4, shown: 2), 2)
        XCTAssertEqual(moreItems(itemCount: 3, shown: 3), 0)
        XCTAssertEqual(moreItems(itemCount: 1, shown: 3), 0, "fewer items than thumbnails can't be")
        XCTAssertEqual(moreItems(itemCount: nil, shown: 2), 0, "no count: nothing is claimed")
    }

    @MainActor
    func testTheDeliveryLineSaysArrivesOrDelivered() async throws {
        let orders = try await sampleOrders()
        let notes = orders.map { order in deliveryNote(order, date: { iso in iso }) }
        XCTAssertEqual(notes[0], "Arrives 2026-10-14T18:00:00Z")
        XCTAssertEqual(notes[1], "Delivered 2026-09-25T13:05:00Z")
        XCTAssertNil(notes[2], "nothing shipped")
        XCTAssertNil(notes[3], "cancelled")
        var cancelled = orders[1]
        cancelled.cancelledAt = "2026-09-22T00:00:00Z"
        XCTAssertNil(deliveryNote(cancelled, date: { iso in iso }), "a cancelled order says nothing of a delivery")
    }

    // MARK: Items

    @MainActor
    func testAnItemsDetailsLeaveOutWhatIsMissing() async throws {
        let crewneck = try await sampleOrder().lines[0]
        XCTAssertEqual(
            itemDetails(crewneck.variantTitle, sku: crewneck.sku, quantity: crewneck.quantity),
            ["Medium / Olive", "SKU MENCREWNECK-MO", "Qty 1"]
        )
        XCTAssertEqual(itemDetails("Default Title", sku: " ", quantity: 2), ["Qty 2"], "a product without options has no variant worth showing")
        XCTAssertEqual(itemDetails(nil, sku: nil, quantity: nil), [])
    }

    // MARK: Buy again

    private func line(_ title: String, _ quantity: Int, _ variantId: String?) -> OrderLine {
        OrderLine(title: title, variantTitle: nil, quantity: quantity, image: nil, variantId: variantId, total: nil)
    }

    @MainActor
    func testBuyAgainAddsEachVariantWithItsQuantity() async throws {
        let order = try await sampleOrder()
        let plan = buyAgainPlan(order.lines)
        XCTAssertEqual(plan.lines, [
            BuyAgainLine(variantId: "gid://shopify/ProductVariant/43696905224214", quantity: 1, title: "Men's Crewneck"),
            BuyAgainLine(variantId: "gid://shopify/ProductVariant/43696926949398", quantity: 2, title: "Sweatpants"),
            BuyAgainLine(variantId: "gid://shopify/ProductVariant/43696932126742", quantity: 1, title: "Men's T-shirt"),
        ])
        XCTAssertEqual(plan.unavailable, [])
    }

    func testBuyAgainMergesAVariantAndNamesWhatIsGone() {
        let plan = buyAgainPlan([
            line("Hoodie", 1, "v1"),
            line("Hoodie", 2, "v1"),
            line("Retired scarf", 1, nil),
            line("Removed by an edit", 0, "v2"),
        ])
        XCTAssertEqual(plan.lines, [BuyAgainLine(variantId: "v1", quantity: 3, title: "Hoodie")])
        XCTAssertEqual(plan.unavailable, ["Retired scarf"])
        XCTAssertEqual(buyAgainPlan([]), BuyAgain(lines: [], unavailable: []))
    }

    func testBuyAgainTellsWhatHappened() {
        XCTAssertEqual(buyAgainMessage(added: 3, unavailable: []), "Added to your cart")
        XCTAssertEqual(
            buyAgainMessage(added: 1, unavailable: ["Sweatpants", "Hoodie"]),
            "Added to your cart. No longer available: Sweatpants, Hoodie"
        )
        XCTAssertEqual(buyAgainMessage(added: 0, unavailable: ["Sweatpants"]), "No longer available: Sweatpants")
    }

    // MARK: Payment and totals

    @MainActor
    func testAPaymentIsNamedByItsCardElseItsType() async throws {
        let order = try await sampleOrder()
        XCTAssertEqual(paymentMethods(order.transactions), ["Visa ending in 4242"], "the refund on the same card isn't a second payment")
        XCTAssertEqual(paymentLabel(OrderTransaction(id: "t", kind: "SALE", type: "BANK_DEPOSIT")), "Bank deposit")
        XCTAssertNil(paymentLabel(OrderTransaction(id: "t", kind: "SALE")))
        let failed = OrderTransaction(id: "t", kind: "SALE", status: "FAILURE", type: "CARD")
        let manual = OrderTransaction(id: "u", kind: "SALE", status: "SUCCESS", type: "MANUAL")
        XCTAssertEqual(paymentMethods([failed, manual, manual]), ["Manual"])
        XCTAssertEqual(paymentMethods([]), [])
    }

    @MainActor
    func testADiscountShowsAsAPercentageOrAnAmount() async throws {
        let order = try await sampleOrder()
        let discount = try XCTUnwrap(order.discounts.first)
        XCTAssertEqual(discountLabel(discount), "-10%")
        XCTAssertEqual(discountLabel(.percentage(12.5)), "-12.5%")
        let five = Money(amount: "5.0", currencyCode: "USD")
        XCTAssertEqual(discountLabel(.amount(five)), "-\(five.display())")
        XCTAssertNil(discountLabel(.other("SomethingNew")))
    }
}
