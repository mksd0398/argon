import SwiftUI

public enum ArgonTopBarVariant: Sendable {
    /// Inline title, or the shop's logo at the start when one is given.
    case standard
    /// Large title that collapses on scroll.
    case largeTitle
    /// The shop's logo in the middle (the title while it loads or without one).
    case centeredLogo
    /// Inline title and the native search field, always on show under it.
    case search
}

/// An icon button in the top bar, with an optional count badge.
public struct ArgonTopBarAction {
    public let icon: ArgonIconName
    public let accessibilityLabel: String
    public let badge: Int?
    public let action: () -> Void

    public init(icon: ArgonIconName, accessibilityLabel: String, badge: Int? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.badge = badge
        self.action = action
    }
}

/// The native navigation bar of the enclosing `NavigationStack`, set up for one screen. Use `.argonTopBar(...)` on the
/// screen's content.
public struct ArgonTopBar: ViewModifier {
    let variant: ArgonTopBarVariant
    let title: String
    let logoUrl: URL?
    let leading: [ArgonTopBarAction]
    let trailing: [ArgonTopBarAction]
    let searchText: Binding<String>?
    let isSearching: Binding<Bool>?
    @Environment(\.argonTheme) var theme

    public func body(content: Content) -> some View {
        // with a logo, the logo sits at the start in place of the title (a home screen with its logo at the start)
        let logoAtStart = variant == .standard && logoUrl != nil
        content
            .navigationTitle(logoAtStart ? "" : title)
            .navigationBarTitleDisplayMode(variant == .largeTitle ? .large : .inline)
            .toolbar {
                if variant == .centeredLogo {
                    ToolbarItem(placement: .principal) { logo(.center) }
                }
                if !leading.isEmpty || logoAtStart {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        buttons(leading)
                        if logoAtStart { logo(.leading) }
                    }
                }
                if !trailing.isEmpty {
                    ToolbarItemGroup(placement: .topBarTrailing) { buttons(trailing) }
                }
            }
            .modifier(ArgonSearchable(text: variant == .search ? searchText : nil, isSearching: isSearching, prompt: title))
    }

    /// The logo, fitted into 160 x 28 points and held to `alignment` of that box; the title while it loads or without one.
    private func logo(_ alignment: Alignment) -> some View {
        AsyncImage(url: logoUrl) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Text(title).font(theme.type.headline).foregroundStyle(theme.colors.ink).lineLimit(1)
        }
        .frame(maxWidth: 160, maxHeight: 28, alignment: alignment)
        .accessibilityLabel(title)
    }

    private func buttons(_ actions: [ArgonTopBarAction]) -> some View {
        ForEach(actions.indices, id: \.self) { index in
            let action = actions[index]
            Button(action: action.action) {
                ArgonIcon(name: action.icon, size: 18)
                    .overlay(alignment: .topTrailing) {
                        if let badge = action.badge {
                            ArgonBadge(count: badge).offset(x: 10, y: -8)
                        }
                    }
            }
            .accessibilityLabel(action.accessibilityLabel)
        }
    }
}

private struct ArgonSearchable: ViewModifier {
    let text: Binding<String>?
    let isSearching: Binding<Bool>?
    let prompt: String

    // the drawer stays open: a screen with a search bar is there to be searched, so the field doesn't hide on scroll
    private var placement: SearchFieldPlacement { .navigationBarDrawer(displayMode: .always) }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text = text {
            if let isSearching = isSearching {
                content.searchable(text: text, isPresented: isSearching, placement: placement, prompt: Text(prompt))
            } else {
                content.searchable(text: text, placement: placement, prompt: Text(prompt))
            }
        } else {
            content
        }
    }
}

extension View {
    /// Sets up the enclosing `NavigationStack`'s bar for this screen: title, or the logo (centred, or at the start in
    /// place of a `.standard` title), icon actions on either side, and with `.search` the native search field bound to
    /// `searchText`. `isSearching` is whether that field is being typed in: set it to give the field the keyboard.
    public func argonTopBar(
        variant: ArgonTopBarVariant = .standard,
        title: String,
        logoUrl: URL? = nil,
        leading: [ArgonTopBarAction] = [],
        trailing: [ArgonTopBarAction] = [],
        searchText: Binding<String>? = nil,
        isSearching: Binding<Bool>? = nil
    ) -> some View {
        modifier(ArgonTopBar(
            variant: variant, title: title, logoUrl: logoUrl, leading: leading, trailing: trailing,
            searchText: searchText, isSearching: isSearching
        ))
    }
}
