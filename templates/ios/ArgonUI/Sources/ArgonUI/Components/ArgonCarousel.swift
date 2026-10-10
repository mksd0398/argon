import SwiftUI

/// Swipeable pages, edge to edge (a native paging scroll view): the current page sits between `itemSpacing` gaps and
/// its neighbours peek in by `peekFraction` of the width (0.04 = 4%), so pages scroll off the carousel's edges. Give it
/// the screen's full width (no horizontal padding around it) and a height. Dots below; optional autoplay that waits
/// again after each swipe and stays off under Reduce Motion.
@MainActor
public struct ArgonCarousel<Item: View>: View {
    let count: Int
    let autoplaySeconds: Double?
    let showsIndicators: Bool
    let peekFraction: Double
    let itemSpacing: CGFloat?
    let itemContent: (Int) -> Item
    @State private var page: Int? = 0
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.argonTheme) private var theme

    /// `itemSpacing` nil = the theme's small spacing.
    public init(
        count: Int,
        autoplaySeconds: Double? = nil,
        showsIndicators: Bool = true,
        peekFraction: Double = 0.04,
        itemSpacing: CGFloat? = nil,
        @ViewBuilder itemContent: @escaping (Int) -> Item
    ) {
        self.count = count
        self.autoplaySeconds = autoplaySeconds
        self.showsIndicators = showsIndicators
        self.peekFraction = peekFraction
        self.itemSpacing = itemSpacing
        self.itemContent = itemContent
    }

    public var body: some View {
        let spacing = itemSpacing ?? theme.spacing.s
        let index = page ?? 0
        // the side inset is what shows the neighbours: a gap, then the peek
        let side = spacing + width * CGFloat(min(max(peekFraction, 0), 0.4))
        VStack(spacing: theme.spacing.s) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: spacing) {
                    ForEach(0..<max(count, 0), id: \.self) { item in
                        itemContent(item).containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .safeAreaPadding(.horizontal, side)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { width = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, new in width = new }
                }
            }
            if showsIndicators && count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { dot in
                        Circle()
                            .fill(dot == index ? theme.colors.ink : theme.colors.border)
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        // restarts on every page change, so a swipe gets the full wait too
        .task(id: [index, reduceMotion ? 1 : 0]) {
            guard let seconds = autoplaySeconds, seconds > 0, count > 1, !reduceMotion else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation { page = (index + 1) % count }
        }
    }
}
