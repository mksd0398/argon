import Foundation

// The orders pages' rules, kept free of UI so they can be tested (and read side by side with Android).

private let isoDate = ISO8601DateFormatter()

/// "Oct 1, 2026" in the device's zone and locale; the text as it came when it isn't an ISO-8601 date-time.
func displayDate(_ iso: String) -> String {
    guard let date = isoDate.date(from: iso) else { return iso }
    return date.formatted(date: .abbreviated, time: .omitted)
}

/// PARTIALLY_REFUNDED -> "Partially refunded".
func displayStatus(_ status: String) -> String {
    let words = status.lowercased().replacingOccurrences(of: "_", with: " ")
    return words.prefix(1).uppercased() + String(words.dropFirst())
}

/// The four steps of an order's progress, in order.
let orderSteps = ["Confirmed", "Shipped", "Out for delivery", "Delivered"]

/// An order's status in the shopper's words. A cancelled order is "Cancelled"; else what its latest shipment says
/// (`shipmentStatus`: DELIVERED, IN_TRANSIT, ...); else, with no shipment news, its `fulfillmentStatus`.
func orderStatus(cancelledAt: String?, shipmentStatus: String?, fulfillmentStatus: String?) -> String {
    if cancelledAt != nil { return "Cancelled" }
    switch shipmentStatus {
    case "DELIVERED"?: return "Delivered"
    case "OUT_FOR_DELIVERY"?: return "Out for delivery"
    case "IN_TRANSIT"?, "CARRIER_PICKED_UP"?, "CONFIRMED"?: return "On its way"
    case let status? where status.hasPrefix("LABEL_"): return "On its way"
    case "ATTEMPTED_DELIVERY"?, "DELAYED"?, "FAILURE"?: return "Delivery issue"
    case "READY_FOR_PICKUP"?: return "Ready for pickup"
    case "PICKED_UP"?: return "Picked up"
    default: break
    }
    switch fulfillmentStatus {
    case "FULFILLED"?: return "Shipped"
    case "PARTIALLY_FULFILLED"?: return "Partly shipped"
    case "ON_HOLD"?: return "On hold"
    default: return "Confirmed"
    }
}

/// The status of an order in the list.
func orderStatus(_ order: OrderSummary) -> String {
    orderStatus(cancelledAt: order.cancelledAt, shipmentStatus: order.latestShipmentStatus, fulfillmentStatus: order.fulfillmentStatus)
}

/// The status of an order on its page: by its first shipment, as the list has it.
func orderStatus(_ order: Order) -> String {
    orderStatus(
        cancelledAt: order.cancelledAt,
        shipmentStatus: order.fulfillments.first?.latestShipmentStatus,
        fulfillmentStatus: order.fulfillmentStatus
    )
}

/// How far an order has come, as an index into `orderSteps`, from what its shipment's carrier reported (its events and
/// latest status): 0 Confirmed (nothing shipped, or the shipment was cancelled), 1 Shipped, 2 Out for delivery (also a
/// delivery that was attempted, or an order ready for pickup), 3 Delivered (or picked up).
func orderProgressStep(_ fulfillment: Fulfillment?) -> Int {
    guard let fulfillment = fulfillment, !["CANCELLED", "ERROR", "FAILURE"].contains(fulfillment.status ?? "") else { return 0 }
    let seen = fulfillment.events.map { $0.status } + [fulfillment.latestShipmentStatus].compactMap { $0 }
    if fulfillment.isPickedUp || seen.contains("DELIVERED") || seen.contains("PICKED_UP") { return 3 }
    if seen.contains("OUT_FOR_DELIVERY") || seen.contains("ATTEMPTED_DELIVERY") || seen.contains("READY_FOR_PICKUP") { return 2 }
    return 1
}

/// A variant's title worth showing: not blank, and not Shopify's "Default Title" of a product without options.
func variantLabel(_ title: String?) -> String? {
    guard let title = trimmedText(title), title != "Default Title" else { return nil }
    return title
}

/// The lines under an ordered item's title: its variant, "SKU ..." and "Qty N", each only when there is one.
func itemDetails(_ variantTitle: String?, sku: String?, quantity: Int?) -> [String] {
    [
        variantLabel(variantTitle),
        trimmedText(sku).map { "SKU \($0)" },
        quantity.map { "Qty \($0)" },
    ].compactMap { $0 }
}

/// A shipment's events with the newest first (those of one moment stay in the order they came).
func newestFirst(_ fulfillment: Fulfillment) -> [FulfillmentEvent] {
    fulfillment.events.enumerated().sorted { a, b in
        let first = a.element.happenedAt ?? "", second = b.element.happenedAt ?? ""
        return first == second ? a.offset < b.offset : first > second
    }.map { $0.element }
}

