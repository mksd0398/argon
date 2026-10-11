import ArgonUI
import ShopifyCheckoutSheetKit
import SwiftUI

// This file imports Checkout Kit, whose public `Image` would clash with SwiftUI's: no unqualified `Image` here.

/// "Men's T-shirt · Small / Olive × 1": a bundle's part on a cart line (the variant left out when it is "Default Title").
func componentLabel(_ part: CartLineComponent) -> String {
    let product = part.productTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : part.productTitle
    let variant = part.variantTitle == "Default Title" ? nil : part.variantTitle
    return [product, variant].compactMap { $0 }.joined(separator: " · ") + " × \(part.quantity)"
}

// MARK: - Checkout

/// What went wrong, in Checkout Kit's words.
private func checkoutMessage(_ error: CheckoutError) -> String {
    // if-case rather than a switch: a later 3.x may add cases
    if case let .checkoutExpired(message, _, _) = error { return message }
    if case let .checkoutUnavailable(message, _, _) = error { return message }
    if case let .configurationError(message, _, _) = error { return message }
    if case let .sdkError(underlying, _) = error { return underlying.localizedDescription }
    return String(describing: error)
}

/// Shopify's checkout for `url` (`CartStore.checkoutUrl`) as a sheet: see `View.checkoutSheet`.
private struct CheckoutPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let url: URL?
    let onDismiss: (_ failure: String?) -> Void
    // A checkout failure, handed on once the sheet is gone: a message raised while it is still dismissing can be lost.
    @State private var failure: String? = nil

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: { dismissed() }) {
            if let url = url {
                CheckoutSheet(checkout: url)
                    .onCancel { isPresented = false }
                    // the sheet stays open on the order confirmation until the shopper closes it (onCancel)
                    .onComplete { _ in Task { await AppGraph.cart.completed() } }
                    .onFail { error in
                        // the cart is kept; one Shopify no longer has (expired, already paid) is dropped by loading it again
                        if case .checkoutExpired = error { Task { _ = try? await AppGraph.cart.load() } }
                        failure = checkoutMessage(error)
                        isPresented = false
                    }
                    .ignoresSafeArea()
            }
        }
    }

    /// Runs once the sheet has finished dismissing, whoever dismissed it (the shopper, the kit or `onFail`).
    private func dismissed() {
        let reason = failure
        failure = nil
        onDismiss(reason)
    }
}

extension View {
    /// Shows Shopify's checkout for `url` over this screen while `isPresented`: the cart screen's "Checkout" and the
    /// product page's "Buy now". A placed order spends the cart. A checkout that fails keeps it; one Shopify no longer has
    /// (expired, already paid) is dropped by loading the cart again. `onDismiss` runs once the sheet has gone, with the
    /// reason when it failed: keep `url` set until then, so the sheet doesn't blank while it animates out.
    func checkoutSheet(isPresented: Binding<Bool>, url: URL?, onDismiss: @escaping (_ failure: String?) -> Void) -> some View {
        modifier(CheckoutPresenter(isPresented: isPresented, url: url, onDismiss: onDismiss))
    }
}

// MARK: - Views

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
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let cart = AppGraph.cart.cart
        VStack {
            if let cart = cart, !cart.lines.isEmpty {
                content(cart)
            } else if loading && cart == nil {
                ArgonSpinner()
            } else if let failure = failure, cart == nil {
                ErrorView(message: failure) { attempt += 1 }
            } else {
                Text("Your cart is empty").font(theme.type.body).foregroundStyle(theme.colors.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.paper)
        .argonTopBar(title: "Cart")
        // The app loaded the cart at start; load again on each visit so the screen is current (and Retry has something to run).
        .task(id: attempt) { await load() }
        // Warm up checkout once the shopper is looking at a non-empty cart, and again after every change to it.
        .task(id: cart) { await preload(cart) }
        .argonModal(
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
            title: message ?? "",
            message: "",
            primaryAction: ArgonModalAction("OK")
        )
        .checkoutSheet(isPresented: $checkingOut, url: checkout) { failure in
            checkout = nil
            if let failure = failure { message = failure }
        }
    }

    private func content(_ cart: Cart) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: theme.spacing.l) {
                    ForEach(cart.lines, id: \.id) { line in
                        CartLineRow(line: line, busy: busy) { quantity in
                            act { try await AppGraph.cart.update(line.id, quantity: quantity) }
                        }
                    }
                }
                .padding(theme.spacing.l)
            }
            ArgonDivider()
            VStack(spacing: theme.spacing.m) {
                HStack(spacing: theme.spacing.s) {
                    Text("Subtotal").frame(maxWidth: .infinity, alignment: .leading)
                    Text(cart.subtotal.display())
                }
                .font(theme.type.headline)
                .foregroundStyle(theme.colors.ink)
                ArgonButton(title: "Checkout", isEnabled: !busy, fullWidth: true) { startCheckout() }
            }
            .padding(theme.spacing.l)
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
    /// Nothing is preloaded while checkout is open.
    private func preload(_ cart: Cart?) async {
        guard let cart = cart, !cart.lines.isEmpty else { return }
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            return
        }
        // preloading is only a hint: checkout still works without it, and Checkout reports real problems
        guard let link = await AppGraph.cart.checkoutUrl(), let url = URL(string: link), !Task.isCancelled else { return }
        // not while the sheet is open: Checkout Kit 3.9.1 would swap the view under it and lose its onComplete and onFail
        guard !checkingOut else { return }
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
        act {
            guard let link = await AppGraph.cart.checkoutUrl(), let url = URL(string: link) else { return }
            checkout = url
            checkingOut = true
        }
    }
}

/// A cart line: image, product, variant, the selling plan it is bought on, a bundle's parts, then the quantity on the
/// variant's quantity rule (its minimum, maximum and increments) with a bin beside it that removes the line.
/// `onQuantity` gets the new quantity; 0 removes the line.
@MainActor
private struct CartLineRow: View {
    let line: CartLine
    let busy: Bool
    let onQuantity: (Int) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let rule = line.quantityRule
        HStack(alignment: .top, spacing: theme.spacing.m) {
            StoreImage(url: line.image?.url, alt: line.image?.alt ?? line.productTitle)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.m))
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                HStack(alignment: .top, spacing: theme.spacing.s) {
                    Text(line.productTitle).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Text(line.total.display()).lineLimit(1).layoutPriority(1)
                }
                .font(theme.type.label)
                .foregroundStyle(theme.colors.ink)
                Group {
                    // a product without options has Shopify's one "Default Title" variant; nothing worth showing
                    if line.variantTitle != "Default Title" { Text(line.variantTitle) }
                    if let plan = line.sellingPlanName { Text(plan) }
                    ForEach(line.components, id: \.id) { part in Text(componentLabel(part)) }
                }
                .font(theme.type.caption)
                .foregroundStyle(theme.colors.muted)
                HStack(spacing: theme.spacing.xs) {
                    ArgonQuantityStepper(
                        value: line.quantity,
                        onChange: onQuantity,
                        min: rule?.min ?? 1,
                        max: rule?.maximum,
                        step: rule?.step ?? 1,
                        size: .s,
                        isEnabled: !busy
                    )
                    Button { onQuantity(0) } label: {
                        ArgonIcon(name: .trash, size: 20, tint: theme.colors.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .opacity(busy ? 0.4 : 1)
                    .accessibilityLabel("Remove from cart")
                }
                .padding(.top, theme.spacing.xs)
            }
        }
    }
}
