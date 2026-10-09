import SwiftUI

/// A titled section that expands to show `content`: the native disclosure group. The caller owns `isExpanded`.
@MainActor
public struct ArgonAccordion<Content: View>: View {
    let title: String
    let isExpanded: Bool
    let onToggle: () -> Void
    let content: Content
    @Environment(\.argonTheme) private var theme

    public init(title: String, isExpanded: Bool, onToggle: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.content = content()
    }

    public var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { isExpanded }, set: { if $0 != isExpanded { onToggle() } })) {
            content
                .font(theme.type.body)
                .foregroundStyle(theme.colors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, theme.spacing.s)
        } label: {
            Text(title).font(theme.type.headline).foregroundStyle(theme.colors.ink)
        }
        .tint(theme.colors.ink) // the chevron
        .padding(.vertical, theme.spacing.s)
    }
}
