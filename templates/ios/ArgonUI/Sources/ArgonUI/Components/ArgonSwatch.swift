import SwiftUI

/// A colour to choose: a circle in the colour (`#RRGGBB`) or the image, with a ring when selected and a diagonal strike
/// when unavailable. `label` is its accessibility name, shown under the circle at size L. Without a colour or an image
/// the circle shows the label's first letter. A button when `onClick` is given.
@MainActor
public struct ArgonSwatch: View {
    let colorHex: String?
    let imageUrl: URL?
    let label: String
    let isSelected: Bool
    let isAvailable: Bool
    let size: ArgonSize
    let onClick: (() -> Void)?
    @Environment(\.argonTheme) private var theme

    public init(
        colorHex: String?,
        imageUrl: URL? = nil,
        label: String,
        isSelected: Bool = false,
        isAvailable: Bool = true,
        size: ArgonSize = .m,
        onClick: (() -> Void)? = nil
    ) {
        self.colorHex = colorHex
        self.imageUrl = imageUrl
        self.label = label
        self.isSelected = isSelected
        self.isAvailable = isAvailable
        self.size = size
        self.onClick = onClick
    }

    public var body: some View {
        Group {
            if let onClick = onClick {
                Button(action: onClick) { content }.buttonStyle(ArgonPressStyle())
            } else {
                content
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The circle (and the label under it at size L), read out as one thing: the label, and "Unavailable" when struck.
    private var content: some View {
        swatch
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(isAvailable ? Text(verbatim: "") : Text("Unavailable"))
    }

    private var swatch: some View {
        let diameter: CGFloat = size == .s ? 16 : size == .m ? 32 : 44
        // room for the selection ring, kept when unselected so a row of swatches doesn't shift
        let ring: CGFloat = size == .s ? 2 : 4
        return VStack(spacing: theme.spacing.xs) {
            circle(diameter)
                .padding(ring)
                .overlay {
                    if isSelected { Circle().strokeBorder(theme.colors.ink, lineWidth: size == .s ? 1 : 2) }
                }
            if size == .l {
                Text(label)
                    .font(theme.type.caption)
                    .foregroundStyle(isAvailable ? theme.colors.ink : theme.colors.muted)
                    .lineLimit(1)
                    .frame(width: diameter + 24)
            }
        }
        .contentShape(Rectangle())
    }

    private func circle(_ diameter: CGFloat) -> some View {
        ZStack {
            if let color = ArgonTheme.color(hex: colorHex) {
                color
            } else {
                theme.colors.surface
                if imageUrl == nil, size != .s {
                    Text(String(label.prefix(1)).uppercased())
                        .font(ArgonTypography.fixed(size: diameter * 0.4, weight: 600))
                        .foregroundStyle(theme.colors.muted)
                }
            }
            if let imageUrl = imageUrl {
                AsyncImage(url: imageUrl) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .opacity(isAvailable ? 1 : 0.45)
        // a hairline, so white and near-paper colours keep an edge
        .overlay { Circle().strokeBorder(theme.colors.border, lineWidth: 1) }
        .overlay {
            if !isAvailable {
                GeometryReader { geometry in
                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width * 0.15, y: geometry.size.height * 0.85))
                        path.addLine(to: CGPoint(x: geometry.size.width * 0.85, y: geometry.size.height * 0.15))
                    }
                    .stroke(theme.colors.ink, lineWidth: 1.5)
                }
            }
        }
    }
}
