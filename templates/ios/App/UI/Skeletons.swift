import ArgonUI
import SwiftUI

/// What a screen's first load shows: the shape of what is coming, in skeleton blocks on the 16 pt gutter, so the content
/// takes their place without a jump. VoiceOver hears it as one "Loading". It holds to the top and doesn't scroll.
@MainActor
struct ScreenSkeleton: View {
    enum Kind {
        /// A hero, a row of circles (categories), a heading and a row of product cards: home and custom pages.
        case home
        /// Two columns of product cards: collections, search results, the wishlist.
        case grid
        /// The gallery, title, price, options and the buy button.
        case product
        /// Rows of a thumbnail and two lines: the cart, orders, addresses, the account.
        case list
        /// Lines of text: a policy, a store page.
        case text
    }

    let kind: Kind
    @Environment(\.argonTheme) private var theme

    init(_ kind: Kind) {
        self.kind = kind
    }

    var body: some View {
        ScrollView {
            Group {
                switch kind {
                case .home: home
                case .grid: grid
                case .product: product
                case .list: list
                case .text: text
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDisabled(true)
        .argonSkeletonScreen()
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            ArgonSkeleton.box(aspectRatio: 0.8, cornerRadius: theme.radius.m)
            HStack(spacing: theme.spacing.m) {
                ForEach(0..<4, id: \.self) { _ in
                    ArgonSkeleton.circle(size: 64).frame(maxWidth: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                ArgonSkeleton.line(width: 160, height: 20)
                cards(2)
            }
        }
        .padding(theme.spacing.l)
    }

    private var grid: some View {
        VStack(spacing: theme.spacing.l) {
            ForEach(0..<3, id: \.self) { _ in cards(2) }
        }
        .padding([.horizontal, .top], theme.spacing.l)
    }

    private var product: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArgonSkeleton.box(aspectRatio: 0.8, cornerRadius: 0)
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                ArgonSkeleton.line(height: 22)
                ArgonSkeleton.line(width: 180, height: 22)
                ArgonSkeleton.line(width: 90, height: 18).padding(.top, theme.spacing.xs)
                HStack(spacing: theme.spacing.s) {
                    ForEach(0..<4, id: \.self) { _ in
                        ArgonSkeleton(cornerRadius: theme.radius.pill).frame(width: 56, height: 36)
                    }
                }
                .padding(.vertical, theme.spacing.s)
                ArgonSkeleton(cornerRadius: theme.radius.m).frame(height: 56)
            }
            .padding(.horizontal, theme.spacing.l)
            .padding(.top, theme.spacing.l)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: theme.spacing.l) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(alignment: .top, spacing: theme.spacing.m) {
                    ArgonSkeleton(cornerRadius: theme.radius.s).frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: theme.spacing.s) {
                        ArgonSkeleton.line()
                        ArgonSkeleton.line(width: 120)
                    }
                    .padding(.top, theme.spacing.xs)
                }
            }
        }
        .padding(theme.spacing.l)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            ForEach(0..<8, id: \.self) { index in
                // every fourth line ends a paragraph, short
                if index % 4 == 3 { ArgonSkeleton.line(width: 140) } else { ArgonSkeleton.line() }
            }
        }
        .padding(theme.spacing.l)
    }

    /// `count` product cards side by side, as the grid lays them out: the 4:5 picture, then two lines.
    private func cards(_ count: Int) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.m) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    ArgonSkeleton.box(aspectRatio: 0.8, cornerRadius: theme.radius.m)
                    ArgonSkeleton.line().padding(.top, theme.spacing.xs)
                    ArgonSkeleton.line(width: 64)
                }
            }
        }
    }
}
