import ArgonUI
import SwiftUI

@MainActor
private func loadOrder(_ id: String) async throws -> Order {
    guard let order = try await AppGraph.customerAccount.order(id) else { throw NotFound(what: "Order") }
    return order
}

/// One order in full (route `order/<id>`).
@MainActor
struct OrderView: View {
    let id: String
    @Environment(\.argonTheme) private var theme

    var body: some View {
        // not kept: back from a return request, the order shows it
        FreshLoader(load: { try await loadOrder(id) }) { OrderContent(order: $0) }
            .background(theme.colors.paper)
            .argonTopBar(title: "Order")
    }
}

@MainActor
private struct OrderContent: View {
    let order: Order
    @Environment(Router.self) private var router
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let openWeb: (String) -> Void = { router.open(.web($0)) }
        // a cancelled shipment's tracking is nobody's news
        let shipments = order.fulfillments.filter { $0.status != "CANCELLED" }
        // an order with nothing to say about its payment (no status, no transactions, no terms) has no payment block
        let methods = paymentMethods(order.transactions)
        // where it ships, and where it is billed when that is somewhere else; a digital order has only the second
        let shipping = order.shippingAddress.map(addressLines) ?? []
        let billing = order.billingAddress.map(addressLines) ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.l) {
                Group {
                    OrderHeader(order: order)
                    // a cancelled order goes nowhere, and one with nothing to ship (a gift card) has no shipment to follow
                    if order.cancelledAt == nil && order.requiresShipping {
                        OrderProgress(step: orderProgressStep(order.fulfillments.first))
                    }
                    ForEach(shipments, id: \.id) { ShipmentCard(fulfillment: $0, openWeb: openWeb) }
                    if !order.lines.isEmpty { SectionHeader(title: "Items") }
                    ForEach(order.lines.indices, id: \.self) { index in
                        let line = order.lines[index]
                        ItemRow(
                            image: line.image,
                            title: line.title,
                            details: itemDetails(line.variantTitle, sku: line.sku, quantity: line.quantity),
                            trailing: (line.total ?? line.price)?.display()
                        )
                    }
                    OrderTotals(order: order, openWeb: openWeb)
                    if order.financialStatus != nil || !methods.isEmpty || order.paymentInformation?.paymentTerms != nil {
                        OrderPayment(order: order, methods: methods)
                    }
                }
                Group {
                    if !shipping.isEmpty { AddressPanel(title: "Shipping address", lines: shipping) }
                    if !billing.isEmpty && billing != shipping { AddressPanel(title: "Billing address", lines: billing) }
                    if order.purchasingCompany != nil || trimmedText(order.poNumber) != nil { OrderBusiness(order: order) }
                    if let note = order.note, trimmedText(note) != nil {
                        Panel(title: "Note") { Text(note).font(theme.type.body).foregroundStyle(theme.colors.ink) }
                    }
                    if !order.returns.isEmpty { SectionHeader(title: "Returns") }
                    ForEach(order.returns, id: \.id) { ReturnCard(item: $0) }
                    OrderActions(order: order)
                }
            }
            .padding(theme.spacing.l)
        }
    }
}

/// Name, date, the status tag and "Edited"; a cancelled order says when.
@MainActor
private struct OrderHeader: View {
    let order: Order
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(order.name).font(theme.type.title).foregroundStyle(theme.colors.ink).lineLimit(1)
            Text(displayDate(order.processedAt)).font(theme.type.body).foregroundStyle(theme.colors.muted)
            HStack(spacing: theme.spacing.s) {
                ArgonTag(text: orderStatus(order), style: .info)
                if order.edited { ArgonTag(text: "Edited", style: .info) }
            }
            if let cancelled = order.cancelledAt {
                Text(verbatim: "Cancelled on \(displayDate(cancelled))").font(theme.type.label).foregroundStyle(theme.colors.muted)
            }
        }
    }
}

