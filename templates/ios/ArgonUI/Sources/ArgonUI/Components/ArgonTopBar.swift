import SwiftUI
import UIKit

public enum ArgonTopBarVariant: Sendable {
    /// Inline title, or the shop's logo at the start when one is given.
    case standard
    /// Large title that collapses on scroll.
    case largeTitle
    /// The shop's logo in the middle (the title while it loads or without one).
    case centeredLogo
    /// Inline title and the native search field, always on show under it.
    case search
    /// The centred logo bar with no background, over a picture that runs to the top edge of the screen (see `solid`).
    case overlay
}

/// An icon button in the top bar, with an optional count badge.
public struct ArgonTopBarAction {
    public let icon: ArgonIconName
    public let accessibilityLabel: String
    public let badge: Int?
    public let action: () -> Void

    public init(icon: ArgonIconName, accessibilityLabel: String, badge: Int? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.badge = badge
        self.action = action
    }
}

/// The native navigation bar of the enclosing `NavigationStack`, set up for one screen. Use `.argonTopBar(...)` on the
/// screen's content.
public struct ArgonTopBar: ViewModifier {
    let variant: ArgonTopBarVariant
    let title: String
    let logoUrl: URL?
    let leading: [ArgonTopBarAction]
    let trailing: [ArgonTopBarAction]
    let searchText: Binding<String>?
    let isSearching: Binding<Bool>?
    let solid: Double
    let darkOverPicture: Bool
    @Environment(\.argonTheme) var theme
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.argonBarColors) var barColors

    private var foreground: Color? { ArgonTheme.color(hex: barColors.foreground) }

    public func body(content: Content) -> some View {
        // with a logo, the logo sits at the start in place of the title (a home screen with its logo at the start)
        let logoAtStart = variant == .standard && logoUrl != nil
        // the overlay bar is drawn in colours of its own; every other bar in the system's (or the app's `barColors`)
        let overlay = variant == .overlay
            ? overlayBarColors(solid: solid, dark: colorScheme == .dark, darkContent: darkOverPicture, bar: barColors)
            : nil
        let tint = overlay?.content.color
        content
            .navigationTitle(logoAtStart ? "" : title)
            .navigationBarTitleDisplayMode(variant == .largeTitle ? .large : .inline)
            .toolbar {
                if variant == .centeredLogo || variant == .overlay {
                    ToolbarItem(placement: .principal) { logo(.center, tint: tint) }
                }
                if !leading.isEmpty || logoAtStart {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        buttons(leading, tint: tint ?? foreground)
                        if logoAtStart { logo(.leading) }
                    }
                }
                if !trailing.isEmpty {
                    ToolbarItemGroup(placement: .topBarTrailing) { buttons(trailing, tint: tint ?? foreground) }
                }
            }
            .modifier(ArgonSearchable(text: variant == .search ? searchText : nil, isSearching: isSearching, prompt: title))
            .modifier(ArgonOverlayBar(colors: overlay, onPicture: solid < 0.5, darkContent: darkOverPicture))
    }

    /// The logo, fitted into 160 x 28 points and held to `alignment` of that box; the title while it loads or without one.
    /// `tint` is the overlay bar's colour for its content.
    private func logo(_ alignment: Alignment, tint: Color? = nil) -> some View {
        let name = Text(title).font(theme.type.headline).foregroundStyle(tint ?? foreground ?? theme.colors.ink).lineLimit(1)
        return Group {
            if let tint = tint, let url = logoUrl {
                OverlayLogo(url: url, tint: solid < 0.5 ? tint : nil) { name }
            } else {
                AsyncImage(url: logoUrl) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    name
                }
            }
        }
        .frame(maxWidth: 160, maxHeight: 28, alignment: alignment)
        .accessibilityLabel(title)
    }

    private func buttons(_ actions: [ArgonTopBarAction], tint: Color? = nil) -> some View {
        ForEach(actions.indices, id: \.self) { index in
            let action = actions[index]
            Button(action: action.action) {
                ArgonIcon(name: action.icon, size: 18, tint: tint)
                    .overlay(alignment: .topTrailing) {
                        if let badge = action.badge {
                            ArgonBadge(count: badge).offset(x: 10, y: -8)
                        }
                    }
            }
            .accessibilityLabel(action.accessibilityLabel)
        }
    }
}

