import SwiftUI

public enum ArgonTopBarVariant: Sendable {
    /// Inline title.
    case standard
    /// Large title that collapses on scroll.
    case largeTitle
    /// The shop's logo in the middle (the title while it loads or without one).
    case centeredLogo
    /// Inline title and the native search field.
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
    @Environment(\.argonTheme) var theme

    public func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(variant == .largeTitle ? .large : .inline)
            .toolbar {
                if variant == .centeredLogo {
                    ToolbarItem(placement: .principal) { logo }
                }
                if !leading.isEmpty {
                    ToolbarItemGroup(placement: .topBarLeading) { buttons(leading) }
                }
                if !trailing.isEmpty {
                    ToolbarItemGroup(placement: .topBarTrailing) { buttons(trailing) }
                }
            }
            .modifier(ArgonSearchable(text: variant == .search ? searchText : nil, prompt: title))
    }

    private var logo: some View {
        AsyncImage(url: logoUrl) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Text(title).font(theme.type.headline).foregroundStyle(theme.colors.ink)
        }
        .frame(maxWidth: 160, maxHeight: 28)
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
    let prompt: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text = text {
            content.searchable(text: text, prompt: Text(prompt))
        } else {
            content
        }
    }
}

extension View {
    /// Sets up the enclosing `NavigationStack`'s bar for this screen: title or centred logo, icon actions on either
    /// side, and with `.search` the native search field bound to `searchText`.
    public func argonTopBar(
        variant: ArgonTopBarVariant = .standard,
        title: String,
        logoUrl: URL? = nil,
        leading: [ArgonTopBarAction] = [],
        trailing: [ArgonTopBarAction] = [],
        searchText: Binding<String>? = nil
    ) -> some View {
        modifier(ArgonTopBar(
            variant: variant, title: title, logoUrl: logoUrl, leading: leading, trailing: trailing, searchText: searchText
        ))
    }
}