/// The bar and its four steps; the ones reached are in ink. `step`: an index into `orderSteps`.
@MainActor
private struct OrderProgress: View {
    let step: Int
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let last = orderSteps.count - 1
        VStack(spacing: theme.spacing.s) {
            ArgonProgressBar(value: Double(step) / Double(last))
            HStack(alignment: .top, spacing: theme.spacing.xs) {
                ForEach(orderSteps.indices, id: \.self) { index in
                    Text(orderSteps[index])
                        .font(theme.type.caption)
                        .foregroundStyle(index <= step ? theme.colors.ink : theme.colors.muted)
                        .multilineTextAlignment(index == 0 ? .leading : index == last ? .trailing : .center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : index == last ? .trailing : .center)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Order progress: \(orderSteps[step])"))
    }
}

/// One shipment: its carrier, tracking numbers, when it should arrive, what the carrier reported (newest first), and "Track package".
@MainActor
private struct ShipmentCard: View {
    let fulfillment: Fulfillment
    let openWeb: (String) -> Void

    var body: some View {
        let tracking = fulfillment.tracking
        let numbers = tracking.compactMap { trimmedText($0.number) }
        let events = newestFirst(fulfillment)
        let urls = tracking.compactMap { trimmedText($0.url) }
        Panel(title: tracking.compactMap { trimmedText($0.company) }.first ?? "Shipment") {
            ForEach(numbers.indices, id: \.self) { InfoRow(label: "Tracking number", value: numbers[$0]) }
            // an estimate is old news once the parcel is there
            if orderProgressStep(fulfillment) < orderSteps.count - 1, let estimate = fulfillment.estimatedDeliveryAt {
                InfoRow(label: "Estimated delivery", value: displayDate(estimate))
            }
            ForEach(events.indices, id: \.self) { index in
                InfoRow(label: displayStatus(events[index].status), value: events[index].happenedAt.map(displayDate) ?? "")
            }
            ForEach(urls.indices, id: \.self) { index in
                ArgonButton(title: "Track package", style: .secondary, size: .s, icon: .truck) { openWeb(urls[index]) }
            }
        }
    }
}

/// Subtotal, discounts, shipping (with its method), tax, total, what was refunded, and what is still to pay with "Pay now".
@MainActor
private struct OrderTotals: View {
    let order: Order
    let openWeb: (String) -> Void

    var body: some View {
        let discounts = order.discounts.compactMap(discountLabel)
        Panel {
            if let subtotal = order.subtotal { InfoRow(label: "Subtotal", value: subtotal.display()) }
            ForEach(discounts.indices, id: \.self) { InfoRow(label: "Discount", value: discounts[$0]) }
            if let shipping = order.totalShipping {
                InfoRow(label: "Shipping", value: shipping.display(), note: order.shippingLine?.title)
            }
            if let tax = order.totalTax { InfoRow(label: "Tax", value: tax.display()) }
            InfoRow(label: "Total", value: order.total.display(), strong: true)
            if let refunded = order.totalRefunded, refunded.isPositive() {
                InfoRow(label: "Refunded", value: refunded.display())
            }
            if let outstanding = order.paymentInformation?.totalOutstandingAmount, outstanding.isPositive() {
                InfoRow(label: "Outstanding", value: outstanding.display())
                if let url = order.paymentInformation?.paymentCollectionUrl {
                    ArgonButton(title: "Pay now", fullWidth: true) { openWeb(url) }
                }
            }
        }
    }
}

/// Whether it is paid, how it was paid (`methods`), and a company's payment terms with their due date.
@MainActor
private struct OrderPayment: View {
    let order: Order
    let methods: [String]
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let terms = order.paymentInformation?.paymentTerms
        Panel(title: "Payment") {
            if let status = order.financialStatus { InfoRow(label: "Status", value: displayStatus(status)) }
            ForEach(methods, id: \.self) { method in
                Text(method).font(theme.type.body).foregroundStyle(theme.colors.ink)
            }
            if let name = terms?.paymentTermsName { InfoRow(label: "Payment terms", value: name) }
            if let due = terms?.nextDueAt { InfoRow(label: "Due", value: displayDate(due)) }
            if terms?.overdue == true { ErrorText("Overdue") }
        }
    }
}

@MainActor
private struct AddressPanel: View {
    let title: String
    let lines: [String]
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Panel(title: title) {
            Text(lines.joined(separator: "\n")).font(theme.type.body).foregroundStyle(theme.colors.ink)
        }
    }
}

/// A company order's PO number, company and location.
@MainActor
private struct OrderBusiness: View {
    let order: Order

