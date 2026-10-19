import ArgonUI
import SwiftUI
import UIKit

// The parts of the app shell the merchant's settings add (screens v2, "App shell"): the announcement strip and the
// home's drawer. The tab bar is in Router.swift, the home's top bar in HomeView.swift. The same on Android (ShellBars.kt).

/// The announcement strip over a tab root's top bar (its colour runs up under the status bar): one message at a time,
/// the next every `interval` seconds; a message with a link opens it (`Links.resolve`). `onClose` (shown when it is
/// dismissible) hides it for the session.
@MainActor
struct AnnouncementBar: View {
    let announcement: Announcement
    let onOpen: (Route) -> Void
    let onClose: () -> Void
    @State private var index = 0
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let messages = announcement.messages
        let message = messages[index % messages.count]
        let route = Links.resolve(message.link, hosts: AppGraph.brand.value?.hosts ?? [AppGraph.shopDomain])
        let ink = ArgonTheme.color(hex: announcement.color) ?? theme.colors.paper
        HStack(spacing: 0) {
            Text(message.text)
                .font(theme.type.label)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, theme.spacing.l)
                .padding(.vertical, theme.spacing.xs)
                .contentShape(Rectangle())
                .onTapGesture { if let route = route { onOpen(route) } }
                .accessibilityAddTraits(route != nil ? .isButton : [])
                .id(index)
                .transition(.opacity)
            if announcement.dismissible {
                Button(action: onClose) {
                    ArgonIcon(name: .close, size: 14, tint: ink).frame(width: 44, height: 36)
                }
                .accessibilityLabel("Close")
            }
        }
        .frame(minHeight: 36)
        .background { (ArgonTheme.color(hex: announcement.background) ?? theme.colors.ink).ignoresSafeArea(edges: .top) }
        .animation(.easeInOut(duration: 0.3), value: index)
        .task(id: messages.count) {
            guard messages.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(announcement.interval) * 1_000_000_000)
                if !Task.isCancelled { index = (index + 1) % messages.count }
            }
        }
    }
}

/// The drawer of the Shopify menu `menu` (`navigation.drawer`), over the whole app while `AppGraph.tabs.drawerOpen`
/// (the home's menu button opens it). The menu's items open their routes on the home tab; a parent lists its children
/// under it. A menu that can't be loaded leaves the drawer empty.
@MainActor
struct HomeDrawer: View {
    let menu: String
    @State private var items: [MenuItem] = []
    @Environment(\.argonTheme) private var theme

    var body: some View {
        ArgonSideMenu(
            isOpen: AppGraph.tabs.drawerOpen,
            onDismiss: { AppGraph.tabs.drawerOpen = false },
            header: {
                Text(AppGraph.brand.value?.name ?? "")
                    .font(theme.type.headline)
                    .foregroundStyle(theme.colors.ink)
                    .padding(theme.spacing.l)
            },
            footer: { EmptyView() },
            content: {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    ArgonSideMenuItem(title: item.title) { select(item) }
                    ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                        ArgonSideMenuItem(title: child.title) { select(child) }.padding(.leading, theme.spacing.l)
                    }
                }
            }
        )
        .task {
            guard let brand = try? await AppGraph.loadBrand(), let found = try? await AppGraph.storefront.menu(menu) else { return }
            items = Links.menu(found.items, hosts: brand.hosts)
        }
    }

    private func select(_ item: MenuItem) {
        AppGraph.tabs.drawerOpen = false
        // a header item (url "#") is a web placeholder without an http(s) URL and has nothing to open
        if case let .web(url) = item.route, !url.hasPrefix("http") { return }
        AppGraph.tabs.open(item.route)
    }
}

extension Appearance {
    /// The colour scheme the app is drawn in; nil: the device's.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The settings' bar colours (`navigation.topBar.background` / `foreground`, `navigation.tabBar`) on UIKit's bars, so
/// every screen's top bar has them, the ones that don't use `argonTopBar` too: the background, the title, the back
/// button; the tab bar's background and its tabs' icons and titles. Called once, before the first bar is drawn. Without
/// colours the bars are left as the system draws them; with some, clear at the scroll edge where no background is given.
@MainActor
func applyBarColors(_ navigation: Navigation) {
    func color(_ hex: String?) -> UIColor? {
        ArgonTheme.rgb(hex: hex).map { UIColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
    }
    let background = color(navigation.topBarBackground), foreground = color(navigation.topBarForeground)
    if background != nil || foreground != nil {
        func bar(edge: Bool) -> UINavigationBarAppearance {
            let bar = UINavigationBarAppearance()
            if let background = background {
                bar.configureWithOpaqueBackground()
                bar.backgroundColor = background
            } else if edge {
                bar.configureWithTransparentBackground()
            } else {
                bar.configureWithDefaultBackground()
            }
            if let foreground = foreground {
                bar.titleTextAttributes = [.foregroundColor: foreground]
                bar.largeTitleTextAttributes = [.foregroundColor: foreground]
                bar.backButtonAppearance.normal.titleTextAttributes = [.foregroundColor: foreground]
                // drawn in its own colour: the stacks' tint (the accent) would colour a template image
                let back = UIImage(systemName: "chevron.backward")?.withTintColor(foreground, renderingMode: .alwaysOriginal)
                bar.setBackIndicatorImage(back, transitionMaskImage: back)
            }
            return bar
        }
        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = bar(edge: false)
        proxy.compactAppearance = bar(edge: false)
        proxy.scrollEdgeAppearance = bar(edge: true)
    }
    let tabBackground = color(navigation.tabBarBackground), active = color(navigation.tabBarActive), inactive = color(navigation.tabBarInactive)
    if tabBackground != nil || active != nil || inactive != nil {
        func bar(edge: Bool) -> UITabBarAppearance {
            let bar = UITabBarAppearance()
            if let background = tabBackground {
                bar.configureWithOpaqueBackground()
                bar.backgroundColor = background
            } else if edge {
                bar.configureWithTransparentBackground()
            } else {
                bar.configureWithDefaultBackground()
            }
            for item in [bar.stackedLayoutAppearance, bar.inlineLayoutAppearance, bar.compactInlineLayoutAppearance] {
                if let inactive = inactive {
                    item.normal.iconColor = inactive
                    item.normal.titleTextAttributes = [.foregroundColor: inactive]
                }
                if let active = active {
                    item.selected.iconColor = active
                    item.selected.titleTextAttributes = [.foregroundColor: active]
                }
            }
            return bar
        }
        let proxy = UITabBar.appearance()
        proxy.standardAppearance = bar(edge: false)
        proxy.scrollEdgeAppearance = bar(edge: true)
        if let inactive = inactive { proxy.unselectedItemTintColor = inactive }
    }
}
