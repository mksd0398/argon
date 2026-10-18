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

/// What the home shows: the store's `app_screen` "home" when it has sections to draw (screens v2), else the page of
/// its `HomeTemplate`, exactly as before.
private enum HomePage {
    case sections(LoadedScreen)
    case template(HomeContent)
}

@MainActor
private func loadHome() async throws -> HomePage {
    let brand = try await AppGraph.loadBrand()
    let api = AppGraph.storefront
    // Both asked for at once (async let), not one after the other: the v1 page is loading while the app_screen is asked
    // for. A store with sections gets them as soon as they are here (the v1 load is then cancelled); one without gets
    // its v1 page once both have answered, so the wait is the slower of the two, never their sum.
    async let screen = loadScreen("home")
    async let content = homeContent(
        AppGraph.homeTemplate,
        brand,
        home: { try await api.homeScreen("home") },
        fallback: { try await api.fallbackHome() }
    )
    if let screen = await screen, !screen.template.content.isEmpty { return .sections(screen) }
    return .template(try await content)
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
    @State private var loaded: (buyer: String?, page: HomePage)? = nil
    @State private var error: String? = nil
    @State private var attempt = 0
    // How solid the fashion home's bar is: its page sets it as the hero scrolls. Only the bar reads it, so only the bar
    // is redrawn. Solid until there is a hero under it (while the home loads, or fails).
    @State private var barSolid = 1.0
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let template = AppGraph.homeTemplate
        let buyer = AppGraph.buyer.company?.locationId
        let onOpen: (Route) -> Void = { router.open($0) }
        let navigation = AppGraph.navigation
        let sectionsShown: Bool = {
            if case .sections? = loaded?.page { return true }
            return false
        }()
        let inCart = AppGraph.cart.cart?.totalQuantity ?? 0
        VStack(spacing: 0) {
            if case let .sections(screen)? = loaded?.page {
                if navigation.transparentOnHome {
                    SectionsUnderBar(screen: screen, solid: $barSolid)
                } else {
                    ScrollView {
                        SectionList(sections: screen.template.content, screen: screen, context: screen.context())
                            .padding(.top, theme.spacing.s)
                            .padding(.bottom, theme.spacing.xl)
                    }
                }
            } else if case let .template(content)? = loaded?.page {
                switch template {
                case .fashion: HomeFashion(content: content, onOpen: onOpen, solid: $barSolid)
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
        // the store's own home lies under the bar with transparentOnHome; the fashion page always does
        .modifier(HomeTopBar(
            template: template,
            brand: AppGraph.brand.value,
            overlay: sectionsShown ? navigation.transparentOnHome : template == .fashion,
            solid: $barSolid,
            onSearch: { router.open(.search("")) },
            onMenu: navigation.drawerMenu == nil ? nil : { AppGraph.tabs.drawerOpen = true },
            // a bar without the cart tab has the cart behind a bag button here
            onCart: navigation.hasTab("cart") ? nil : { AppGraph.tabs.select("cart") },
            cartCount: inCart
        ))
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
                let page = try await loadHome()
                loaded = (buyer, page)
            } catch {
                // leaving the screen cancels the load; it runs again when the screen is shown
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

/// The home's top bar. Each template has its own: fashion centres the logo over its hero (`overlay`: clear at `solid` 0,
/// the normal bar at 1), beauty has it at the start, both with a search button; grocery and B2B show a search field. The
/// settings' `topBar.style` replaces it (`standard`, `centered_logo`, `search`) where the page isn't laid under it. The
/// shop's name stands in for a missing logo. `onMenu` (the settings' drawer) adds a menu button, `onCart` (a bar without
/// the cart tab) a bag button.
private struct HomeTopBar: ViewModifier {
    let template: HomeTemplate
    let brand: Brand?
    let overlay: Bool
    @Binding var solid: Double
    let onSearch: () -> Void
    var onMenu: (() -> Void)? = nil
    var onCart: (() -> Void)? = nil
    var cartCount = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        let name = brand?.name ?? ""
        let logo = (brand?.logo?.url).flatMap { URL(string: $0) }
        let leading = onMenu.map { [ArgonTopBarAction(icon: .menu, accessibilityLabel: "Menu", action: $0)] } ?? []
        let cart = onCart.map { [ArgonTopBarAction(icon: .bag, accessibilityLabel: "Cart", badge: cartCount > 0 ? cartCount : nil, action: $0)] } ?? []
        let trailing = [ArgonTopBarAction(icon: .search, accessibilityLabel: "Search", action: onSearch)] + cart
        switch overlay ? "overlay" : AppGraph.navigation.topBarStyle ?? Self.style(template) {
        case "overlay": content.argonTopBar(variant: .overlay, title: name, logoUrl: logo, leading: leading, trailing: trailing, solid: solid)
        case "centered_logo": content.argonTopBar(variant: .centeredLogo, title: name, logoUrl: logo, leading: leading, trailing: trailing)
        case "search": searchBar(content, template == .b2b ? "Search by name or SKU" : "Search products", leading, cart)
        default: content.argonTopBar(title: name, logoUrl: logo, leading: leading, trailing: trailing)
        }
    }

    /// The template's own bar.
    private static func style(_ template: HomeTemplate) -> String {
        switch template {
        case .fashion: return "overlay"
        case .beauty: return "standard"
        case .grocery, .b2b: return "search"
        }
    }

    /// The search field in place of the navigation bar, over the page.
    private func searchBar(_ content: Content, _ placeholder: String, _ leading: [ArgonTopBarAction], _ trailing: [ArgonTopBarAction]) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                SearchField(placeholder: placeholder, onSearch: onSearch, leading: leading, trailing: trailing)
            }
    }
}

/// A search field that isn't typed in: a tap anywhere on it opens the search screen (`onSearch`), which has the real one.
/// The field is looks only: it is one button, named by the `placeholder`. (The navigation bar's own search field can't be
/// covered by a button, so this one is drawn.) `leading` and `trailing` are icon buttons beside it.
@MainActor
private struct SearchField: View {
    let placeholder: String
    let onSearch: () -> Void
    var leading: [ArgonTopBarAction] = []
    var trailing: [ArgonTopBarAction] = []
    @Environment(\.argonTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            ForEach(Array(leading.enumerated()), id: \.offset) { _, action in button(action) }
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
            ForEach(Array(trailing.enumerated()), id: \.offset) { _, action in button(action) }
        }
        .padding(.horizontal, theme.spacing.l)
        .padding(.top, theme.spacing.xs)
        .padding(.bottom, theme.spacing.s)
        // the page scrolls under the field, and under the status bar above it
        .background { theme.colors.paper.ignoresSafeArea(edges: .top) }
    }

    private func button(_ action: ArgonTopBarAction) -> some View {
        Button(action: action.action) {
            ArgonIcon(name: action.icon, tint: theme.colors.ink)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if let badge = action.badge { ArgonBadge(count: badge) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.accessibilityLabel)
    }
}

/// The store's own home with the settings' `transparentOnHome`: from the top edge of the screen, its bar lying over the
/// first section, clear while that section is in view and solid once it has scrolled under the bar (`heroSolid`, as the
/// fashion page's hero).
@MainActor
private struct SectionsUnderBar: View {
    let screen: LoadedScreen
    @Binding var solid: Double
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let sections = screen.template.content
        let context = screen.context()
        GeometryReader { proxy in
            // the bar with the status bar: what the page keeps clear of at its top
            let barHeight = proxy.safeAreaInsets.top
            ScrollView {
                VStack(spacing: theme.spacing.xl) {
                    SectionList(sections: Array(sections.prefix(1)), screen: screen, context: context)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            let now = heroSolid(scrolled: -frame.minY, heroHeight: frame.height, barHeight: barHeight)
                            if now != solid { solid = now }
                        }
                    SectionList(sections: Array(sections.dropFirst()), screen: screen, context: context)
                }
                .padding(.bottom, theme.spacing.xl)
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}
