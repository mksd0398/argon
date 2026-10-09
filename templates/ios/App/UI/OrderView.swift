import SwiftUI

/// "Fulfilled", "Unfulfilled", or each fulfillment's status.
private func fulfillment(_ statuses: [String]) -> String {
    if statuses.isEmpty { return "Unfulfilled" }
    var distinct: [String] = []
    for status in statuses where !distinct.contains(status) { distinct.append(status) }
    return distinct.map { $0 == "SUCCESS" ? "Fulfilled" : displayStatus($0) }.joined(separator: ", ")
}

@MainActor
private func loadOrder(_ id: String) async throws -> Order {
    guard let order = try await AppGraph.customerAccount.order(id) else { throw NotFound(what: "Order") }
    return order
}

@MainActor
struct OrderView: View {
    let id: String

    var body: some View {
        Loader(load: { try await loadOrder(id) }) { OrderContent(order: $0) }
            .navigationTitle("Order")
            .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
private struct OrderContent: View {
    let order: Order

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(order.name).font(.title2)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(order.lines.indices, id: \.self) { index in
                    OrderLineRow(line: order.lines[index])
                }
                Divider()
                if let subtotal = order.subtotal { TotalRow(label: "Subtotal", money: subtotal) }
                TotalRow(label: "Total", money: order.total)
            }
            .padding(16)
        }
    }

    private var detail: String {
        var parts = [displayDate(order.processedAt)]
        if let status = order.financialStatus { parts.append(displayStatus(status)) }
        parts.append(fulfillment(order.fulfillments.compactMap { $0.status }))
        return parts.joined(separator: " · ")
    }
}

@MainActor
private struct TotalRow: View {
    let label: String
    let money: Money

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(money.display())
        }
        .font(.headline)
    }
}

@MainActor
private struct OrderLineRow: View {
    let line: OrderLine

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(img: line.image)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title).lineLimit(2)
                // a product without options has Shopify's one "Default Title" variant; nothing worth showing
                if let variant = line.variantTitle, variant != "Default Title" {
                    Text(variant).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(verbatim: "Qty \(line.quantity)").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let total = line.total { Text(total.display()) }
        }
    }
}
