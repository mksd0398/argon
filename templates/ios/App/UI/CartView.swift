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

// MARK: - Totals

private extension Money {
    /// The amount as a number; zero when it can't be read.
    var value: Decimal { Decimal(string: amount) ?? 0 }
}

/// How far a cart is from free shipping: what is still to add (`remaining`, zero once reached) and the `progress` to
/// it, 0...1.
struct FreeShipping: Equatable {
    let remaining: Money
    let progress: Double

    var reached: Bool { !remaining.isPositive() }
}

/// Free shipping for a cart worth `subtotal` (its total after discounts) in a store that ships free from `threshold`, a
/// number in `shopCurrency`; nil for a store without one (`FREE_SHIPPING_THRESHOLD` unset), an amount that can't be
/// read, a cart in another currency, and until the shop's currency is known.
/// ponytail: the threshold is one number, in the shop's own currency: a shopper buying in another one sees no progress.
/// Upgrade: one threshold per currency, if stores selling in several ask for it.
func freeShipping(subtotal: Money, threshold: Double?, shopCurrency: String?) -> FreeShipping? {
    // the threshold through its text: a Decimal made from a Double keeps the Double's binary error (49.99 isn't 49.99)
    guard subtotal.currencyCode == shopCurrency, let threshold = threshold, threshold > 0, threshold.isFinite,
          let goal = Decimal(string: String(threshold)), let have = Decimal(string: subtotal.amount) else { return nil }
    let progress = NSDecimalNumber(decimal: have / goal).doubleValue
    return FreeShipping(
        remaining: Money(amount: "\(max(goal - have, 0))", currencyCode: subtotal.currencyCode),
        progress: min(max(progress, 0), 1)
    )
}

/// What `line` would cost at its compare-at price; nil when it has none above its price.
func compareAtTotal(_ line: CartLine) -> Money? {
    guard let was = line.compareAtUnitPrice, was.value > line.unitPrice.value else { return nil }
    return Money(amount: "\(was.value * Decimal(line.quantity))", currencyCode: was.currencyCode)
}

/// "WELCOME10 −$12.00": a discount on a line, by its code or its title, and what it takes off.
func discountLabel(_ discount: CartDiscount) -> String {
    "\(discount.label) −\(discount.amount.display())"
}

/// The cart's totals as its summary shows them: `subtotal` is the lines before discounts, `discounts` what codes and
/// automatic discounts take off, `savings` that plus what the compare-at prices say is saved, `total` what Shopify asks
/// for. `discounts` and `savings` are zero when there are none (their rows then hide).
struct CartSummary: Equatable {
    let subtotal: Money
    let discounts: Money
    let savings: Money
    let total: Money
}

func cartSummary(_ cart: Cart) -> CartSummary {
    func money(_ amount: Decimal) -> Money { Money(amount: "\(amount)", currencyCode: cart.total.currencyCode) }
    let subtotal = cart.lines.reduce(Decimal(0)) { $0 + $1.subtotal.value }
    let discounts = cart.lines.flatMap { $0.discounts }.reduce(Decimal(0)) { $0 + $1.amount.value }
    let marked = cart.lines.reduce(Decimal(0)) { sum, line in
        sum + max((compareAtTotal(line)?.value ?? 0) - line.subtotal.value, 0)
    }
    return CartSummary(subtotal: money(subtotal), discounts: money(discounts), savings: money(marked + discounts), total: cart.total)
}

