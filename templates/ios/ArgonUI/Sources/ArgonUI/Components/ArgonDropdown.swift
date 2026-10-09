import SwiftUI

/// Pick one of `options` from the native menu. The field shows `label` alone until there is a selection, then `label`
/// small above the selected option.
@MainActor
public struct ArgonDropdown: View {
    let label: String
    let options: [String]
    let selectedIndex: Int?
    let onSelect: (Int) -> Void
    @Environment(\.argonTheme) private var theme

    public init(label: String, options: [String], selectedIndex: Int?, onSelect: @escaping (Int) -> Void) {
        self.label = label
        self.options = options
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
    }

    public var body: some View {
        let selected = selectedIndex.flatMap { options.indices.contains($0) ? options[$0] : nil }
        Menu {
            ForEach(options.indices, id: \.self) { index in
                Button { onSelect(index) } label: {
                    if index == selectedIndex {
                        Label(options[index], systemImage: "checkmark")
                    } else {
                        Text(options[index])
                    }
                }
            }
        } label: {
            HStack(spacing: theme.spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    if let selected = selected {
                        Text(label).font(theme.type.caption).foregroundStyle(theme.colors.muted)
                        Text(selected).font(theme.type.body).foregroundStyle(theme.colors.ink)
                    } else {
                        Text(label).font(theme.type.body).foregroundStyle(theme.colors.muted)
                    }
                }
                Spacer(minLength: 0)
                ArgonIcon(name: .chevronDown, size: 14, tint: theme.colors.muted)
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(minHeight: 52)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.m))
            .overlay { RoundedRectangle(cornerRadius: theme.radius.m).strokeBorder(theme.colors.border, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityValue(selected ?? "")
    }
}