    var body: some View {
        Panel(title: "Business details") {
            if let number = trimmedText(order.poNumber) { InfoRow(label: "PO number", value: number) }
            if let purchaser = order.purchasingCompany {
                InfoRow(label: "Company", value: purchaser.company.name)
                InfoRow(label: "Location", value: purchaser.location.name)
            }
        }
    }
}

/// A return: its name, status and date, what went back and why, what comes instead, and why the store declined it.
@MainActor
private struct ReturnCard: View {
    let item: OrderReturn
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Panel {
            HStack(spacing: theme.spacing.s) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(trimmedText(item.name) ?? "Return").font(theme.type.headline).foregroundStyle(theme.colors.ink).lineLimit(1)
                    if let created = item.createdAt {
                        Text(displayDate(created)).font(theme.type.caption).foregroundStyle(theme.colors.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ArgonTag(text: displayStatus(item.status), style: .info)
            }
            ForEach(item.lines, id: \.id) { line in
                ItemRow(
                    image: line.image,
                    title: line.title ?? "Item",
                    details: itemDetails(line.variantTitle, sku: nil, quantity: line.quantity) + [line.reason].compactMap { $0 }
                )
            }
            if !item.exchangeLines.isEmpty {
                Text("Exchanged for").font(theme.type.label).foregroundStyle(theme.colors.ink)
            }
            ForEach(item.exchangeLines, id: \.id) { line in
                ItemRow(image: line.image, title: line.title, details: itemDetails(line.variantTitle, sku: nil, quantity: line.quantity))
            }
            if let decline = item.decline {
                let why = [decline.reason.map(displayStatus), trimmedText(decline.note)].compactMap { $0 }.joined(separator: ": ")
                ErrorText(why.isEmpty ? "Declined" : "Declined: \(why)")
            }
        }
    }
}

/// "Return or exchange items" (when something can go back), "Buy again", "View order status page" and "Need help?".
@MainActor
private struct OrderActions: View {
    let order: Order
    @State private var buying = false
    @Environment(Router.self) private var router
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.s) {
            if order.hasReturnableItems {
                ArgonButton(title: "Return or exchange items", fullWidth: true) { router.path.append(.return(order.id)) }
            }
            if !order.lines.isEmpty {
                ArgonButton(title: "Buy again", style: .secondary, isLoading: buying, fullWidth: true) {
                    buying = true
                    // not tied to the screen: leaving the order doesn't drop the cart writes
                    Task {
                        do {
                            let message = try await buyAgain(order)
                            AppGraph.toast.show(message)
                        } catch {
                            AppGraph.toast.show((error as? LocalizedError)?.errorDescription ?? "Couldn't update the cart")
                        }
                        buying = false
                    }
                }
            }
            // the store's own order page: whatever its apps add to customer accounts shows there
            if let url = order.statusPageUrl {
                ArgonButton(title: "View order status page", style: .secondary, icon: .external, fullWidth: true) {
                    router.open(.web(url))
                }
            }
            ArgonButton(title: "Need help?", style: .tertiary, fullWidth: true) { router.open(contactRoute()) }
        }
    }
}

/// Puts the order's items in the cart again, one variant at a time, and returns what to tell the shopper. An item Shopify
/// refuses, or takes without the cart gaining any of it (sold out), is named as no longer available; anything else that
/// goes wrong (no connection) is thrown.
/// ponytail: one cart call per variant (`CartStore.add` takes one). Give the cart store an add of several lines when
/// orders with many lines make this slow.
@MainActor
private func buyAgain(_ order: Order) async throws -> String {
    let plan = buyAgainPlan(order.lines)
    var unavailable = plan.unavailable
    var added = 0
    for line in plan.lines {
        let before = quantityIn(AppGraph.cart.cart, line.variantId)
        do {
            try await AppGraph.cart.add(line.variantId, quantity: line.quantity)
        } catch ArgonAPIError.userErrors(_, _) {
            // Shopify's answer for this one item (it no longer exists, or its quantity rule says no): the rest still go in
        }
        if quantityIn(AppGraph.cart.cart, line.variantId) > before {
            added += 1
        } else {
            unavailable.append(line.title)
        }
    }
    return buyAgainMessage(added: added, unavailable: unavailable.distinct { $0 })
}
