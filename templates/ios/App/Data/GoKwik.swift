import Foundation

// GoKwik's hosted checkout (`CHECKOUT=gokwik`): the URL the web view opens and the events its page posts back. The
// protocol is the one of GoKwik's Flutter SDK 1.0.37; nothing of it runs in an app with Shopify's checkout.

/// Which GoKwik backend the app talks to (`GOKWIK_ENVIRONMENT`): `sandbox`, else production.
enum GoKwikEnvironment: String, Equatable, Sendable {
    case production, sandbox

    init(config: String) {
        self = config.trimmingCharacters(in: .whitespaces).lowercased() == "sandbox" ? .sandbox : .production
    }

    /// KwikPass's REST base.
    var apiBase: String {
        self == .sandbox ? "https://api-gw-v4.dev.gokwik.io/sandbox/" : "https://gkx.gokwik.co/"
    }

    /// The Shopify checkout page, ending in `storeInfo=`.
    var checkoutBase: String {
        self == .sandbox
            ? "https://sandbox.pdp.gokwik.co/app/kwik-checkout.html?storeInfo="
            : "https://pdp.gokwik.co/app/kwik-checkout.html?storeInfo="
    }
}

/// The UPI apps checkout offers to pay with: the URL scheme that tells one is installed (Info.plist's
/// `LSApplicationQueriesSchemes` lists them all) and the name GoKwik knows it by.
let goKwikUpiApps: [(scheme: String, name: String)] = [
    ("tez", "googlepay"), ("phonepe", "phonepe"), ("bhim", "bhim"), ("paytmmp", "paytm"), ("credpay", "cred"), ("slice-upi", "slice"),
]

private func base64(_ text: String) -> String {
    Data(text.utf8).base64EncodedString()
}

private func base64Json(_ value: Any) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    return data.base64EncodedString()
}

/// GoKwik's checkout for the Storefront cart `cartId` (`gid://shopify/Cart/<id>?key=<key>`). `coreToken` and `email` are
/// the signed-in KwikPass shopper's (checkout then skips its own OTP); `upiApps` the installed UPI apps' names.
/// The query values are base64 as GoKwik's SDK sends them, unescaped: the standard alphabet's `+` and `/` are left as they
/// are (`=` too), and the page reads them so.
func goKwikCheckoutUrl(
    cartId: String,
    storefrontToken: String,
    shopDomain: String,
    merchantId: String,
    environment: GoKwikEnvironment,
    coreToken: String? = nil,
    email: String? = nil,
    upiApps: [String] = []
) -> URL? {
    let prefix = "gid://shopify/Cart/"
    let storeInfo: [String: Any] = [
        "type": "merchantInfo",
        "source": "app",
        "platform": "ios",
        "appFlow": "true",
        "tag": "mobile_app_ios",
        "blockExternalEvents": true,
        "mid": merchantId,
        "environment": environment.rawValue,
        "storeId": "", "fbpixel": "", "gaTrackingID": "", "webEngageID": "", "moEngageID": "", "sessionId": "",
        "utmParams": [String: String](),
        "discountCodes": "",
        "storeData": [
            "cartId": cartId.hasPrefix(prefix) ? String(cartId.dropFirst(prefix.count)) : cartId,
            "storefrontAccessToken": storefrontToken,
            "shopDomain": shopDomain,
        ],
    ]
    var link = environment.checkoutBase + base64Json(storeInfo)
    // typed, so it can't fall through to empty data as an untyped dictionary can on Apple's JSONSerialization
    if let token = coreToken, !token.isEmpty, let json = try? JSONEncoder().encode(["coreToken": token]) {
        link += "&gk_token=" + json.base64EncodedString()
    }
    if let email = email, !email.isEmpty { link += "&kp_email=" + base64(email) }
    if !upiApps.isEmpty { link += "&upi_apps=" + base64Json(upiApps) }
    return URL(string: link)
}

/// Whether `host` is GoKwik's (`gokwik.co` or under it): the only pages whose messages the checkout acts on.
func isGoKwikHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return host == "gokwik.co" || host.hasSuffix(".gokwik.co")
}

/// What the checkout page said through `Flutter.postMessage`.
enum GoKwikEvent {
    /// Checkout is on screen: the spinner goes.
    case loaded
    /// The order was placed; `data` is GoKwik's order payload (its shape isn't documented).
    case orderSuccess(data: [String: Any])
    /// The shopper closed checkout.
    case closed
    /// A link to open in the browser.
    case openInBrowser(URL)
    /// GoKwik's checkout is off for this cart: Shopify's takes over.
    case disabled
    /// Not the page's: the page couldn't be loaded at all (offline), with the reason.
    case failed(String)
}

