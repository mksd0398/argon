import ShopifyCheckoutSheetKit
import SwiftUI

// This file imports Checkout Kit, whose public `Image` would clash with SwiftUI's: icons here are `Label`s.

/// What went wrong, in Checkout Kit's words.
private func checkoutMessage(_ error: CheckoutError) -> String {
    // if-case rather than a switch: a later 3.x may add cases
    if case let .checkoutExpired(message, _, _) = error { return message }
    if case let .checkoutUnavailable(message, _, _) = error { return message }
    if case let .configurationError(message, _, _) = error { return message }
    if case let .sdkError(underlying, _) = error { return underlying.localizedDescription }
    return String(describing: error)
}

@MainActor
struct CartView: View {
    @State private var busy = false
    @State private var loading = true
    @State private var failure: String? = nil
    @State private var attempt = 0
    @State private var message: String? = nil
    // The URL stays set until the sheet has gone, so it doesn't blank while animating out; `checkingOut` drives it.
    @State private var checkout: URL? = nil
    @State private var checkingOut = false
    // A checkout failure, shown once the sheet is gone: an alert raised while it is still dismissing can be lost.
    @State private var checkoutFailure: String? = nil

    var body: some View {
        let cart = AppGraph.cart.cart
        VStack {
            if let cart = cart, !cart.lines.isEmpty {
                content(cart)
            } else if loading && cart == nil {
                ProgressView()
            } else if let failure = failure, cart == nil {
                ErrorView(message: failure) { attempt += 1 }
            } else {
                Text("Your cart is empty")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Cart")
        // The app loaded the cart at start; load again on each visit so the screen is current (and Retry has something to run).
        .task(id: attempt) { await load() }
        // Warm up checkout once the shopper is looking at a non-empty cart, and again after every change to it.
        .task(id: cart) { await preload(cart) }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $checkingOut, onDismiss: { checkoutDismissed() }) {
            if let url = checkout {
                CheckoutSheet(checkout: url)
                    .onCancel { checkingOut = false }
                    // the sheet stays open on the order confirmation until the shopper closes it (onCancel)
                    .onComplete { _ in Task { await AppGraph.cart.completed() } }
                    .onFail { error in
                        // the cart is kept; one Shopify no longer has (expired, already paid) is dropped by loading it again
                        if case .checkoutExpired = error { Task { _ = try? await AppGraph.cart.load() } }
                        checkoutFailure = checkoutMessage(error)
                        checkingOut = false
                    }
                    .ignoresSafeArea()
            }
        }
    }

    /// Runs once the checkout sheet has finished dismissing, whoever dismissed it (the shopper, the kit or `onFail`).
    private func checkoutDismissed() {
        checkout = nil
        if let failure = checkoutFailure { message = failure }
        checkoutFailure = nil
    }

    private func content(_ cart: Cart) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(cart.lines, id: \.id) { line in
                        CartLineRow(line: line, busy: busy) { quantity in
                            act { try await AppGraph.cart.update(line.id, quantity: quantity) }
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            VStack(spacing: 12) {
                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(cart.subtotal.display())
                }
                .font(.headline)
                Button { startCheckout() } label: {
                    Text("Checkout").onBrand().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy)
            }
            .padding(16)
        }
    }

    private func load() async {
        loading = true
        failure = nil
        do {
            try await AppGraph.cart.load()
        } catch {
            if !Task.isCancelled { failure = error.localizedDescription }
        }
        loading = false
    }

    /// The sleep is a debounce: tapping the stepper quickly restarts this task, so only the last cart is preloaded.
    private func preload(_ cart: Cart?) async {
        guard let cart = cart, !cart.lines.isEmpty else { return }
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            return
        }
        // preloading is only a hint: checkout still works without it, and Checkout reports real problems
        guard let link = await AppGraph.cart.checkoutUrl(), let url = URL(string: link), !Task.isCancelled else { return }
        ShopifyCheckoutSheetKit.preload(checkout: url)
    }

    /// Runs `block` with the screen busy; a failure shows as an alert.
    private func act(_ block: @escaping () async throws -> Void) {
        busy = true
        Task {
            do {
                try await block()
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }

    private func startCheckout() {
        checkoutFailure = nil
        act {
            guard let link = await AppGraph.cart.checkoutUrl(), let url = URL(string: link) else { return }
            checkout = url
            checkingOut = true
        }
    }
}

@MainActor
private struct CartLineRow: View {
    let line: CartLine
    let busy: Bool
    let onQuantity: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(img: line.image)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(line.productTitle).lineLimit(2)
                // a product without options has Shopify's one "Default Title" variant; nothing worth showing
                if line.variantTitle != "Default Title" {
                    Text(line.variantTitle).font(.subheadline).foregroundStyle(.secondary)
                }
                stepper
            }
            Spacer(minLength: 0)
            Text(line.total.display())
        }
    }

    /// − and +; at 1 the − becomes a bin, because it removes the line.
    private var stepper: some View {
        HStack(spacing: 4) {
            Button { onQuantity(line.quantity - 1) } label: {
                if line.quantity <= 1 {
                    Label("Remove from cart", systemImage: "trash")
                } else {
                    Label("Decrease quantity", systemImage: "minus")
                }
            }
            Text(verbatim: "\(line.quantity)").frame(minWidth: 28)
            Button { onQuantity(line.quantity + 1) } label: {
                Label("Increase quantity", systemImage: "plus")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .disabled(busy)
    }
}
