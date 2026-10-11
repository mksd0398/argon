import Foundation
import os
import ShopifyCheckoutSheetKit

// Analytics: one hub (`Analytics`) that every screen and store reports into, with the providers (Google Analytics, Meta,
// MoEngage) behind it as `AnalyticsSink`s. The events, their names and where each is fired are the same on Android.
// This file imports Checkout Kit, which has a public `CartLine` and `Product` of its own: unqualified, those names are
// the app's.

/// A product in an event. Ids are the numeric tail of the Shopify gid ("gid://shopify/Product/123" is "123"): what
/// Google's and Meta's catalogs use. `variant` is the variant's title, `price` one item's.
struct AnalyticsItem: Equatable, Sendable {
    let productId: String
    var variantId: String? = nil
    let name: String
    var brand: String? = nil
    var category: String? = nil
    var variant: String? = nil
    var price: Double? = nil
    var quantity = 1
}

/// What the shopper did, one case per event.
enum AnalyticsEvent: Equatable, Sendable {
    case screenView(String)
    case viewItemList(listId: String?, listName: String, items: [AnalyticsItem])
    case viewItem(AnalyticsItem, currency: String)
    case search(String)
    case addToWishlist(AnalyticsItem, currency: String)
    case addToCart(AnalyticsItem, currency: String)
    case removeFromCart(AnalyticsItem, currency: String)
    case viewCart(items: [AnalyticsItem], value: Double, currency: String)
    case beginCheckout(items: [AnalyticsItem], value: Double, currency: String, coupon: String? = nil)
    case addShippingInfo(value: Double, currency: String)
    case addPaymentInfo(value: Double, currency: String)
    /// `orderId`: the order's numeric id, the same in the app and on the server, which is what stops a sale being counted twice.
    case purchase(
        orderId: String,
        value: Double,
        currency: String,
        tax: Double? = nil,
        shipping: Double? = nil,
        coupon: String? = nil,
        items: [AnalyticsItem]
    )
    case login

    /// Google Analytics 4's name for the event.
    var name: String {
        switch self {
        case .screenView: return "screen_view"
        case .viewItemList: return "view_item_list"
        case .viewItem: return "view_item"
        case .search: return "search"
        case .addToWishlist: return "add_to_wishlist"
        case .addToCart: return "add_to_cart"
        case .removeFromCart: return "remove_from_cart"
        case .viewCart: return "view_cart"
        case .beginCheckout: return "begin_checkout"
        case .addShippingInfo: return "add_shipping_info"
        case .addPaymentInfo: return "add_payment_info"
        case .purchase: return "purchase"
        case .login: return "login"
        }
    }

    /// The event's values under Google Analytics 4's parameter names, flat, without those it has none of. An item list is
    /// one short text per item ("<product id>/<variant id> x<quantity>").
    var params: [String: Any] { Dictionary(values) { _, last in last } }

    /// `params` as the log prints them, in Android's order and form: "{value=324.0, currency=CAD, items=[123/456 x3]}".
    fileprivate var paramsText: String {
        let texts: [String] = values.map { key, value in
            // a list of texts without the quotes Swift would print around each
            let text = (value as? [String]).map { "[" + $0.joined(separator: ", ") + "]" } ?? "\(value)"
            return key + "=" + text
        }
        return "{" + texts.joined(separator: ", ") + "}"
    }

    private var values: [(String, Any)] {
        switch self {
        case let .screenView(screen):
            return present(["screen_name": screen])
        case let .viewItemList(listId, listName, items):
            return present(["item_list_id": listId, "item_list_name": listName, "items": labels(items)])
        case let .viewItem(item, currency), let .addToWishlist(item, currency), let .addToCart(item, currency),
             let .removeFromCart(item, currency):
            return present([
                "item_id": item.productId, "variant_id": item.variantId, "item_name": item.name, "item_brand": item.brand,
                "item_category": item.category, "item_variant": item.variant, "price": item.price, "quantity": item.quantity,
                "currency": currency,
            ])
        case let .search(term):
            return present(["search_term": term])
        case let .viewCart(items, value, currency):
            return present(["value": value, "currency": currency, "items": labels(items)])
        case let .beginCheckout(items, value, currency, coupon):
            return present(["value": value, "currency": currency, "coupon": coupon, "items": labels(items)])
        case let .addShippingInfo(value, currency), let .addPaymentInfo(value, currency):
            return present(["value": value, "currency": currency])
        case let .purchase(orderId, value, currency, tax, shipping, coupon, items):
            return present([
                "transaction_id": orderId, "value": value, "currency": currency, "tax": tax, "shipping": shipping,
                "coupon": coupon, "items": labels(items),
            ])
        case .login:
            return []
        }
    }
}

/// The pairs that have a value, in the order written.
private func present(_ pairs: KeyValuePairs<String, Any?>) -> [(String, Any)] {
    pairs.compactMap { pair in pair.value.map { (pair.key, $0) } }
}

