import SwiftUI

/// Swipeable pages (the native page-style tab view), with dots below and optional autoplay that waits again after each
/// swipe and stays off under Reduce Motion. Give it a height.
@MainActor
public struct ArgonCarousel<Item: View>: View {
    let count: Int
    let autoplaySeconds: Double?
    let showsIndicators: Bool
    let itemContent: (Int) -> Item
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.argonTheme) private var theme

    public init(count: Int, autoplaySeconds: Double? = nil, showsIndicators: Bool = true, @ViewBuilder itemContent: @escaping (Int) -> Item) {
        self.count = count
        self.autoplaySeconds = autoplaySeconds
        self.showsIndicators = showsIndicators
        self.itemContent = itemContent
    }

    public var body: some View {
        VStack(spacing: theme.spacing.s) {
            TabView(selection: $index) {
                ForEach(0..<max(count, 0), id: \.self) { page in
                    itemContent(page).tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            if showsIndicators && count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { page in
                        Circle()
                            .fill(page == index ? theme.colors.ink : theme.colors.border)
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
            withAnimation { index = (index + 1) % count }
        }
    }
}