/// The products to suggest under a cart: the `recommended` ones that aren't in the `cart` already.
func suggestions(recommended: [ProductCard], cart: Cart?) -> [ProductCard] {
    let inCart = Set((cart?.lines ?? []).map { $0.productId })
    return recommended.filter { !inCart.contains($0.id) }
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
///
/// Analytics hears of the whole way from here: `begin_checkout` as the sheet opens (the app has the whole cart), the
/// shipping and payment steps from the checkout's web pixel events, and the purchase from the completed order, which
/// comes once (the pixel's `checkout_completed` is left alone).
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
                    .onComplete { event in
                        AppGraph.analytics.track(purchase(event.orderDetails))
                        Task { await AppGraph.cart.completed() }
                    }
                    .onPixelEvent { event in
                        if let step = checkoutStep(event) { AppGraph.analytics.track(step) }
                    }
                    .onFail { error in
                        // the cart is kept; one Shopify no longer has (expired, already paid) is dropped by loading it again
                        if case .checkoutExpired = error { Task { _ = try? await AppGraph.cart.load() } }
                        failure = checkoutMessage(error)
                        isPresented = false
                    }
                    .ignoresSafeArea()
            }
        }
        .onChange(of: isPresented) { _, presented in
            if presented, let cart = AppGraph.cart.cart { AppGraph.analytics.track(beginCheckout(cart)) }
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

/// The Cart tab: one scrolling list (free-shipping progress, the lines, the discount code, "You may also like") over a
/// pinned summary with "Checkout"; an empty cart offers "Start shopping".
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
    @State private var alsoLike: [ProductCard] = []
    // the currency of the shop's own prices, which `FREE_SHIPPING_THRESHOLD` is a number in; nil until the shop has answered
    @State private var shopCurrency: String? = nil
    @State private var keyboardUp = false
    @Environment(Router.self) private var router
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let cart = AppGraph.cart.cart
        let firstProduct = cart?.lines.first?.productId ?? ""
        VStack {
            if let cart = cart, !cart.lines.isEmpty {
                content(cart)
            } else if loading && cart == nil {
                ArgonSpinner()
            } else if let failure = failure, cart == nil {
                ErrorView(message: failure) { attempt += 1 }
            } else {
                VStack(spacing: theme.spacing.l) {
                    Text("Your cart is empty").font(theme.type.body).foregroundStyle(theme.colors.muted)
                    ArgonButton(title: "Start shopping") { AppGraph.tabs.selected = .shop }
                }
                .padding(theme.spacing.xxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.paper)
        .argonTopBar(title: "Cart")
        // The app loaded the cart at start; load again on each visit so the screen is current (and Retry has something to run).
        .task(id: attempt) { await load() }
        // Warm up checkout once the shopper is looking at a non-empty cart, and again after every change to it.
        .task(id: cart) { await preload(cart) }
        .task(id: firstProduct) { await suggest(firstProduct) }
        // the shop is fetched once for the whole app, so this is rarely a call; when it can't be asked, the row stays away
        .task { if let shop = try? await AppGraph.storefront.shop() { shopCurrency = shop.paymentSettings.currencyCode } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
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
        let gutter = theme.spacing.l
        let shipping = freeShipping(subtotal: cart.total, threshold: AppGraph.freeShippingThreshold, shopCurrency: shopCurrency)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: theme.spacing.l) {
                    if let shipping = shipping {
                        FreeShippingBar(shipping: shipping).padding(.horizontal, gutter)
                    }
                    LazyVStack(spacing: theme.spacing.l) {
                        ForEach(cart.lines, id: \.id) { line in
                            CartLineRow(line: line, busy: busy) { quantity in
                                act { try await AppGraph.cart.update(line.id, quantity: quantity) }
                            }
                        }
                    }
                    .padding(.horizontal, gutter)
                    // not in the lazy list: a code being typed must not go when the field scrolls away
                    DiscountCode(cart: cart).padding(.horizontal, gutter)
                    if !alsoLike.isEmpty {
                        VStack(alignment: .leading, spacing: theme.spacing.m) {
                            SectionHeader(title: "You may also like").padding(.horizontal, gutter)
                            ProductCardRow(cards: alsoLike, style: .compact, cardWidth: 132) { router.open(.product($0.handle)) }
                        }
                    }
                }
                .padding(.vertical, theme.spacing.l)
            }
            // a code being typed: dragging the list puts the keyboard away
            .scrollDismissesKeyboard(.interactively)
            // While the keyboard is up (the discount code) the list has the room; the summary is back when it is gone.
            if !keyboardUp { summary(cartSummary(cart)) }
        }
    }

    /// The pinned summary: the totals, the note about what checkout adds, and "Checkout".
    private func summary(_ totals: CartSummary) -> some View {
        let type = theme.type, colors = theme.colors
        return VStack(spacing: 0) {
            ArgonDivider()
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                summaryRow("Subtotal", totals.subtotal.display(), type.body, colors.muted, colors.ink)
                if totals.discounts.isPositive() {
                    summaryRow("Discounts", "−\(totals.discounts.display())", type.body, colors.muted, colors.ink)
                }
                if totals.savings.isPositive() {
                    summaryRow("You save", totals.savings.display(), type.body, colors.success, colors.success)
                }
                summaryRow("Total", totals.total.display(), type.headline, colors.ink, colors.ink)
                Text("Taxes and shipping are calculated at checkout").font(type.caption).foregroundStyle(colors.muted)
                ArgonButton(title: "Checkout", isEnabled: !busy, fullWidth: true) { startCheckout() }
                    .padding(.top, theme.spacing.xs)
            }
            .padding(theme.spacing.l)
        }
    }

    private func summaryRow(_ label: String, _ value: String, _ font: Font, _ labelColor: Color, _ valueColor: Color) -> some View {
        HStack(spacing: theme.spacing.s) {
            Text(label).foregroundStyle(labelColor).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).foregroundStyle(valueColor)
        }
        .font(font)
    }

    /// "You may also like": the products related to the cart's first product (`productId`), without those in the cart
    /// when they are loaded (one added from here stays, with its stepper). Empty until they load, and when they can't be.
    private func suggest(_ productId: String) async {
        guard !productId.isEmpty else {
            alsoLike = []
            return
        }
        do {
            let recommended = try await AppGraph.storefront.recommendations(productId: productId)
            alsoLike = suggestions(recommended: recommended, cart: AppGraph.cart.cart)
        } catch {
            // leaving the screen cancels the load; it runs again when the screen is shown
            if !Task.isCancelled { alsoLike = [] }
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
        // analytics' `view_cart`: once per visit, of the cart as it is now (the last known one when the load failed)
        if !Task.isCancelled, let cart = AppGraph.cart.cart, !cart.lines.isEmpty { AppGraph.analytics.track(viewCart(cart)) }
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

/// "Add $30.00 more for free shipping" over a bar of how far the cart is; "You've unlocked free shipping" once it is there.
@MainActor
private struct FreeShippingBar: View {
    let shipping: FreeShipping
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let words: String = shipping.reached ? "You've unlocked free shipping" : "Add \(shipping.remaining.display()) more for free shipping"
        let color = shipping.reached ? theme.colors.success : theme.colors.ink
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(spacing: theme.spacing.s) {
                ArgonIcon(name: .truck, size: 20, tint: color)
                Text(words).font(theme.type.label).foregroundStyle(color)
            }
            ArgonProgressBar(value: shipping.progress)
        }
    }
}

