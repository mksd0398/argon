import SwiftUI

/// A tab of the bottom bar. `badge` is a count (none when nil or 0).
public struct ArgonBottomBarItem: Identifiable {
    public let id: String
    public let title: String
    public let icon: ArgonIconName
    public let badge: Int?

    public init(id: String, title: String, icon: ArgonIconName, badge: Int? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.badge = badge
    }
}

/// The app's tabs: the native tab view and tab bar, showing `content` for the selected item. The caller owns the
/// selection.
@MainActor
public struct ArgonBottomBar<Content: View>: View {
    let items: [ArgonBottomBarItem]
    let selectedId: String
    let onSelect: (String) -> Void
    let content: (ArgonBottomBarItem) -> Content
    @Environment(\.argonTheme) private var theme

    public init(
        items: [ArgonBottomBarItem],
        selectedId: String,
        onSelect: @escaping (String) -> Void,
        @ViewBuilder content: @escaping (ArgonBottomBarItem) -> Content
    ) {
        self.items = items
        self.selectedId = selectedId
        self.onSelect = onSelect
        self.content = content
    }

    public var body: some View {
        TabView(selection: Binding(get: { selectedId }, set: { onSelect($0) })) {
            ForEach(items) { item in
                content(item)
                    .tabItem { Label(item.title, systemImage: item.icon.systemName) }
                    .tag(item.id)
                    .badge(badgeText(item.badge))
            }
        }
        .tint(theme.colors.accent)
    }

    private func badgeText(_ count: Int?) -> Text? {
        guard let count = count, count > 0, let text = ArgonBadge.text(count) else { return nil }
        return Text(text)
    }
}
