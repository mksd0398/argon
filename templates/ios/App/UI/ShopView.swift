import ArgonUI
import SwiftUI

/// The `main-menu` tree; when the store has none, its first collections as a flat list.
@MainActor
private func loadMenu() async throws -> [MenuItem] {
    let brand = try await AppGraph.loadBrand()
    let api = AppGraph.storefront
    if let menu = try await api.menu("main-menu") {
        let items = Links.menu(menu.items, hosts: brand.hosts)
        if !items.isEmpty { return items }
    }
    return try await api.fallbackHome().map { MenuItem(title: $0.title, route: .collection($0.handle), children: []) }
}

/// The Shop tab: the store's menu as a list that expands in place, with search in the top bar.
@MainActor
struct ShopView: View {
    @Environment(Router.self) private var router
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Loader(load: loadMenu) { menu in
            if menu.isEmpty {
                Text("Nothing to show yet.").font(theme.type.body).foregroundStyle(theme.colors.muted)
            } else {
                ScrollView {
                    // not lazy: a menu is a handful of rows, and each keeps whether it is open while it scrolls away
                    VStack(spacing: 0) {
                        ForEach(menu.indices, id: \.self) { index in
                            MenuRow(item: menu[index], depth: 0) { router.open($0) }
                        }
                    }
                }
            }
        }
        .background(theme.colors.paper)
        .argonTopBar(title: "Shop", trailing: [ArgonTopBarAction(icon: .search, accessibilityLabel: "Search") { router.open(.search("")) }])
    }
}

/// A leaf opens its route. A parent expands (its own route, when it has one, becomes the first child "All ...").
@MainActor
private struct MenuRow: View {
    let item: MenuItem
    let depth: Int
    let onOpen: (Route) -> Void
    @State private var open = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let parent = !item.children.isEmpty
        VStack(spacing: 0) {
            Button {
                if parent { open.toggle() } else { onOpen(item.route) }
            } label: {
                HStack(spacing: theme.spacing.s) {
                    Text(item.title)
                        .font(theme.type.body)
                        .foregroundStyle(theme.colors.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if parent { ArgonIcon(name: open ? .chevronUp : .chevronDown, tint: theme.colors.muted) }
                }
                .padding(.leading, theme.spacing.l * CGFloat(depth + 1))
                .padding(.trailing, theme.spacing.l)
                .padding(.vertical, theme.spacing.m)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // the chevron is decoration: what a tap does is said with the title
            .accessibilityLabel(parent ? "\(item.title), \(open ? "Collapse" : "Expand")" : item.title)
            ArgonDivider()
            if parent && open {
                // AnyView: a row that contains rows needs a type that doesn't contain itself
                if opensSomething {
                    AnyView(MenuRow(item: MenuItem(title: "All \(item.title)", route: item.route, children: []), depth: depth + 1, onOpen: onOpen))
                }
                ForEach(item.children.indices, id: \.self) { index in
                    AnyView(MenuRow(item: item.children[index], depth: depth + 1, onOpen: onOpen))
                }
            }
        }
    }

    /// A header item (url "#") is a web placeholder without an http(s) URL and has nothing to open.
    private var opensSomething: Bool {
        if case let .web(url) = item.route { return url.hasPrefix("http") }
        return true
    }
}