private struct ArgonSearchable: ViewModifier {
    let text: Binding<String>?
    let isSearching: Binding<Bool>?
    let prompt: String

    // the drawer stays open: a screen with a search bar is there to be searched, so the field doesn't hide on scroll
    private var placement: SearchFieldPlacement { .navigationBarDrawer(displayMode: .always) }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text = text {
            if let isSearching = isSearching {
                content.searchable(text: text, isPresented: isSearching, placement: placement, prompt: Text(prompt))
            } else {
                content.searchable(text: text, placement: placement, prompt: Text(prompt))
            }
        } else {
            content
        }
    }
}

// MARK: Overlay

/// How dark the overlay bar's shade is at the top edge of the screen.
public let overlayBarShade = 0.65

/// A colour as red, green, blue and opacity, each 0...1.
public struct ArgonRGBA: Equatable, Sendable {
    public let red, green, blue, opacity: Double

    var color: Color { Color(red: red, green: green, blue: blue, opacity: opacity) }
}

/// What the overlay bar is drawn with: its background, its title and icons, and the top of the shade behind it.
public struct OverlayBarColors: Equatable, Sendable {
    public let container, content, shade: ArgonRGBA
}

/// The colours the app gives its solid bars (`#RRGGBB`; nil: the theme's): the top bar's background and its title and
/// icons. Set it in the environment over the screens (`\.argonBarColors`); the overlay bar turns into these once solid.
public struct ArgonBarColors: Equatable, Sendable {
    public var background: String?
    public var foreground: String?

    public init(background: String? = nil, foreground: String? = nil) {
        self.background = background
        self.foreground = foreground
    }
}

private struct ArgonBarColorsKey: EnvironmentKey {
    static let defaultValue = ArgonBarColors()
}

extension EnvironmentValues {
    public var argonBarColors: ArgonBarColors {
        get { self[ArgonBarColorsKey.self] }
        set { self[ArgonBarColorsKey.self] = newValue }
    }
}

/// The overlay bar at `solid` (0 over the picture ... 1 the normal bar; clamped) in the light or the `dark` appearance.
/// Over the picture it uses the dark palette whatever the appearance, as everything that sits on a photo does: light
/// content, a dark shade; with `darkContent` (a light picture) the light palette: dark content, a light shade. Solid, it
/// is the theme's bar, or `bar`'s colours where they are given.
public func overlayBarColors(solid: Double, dark: Bool, darkContent: Bool = false, bar: ArgonBarColors = ArgonBarColors()) -> OverlayBarColors {
    let t = min(max(solid, 0), 1)
    let onPhoto = darkContent ? ArgonPalette.light : ArgonPalette.dark, theme = dark ? ArgonPalette.dark : ArgonPalette.light
    func parts(_ hex: String, opacity: Double = 1) -> ArgonRGBA {
        let c = ArgonTheme.rgb(hex: hex) ?? (red: 0, green: 0, blue: 0)
        return ArgonRGBA(red: c.red, green: c.green, blue: c.blue, opacity: opacity)
    }
    func mix(_ from: Double, _ to: Double) -> Double { from * (1 - t) + to * t }
    let light = parts(onPhoto.ink), ink = parts(bar.foreground ?? theme.ink)
    return OverlayBarColors(
        container: parts(bar.background ?? theme.paper, opacity: t),
        content: ArgonRGBA(red: mix(light.red, ink.red), green: mix(light.green, ink.green), blue: mix(light.blue, ink.blue), opacity: 1),
        shade: parts(onPhoto.paper, opacity: overlayBarShade * (1 - t))
    )
}

