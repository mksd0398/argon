import SwiftUI

/// A checkbox (iOS has none outside macOS): a rounded box, filled with a check when `isChecked`.
@MainActor
public struct ArgonCheckbox: View {
    let isChecked: Bool
    let label: String?
    let isEnabled: Bool
    let onChange: (Bool) -> Void
    @Environment(\.argonTheme) private var theme

    public init(isChecked: Bool, label: String? = nil, isEnabled: Bool = true, onChange: @escaping (Bool) -> Void) {
        self.isChecked = isChecked
        self.label = label
        self.isEnabled = isEnabled
        self.onChange = onChange
    }

    public var body: some View {
        Button { onChange(!isChecked) } label: {
            HStack(spacing: theme.spacing.m) {
                RoundedRectangle(cornerRadius: theme.radius.s)
                    .fill(isChecked ? theme.colors.accent : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: theme.radius.s)
                            .strokeBorder(isChecked ? theme.colors.accent : theme.colors.muted, lineWidth: 1.5)
                    }
                    .overlay {
                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(theme.colors.onAccent)
                        }
                    }
                    .frame(width: 22, height: 22)
                if let label = label {
                    Text(label).font(theme.type.body).foregroundStyle(theme.colors.ink)
                }
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        // a custom style: inside a List row only the box takes the tap, not the whole row
        .buttonStyle(ArgonPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityValue(isChecked ? Text("Checked") : Text("Unchecked"))
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

/// One radio button: a ring, with a dot when `isSelected`.
@MainActor
public struct ArgonRadioButton: View {
    let isSelected: Bool
    let label: String
    let onSelect: () -> Void
    @Environment(\.argonTheme) private var theme

    public init(isSelected: Bool, label: String, onSelect: @escaping () -> Void) {
        self.isSelected = isSelected
        self.label = label
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: theme.spacing.m) {
                Circle()
                    .strokeBorder(isSelected ? theme.colors.accent : theme.colors.muted, lineWidth: 1.5)
                    .overlay {
                        if isSelected { Circle().fill(theme.colors.accent).padding(5) }
                    }
                    .frame(width: 22, height: 22)
                Text(label).font(theme.type.body).foregroundStyle(theme.colors.ink)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ArgonPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Radio buttons, one per option, stacked.
@MainActor
public struct ArgonRadioGroup: View {
    let options: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    public init(options: [String], selectedIndex: Int, onSelect: @escaping (Int) -> Void) {
        self.options = options
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                ArgonRadioButton(isSelected: index == selectedIndex, label: options[index]) { onSelect(index) }
            }
        }
    }
}

/// An on/off switch: the native toggle in the accent colour.
@MainActor
public struct ArgonSwitch: View {
    let isOn: Bool
    let label: String?
    let onChange: (Bool) -> Void
    @Environment(\.argonTheme) private var theme

    public init(isOn: Bool, label: String? = nil, onChange: @escaping (Bool) -> Void) {
        self.isOn = isOn
        self.label = label
        self.onChange = onChange
    }

    public var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { onChange($0) })) {
            Text(label ?? "").font(theme.type.body).foregroundStyle(theme.colors.ink)
        }
        .labelsHidden(label == nil)
        .tint(theme.colors.accent)
    }
}

private extension View {
    @ViewBuilder
    func labelsHidden(_ hidden: Bool) -> some View {
        if hidden { labelsHidden() } else { self }
    }
}