/// The event in a message: a JSON string `{"type": …, "data": …}`. Nil for one the app doesn't act on (`gokwik_events`,
/// an unknown type) or can't read.
func goKwikEvent(_ message: String) -> GoKwikEvent? {
    guard let object = (try? JSONSerialization.jsonObject(with: Data(message.utf8))) as? [String: Any],
          let type = object["type"] as? String else { return nil }
    let data = object["data"]
    switch type {
    case "gokwikLoaded": return .loaded
    case "orderSuccess": return .orderSuccess(data: data as? [String: Any] ?? [:])
    case "modal_closed": return .closed
    case "openInBrowserTab":
        // GUESS: `{url}`, or the URL itself
        let link = (data as? [String: Any])?["url"] as? String ?? data as? String
        return link.flatMap { URL(string: $0) }.map { .openInBrowser($0) }
    case "gk-checkout-disable": return .disabled
    default: return nil
    }
}

/// The purchase in GoKwik's `orderSuccess` payload, with the `cart` it checked out for the items; nil without an order
/// id (the id is what stops the server's report counting it twice).
/// ponytail: the payload's field names are guesses (GoKwik doesn't document them): `order_id`/`orderId`/`id`, the total
/// as `total_price`/`totalPrice`/`amount`/`total`, `currency`. Replace with the real names from a test order's payload.
func goKwikPurchase(_ data: [String: Any], cart: Cart?) -> AnalyticsEvent? {
    func text(_ keys: [String]) -> String? {
        for key in keys {
            if let value = data[key] as? String, !value.isEmpty { return value }
            if let value = data[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }
    guard let orderId = text(["order_id", "orderId", "id"]) else { return nil }
    let value = text(["total_price", "totalPrice", "amount", "total"]).flatMap { Double($0) } ?? cart.flatMap { Double($0.total.amount) } ?? 0
    return .purchase(
        orderId: gidTail(orderId),
        value: value,
        currency: text(["currency", "currencyCode"]) ?? cart?.total.currencyCode ?? "",
        items: cart?.lines.map { $0.analyticsItem() } ?? []
    )
}

/// The UPI handshake the page waits for around a UPI app's launch: `state` is `launching`, then `launched` or `failed`.
func goKwikUpiScript(_ state: String) -> String {
    let nonce = "\(Int(Date().timeIntervalSince1970 * 1_000_000))-\(Int.random(in: 0..<1_000_000))"
    let data = #"{\"action\":\"upiIntent\",\"state\":\"\#(state)\",\"newArch\":true,\"nonce\":\"\#(nonce)\"}"#
    return #"document.dispatchEvent(new MessageEvent('message', { data: "\#(data)" }));"#
}

/// Installs `window.Flutter`, the channel GoKwik's page posts to, at document start.
let goKwikBridgeScript = "window.Flutter={postMessage:function(m){webkit.messageHandlers.Flutter.postMessage(m)}};"

/// Hands the page's checkout events to the channel; run once, after the first page has loaded.
let goKwikListenerScript = """
(function checkGoKwikSdk() {
  if (typeof gokwikSdk !== 'undefined' && typeof gokwikSdk.on === 'function') {
    gokwikSdk.on('modal_closed', d => Flutter.postMessage(JSON.stringify({ type: 'modal_closed', data: d })));
    gokwikSdk.on('orderSuccess', d => Flutter.postMessage(JSON.stringify({ type: 'orderSuccess', data: d })));
    gokwikSdk.on('openInBrowserTab', d => Flutter.postMessage(JSON.stringify({ type: 'openInBrowserTab', data: d })));
  } else { setTimeout(checkGoKwikSdk, 500); }
})();
document.addEventListener("gk-checkout-disable", e => Flutter.postMessage(JSON.stringify({ type: 'gk-checkout-disable', data: e })));
window.addEventListener('message', e => { if (e.data && e.data.type === "gokwik_events") Flutter.postMessage(JSON.stringify({ type: 'gokwik_events', data: e?.data?.data })); });
window.addEventListener("gokwikLoaded", e => Flutter.postMessage(JSON.stringify({ type: 'gokwikLoaded', data: e })));
"""
