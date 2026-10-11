import ArgonUI
import Foundation
import os
import SwiftUI

// MARK: Logic

private let homeLog = Logger(subsystem: "app.storefront", category: "HomeScreen")

/// What the home screen shows for `template`: the sections of the store's `mobile_screen` "home" (`home` runs the
/// HomeScreen query) and its first collections (`fallback` runs FallbackHome), fetched side by side and put together by
/// `Sections.content` (each part is the store's own when it has it, else made from the collections). A store that
/// refuses the metaobject query with GraphQL errors (a token without metaobject access) counts as having no sections.
/// HTTP and response-shape failures of either query are rethrown: the screen shows an error with Retry instead of
/// keeping a degraded home.
@MainActor
func homeContent(
    _ template: HomeTemplate,
    _ brand: Brand,
    home: @escaping @MainActor () async throws -> [Metaobject],
    fallback: @escaping @MainActor () async throws -> [CollectionCard]
) async throws -> HomeContent {
    async let collections = fallback()
    var sections: [Section] = []
    do {
        sections = Sections.fromHome(try await home(), hosts: brand.hosts)
    } catch ArgonAPIError.graphql(let messages) {
        // GraphQL messages name fields and permissions, never a token: logged so a merchant can see why the home fell back
        homeLog.warning("home screen query refused, showing the store's collections: \(messages.joined(separator: "; "), privacy: .public)")
    }
    return Sections.content(template, brand, sections, try await collections)
}

// MARK: Views

@MainActor
private func loadHome() async throws -> HomeContent {
    let brand = try await AppGraph.loadBrand()
    let api = AppGraph.storefront
    return try await homeContent(
        AppGraph.homeTemplate,
        brand,
        home: { try await api.homeScreen("home") },
        fallback: { try await api.fallbackHome() }
    )
}

/// What a load of the home is for: the buyer (a company location's id, nil for retail) and the try.
private struct HomeLoad: Equatable {
    let buyer: String?
    let attempt: Int
}

/// The home tab: the top bar and the page of the store's `HomeTemplate` (`AppGraph.homeTemplate`).
@MainActor
struct HomeView: View {
    // The home's content and the buyer it was loaded for, kept in the view's state: coming back from a product doesn't
    // reload.
    // ponytail: no refresh until the app restarts or the buyer changes; add pull-to-refresh if merchants need live edits.
    @State private var loaded: (buyer: String?, content: HomeContent)? = nil
    @State private var error: String? = nil
    @State private var attempt = 0
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let template = AppGraph.homeTemplate
        let buyer = AppGraph.buyer.company?.locationId
        let onOpen: (Route) -> Void = { router.open($0) }
        VStack(spacing: 0) {
            if let content = loaded?.content {
                switch template {
                case .fashion: HomeFashion(content: content, onOpen: onOpen)
                case .beauty: HomeBeauty(content: content, onOpen: onOpen)
                case .grocery: HomeGrocery(content: content, onOpen: onOpen)
                case .b2b: HomeB2B(content: content, onOpen: onOpen)
                }
            } else if let error = error {
                ErrorView(message: error) { attempt += 1 }
            } else {
                ArgonSpinner()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.paper)
        .modifier(HomeTopBar(template: template, brand: AppGraph.brand.value) { router.open(.search("")) })
        // A load that failed offline or behind the lock screen runs again when the app is back, without a tap.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, error != nil { attempt += 1 }
        }
        // Loaded at first, on Retry, and again when the buyer changes: a company's catalogue has its own products and
        // prices. Until the new content is here the page keeps showing the old one.
        .task(id: HomeLoad(buyer: buyer, attempt: attempt)) {
            if let shown = loaded, shown.buyer == buyer { return }
            error = nil
            do {
                let content = try await loadHome()
                loaded = (buyer, content)
            } catch {
                // leaving the screen cancels the load; it runs again when the screen is shown
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

/// Each template's top bar: fashion centres the logo, beauty has it at the start, both with a search button; grocery and
/// B2B show a search field. The shop's name stands in for a missing logo.
private struct HomeTopBar: ViewModifier {
    let template: HomeTemplate
    let brand: Brand?
    let onSearch: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        let name = brand?.name ?? ""
        let logo = (brand?.logo?.url).flatMap { URL(string: $0) }
        let search = [ArgonTopBarAction(icon: .search, accessibilityLabel: "Search", action: onSearch)]
        switch template {
        case .fashion: content.argonTopBar(variant: .centeredLogo, title: name, logoUrl: logo, trailing: search)
        case .beauty: content.argonTopBar(title: name, logoUrl: logo, trailing: search)
        case .grocery: searchBar(content, "Search products")
        case .b2b: searchBar(content, "Search by name or SKU")
        }
    }

    /// The search field in place of the navigation bar, over the page.
    private func searchBar(_ content: Content, _ placeholder: String) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { SearchField(placeholder: placeholder, onSearch: onSearch) }
    }
}

/// A search field that isn't typed in: a tap anywhere on it opens the search screen (`onSearch`), which has the real one.
/// The field is looks only: it is one button, named by the `placeholder`. (The navigation bar's own search field can't be
/// covered by a button, so this one is drawn.)
@MainActor
private struct SearchField: View {
    let placeholder: String
    let onSearch: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Button(action: onSearch) {
            HStack(spacing: theme.spacing.s) {
                ArgonIcon(name: .search, size: 18, tint: theme.colors.muted)
                Text(placeholder).font(theme.type.body).foregroundStyle(theme.colors.muted).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.l)
            .frame(minHeight: 48)
            .background(theme.colors.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(theme.colors.border, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, theme.spacing.l)
        .padding(.top, theme.spacing.xs)
        .padding(.bottom, theme.spacing.s)
        // the page scrolls under the field, and under the status bar above it
        .background { theme.colors.paper.ignoresSafeArea(edges: .top) }
    }
}
