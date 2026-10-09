import SwiftUI

public enum ArgonCardStyle: Sendable {
    /// Surface with a soft shadow.
    case elevated
    /// Surface with a border.
    case outlined
    /// A muted fill, no border or shadow.
    case filled
}

/// A rounded container for `content` (which brings its own padding); tappable when `onClick` is given.
@MainActor
public struct ArgonCard<Content: View>: View {
    let style: ArgonCardStyle
    let onClick: (() -> Void)?
    let content: Content
    @Environment(\.argonTheme) private var theme

    public init(style: ArgonCardStyle = .elevated, onClick: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.style = style
        self.onClick = onClick
        self.content = content()
    }

    public var body: some View {
        if let onClick = onClick {
            Button(action: onClick) { card }.buttonStyle(ArgonPressStyle())
        } else {
            card
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.l, style: .continuous)
        return content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style == .filled ? theme.colors.border.opacity(0.5) : theme.colors.surface)
            .clipShape(shape)
            .overlay {
                if style == .outlined { shape.strokeBorder(theme.colors.border, lineWidth: 1) }
            }
            .shadow(color: .black.opacity(style == .elevated ? 0.08 : 0), radius: 8, y: 2)
            .contentShape(shape)
    }
}
