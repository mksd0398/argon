import Foundation

// What each provider is sent for an event: the hub's events under the provider's own names. Pure and always compiled, so
// they are tested without any SDK; a provider's sink (FirebaseSink.swift, MetaSink.swift, MoEngageSink.swift: each
// compiled in only when the app has the provider's Swift package) only hands the result to its SDK. The names and the
// rules are the same on Android.

/// The pairs that have a value. Sendable, which MoEngage's SDK asks of what it is handed; any of them is an `Any` to
/// the other two.
private func values(_ pairs: KeyValuePairs<String, (any Sendable)?>) -> [String: any Sendable] {
    Dictionary(pairs.compactMap { pair in pair.value.map { (pair.key, $0) } }) { _, last in last }
}

// amounts are decimal: 19.99 x 3 is 59.97, not the 59.969999999999995 of doubles
private func decimal(_ amount: Double) -> Decimal { Decimal(string: "\(amount)") ?? Decimal(amount) }

private func double(_ amount: Decimal) -> Double { Double("\(amount)") ?? 0 }

private extension AnalyticsItem {
    var total: Double? { price.map { double(decimal($0) * Decimal(quantity)) } }

    var ga4: [String: any Sendable] {
        values([
            "item_id": productId, "item_name": name, "item_brand": brand, "item_category": category, "item_variant": variant,
            "price": price, "quantity": quantity,
        ])
    }

    // The id Meta's catalog knows a product by. A catalog synced from Shopify lists variants, so it is the variant's.
    var metaId: String { variantId ?? productId }
}

// MARK: - Google Analytics 4 (Firebase)

/// `event`'s parameters for Google Analytics 4, where its name is `AnalyticsEvent.name`: the flat ones, with `items` as
/// one dictionary per item. A purchase is worth the order's total without tax and shipping, which are parameters of their
/// own (the store's server reports the same number). Nil: not sent, which is the purchase when the server reports it
/// (`serverPurchase`, see FirebaseSink).
func ga4Params(_ event: AnalyticsEvent, serverPurchase: Bool = false) -> [String: Any]? {
    var params = event.params
    switch event {
    case let .viewItem(item, currency), let .addToWishlist(item, currency), let .addToCart(item, currency),
         let .removeFromCart(item, currency):
        params = values(["currency": currency, "value": item.total, "items": [item.ga4]])
    case let .viewItemList(_, _, items), let .viewCart(items, _, _), let .beginCheckout(items, _, _, _):
        params["items"] = items.map { $0.ga4 }
    case let .purchase(_, value, _, tax, shipping, _, items):
        if serverPurchase { return nil }
        params["value"] = double(decimal(value) - decimal(tax ?? 0) - decimal(shipping ?? 0))
        params["items"] = items.map { $0.ga4 }
    default:
        break // a screen, a search, the two checkout steps, a sign-in: flat already
    }
    return params
}

// MARK: - Meta (the Facebook SDK's App Events)

/// An App Event as the Facebook SDK logs it: a standard event's `name`, the `value` it sums (none: nil) and its `params`.
struct MetaEvent {
    let name: String
    let value: Double?
    let params: [String: Any]
}

/// `value` (lists, dictionaries, texts, numbers) as JSON, the same text each time.
private func json(_ value: Any) -> String {
    let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
}

/// `items` under Meta's parameter names: `fb_content_id` is the one id, or a JSON list of them; `fb_content` adds the
/// quantities.
private func metaContents(_ items: [AnalyticsItem], currency: String) -> [String: Any] {
    [
        "fb_content_id": items.count == 1 ? items[0].metaId : json(items.map { $0.metaId }),
        "fb_content": json(items.map { ["id": $0.metaId, "quantity": $0.quantity] as [String: Any] }),
        "fb_content_type": "product",
        "fb_currency": currency,
        "fb_num_items": items.reduce(0) { $0 + $1.quantity },
    ]
}

/// `event` as Meta's standard App Event; nil for those Meta has no standard event for (a list, a removal, the cart,
/// shipping details, a screen, a sign-in): they are not sent. The purchase is worth the order's total, and its `event_id`
/// is the one the store's server sends the same purchase under, by which Meta counts the two once.
func metaEvent(_ event: AnalyticsEvent) -> MetaEvent? {
    func about(_ name: String, _ item: AnalyticsItem, _ currency: String) -> MetaEvent {
        MetaEvent(name: name, value: item.total, params: metaContents([item], currency: currency))
    }
    switch event {
    case let .viewItem(item, currency):
        return about("fb_mobile_content_view", item, currency)
    case let .search(term):
        return MetaEvent(name: "fb_mobile_search", value: nil, params: ["fb_search_string": term])
    case let .addToWishlist(item, currency):
        return about("fb_mobile_add_to_wishlist", item, currency)
    case let .addToCart(item, currency):
        return about("fb_mobile_add_to_cart", item, currency)
    case let .beginCheckout(items, value, currency, _):
        return MetaEvent(name: "fb_mobile_initiated_checkout", value: value, params: metaContents(items, currency: currency))
    case .addPaymentInfo:
        return MetaEvent(name: "fb_mobile_add_payment_info", value: nil, params: ["fb_success": 1])
    case let .purchase(orderId, value, currency, _, _, _, items):
        var params = metaContents(items, currency: currency)
        params["event_id"] = "purchase-\(orderId)"
        return MetaEvent(name: "fb_mobile_purchase", value: value, params: params)
    default:
        return nil
    }
}