/// "1 item", "4 items".
func itemCountLabel(_ count: Int) -> String {
    count == 1 ? "1 item" : "\(count) items"
}

/// The "+N" after an order's thumbnails: how many of its `itemCount` items the `shown` thumbnails leave out.
func moreItems(itemCount: Int?, shown: Int) -> Int {
    max((itemCount ?? shown) - shown, 0)
}

/// An order's delivery line in the list: "Delivered <date>" once it was, "Arrives <date>" while its shipment has a date;
/// nil for a cancelled order and for one with no shipment news. `date` formats an ISO date.
func deliveryNote(_ order: OrderSummary, date: (String) -> String = displayDate) -> String? {
    if order.cancelledAt != nil { return nil }
    if let delivered = order.latestFulfillmentDeliveryDate { return "Delivered \(date(delivered))" }
    return order.estimatedDeliveryAt.map { "Arrives \(date($0))" }
}

/// One thing "Buy again" adds to the cart; `title` names it if it turns out to be unavailable.
struct BuyAgainLine: Equatable {
    let variantId: String
    var quantity: Int
    let title: String
}

/// What "Buy again" does with an order: the `lines` to add, and the titles of the items that can't be bought any more.
struct BuyAgain: Equatable {
    let lines: [BuyAgainLine]
    let unavailable: [String]
}

/// The cart lines that buy `lines` again: each variant once, with the quantity ordered (two lines of one variant add up).
/// A line whose variant no longer exists (no variant id) is `BuyAgain.unavailable`; a line with no quantity is skipped.
func buyAgainPlan(_ lines: [OrderLine]) -> BuyAgain {
    let wanted = lines.filter { $0.quantity > 0 }
    var add: [BuyAgainLine] = []
    for line in wanted {
        guard let variantId = line.variantId else { continue }
        if let same = add.firstIndex(where: { $0.variantId == variantId }) {
            add[same].quantity += line.quantity
        } else {
            add.append(BuyAgainLine(variantId: variantId, quantity: line.quantity, title: line.title))
        }
    }
    return BuyAgain(lines: add, unavailable: wanted.filter { $0.variantId == nil }.map { $0.title }.distinct { $0 })
}

/// What "Buy again" tells the shopper: `added` lines went in the cart, the `unavailable` titles couldn't.
func buyAgainMessage(added: Int, unavailable: [String]) -> String {
    if unavailable.isEmpty { return "Added to your cart" }
    let gone = unavailable.joined(separator: ", ")
    return added == 0 ? "No longer available: \(gone)" : "Added to your cart. No longer available: \(gone)"
}

/// How many of the variant are in `cart`.
func quantityIn(_ cart: Cart?, _ variantId: String) -> Int {
    (cart?.lines ?? []).filter { $0.variantId == variantId }.reduce(0) { $0 + $1.quantity }
}

/// How a payment was made: "Visa ending in 4242", "Gift card ending in 1234", else its type ("Bank deposit"); nil when
/// the transaction says none of it.
func paymentLabel(_ transaction: OrderTransaction) -> String? {
    let brand = trimmedText(transaction.cardBrand).map(displayStatus)
    if let brand = brand, let last4 = trimmedText(transaction.last4) { return "\(brand) ending in \(last4)" }
    if let brand = brand { return brand }
    if let giftCard = trimmedText(transaction.giftCardLast4) { return "Gift card ending in \(giftCard)" }
    return trimmedText(transaction.type).map(displayStatus)
}

/// The ways an order was paid, each once: its payments (not its refunds), leaving out the ones that failed.
func paymentMethods(_ transactions: [OrderTransaction]) -> [String] {
    transactions
        .filter { ["SALE", "CAPTURE", "AUTHORIZATION"].contains($0.kind ?? "") }
        .filter { $0.status != "FAILURE" && $0.status != "ERROR" }
        .compactMap(paymentLabel)
        .distinct { $0 }
}

/// A discount on an order as its totals show it: "-10%" or "-$5.00"; nil for a kind of discount this app doesn't know.
func discountLabel(_ value: DiscountValue) -> String? {
    switch value {
    case let .amount(money): return "-\(money.display())"
    case let .percentage(percentage):
        // 10.0 reads "10", 12.5 stays "12.5"
        let number = String(percentage)
        return "-\(number.hasSuffix(".0") ? String(number.dropLast(2)) : number)%"
    case .other: return nil
    }
}
