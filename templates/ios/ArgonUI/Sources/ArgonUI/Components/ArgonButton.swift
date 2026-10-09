import SwiftUI

public enum ArgonButtonStyle: Sendable {
    /// Accent fill.
    case primary
    /// Ink outline.
    case secondary
    /// Text only.
    case tertiary
    /// Sale-red fill, for actions that remove or cancel.
    case destructive
}

/// A native button in Argon's styles. While loading it shows a spinner and takes no taps.
@MainActor
public struct ArgonButton: View {
    let title: String
    let style: ArgonButtonStyle
    let size: ArgonSize
    let icon: ArgonIconName?
    let isLoading: Bool
    let isEnabled: Bool
    let fullWidth: Bool
    let action: () -> Void
    @Environment(\.argonTheme) private var theme

    public init(
        title: String,
        style: ArgonButtonStyle = .primary,
        size: ArgonSize = .m,
        icon: ArgonIconName? = nil,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.size = size
        self.icon = icon
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.s) {
                if let icon = icon { ArgonIcon(name: icon, size: size == .l ? 20 : 17) }
                Text(title).lineLimit(1)
            }
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading { ProgressView().tint(foreground) }
            }
            .font(theme.type.label)
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .s ? theme.spacing.m : theme.spacing.xl)
            // every size keeps the 44 pt touch target
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size == .s ? 44 : size == .m ? 48 : 56)
            .background(background, in: Capsule())
            .overlay {
                if style == .secondary { Capsule().strokeBorder(theme.colors.ink, lineWidth: 1) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(ArgonPressStyle())
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityValue(isLoading ? Text("Loading") : Text(verbatim: ""))
    }

    private var foreground: Color {
        switch style {
        case .primary: return theme.colors.onAccent
        case .secondary, .tertiary: return theme.colors.ink
        case .destructive: return theme.colors.paper
        }
    }

    private var background: Color {
        switch style {
        case .primary: return theme.colors.accent
        case .secondary, .tertiary: return .clear
        case .destructive: return theme.colors.sale
        }
    }
}

/// Dims a pressed control.
struct ArgonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// One choice among a few, side by side: the native segmented control.
@MainActor
public struct ArgonButtonGroup: View {
    let options: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    public init(options: [String], selectedIndex: Int, onSelect: @escaping (Int) -> Void) {
        self.options = options
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
    }

    public var body: some View {
        Picker("", selection: Binding(get: { selectedIndex }, set: { onSelect($0) })) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index]).tag(index)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