/// Meta's `extinfo`: what its Conversions API wants to know of the device behind an app's event, as the JSON list (16
/// texts in this order, "i2" first: the iOS layout) that a cart carries to the store's server. Sizes are in points.
/// Three are the empty text Meta asks for where there is no value: the carrier, which an iPhone no longer tells an app,
/// and the two storage sizes, which Apple lets an app read only for a reason of its own list, and this isn't one.
func metaExtinfo(
    bundleId: String,
    build: String,
    version: String,
    osVersion: String,
    model: String,
    locale: String,
    timezoneAbbreviation: String,
    screenWidth: Int,
    screenHeight: Int,
    screenDensity: Int,
    cores: Int,
    timezone: String
) -> String {
    json([
        "i2", bundleId, build, version, osVersion, model, locale, timezoneAbbreviation, "", "\(screenWidth)",
        "\(screenHeight)", "\(screenDensity)", "\(cores)", "", "", timezone,
    ])
}

// MARK: - MoEngage

// One product's attributes: the names MoEngage's Shopify integration tracks the same things under.
private func moEngage(_ item: AnalyticsItem, currency: String) -> [String: any Sendable] {
    values([
        "Product ID": item.productId, "Product Title": item.name, "Variation ID": item.variantId,
        "Variation Title": item.variant, "Vendor Name": item.brand, "Price": item.price, "Currency": currency,
        "Quantity": item.quantity,
    ])
}

// An event's `own` attributes and those of its `items`, a list of each, under the same integration's names. A list an
// item has nothing for is shorter than the others; one no item has anything for is left out.
private func moEngage(_ own: [String: any Sendable], _ items: [AnalyticsItem]) -> [String: any Sendable] {
    let lists: [String: [any Sendable]] = [
        "Product IDs": items.map { $0.productId }, "Product Titles": items.map { $0.name },
        "Variation IDs": items.compactMap { $0.variantId }, "Product Prices": items.compactMap { $0.price },
        "Product Quantities": items.map { $0.quantity }, "Vendor Names": items.compactMap { $0.brand },
    ]
    return own.merging(lists.filter { !$0.value.isEmpty }) { _, last in last }
}

/// `event` as MoEngage's event: its name and attributes. The names are those MoEngage's Shopify integration (its Web SDK)
/// tracks the same action under, so a store's web and app events are one; where it has none, the same style. Never its
/// "Shopify - ..." names: those come from the store's webhooks, for the app's orders too.
func moEngageEvent(_ event: AnalyticsEvent) -> (name: String, attributes: [String: any Sendable]) {
    switch event {
    case let .screenView(screen):
        return ("Screen Viewed", ["Screen Name": screen])
    case let .viewItemList(listId, listName, items):
        return ("Product List Viewed", moEngage(values(["List ID": listId, "List Name": listName]), items))
    case let .viewItem(item, currency):
        return ("Product Viewed", moEngage(item, currency: currency))
    case let .search(term):
        return ("Product Searched", ["Search String": term])
    case let .addToWishlist(item, currency):
        return ("Wishlist Added", moEngage(item, currency: currency))
    case let .addToCart(item, currency):
        return ("Add to Cart", moEngage(item, currency: currency))
    case let .removeFromCart(item, currency):
        return ("Removed From Cart", moEngage(item, currency: currency))
    case let .viewCart(items, value, currency):
        return ("Cart Viewed", moEngage(["Total Price": value, "Currency": currency], items))
    case let .beginCheckout(items, value, currency, coupon):
        // "currency": the integration's own spelling on this one event
        return ("Checkout Started", moEngage(values(["Total Price": value, "currency": currency, "Coupon": coupon]), items))
    case let .addShippingInfo(value, currency):
        return ("Shipping Info Added", ["Total Price": value, "Currency": currency])
    case let .addPaymentInfo(value, currency):
        return ("Payment Info Added", ["Total Price": value, "Currency": currency])
    case let .purchase(orderId, value, currency, tax, shipping, coupon, items):
        let own = values([
            "Order ID": orderId, "Total Price": value, "Currency": currency, "Tax": tax, "Shipping": shipping, "Coupon": coupon,
        ])
        return ("Order Placed", moEngage(own, items))
    case .login:
        return ("Customer Logged In", [:])
    }
}
