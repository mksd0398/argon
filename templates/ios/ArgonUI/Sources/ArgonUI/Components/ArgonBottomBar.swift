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
/// selection. Without `showLabels` the bar shows the icons alone (each still named for VoiceOver). `activeColor` is the
/// selected tab's icon and title (nil: the accent).
@MainActor
public struct ArgonBottomBar<Content: View>: View {
    let items: [ArgonBottomBarItem]
    let selectedId: String
    let onSelect: (String) -> Void
    let showLabels: Bool
    let activeColor: Color?
    let content: (ArgonBottomBarItem) -> Content
    @Environment(\.argonTheme) private var theme

    public init(
        items: [ArgonBottomBarItem],
        selectedId: String,
        onSelect: @escaping (String) -> Void,
        showLabels: Bool = true,
        activeColor: Color? = nil,
        @ViewBuilder content: @escaping (ArgonBottomBarItem) -> Content
    ) {
        self.items = items
        self.selectedId = selectedId
        self.onSelect = onSelect
        self.showLabels = showLabels
        self.activeColor = activeColor
        self.content = content
    }

    public var body: some View {
        TabView(selection: Binding(get: { selectedId }, set: { onSelect($0) })) {
            ForEach(items) { item in
                content(item)
                    .tabItem {
                        if showLabels {
                            Label(item.title, systemImage: item.icon.systemName)
                        } else {
                            Image(systemName: item.icon.systemName).accessibilityLabel(item.title)
                        }
                    }
                    .tag(item.id)
                    .badge(badgeText(item.badge))
            }
        }
        .tint(activeColor ?? theme.colors.accent)
    }

    private func badgeText(_ count: Int?) -> Text? {
        guard let count = count, count > 0, let text = ArgonBadge.text(count) else { return nil }
        return Text(text)
    }
}
