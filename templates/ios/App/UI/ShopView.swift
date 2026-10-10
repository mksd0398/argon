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

@MainActor
struct ShopView: View {
    @Environment(Router.self) private var router

    var body: some View {
        Loader(load: loadMenu) { menu in
            if menu.isEmpty {
                Text("Nothing to show yet.")
            } else {
                List {
                    ForEach(menu.indices, id: \.self) { index in
                        MenuRow(item: menu[index])
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Shop")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.open(.search("")) } label: { Label("Search", systemImage: "magnifyingglass") }
            }
        }
    }
}

/// A leaf opens its route. A parent expands (its own route, when it has one, becomes the first child "All ...").
@MainActor
private struct MenuRow: View {
    let item: MenuItem
    @State private var open = false
    @Environment(Router.self) private var router

    var body: some View {
        if item.children.isEmpty {
            Button(item.title) { router.open(item.route) }
                .foregroundStyle(.primary)
        } else {
            DisclosureGroup(item.title, isExpanded: $open) {
                if opensSomething {
                    // AnyView: a row that contains rows needs a type that doesn't contain itself
                    AnyView(MenuRow(item: MenuItem(title: "All \(item.title)", route: item.route, children: [])))
                }
                ForEach(item.children.indices, id: \.self) { index in
                    AnyView(MenuRow(item: item.children[index]))
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