private func labels(_ items: [AnalyticsItem]) -> [String] {
    items.map { [$0.productId, $0.variantId].compactMap { $0 }.joined(separator: "/") + " x\($0.quantity)" }
}

/// The signed-in customer (`id`: their numeric id).
struct AnalyticsUser: Equatable, Sendable {
    let id: String
    var email: String? = nil
    var phone: String? = nil
    var firstName: String? = nil
    var lastName: String? = nil
}

/// One destination of the events: a provider's SDK, or the debug log. A sink takes what it has a use for and leaves the
/// rest at these defaults. Its calls come on the main actor and must not block; they can't throw, so a sink deals with
/// its own failures.
@MainActor
protocol AnalyticsSink {
    func track(_ event: AnalyticsEvent)

    /// The signed-in customer; nil after a sign-out.
    func identify(_ user: AnalyticsUser?)

    /// What a new cart carries for the store's server to tie the order to this app install (the provider's own ids).
    func cartAttributes() async -> [String: String]

    /// Whether the shopper shares usage data. A provider's SDK collects on its own (automatic events, an advertising id,
    /// sessions), which the hub's gate can't stop: its sink turns the SDK's own collection on or off here.
    func setEnabled(_ allowed: Bool)
}

extension AnalyticsSink {
    func track(_ event: AnalyticsEvent) {}

    func identify(_ user: AnalyticsUser?) {}

    func cartAttributes() async -> [String: String] { [:] }

    func setEnabled(_ allowed: Bool) {}
}

/// The hub: screens and stores report here (`AppGraph.analytics`), and every sink gets what they report while the shopper
/// allows it (`allowed`, see `AnalyticsConsentStore`). Nothing here throws into its caller: a sink's calls can't.
@MainActor
final class Analytics {
    private let sinks: [AnalyticsSink]
    private let allowed: () -> Bool

    init(sinks: [AnalyticsSink], allowed: @escaping () -> Bool) {
        self.sinks = sinks
        self.allowed = allowed
        consentChanged()
    }

    /// Tells every sink the shopper's choice (`AnalyticsSink.setEnabled`): once as the hub is built, where the choice is
    /// already known, and again each time it changes.
    func consentChanged() {
        let allowed = allowed()
        for sink in sinks { sink.setEnabled(allowed) }
    }

    func track(_ event: AnalyticsEvent) {
        guard allowed() else { return }
        for sink in sinks { sink.track(event) }
    }

    /// The signed-in customer; nil after a sign-out.
    func identify(_ user: AnalyticsUser?) {
        guard allowed() else { return }
        for sink in sinks { sink.identify(user) }
    }

    /// The attributes of a new cart (they become the order's note attributes): the sinks' together and, when they have
    /// any, `_argon_platform`, by which the store's server knows an order of the app's. Empty when no sink has one (an
    /// order nobody has an id to report for), and when not allowed.
    func cartAttributes() async -> [String: String] {
        guard allowed() else { return [:] }
        var attributes: [String: String] = [:]
        for sink in sinks {
            attributes.merge(await sink.cartAttributes()) { _, last in last }
        }
        if !attributes.isEmpty { attributes["_argon_platform"] = "ios" }
        return attributes
    }
}

private let analyticsLog = Logger(subsystem: "app.storefront", category: "Analytics")

/// Debug builds only (`logSink`): one line per event in the Xcode console and the device's log,
/// `Analytics: add_to_cart {…}`, so the events can be checked without any provider account. Of the customer it logs the
/// id alone. `write` is where a line goes.
struct LogSink: AnalyticsSink {
    // a notice: Console and a device's log leave out anything quieter. Public: a debug build's log isn't redacted.
    var write: (String) -> Void = { line in analyticsLog.notice("\(line, privacy: .public)") }

    func track(_ event: AnalyticsEvent) {
        write("Analytics: \(event.name) \(event.paramsText)")
    }

    func identify(_ user: AnalyticsUser?) {
        // "null" for nobody, as Android's log has it: the two read the same
        write("Analytics: identify \(user?.id ?? "null")")
    }
}

/// The debug log as a sink; nil in a release build.
@MainActor
func logSink() -> AnalyticsSink? {
    #if DEBUG
    return LogSink()
    #else
    return nil
    #endif
}

// MARK: - The mappers: the app's own models, and Checkout Kit's, as items and events

/// "gid://shopify/Product/123" is "123".
func gidTail(_ gid: String) -> String {
    let path = gid.prefix { $0 != "?" }
    return String(path.split(separator: "/", omittingEmptySubsequences: false).last ?? "")
}

private extension Money {
    var number: Double? { Double(amount) }
}

/// `title` unless it is the "Default Title" of a product without options.
private func variantName(_ title: String?) -> String? {
    title == "Default Title" ? nil : title
}

extension CartLine {
    /// The line as an item; `quantity` is how many of it the event is about (a change of two is 2), the line's own when nil.
    func analyticsItem(quantity: Int? = nil) -> AnalyticsItem {
        AnalyticsItem(
            productId: gidTail(productId),
            variantId: gidTail(variantId),
            name: productTitle,
            variant: variantName(variantTitle),
            price: unitPrice.number,
            quantity: quantity ?? self.quantity
        )
    }
}

