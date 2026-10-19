import ArgonUI
import SwiftUI

// The small blocks the account, orders and returns pages share.

/// The store's contact page, in the in-app browser: where "Help" and "Need help?" lead.
func contactRoute() -> Route {
    .web("https://\(AppGraph.shopDomain)/pages/contact")
}

/// A `Loader` whose result isn't kept: the screen loads again each time it comes back into view (from a pushed screen, or
/// from another tab). For the customer's own data, which a screen further on may have changed.
@MainActor
struct FreshLoader<Value, Content: View>: View {
    private let load: () async throws -> Value
    private let content: (Value) -> Content
    private let skeleton: ScreenSkeleton.Kind
    @State private var visit = 0
    @State private var away = false

    init(load: @escaping () async throws -> Value, skeleton: ScreenSkeleton.Kind = .list, @ViewBuilder content: @escaping (Value) -> Content) {
        self.load = load
        self.skeleton = skeleton
        self.content = content
    }

    var body: some View {
        Loader(load: load, skeleton: skeleton, content: content)
            .id(visit)
            // on the way back, not on the way out: a load started while the screen is covered would miss what the
            // screen over it goes on to change
            .onAppear {
                if away {
                    away = false
                    visit += 1
                }
            }
            .onDisappear { away = true }
    }
}

/// What went wrong with a change (Shopify's own words), shown where it happened; nothing without a `message`.
@MainActor
struct ErrorText: View {
    let message: String?
    @Environment(\.argonTheme) private var theme

    init(_ message: String?) {
        self.message = message
    }

    var body: some View {
        if let message = message, trimmedText(message) != nil {
            Text(message)
                .font(theme.type.label)
                .foregroundStyle(theme.colors.sale)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A label with its value at the end of the line ("Subtotal", "$230.00"); `note` is a quieter line under the label (the
/// shipping method). `strong` is for the line that matters most (the total).
@MainActor
struct InfoRow: View {
    let label: String
    let value: String
    var note: String? = nil
    var strong = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let style = strong ? theme.type.headline : theme.type.body
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(style).foregroundStyle(strong ? theme.colors.ink : theme.colors.muted)
                if let note = trimmedText(note) {
                    Text(note).font(theme.type.caption).foregroundStyle(theme.colors.muted)
                }
            }
            Spacer(minLength: theme.spacing.m)
            // a long value (a company's name) wraps instead of pushing its label off the line
            Text(value).font(style).foregroundStyle(theme.colors.ink).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A bordered block of a page, with an optional heading; it fills the width it is given.
@MainActor
struct Panel<Content: View>: View {
    private let title: String?
    private let content: Content
    @Environment(\.argonTheme) private var theme

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ArgonCard(style: .outlined) {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                if let title = title {
                    Text(title).font(theme.type.headline).foregroundStyle(theme.colors.ink).accessibilityAddTraits(.isHeader)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.spacing.l)
        }
    }
}

/// Its children side by side, going on to a further line when the width runs out (a row of tags, of small buttons).
struct WrappingRow: Layout {
    /// Between neighbours on a line.
    var spacing: CGFloat
    /// Between lines.
    var lineSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews, width: bounds.width).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// Where each child goes in a row `width` wide, and the size they take together. A child wider than the row gets the
    /// row's width (its text shortens).
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x + size.width)
            x += size.width + spacing
        }
        return (frames, CGSize(width: widest, height: y + lineHeight))
    }
}
