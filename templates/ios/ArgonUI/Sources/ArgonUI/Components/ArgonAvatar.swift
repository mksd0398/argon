import SwiftUI

/// A round avatar: the image when there is one (initials or the icon show while it loads), else the initials, else the
/// icon (a person by default).
@MainActor
public struct ArgonAvatar: View {
    let imageUrl: URL?
    let initials: String?
    let icon: ArgonIconName?
    let size: ArgonSize
    @Environment(\.argonTheme) private var theme

    public init(imageUrl: URL? = nil, initials: String? = nil, icon: ArgonIconName? = nil, size: ArgonSize = .m) {
        self.imageUrl = imageUrl
        self.initials = initials
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        let diameter: CGFloat = size == .s ? 32 : size == .m ? 40 : 56
        ZStack {
            theme.colors.border
            if let initials = initials, !initials.isEmpty {
                Text(String(initials.prefix(2)).uppercased())
                    .font(ArgonTypography.fixed(size: diameter * 0.38, weight: 600))
                    .foregroundStyle(theme.colors.ink)
            } else {
                ArgonIcon(name: icon ?? .person, size: diameter * 0.5, tint: theme.colors.muted)
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
        .accessibilityElement()
        .accessibilityLabel(initials ?? "")
        .accessibilityHidden(initials == nil)
    }
}