extension ProductCard {
    /// The card as an item, by the variant the list shows it by.
    func analyticsItem() -> AnalyticsItem {
        AnalyticsItem(
            productId: gidTail(id),
            variantId: firstVariant.map { gidTail($0.id) },
            name: title,
            brand: trimmedText(vendor),
            price: price.number
        )
    }
}

extension Product {
    // the variant the product's page opens on (ProductView's initialSelection)
    private var openingVariant: Variant? { variants.first { $0.available } ?? variants.first }

    private var openingPrice: Money { openingVariant?.price ?? priceRange.minVariantPrice }

    /// The product as an item, by the variant its page opens on: the first available one, else the first.
    func analyticsItem() -> AnalyticsItem {
        let variant = openingVariant
        return AnalyticsItem(
            productId: gidTail(id),
            variantId: variant.map { gidTail($0.id) },
            name: title,
            brand: trimmedText(vendor),
            category: trimmedText(productType),
            variant: variantName(variant?.title),
            price: openingPrice.number
        )
    }

    /// The currency of `analyticsItem`'s price.
    var analyticsCurrency: String { openingPrice.currencyCode }
}

extension Customer {
    func analyticsUser() -> AnalyticsUser {
        AnalyticsUser(id: gidTail(id), email: email, phone: phone, firstName: firstName, lastName: lastName)
    }
}

/// What a change of a cart's lines put in and took out, as events: each line's quantity `after` against the one `before`.
/// A line with more is an `add_to_cart` of the difference, one with less (or gone) a `remove_from_cart` of it.
func cartLineEvents(before: [CartLine], after: [CartLine]) -> [AnalyticsEvent] {
    let was = Dictionary(before.map { ($0.id, $0.quantity) }) { _, last in last }
    let now = Dictionary(after.map { ($0.id, $0.quantity) }) { _, last in last }
    return (after + before.filter { now[$0.id] == nil }).compactMap { line in
        let change = (now[line.id] ?? 0) - (was[line.id] ?? 0)
        let currency = line.unitPrice.currencyCode
        if change > 0 { return .addToCart(line.analyticsItem(quantity: change), currency: currency) }
        if change < 0 { return .removeFromCart(line.analyticsItem(quantity: -change), currency: currency) }
        return nil
    }
}

/// The cart as the cart screen shows it: its lines, worth its total (after discounts).
func viewCart(_ cart: Cart) -> AnalyticsEvent {
    .viewCart(items: cart.lines.map { $0.analyticsItem() }, value: cart.total.number ?? 0, currency: cart.total.currencyCode)
}

/// The cart going to checkout; its coupon is its discount codes that count ("A,B").
func beginCheckout(_ cart: Cart) -> AnalyticsEvent {
    let codes = cart.discountCodes.filter { $0.applicable }.map { $0.code }
    return .beginCheckout(
        items: cart.lines.map { $0.analyticsItem() },
        value: cart.total.number ?? 0,
        currency: cart.total.currencyCode,
        coupon: codes.isEmpty ? nil : codes.joined(separator: ",")
    )
}

/// The order Checkout Kit says was placed (`CheckoutCompletedEvent.orderDetails`) as the purchase. Its coupon is the
/// titles of the order's discounts: a code's is the code.
func purchase(_ order: CheckoutCompletedEvent.OrderDetails) -> AnalyticsEvent {
    let price = order.cart.price
    let discounts = (price.discounts ?? []).compactMap { $0.title }
    return .purchase(
        orderId: gidTail(order.id),
        value: price.total?.amount ?? 0,
        currency: price.total?.currencyCode ?? "",
        tax: price.taxes?.amount,
        shipping: price.shipping?.amount,
        coupon: discounts.isEmpty ? nil : discounts.joined(separator: ","),
        items: order.cart.lines.map { line in
            AnalyticsItem(
                productId: gidTail(line.productId ?? ""),
                variantId: line.merchandiseId.map { gidTail($0) },
                name: line.title,
                price: line.price.amount,
                quantity: line.quantity
            )
        }
    )
}

/// The checkout step a Checkout Kit web pixel event stands for: shipping or payment details submitted, worth the
/// checkout's total. Nil for every other standard event (the app reports those itself, where it has the whole cart), for
/// a store's custom events, and for an event without a total.
func checkoutStep(_ event: PixelEvent) -> AnalyticsEvent? {
    guard case let .standardEvent(standard) = event, let checkout = standard.data?.checkout,
          let value = checkout.totalPrice?.amount,
          let currency = checkout.currencyCode ?? checkout.totalPrice?.currencyCode else { return nil }
    switch standard.name ?? "" {
    case "checkout_shipping_info_submitted": return .addShippingInfo(value: value, currency: currency)
    case "payment_info_submitted": return .addPaymentInfo(value: value, currency: currency)
    default: return nil
    }
}
