import ArgonUI
import Observation
import os
import SafariServices
import SwiftUI

private let appLog = Logger(subsystem: "app.storefront", category: "AppGraph")

/// A screen pushed onto a tab's stack.
enum Destination: Hashable {
    case product(String)
    case collection(String)
    case search(String)
    case order(String)
    /// The customer's orders.
    case orders
    /// The return and exchange flow of the order with this id.
    case `return`(String)
    case profile
    case addresses
    /// The shop policy with this handle: `privacy-policy`, `terms-of-service`, `refund-policy`, `shipping-policy`, ...
    case policy(String)
    /// The ArgonUI gallery (linked from Account in debug builds only).
    case components

    /// The screen's short, stable name for analytics: the first part of its route on Android (`product/{handle}` is "product").
    var screenName: String {
        switch self {
        case .product: return "product"
        case .collection: return "collection"
        case .search: return "search"
        case .order: return "order"
        case .orders: return "orders"
        case .return: return "return"
        case .profile: return "profile"
        case .addresses: return "addresses"
        case .policy: return "policy"
        case .components: return "components"
        }
    }
}

/// Analytics' `screen_view`, once each time the screen comes into view: when it opens, when its tab is chosen, and when
/// a screen pushed over it is closed. A redraw, or its tab tapped again, is not another view.
private struct ScreenTracker: ViewModifier {
    let name: String
    // in view since the last onDisappear: SwiftUI doesn't promise one onAppear per appearance
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if shown { return }
                shown = true
                AppGraph.analytics.track(.screenView(name))
            }
            .onDisappear { shown = false }
    }
}

extension View {
    /// Reports this screen to analytics as `name` each time it is shown: put it where a tab or a destination is declared.
    func trackScreen(_ name: String) -> some View {
        modifier(ScreenTracker(name: name))
    }
}

/// One tab's navigation: its stack, and the web page shown over it.
@MainActor
@Observable
final class Router {
    var path: [Destination] = []
    var web: URL? = nil

    /// Opens `route` in the app, or in Safari for `.web`.
    func open(_ route: Route) {
        switch route {
        case let .product(handle): path.append(.product(handle))
        case let .collection(handle): path.append(.collection(handle))
        case let .search(query): path.append(.search(query))
        case let .policy(handle): path.append(.policy(handle))
        case let .web(link):
            // SFSafariViewController takes only http(s) (anything else would crash it): nothing to open otherwise
            guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            web = url
        }
    }
}

/// A tab: its own stack and Router, which the screens inside read from the environment.
@MainActor
struct TabStack<Root: View>: View {
    let root: Root
    @State private var router = Router()