/// A cart line: image, product, variant, the selling plan it is bought on, a bundle's parts and each discount on the
/// line, with its price (and, struck under it, what it would cost at its compare-at price) at the end; then the quantity
/// on the variant's quantity rule (its minimum, maximum and increments) with a bin beside it that removes the line.
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
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(line.total.display())
                        if let was = compareAtTotal(line)?.display() {
                            Text(was)
                                .font(theme.type.caption)
                                .strikethrough()
                                .foregroundStyle(theme.colors.muted)
                                .accessibilityLabel("Was \(was)")
                        }
                    }
                    .lineLimit(1)
                    .layoutPriority(1)
                }
                .font(theme.type.label)
                .foregroundStyle(theme.colors.ink)
                Group {
                    // a product without options has Shopify's one "Default Title" variant; nothing worth showing
                    if line.variantTitle != "Default Title" { Text(line.variantTitle) }
                    if let plan = line.sellingPlanName { Text(plan) }
                    ForEach(line.components, id: \.id) { part in Text(componentLabel(part)) }
                    ForEach(Array(line.discounts.enumerated()), id: \.offset) { _, discount in
                        Text(discountLabel(discount)).foregroundStyle(theme.colors.success)
                    }
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

/// The discount code: a field with "Apply", and under it the cart's codes as tags, each with its ✕ (a code that has
/// stopped counting, after the cart changed, is the unfilled one). A code that can't be used on this cart says so under
/// the field. Writes aren't tied to the screen: leaving the tab doesn't drop them.
@MainActor
private struct DiscountCode: View {
    let cart: Cart
    @State private var code = ""
    @State private var error: String? = nil
    @State private var applying = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(alignment: .top, spacing: theme.spacing.s) {
                ArgonInput(label: "Discount code", text: $code, error: error)
                    .disabled(applying)
                    .onChange(of: code) { error = nil }
                VStack(spacing: theme.spacing.xs) {
                    // beside the field's box, which starts under its label: the same label, unseen, over the button
                    Text("Discount code").font(theme.type.label).hidden()
                    ArgonButton(
                        title: "Apply",
                        style: .secondary,
                        isLoading: applying,
                        isEnabled: trimmedText(code) != nil
                    ) { apply() }
                }
            }
            if !cart.discountCodes.isEmpty {
                WrappingRow(spacing: theme.spacing.s) {
                    ForEach(cart.discountCodes, id: \.code) { discount in
                        ArgonTag(text: discount.code, style: .input, isSelected: discount.applicable, onRemove: {
                            write {
                                try await AppGraph.cart.removeDiscount(discount.code)
                                return nil
                            }
                        })
                    }
                }
            }
        }
    }

    private func apply() {
        let entered = code
        // the keyboard goes, so the answer (a tag, or the note under the field) and the summary are in view
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        write {
            guard try await AppGraph.cart.applyDiscount(entered) else { return "This code can't be used on your cart" }
            code = ""
            return nil
        }
    }

    /// Runs a change of the cart's codes; what it returns, or how it failed, shows under the field.
    private func write(_ change: @escaping () async throws -> String?) {
        applying = true
        error = nil
        Task {
            do {
                error = try await change()
            } catch {
                self.error = error.localizedDescription
            }
            applying = false
        }
    }
}
