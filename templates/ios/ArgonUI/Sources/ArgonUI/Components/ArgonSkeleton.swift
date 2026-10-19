import SwiftUI

/// A placeholder block for content on its way: a rounded block in the theme's quiet `border` tone with a light sweep
/// across it (1.2 s, linear), still under Reduce Motion. It fills the space it is given; `line`, `circle` and `box` size
/// it. A screen of them reads to VoiceOver as one "Loading": put `.argonSkeletonScreen()` on their container.
@MainActor
public struct ArgonSkeleton: View {
    let cornerRadius: CGFloat
    @State private var sweeping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.argonTheme) private var theme

    public init(cornerRadius: CGFloat = 8) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        shape
            .fill(theme.colors.border.opacity(0.6))
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        let band = geometry.size.width * 0.6
                        LinearGradient(
                            colors: [.clear, theme.colors.surface.opacity(0.55), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: sweeping ? geometry.size.width : -band)
                    }
                }
            }
            .clipShape(shape)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { sweeping = true }
            }
    }

    /// A line of text: `width` points long (nil: the width it is given), `height` tall, with round ends.
    public static func line(width: CGFloat? = nil, height: CGFloat = 14) -> some View {
        ArgonSkeleton(cornerRadius: height / 2).frame(width: width, height: height)
    }

    /// A circle `size` points across (a category's picture, an avatar).
    public static func circle(size: CGFloat) -> some View {
        ArgonSkeleton(cornerRadius: size / 2).frame(width: size, height: size)
    }

    /// A block of the width it is given at `aspectRatio` (width / height), as a picture of that shape takes.
    public static func box(aspectRatio: CGFloat, cornerRadius: CGFloat = 8) -> some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { ArgonSkeleton(cornerRadius: cornerRadius) }
    }
}

extension View {
    /// A screen of skeletons as VoiceOver hears it: one "Loading", not one per block.
    public func argonSkeletonScreen() -> some View {
        accessibilityElement(children: .ignore).accessibilityLabel("Loading")
    }
}
