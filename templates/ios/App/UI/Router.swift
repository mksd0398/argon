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
    /// An online store page (`page/<handle>`), drawn in the app.
    case page(String)
    /// A custom page from the store's `app_screen` metaobjects (`screen/<handle>`).
    case screen(String)
    /// The root screen of a tab the bar leaves out (`shop`, `wishlist`, `cart`, `account`), pushed instead.
    case tabRoot(String)
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
        case .page: return "page"
        case .screen: return "screen"
        case let .tabRoot(id): return id
        case .components: return "components"
        }
    }
}

/// Analytics' `screen_view`, once each time the screen comes into view: when it opens, when its tab is chosen, and when
/// a screen pushed over it is closed. A redraw, or its tab tapped again, is not another view.
private struct ScreenTracker: ViewModifier {
    let name: String?
    // in view since the last onDisappear: SwiftUI doesn't promise one onAppear per appearance
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !shown, let name = name else { return }
                shown = true
                AppGraph.analytics.track(.screenView(name))
            }
            .onDisappear { shown = false }
    }
}

extension View {
    /// Reports this screen to analytics as `name` each time it is shown: put it where a tab or a destination is declared.
    /// Nil reports nothing.
    func trackScreen(_ name: String?) -> some View {
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
        case let .page(handle): path.append(.page(handle))
        case let .screen(handle): path.append(.screen(handle))
        case let .tab(id): AppGraph.tabs.select(id)
        case let .web(link):
            // SFSafariViewController takes only http(s) (anything else would crash it): nothing to open otherwise
            guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            web = url
        }
    }
}

/// A tab: its own stack and Router, which the screens inside read from the environment. `id` is its `ShellTab.id`;
/// over its root (not the screens pushed on it) the settings' announcement strip shows until it is closed.
@MainActor
struct TabStack<Root: View>: View {
    let id: String
    let root: Root
    @State private var router = Router()

    var body: some View {
        VStack(spacing: 0) {
            if router.path.isEmpty, let announcement = AppGraph.announcement, !AppGraph.tabs.announcementClosed {
                AnnouncementBar(announcement: announcement, onOpen: { router.open($0) }) { AppGraph.tabs.announcementClosed = true }
            }
            stack
        }
        .onAppear { AppGraph.tabs.register(router, for: id) }
    }

    private var stack: some View {
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
                    case let .page(handle): PageView(handle: handle)
                    case let .screen(handle): CustomScreenView(handle: handle)
                    case let .tabRoot(id): TabRoot(id: id, tracks: false)
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

/// The app's built-in tabs, by their ids (the bar itself is `AppGraph.navigation.tabs`, which may add `search` and
/// `screen:<handle>` and leave any of these but home out).
enum AppTab: String, CaseIterable {
    case home, shop, wishlist, cart, account
}

/// The tab on show (`AppGraph.tabs`): a screen sets `selected`, or calls `select`, to send the shopper to another tab
/// ("See all" to Shop, "Sign in" to Account). A tab the bar leaves out is pushed onto the tab on show instead.
@MainActor
@Observable
final class TabState {
    /// The `ShellTab.id` on show.
    var selectedId = AppTab.home.rawValue
    /// The settings' announcement was closed: it stays away for the session.
    var announcementClosed = false
    /// The home's drawer (the settings' `navigation.drawer`) is open.
    var drawerOpen = false
    // each tab's Router (by tab id), and a route asked for before the tab on show had one (a notification's at launch)
    @ObservationIgnored private var routers: [String: Router] = [:]
    @ObservationIgnored private var pending: Route? = nil

    /// The built-in tab on show (home for a search or custom-page tab).
    var selected: AppTab {
        get { AppTab(rawValue: selectedId) ?? .home }
        set { select(newValue.rawValue) }
    }

    /// Goes to tab `id`: switches to it when it is in the bar; otherwise pushes its screen onto the tab on show, which
    /// then has a way back.
    func select(_ id: String) {
        if id == AppTab.home.rawValue || AppGraph.navigation.hasTab(id) {
            selectedId = id
            return
        }
        let router = routers[selectedId]
        if id == "search" {
            router?.path.append(.search(""))
        } else if id.hasPrefix("screen:") {
            router?.path.append(.screen(String(id.dropFirst("screen:".count))))
        } else if AppTab(rawValue: id) != nil {
            router?.path.append(.tabRoot(id))
        }
    }

    /// Opens `route` on the tab on show (a notification's link); before that tab is drawn, as soon as it is.
    func open(_ route: Route) {
        if let router = routers[selectedId] { router.open(route) } else { pending = route }
    }

    func register(_ router: Router, for id: String) {
        routers[id] = router
        if id == selectedId, let route = pending {
            pending = nil
            router.open(route)
        }
    }
}

/// A settings icon name (`Navigation.icons`) as the component library's icon.
func shellIcon(_ name: String) -> ArgonIconName {
    switch name {
    case "home": return .home
    case "grid": return .grid
    case "search": return .search
    case "heart": return .heart
    case "bag": return .bag
    case "person": return .person
    case "tag": return .tag
    case "menu": return .menu
    default: return .star
    }
}

/// The root screen of the tab `id`, reporting itself to analytics under its name.
@MainActor
struct TabRoot: View {
    let id: String
    /// Off where a pushed destination reports it already.
    var tracks = true

    var body: some View {
        Group {
            switch id {
            case "home": HomeView()
            case "shop": ShopView()
            case "wishlist": WishlistView()
            case "cart": CartView()
            case "account": AccountView()
            case "search": SearchView(initial: "")
            default: CustomScreenView(handle: id.hasPrefix("screen:") ? String(id.dropFirst("screen:".count)) : id)
            }
        }
        .trackScreen(tracks ? (id.hasPrefix("screen:") ? "screen" : id) : nil)
    }
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
        // The bar's tabs: the settings', else the built-in five. The Cart tab shows how many items are in the cart (no
        // badge at 0).
        let navigation = AppGraph.navigation
        let items = navigation.tabs.map { tab in
            ArgonBottomBarItem(id: tab.id, title: tab.title, icon: shellIcon(tab.icon), badge: tab.id == "cart" ? AppGraph.cart.cart?.totalQuantity : nil)
        }
        ArgonBottomBar(
            items: items,
            selectedId: AppGraph.tabs.selectedId,
            onSelect: { AppGraph.tabs.select($0) },
            showLabels: navigation.labels
        ) { item in
            // each root reports itself from inside its stack: a screen pushed over it hides it, and closing that shows it again
            TabStack(id: item.id, root: TabRoot(id: item.id))
                // The bar tints itself with the theme's accent; the screens that still draw native controls keep the tint
                // they had (the brand colour, else the system's).
                .tint(brandColor(AppGraph.brand.value?.accent) ?? .accentColor)
        }
        .overlay(alignment: .bottom) { ToastView() }
        // the settings' drawer, over the whole screen; the home's menu button opens it
        .overlay {
            if let menu = navigation.drawerMenu { HomeDrawer(menu: menu) }
        }
        // the one offer of notifications, after a first purchase (push only)
        .modifier(PushOffer())
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
