import SwiftUI

/// Tabs over content: the native segmented control when they fit, or (`isScrollable`) a scrolling row of titles with
/// the selected one underlined and kept in view.
@MainActor
public struct ArgonTabs: View {
    let titles: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let isScrollable: Bool
    @Environment(\.argonTheme) private var theme

    public init(titles: [String], selectedIndex: Int, onSelect: @escaping (Int) -> Void, isScrollable: Bool = false) {
        self.titles = titles
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
        self.isScrollable = isScrollable
    }

    public var body: some View {
        if isScrollable {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.spacing.xl) {
                        ForEach(titles.indices, id: \.self) { index in
                            tab(index)
                        }
                    }
                    .padding(.horizontal, theme.spacing.l)
                }
                .onChange(of: selectedIndex) { _, index in
                    withAnimation { proxy.scrollTo(index, anchor: .center) }
                }
            }
            .overlay(alignment: .bottom) { ArgonDivider() }
        } else {
            ArgonButtonGroup(options: titles, selectedIndex: selectedIndex, onSelect: onSelect)
        }
    }

    private func tab(_ index: Int) -> some View {
        let selected = index == selectedIndex
        return Button { onSelect(index) } label: {
            VStack(spacing: theme.spacing.s) {
                Text(titles[index])
                    .font(selected ? theme.type.headline : theme.type.label)
                    .foregroundStyle(selected ? theme.colors.ink : theme.colors.muted)
                    .fixedSize()
                Rectangle()
                    .fill(selected ? theme.colors.accent : Color.clear)
                    .frame(height: 2)
            }
            .padding(.top, theme.spacing.m)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
