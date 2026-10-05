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
                switch destination {
                case let .product(handle): ProductView(handle: handle)
                case let .collection(handle): CollectionView(handle: handle)
                case let .search(query): SearchView(initial: query)
                case .order: EmptyView() // Task 13: the order screen
                }
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

@MainActor
struct Tabs: View {
    var body: some View {
        TabView {
            TabStack(root: HomeView()).tabItem { Label("Home", systemImage: "house") }
            TabStack(root: ShopView()).tabItem { Label("Shop", systemImage: "list.bullet") }
            TabStack(root: WishlistView()).tabItem { Label("Wishlist", systemImage: "heart") }
            // the Cart tab shows how many items are in the cart (no badge at 0)
            TabStack(root: CartView()).tabItem { Label("Cart", systemImage: "cart") }
                .badge(AppGraph.cart.cart?.totalQuantity ?? 0)
            TabStack(root: Text("Account").navigationTitle("Account")).tabItem { Label("Account", systemImage: "person") }
        }
        // the Cart tab's badge needs the stored cart before that tab is ever opened
        .task {
            do {
                try await AppGraph.cart.load()
            } catch {
                appLog.warning("cart load failed: \(error.localizedDescription)")
            }
        }
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
