import ArgonUI
import SwiftUI
import UIKit
import WebKit

// `custom`: the merchant's HTML. `native` with `nodes` (Krypton's compiled tree) is drawn with the app's own
// components; `web`, or `native` without nodes, is the whole html in a web view sized to its content.

/// `custom`.
@MainActor
struct CustomSection: View {
    let settings: SectionSettings
    let scope: SectionScope

    var body: some View {
        let nodes = settings.values["nodes"]?.array ?? []
        if settings.choice("render", ["native", "web"], "web") == "native" && !nodes.isEmpty {
            CustomNodes(nodes: CustomNode.decode(settings.values["nodes"]), scope: scope)
        } else if let html = scope.liquid(settings.text("html")) {
            WebSection(html: html, height: settings.number("height", 0, 0...2000), scope: scope)
        }
    }
}

// MARK: Native

/// The nodes one under the other: Liquid is evaluated in each text, label and link.
@MainActor
private struct CustomNodes: View {
    let nodes: [CustomNode]
    let scope: SectionScope
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in
                view(node)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // a link in a paragraph or a list opens through the app's links, never the system's handler
        .environment(\.openURL, OpenURLAction { url in
            scope.follow(url.absoluteString)
            return .handled
        })
    }

    @ViewBuilder
    private func view(_ node: CustomNode) -> some View {
        let gutter = theme.spacing.l
        switch node {
        case let .heading(level, text):
            if let text = scope.liquid(text) {
                Text(text)
                    .font(level == 1 ? theme.type.display : level == 2 ? theme.type.title : theme.type.headline)
                    .foregroundStyle(theme.colors.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, gutter)
            }
        case let .paragraph(runs):
            Text(attributed(runs)).font(theme.type.body).foregroundStyle(theme.colors.ink).padding(.horizontal, gutter)
        case let .list(ordered, items):
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, runs in
                    HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s) {
                        Text(ordered ? "\(index + 1)." : "•").font(theme.type.body).foregroundStyle(theme.colors.muted)
                        Text(attributed(runs)).font(theme.type.body).foregroundStyle(theme.colors.ink)
                    }
                }
            }
            .padding(.horizontal, gutter)
        case let .image(url, alt, link):
            let route = scope.route(link)
            AsyncImage(url: scope.liquid(url).flatMap { URL(string: $0) }) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                theme.colors.border.opacity(0.5).aspectRatio(4 / 3, contentMode: .fit)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.m))
            .accessibilityLabel(scope.liquid(alt) ?? "")
            .contentShape(Rectangle())
            .onTapGesture { if let route = route { scope.open(route, nil) } }
            .padding(.horizontal, gutter)
        case let .button(label, link):
            if let label = scope.liquid(label) {
                ArgonButton(title: label) { scope.follow(link) }.padding(.horizontal, gutter)
            }
        case .divider:
            ArgonDivider().padding(.horizontal, gutter)
        case let .product(id):
            if let card = scope.product(id) {
                ProductCardView(card: card, style: .row) { scope.open(.product(card.handle), nil) }.padding(.horizontal, gutter)
            }
        case let .collection(id, limit):
            if let collection = scope.collection(id), !collection.products.isEmpty {
                VStack(alignment: .leading, spacing: theme.spacing.m) {
                    SectionHeader(title: collection.title, actionLabel: "See all") { scope.open(.collection(collection.handle), nil) }
                        .padding(.horizontal, gutter)
                    ProductCardRow(cards: Array(collection.products.prefix(limit))) { scope.open(.product($0.handle), nil) }
                }
            }
        }
    }

    /// The runs as one text: bold, italic, and links (followed through `openURL`).
    private func attributed(_ runs: [TextRun]) -> AttributedString {
        var text = AttributedString()
        for run in runs {
            var piece = AttributedString(Liquid.render(run.text, scope.context))
            var intent: InlinePresentationIntent = []
            if run.bold { intent.insert(.stronglyEmphasized) }
            if run.italic { intent.insert(.emphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if let link = scope.liquid(run.link).flatMap({ URL(string: $0) }) {
                piece.link = link
                piece.underlineStyle = .single
            }
            text += piece
        }
        return text
    }
}

// MARK: Web

/// The html in a page with the theme's colours as CSS variables (`--accent`, `--text`, `--background`), no margins and
/// images no wider than the page. Same document on Android.
func customDocument(_ html: String, accent: String, text: String, background: String) -> String {
    """
    <!doctype html><html><head><meta charset="utf-8">\
    <meta name="viewport" content="width=device-width, initial-scale=1">\
    <style>:root{--accent:\(accent);--text:\(text);--background:\(background)}\
    body{margin:0;padding:0 16px;font-family:"Hanken Grotesk",-apple-system,sans-serif;color:var(--text);background:transparent}\
    img{max-width:100%;height:auto}a{color:var(--accent)}</style></head><body>\(html)</body></html>
    """
}

/// The html in a web view: `height` points tall when above 0, else as tall as its content (measured in the page, again
/// on every resize; 1 to 5000). A tapped link goes through `Links.resolve` instead: an app route opens in the app, a
/// web page in the browser, `mailto:`, `tel:` and `sms:` in their apps; the web view itself never leaves the html.
@MainActor
private struct WebSection: View {
    let html: String
    let height: Double
    let scope: SectionScope
    @State private var measured: CGFloat = 1
    @Environment(\.colorScheme) private var scheme
    @Environment(\.argonTheme) private var theme

    var body: some View {
        // the theme's colours (the merchant's background and text, not Argon's own), as Android's ArgonTheme.colors
        let dark = scheme == .dark
        let document = customDocument(
            html, accent: theme.look.hex("accent", dark: dark) ?? "#000000", text: theme.look.hex("text", dark: dark) ?? "#000000",
            background: theme.look.hex("background", dark: dark) ?? "#FFFFFF"
        )
        HtmlWebView(document: document, baseURL: URL(string: "https://\(AppGraph.shopDomain)/"), onHeight: { measured = $0 }, onLink: open)
            .frame(height: height > 0 ? CGFloat(height) : measured)
    }

    private func open(_ url: URL) {
        if let route = Links.resolve(url.absoluteString, hosts: AppGraph.brand.value?.hosts ?? [AppGraph.shopDomain]) {
            scope.open(route, nil)
        } else if let scheme = url.scheme?.lowercased(), ["mailto", "tel", "sms"].contains(scheme) {
            UIApplication.shared.open(url)
        }
    }
}

// the page reports its height to the app: when loaded, and whenever it changes size
private let measureScript = """
(function(){function post(){window.webkit.messageHandlers.argonHeight.postMessage(document.documentElement.scrollHeight)}
window.addEventListener('load',post);window.addEventListener('resize',post);
if(window.ResizeObserver){new ResizeObserver(post).observe(document.body)}post();})();
"""

@MainActor
private struct HtmlWebView: UIViewRepresentable {
    let document: String
    let baseURL: URL?
    let onHeight: (CGFloat) -> Void
    let onLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "argonHeight")
        configuration.userContentController.addUserScript(
            WKUserScript(source: measureScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.backgroundColor = .clear
        context.coordinator.load(document, in: web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loaded != document { context.coordinator.load(document, in: web) }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "argonHeight")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: HtmlWebView
        var loaded: String? = nil
        // The one navigation the web view makes itself: the html's own load (at the base URL). After it, nothing moves
        // the main frame: a tapped link goes to the app (`onLink`), anything else (a script's redirect, a form) is dropped.
        private var initialLoad = false
        private var height: CGFloat = 0

        init(_ parent: HtmlWebView) {
            self.parent = parent
        }

        func load(_ document: String, in web: WKWebView) {
            loaded = document
            initialLoad = true
            web.loadHTMLString(document, baseURL: parent.baseURL)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            // a page reports what it likes: only a real height, within reason, and only when it changed
            guard let value = (message.body as? NSNumber)?.doubleValue, value.isFinite else { return }
            let measured = CGFloat(min(max(value.rounded(.up), 1), 5000))
            if measured == height { return }
            height = measured
            parent.onHeight(measured)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // frames inside the page (an embedded video) load as they like; never the page itself
            if let frame = action.targetFrame, !frame.isMainFrame {
                decisionHandler(.allow)
                return
            }
            let own = parent.baseURL?.absoluteString ?? "about:blank"
            if initialLoad && action.navigationType == .other && action.request.url?.absoluteString == own {
                initialLoad = false
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated, let url = action.request.url { parent.onLink(url) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            initialLoad = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            initialLoad = false
        }

        // a link that opens a new window (target="_blank"); a script's window.open is dropped
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for action: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if action.navigationType == .linkActivated, let url = action.request.url { parent.onLink(url) }
            return nil
        }
    }
}
