import ObjectiveC
import UIKit
import WebKit

/// Keeps the checkout sheet on checkout: a page of the store's own website (`isStorePage`) that it is about to show, a
/// link the shopper followed or a redirect (the password page, "Continue shopping" on the confirmation), is cancelled
/// and `leave` runs (it closes the sheet and opens the app's cart). Checkout Kit offers no hook for this, so its web
/// view's navigation delegate is wrapped: every other call goes on to it.
final class CheckoutGuard: NSObject, WKNavigationDelegate {
    private weak var inner: WKNavigationDelegate?
    private let isStorePage: (URL) -> Bool
    private let leave: () -> Void
    private var left = false

    init(inner: WKNavigationDelegate?, isStorePage: @escaping (URL) -> Bool, leave: @escaping () -> Void) {
        self.inner = inner
        self.isStorePage = isStorePage
        self.leave = leave
    }

    // what the guard doesn't handle itself goes to the kit's delegate
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (inner?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? { inner }

    private func stop(_ url: URL?) -> Bool {
        if left { return true }
        guard let url = url, isStorePage(url) else { return false }
        left = true
        leave()
        return true
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.targetFrame?.isMainFrame == true, stop(action.request.url) { return decisionHandler(.cancel) }
        if inner?.webView?(webView, decidePolicyFor: action, decisionHandler: decisionHandler) == nil { decisionHandler(.allow) }
    }

    // A redirect is caught by where it lands: its response
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, stop(response.response.url) { return decisionHandler(.cancel) }
        if inner?.webView?(webView, decidePolicyFor: response, decisionHandler: decisionHandler) == nil { decisionHandler(.allow) }
    }
}

private var guardKey: UInt8 = 0

/// Puts `CheckoutGuard` on the checkout sheet on screen: Checkout Kit's web view, found under the presented view
/// controllers. Nothing happens when there is none, or it is guarded already.
@MainActor
func guardCheckoutSheet(isStorePage: @escaping (URL) -> Bool, leave: @escaping () -> Void) {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    var presented = windows.compactMap(\.rootViewController)
    var views: [UIView] = []
    while let controller = presented.popLast() {
        views.append(controller.view)
        if let next = controller.presentedViewController { presented.append(next) }
    }
    guard let webView = views.lazy.compactMap({ $0.checkoutWebView() }).first,
          !(webView.navigationDelegate is CheckoutGuard) else { return }
    let guardian = CheckoutGuard(inner: webView.navigationDelegate, isStorePage: isStorePage, leave: leave)
    // the web view holds its navigation delegate weakly: the guard lives as long as the web view
    objc_setAssociatedObject(webView, &guardKey, guardian, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    webView.navigationDelegate = guardian
}

private extension UIView {
    /// The kit's checkout web view under this view, if there is one.
    func checkoutWebView() -> WKWebView? {
        if let web = self as? WKWebView, String(reflecting: type(of: web)).contains("ShopifyCheckoutSheetKit") { return web }
        for child in subviews { if let web = child.checkoutWebView() { return web } }
        return nil
    }
}
