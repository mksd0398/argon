import SwiftUI

/// A standalone badge: a dot when `count` is nil, else the count ("99+" above 99). Tab items use the native `.badge`.
@MainActor
public struct ArgonBadge: View {
    let count: Int?
    @Environment(\.argonTheme) private var theme

    public init(count: Int? = nil) {
        self.count = count
    }

    /// The badge's text: nil for a dot, the count up to 99, then "99+".
    public nonisolated static func text(_ count: Int?) -> String? {
        guard let count = count else { return nil }
        return count > 99 ? "99+" : String(max(count, 0))
    }

    public var body: some View {
        if let text = Self.text(count) {
            Text(text)
                .font(ArgonTypography.fixed(size: 11, weight: 700))
                .foregroundStyle(theme.colors.paper)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(theme.colors.sale, in: Capsule())
        } else {
            Circle().fill(theme.colors.sale).frame(width: 8, height: 8).accessibilityLabel("New")
        }
    }
}

/// `content` with a badge on its top-trailing corner (a dot when `count` is nil).
@MainActor
public struct ArgonBadgedBox<Content: View>: View {
    let count: Int?
    let content: Content

    public init(count: Int?, @ViewBuilder content: () -> Content) {
        self.count = count
        self.content = content()
    }

    public var body: some View {
        content.overlay(alignment: .topTrailing) {
            ArgonBadge(count: count)
                .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] }
        }
    }
}
