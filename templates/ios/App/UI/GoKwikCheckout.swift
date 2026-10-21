import ArgonUI
import SwiftUI
import UIKit
import WebKit

/// GoKwik's checkout page at `url`, full screen, with a spinner until it is ready. What the page says comes to `onEvent`
/// (only while it is on a GoKwik page); a link to another app (UPI, phone, mail, WhatsApp) opens that app. The page's
/// cookies and storage are its own and go with it: nothing of one checkout is left for the next.
@MainActor
struct GoKwikCheckoutView: View {
    let url: URL
    let onEvent: (GoKwikEvent) -> Void
    @State private var loading = true
    @Environment(\.argonTheme) private var theme

    var body: some View {
        GoKwikWebView(url: url) { event in
            if case .loaded = event { loading = false } else { onEvent(event) }
        } pageLoaded: {
            // ponytail: a page that never says `gokwikLoaded` (it can fire before the listener is in) would keep the
            // spinner up: it goes 3 s after the first page load at the latest.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { loading = false }
        }
        .overlay {
            if loading {
                ArgonSpinner(size: .l).frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.colors.paper)
            }
        }
        .background(theme.colors.paper)
    }
}

private struct GoKwikWebView: UIViewRepresentable {
    let url: URL
    let onEvent: (GoKwikEvent) -> Void
    let pageLoaded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent, pageLoaded: pageLoaded) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // in memory only: the checkout's cookies and storage end with the view
        configuration.websiteDataStore = .nonPersistent()
        let content = configuration.userContentController
        content.addUserScript(WKUserScript(source: goKwikBridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // held weakly: the controller would otherwise keep the coordinator, and the web view, alive
        content.add(WeakMessageHandler(context.coordinator), name: "Flutter")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "Flutter")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let onEvent: (GoKwikEvent) -> Void
        private let pageLoaded: () -> Void
        private var listening = false

        init(onEvent: @escaping (GoKwikEvent) -> Void, pageLoaded: @escaping () -> Void) {
            self.onEvent = onEvent
            self.pageLoaded = pageLoaded
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard isGoKwikHost(message.webView?.url?.host), let text = message.body as? String,
                  let event = goKwikEvent(text) else { return }
            onEvent(event)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !listening else { return }
            listening = true
            webView.evaluateJavaScript(goKwikListenerScript)
            pageLoaded()
        }

        /// Checkout itself didn't load (offline): there is no page to close it from, so it closes with the reason.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // not a load this view cancelled itself (another app's link: WebKit's 102, "interrupted by policy change")
            let code = (error as NSError).code
            if !listening, code != NSURLErrorCancelled, code != 102 { onEvent(.failed(error.localizedDescription)) }
        }

        /// Web pages (checkout, a payment gateway) load in place; any other link is another app's, handed to the system.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = action.request.url, let scheme = url.scheme?.lowercased(),
                  !["http", "https", "about", "data", "blob", "javascript"].contains(scheme) else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            // the page waits for a UPI app's launch to be reported
            webView.evaluateJavaScript(goKwikUpiScript("launching"))
            UIApplication.shared.open(url) { [weak webView] opened in
                webView?.evaluateJavaScript(goKwikUpiScript(opened ? "launched" : "failed"))
            }
        }

        /// A page opening a new window (a gateway's pop-up) gets this one.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for action: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if action.targetFrame == nil { webView.load(action.request) }
            return nil
        }
    }
}

/// Passes messages to `target` without keeping it.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// The installed UPI apps, by GoKwik's names, for checkout's `upi_apps`.
@MainActor
func installedUpiApps() -> [String] {
    goKwikUpiApps.filter { app in URL(string: "\(app.scheme)://").map { UIApplication.shared.canOpenURL($0) } ?? false }.map { $0.name }
}