/// The overlay variant's bar: its background (none over the picture), light status bar content while the picture is
/// under it (dark with `darkContent`), and the shade its content reads on. Nil `colors`: any other variant, left as it is.
private struct ArgonOverlayBar: ViewModifier {
    let colors: OverlayBarColors?
    let onPicture: Bool
    let darkContent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let colors = colors {
            content
                // The shade is behind the whole bar, status bar included, and thins out into the picture half a bar
                // further down: at the height of the icons it is still dark enough for them to read on a bright picture.
                .overlay(alignment: .top) {
                    GeometryReader { proxy in
                        LinearGradient(colors: [colors.shade.color, colors.shade.color.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                            .frame(height: proxy.safeAreaInsets.top / 2)
                    }
                    .allowsHitTesting(false)
                }
                .toolbarBackground(colors.container.color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                // a dark bar has light status bar content, a light one dark
                .toolbarColorScheme(onPicture ? (darkContent ? .light : .dark) : nil, for: .navigationBar)
        } else {
            content
        }
    }
}

/// The logo in the overlay bar. A mark on a clear background (its top-left pixel is see-through) is drawn in `tint`
/// while the bar is over the picture, where its own colour may not show; a logo with a background of its own keeps its
/// colours (tinted, it would be a plain box). Nil `tint`: the logo as it is. `placeholder` shows while it loads, and
/// when it can't be.
private struct OverlayLogo<Placeholder: View>: View {
    let url: URL
    let tint: Color?
    @ViewBuilder let placeholder: Placeholder
    @State private var logo: UIImage? = nil
    @State private var clear = false

    var body: some View {
        Group {
            if let logo = logo {
                Image(uiImage: logo)
                    .renderingMode(tint != nil && clear ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint ?? .primary)
            } else {
                placeholder
            }
        }
        // loaded by hand: AsyncImage doesn't hand over the picture's pixels
        .task(id: url) {
            guard let data = try? await URLSession.shared.data(from: url).0, let image = UIImage(data: data) else { return }
            clear = image.hasClearCorner
            logo = image
        }
    }
}

extension UIImage {
    /// Whether the top-left pixel is see-through.
    var hasClearCorner: Bool {
        guard let corner = cgImage?.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
              let context = CGContext(
                  data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return false }
        context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        // RGBA: the fourth byte is the pixel's alpha
        return context.data.map { $0.load(fromByteOffset: 3, as: UInt8.self) < 255 } ?? false
    }
}

extension View {
    /// Sets up the enclosing `NavigationStack`'s bar for this screen: title, or the logo (centred, or at the start in
    /// place of a `.standard` title), icon actions on either side, and with `.search` the native search field bound to
    /// `searchText`. `isSearching` is whether that field is being typed in: set it to give the field the keyboard.
    /// With `.overlay`, let the screen's content start at the top edge of the screen (ignoring the top safe area): at
    /// `solid` 0 the bar has no background and its logo, title and actions are light over a short dark shade; towards 1
    /// (as the picture under it scrolls away) the normal bar fades in. Only `.overlay` reads `solid` and
    /// `darkOverPicture` (a light picture: dark content over a light shade, and dark status bar content).
    public func argonTopBar(
        variant: ArgonTopBarVariant = .standard,
        title: String,
        logoUrl: URL? = nil,
        leading: [ArgonTopBarAction] = [],
        trailing: [ArgonTopBarAction] = [],
        searchText: Binding<String>? = nil,
        isSearching: Binding<Bool>? = nil,
        solid: Double = 0,
        darkOverPicture: Bool = false
    ) -> some View {
        modifier(ArgonTopBar(
            variant: variant, title: title, logoUrl: logoUrl, leading: leading, trailing: trailing,
            searchText: searchText, isSearching: isSearching, solid: solid, darkOverPicture: darkOverPicture
        ))
    }
}