    var body: some View {
        NavigationStack(path: $router.path) {
            root.navigationDestination(for: Destination.self) { destination in
                Group {
                    switch destination {
                    case let .product(handle): ProductView(handle: handle)
                    case let .collection(handle): CollectionView(handle: handle)
                    case let .search(query): SearchView(initial: query)
                    case let .order(id): OrderView(id: id)
                    case .orders: OrdersView()
                    case let .return(orderId): ReturnView(orderId: orderId)
                    case .profile: ProfileView()
                    case .addresses: AddressesView()
                    case let .policy(handle): PolicyView(handle: handle)
                    case .components: ArgonGallery()
                    }
                }
                .trackScreen(destination.screenName)
            }
        }
        .sheet(isPresented: Binding(get: { router.web != nil }, set: { if !$0 { router.web = nil } })) {
            if let url = router.web { SafariView(url: url).ignoresSafeArea() }
        }
        .environment(router)
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// The app's five tabs.
enum AppTab: String, CaseIterable {
    case home, shop, wishlist, cart, account
}

/// The tab on show (`AppGraph.tabs`): a screen sets `selected` to send the shopper to another tab ("See all" to Shop,
/// "Sign in" to Account).
@MainActor
@Observable
final class TabState {
    var selected = AppTab.home
}

/// A short message shown over the tabs for a few seconds (`AppGraph.toast`): iOS's stand-in for Android's snackbar.
@MainActor
@Observable
final class ToastState {
    private(set) var message: String? = nil
    @ObservationIgnored private var hiding: Task<Void, Never>? = nil

    /// How tall the product page's sticky add-to-cart bar is, for each bar on screen (by the bar's own id; a bar takes
    /// itself out when its page is covered or left): the toast shows above the bar, not over its button.
    var stickyBars: [UUID: CGFloat] = [:]

    /// Shows `message`, in place of the one on show if any.
    func show(_ message: String) {
        self.message = message
        // it comes and goes without taking focus: VoiceOver reads it out
        UIAccessibility.post(notification: .announcement, argument: message)
        hiding?.cancel()
        hiding = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { self.message = nil }
        }
    }
}

@MainActor
private struct ToastView: View {
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack {
            if let message = AppGraph.toast.message {
                Text(message)
                    .font(theme.type.label)
                    .foregroundStyle(theme.colors.paper)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, theme.spacing.l)
                    .padding(.vertical, theme.spacing.m)
                    .background(theme.colors.ink, in: RoundedRectangle(cornerRadius: theme.radius.m))
                    .padding(.horizontal, theme.spacing.l)
                    // above the tab bar, and on a product page above its sticky add-to-cart bar too
                    .padding(.bottom, 64 + (AppGraph.toast.stickyBars.values.max() ?? 0))
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: AppGraph.toast.message)
        .allowsHitTesting(false)
    }
}

@MainActor
struct Tabs: View {
    var body: some View {
        // the Cart tab shows how many items are in the cart (no badge at 0)
        let items = [
            ArgonBottomBarItem(id: AppTab.home.rawValue, title: "Home", icon: .home),
            ArgonBottomBarItem(id: AppTab.shop.rawValue, title: "Shop", icon: .grid),
            ArgonBottomBarItem(id: AppTab.wishlist.rawValue, title: "Wishlist", icon: .heart),
            ArgonBottomBarItem(id: AppTab.cart.rawValue, title: "Cart", icon: .bag, badge: AppGraph.cart.cart?.totalQuantity),
            ArgonBottomBarItem(id: AppTab.account.rawValue, title: "Account", icon: .person),
        ]
        ArgonBottomBar(
            items: items,
            selectedId: AppGraph.tabs.selected.rawValue,
            onSelect: { id in
                if let tab = AppTab(rawValue: id) { AppGraph.tabs.selected = tab }
            }
        ) { item in
            Group {
                // each root reports itself from inside its stack: a screen pushed over it hides it, and closing that shows it again
                switch AppTab(rawValue: item.id) ?? .home {
                case .home: TabStack(root: HomeView().trackScreen("home"))
                case .shop: TabStack(root: ShopView().trackScreen("shop"))
                case .wishlist: TabStack(root: WishlistView().trackScreen("wishlist"))
                case .cart: TabStack(root: CartView().trackScreen("cart"))
                case .account: TabStack(root: AccountView().trackScreen("account"))
                }
            }
            // The bar tints itself with the theme's accent; the screens that still draw native controls keep the tint
            // they had (the brand colour, else the system's).
            .tint(brandColor(AppGraph.brand.value?.accent) ?? .accentColor)
        }
        .overlay(alignment: .bottom) { ToastView() }
        // the Cart tab's badge needs the stored cart before that tab is ever opened
        .task {
            do {
                try await AppGraph.cart.load()
            } catch {
                appLog.warning("cart load failed: \(error.localizedDescription)")
            }
        }
        // the stored session, so the Account tab opens signed in
        .task { await AppGraph.auth.load() }
    }
}

/// Shown instead of the tabs when the app can't reach the store.
@MainActor
struct SetupView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Setup needed").font(.title2)
            Text(verbatim: "STOREFRONT_TOKEN is empty. Set it in ios/Config.xcconfig (see README).")
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
