import SwiftUI

public enum ArgonTagStyle: Sendable {
    /// A toggle in a filter row: outlined, accent-filled with a check when selected.
    case filter
    /// A value the user entered, usually removable.
    case input
    /// A label, not interactive unless given `onClick`.
    case info
}

/// A small capsule label. `onRemove` adds a remove button.
@MainActor
public struct ArgonTag: View {
    let text: String
    let style: ArgonTagStyle
    let isSelected: Bool
    let onClick: (() -> Void)?
    let onRemove: (() -> Void)?
    @Environment(\.argonTheme) private var theme

    public init(
        text: String,
        style: ArgonTagStyle = .filter,
        isSelected: Bool = false,
        onClick: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.text = text
        self.style = style
        self.isSelected = isSelected
        self.onClick = onClick
        self.onRemove = onRemove
    }

    public var body: some View {
        // the remove button sits beside the tappable part, never inside it
        HStack(spacing: 0) {
            if let onClick = onClick {
                Button(action: onClick) { label }
                    .buttonStyle(ArgonPressStyle())
                    .accessibilityAddTraits(style == .filter && isSelected ? .isSelected : [])
            } else {
                label
            }
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    ArgonIcon(name: .close, size: 11)
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ArgonPressStyle())
                .accessibilityLabel("Remove \(text)")
                .padding(.leading, -theme.spacing.s)
            }
        }
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
        .overlay { Capsule().strokeBorder(stroke, lineWidth: 1) }
        .frame(minHeight: 44) // the touch target around the 32 pt capsule
    }

    private var label: some View {
        HStack(spacing: theme.spacing.xs) {
            if style == .filter && isSelected { ArgonIcon(name: .check, size: 12) }
            Text(text).font(theme.type.label).lineLimit(1)
        }
        .padding(.horizontal, theme.spacing.m)
        .frame(height: 32)
        .contentShape(Capsule())
    }

    private var selected: Bool { style == .filter && isSelected }

    private var foreground: Color { selected ? theme.colors.onAccent : theme.colors.ink }

    private var background: Color {
        switch style {
        case .filter: return isSelected ? theme.colors.accent : .clear
        case .input: return theme.colors.surface
        case .info: return theme.colors.border
        }
    }

    private var stroke: Color {
        switch style {
        case .filter: return isSelected ? theme.colors.accent : theme.colors.border
        case .input: return theme.colors.border
        case .info: return .clear
        }
    }
}
