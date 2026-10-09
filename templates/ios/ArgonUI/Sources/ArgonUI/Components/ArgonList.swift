import SwiftUI

/// Rows in the native inset-grouped list, on Argon's colours. It scrolls itself: give it the screen, or a height.
@MainActor
public struct ArgonList<Content: View>: View {
    let header: String?
    let content: Content
    @Environment(\.argonTheme) private var theme

    public init(header: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    public var body: some View {
        List {
            SwiftUI.Section {
                // a Group hands these row modifiers to every row inside
                Group { content }
                    .listRowBackground(theme.colors.surface)
                    .listRowSeparatorTint(theme.colors.border)
            } header: {
                if let header = header {
                    Text(header).font(theme.type.label).foregroundStyle(theme.colors.muted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.colors.paper)
    }
}

/// What leads a list row.
public enum ArgonListLeading {
    case icon(ArgonIconName)
    case avatar(imageUrl: URL?, initials: String?)
    case image(URL?)
}

/// What trails a list row. A counted badge is the list's native badge; a nil count is a dot.
public enum ArgonListTrailing {
    case chevron
    case text(String)
    case badge(Int?)
    case `switch`(isOn: Bool, onChange: (Bool) -> Void)
    case checkbox(isChecked: Bool, onChange: (Bool) -> Void)
}

/// A list row: title, optional subtitle, leading and trailing parts; a button when `onClick` is given.
@MainActor
public struct ArgonListItem: View {
    let title: String
    let subtitle: String?
    let leading: ArgonListLeading?
    let trailing: ArgonListTrailing?
    let onClick: (() -> Void)?
    @Environment(\.argonTheme) private var theme

    public init(
        title: String,
        subtitle: String? = nil,
        leading: ArgonListLeading? = nil,
        trailing: ArgonListTrailing? = nil,
        onClick: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing
        self.onClick = onClick
    }

    public var body: some View {
        Group {
            if let onClick = onClick {
                Button(action: onClick) { row }
            } else {
                row
            }
        }
        .badge(nativeBadge)
    }

    private var row: some View {
        HStack(spacing: theme.spacing.m) {
            leadingView
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(theme.type.body).foregroundStyle(theme.colors.ink)
                if let subtitle = subtitle {
                    Text(subtitle).font(theme.type.caption).foregroundStyle(theme.colors.muted)
                }
            }
            Spacer(minLength: theme.spacing.s)
            trailingView
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingView: some View {
        switch leading {
        case let .icon(name)?:
            ArgonIcon(name: name, size: 20, tint: theme.colors.ink).frame(width: 28)
        case let .avatar(imageUrl, initials)?:
            ArgonAvatar(imageUrl: imageUrl, initials: initials, size: .m)
        case let .image(url)?:
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                theme.colors.border
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.s))
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .chevron?:
            ArgonIcon(name: .chevronRight, size: 14, tint: theme.colors.muted)
        case let .text(text)?:
            Text(text).font(theme.type.body).foregroundStyle(theme.colors.muted)
        case let .badge(count)?:
            if count == nil { ArgonBadge(count: nil) }
        case let .`switch`(isOn, onChange)?:
            ArgonSwitch(isOn: isOn, onChange: onChange)
        case let .checkbox(isChecked, onChange)?:
            ArgonCheckbox(isChecked: isChecked, onChange: onChange)
        case nil:
            EmptyView()
        }
    }

    private var nativeBadge: Text? {
        guard case let .badge(count)? = trailing, let text = ArgonBadge.text(count) else { return nil }
        return Text(text)
    }
}

/// A hairline separator, inset from the leading edge by `inset` points.
@MainActor
public struct ArgonDivider: View {
    let inset: CGFloat?
    @Environment(\.argonTheme) private var theme

    public init(inset: CGFloat? = nil) {
        self.inset = inset
    }

    public var body: some View {
        Divider().overlay(theme.colors.border).padding(.leading, inset ?? 0)
    }
}
