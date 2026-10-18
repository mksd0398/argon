import ArgonUI
import Observation
import SwiftUI

/// The customer's orders, newest first, a page at a time. Kept with the screen (it is what the screen's `Loader` loads),
/// so coming back from an order finds the list as it was.
@MainActor
@Observable
private final class OrderList {
    // each order once: the list is keyed by order id
    private(set) var items: [OrderSummary]
    private(set) var hasNext: Bool
    private(set) var loading = false

    /// Why the last "Load more" failed.
    private(set) var error: String? = nil
    @ObservationIgnored private var cursor: String?

    init(first: Page<OrderSummary>) {
        items = first.items.distinct { $0.id }
        hasNext = first.hasNextPage && first.endCursor != nil
        cursor = first.endCursor
    }

    func loadMore() async {
        if loading || !hasNext { return }
        loading = true
        error = nil
        do {
            let page = try await AppGraph.customerAccount.orders(after: cursor)
            items = (items + page.items).distinct { $0.id }
            cursor = page.endCursor
            // without a cursor "more" could only repeat this page
            hasNext = page.hasNextPage && page.endCursor != nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

/// The customer's orders, newest first (route `orders`).
@MainActor
struct OrdersView: View {
    @State private var screen = ScreenSlot("orders")
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Loader(load: { try await OrderList(first: AppGraph.customerAccount.orders()) }) { list in
            if list.items.isEmpty {
                NoOrders {
                    // back to the account first, so its tab doesn't reopen on this empty list
                    dismiss()
                    AppGraph.tabs.selected = .shop
                }
            } else {
                Orders(list: list, screen: screen) { router.path.append(.order($0.id)) }
            }
        }
        .background(theme.colors.paper)
        .argonTopBar(title: "Orders")
        .task { await screen.load() }
    }
}

@MainActor
private struct Orders: View {
    let list: OrderList
    let screen: ScreenSlot
    let onOpen: (OrderSummary) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        ScrollView {
            ScreenSections(slot: screen, part: .above, top: theme.spacing.l)
            LazyVStack(alignment: .leading, spacing: theme.spacing.m) {
                ForEach(list.items, id: \.id) { order in
                    OrderCard(order: order) { onOpen(order) }
                }
                if list.hasNext {
                    VStack(alignment: .leading, spacing: theme.spacing.s) {
                        ErrorText(list.error)
                        ArgonButton(title: "Load more", style: .secondary, isLoading: list.loading, fullWidth: true) {
                            Task { await list.loadMore() }
                        }
                    }
                }
            }
            .padding(theme.spacing.l)
            ScreenSections(slot: screen, part: .below, bottom: theme.spacing.l)
        }
    }
}

@MainActor
private struct NoOrders: View {
    let onShop: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.m) {
            ArgonIcon(name: .bag, tint: theme.colors.muted)
            Text("No orders yet").font(theme.type.headline).foregroundStyle(theme.colors.ink)
            Text("Your orders will show here.").font(theme.type.body).foregroundStyle(theme.colors.muted)
            ArgonButton(title: "Start shopping", action: onShop)
        }
        .multilineTextAlignment(.center)
        .padding(theme.spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
