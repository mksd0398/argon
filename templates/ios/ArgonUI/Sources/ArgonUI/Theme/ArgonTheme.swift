import SwiftUI
import UIKit

/// Argon's design tokens: colours (light and dark), type, spacing and radius. Read it with `@Environment(\.argonTheme)`;
/// set it with `.argonTheme(accentHex:)`.
public struct ArgonTheme: Equatable {
    public let colors: ArgonColors
    public let type: ArgonTypography
    public let spacing = ArgonSpacing()
    public let radius: ArgonRadius
    private let look: ArgonLook
    private let dynamicTypeSize: DynamicTypeSize

    /// `look`: the accent (the shop's brand colour, `#RRGGBB`; without a readable one the accent is ink), the light
    /// appearance's background and text, the corners and the buttons' shape.
    public init(look: ArgonLook = ArgonLook(), dynamicTypeSize: DynamicTypeSize = .large) {
        ArgonFonts.register()
        self.look = look
        self.dynamicTypeSize = dynamicTypeSize
        colors = ArgonColors(look: look)
        radius = ArgonRadius(corners: look.corners, buttons: look.buttons)
        type = ArgonTypography(dynamicTypeSize: dynamicTypeSize)
    }

    public init(accentHex: String?, dynamicTypeSize: DynamicTypeSize = .large) {
        self.init(look: ArgonLook(accentHex: accentHex), dynamicTypeSize: dynamicTypeSize)
    }

    public static func == (a: ArgonTheme, b: ArgonTheme) -> Bool {
        a.look == b.look && a.dynamicTypeSize == b.dynamicTypeSize
    }
}

/// What a merchant sets of the theme (contract/theme.js): the accent, the light appearance's background and text (nil:
/// Argon's paper and ink), the corners and the buttons' shape.
public struct ArgonLook: Equatable, Sendable {
    public var accentHex: String?
    public var backgroundHex: String?
    public var textHex: String?
    public var corners: ArgonCorners
    public var buttons: ArgonButtonShape

    public init(
        accentHex: String? = nil, backgroundHex: String? = nil, textHex: String? = nil,
        corners: ArgonCorners = .rounded, buttons: ArgonButtonShape = .pill
    ) {
        self.accentHex = accentHex
        self.backgroundHex = backgroundHex
        self.textHex = textHex
        self.corners = corners
        self.buttons = buttons
    }
}

/// The theme's corners: s, m and l in points (contract/theme.js CORNERS).
public enum ArgonCorners: String, CaseIterable, Sendable {
    case square, rounded, round

    public var points: [CGFloat] {
        switch self {
        case .square: return [0, 0, 0]
        case .rounded: return [4, 8, 16]
        case .round: return [8, 16, 24]
        }
    }
}

/// The buttons' shape (contract/theme.js BUTTONS): its corner radius.
public enum ArgonButtonShape: String, CaseIterable, Sendable {
    case pill, rounded, square

    public var points: CGFloat {
        switch self {
        case .pill: return 999
        case .rounded: return 8
        case .square: return 0
        }
    }
}

// MARK: Colour

/// A token's `#RRGGBB` value in one appearance.
public struct ArgonPalette: Sendable {
    public let ink, muted, paper, surface, border, sale, success: String

    public static let light = ArgonPalette(
        ink: "#17150F", muted: "#6E6A63", paper: "#F6F4F0", surface: "#FFFFFF", border: "#E2DED6",
        sale: "#B23A2E", success: "#2E7D4F"
    )
    // paper and ink swap; surface sits close to paper
    public static let dark = ArgonPalette(
        ink: "#F6F4F0", muted: "#A29E96", paper: "#17150F", surface: "#221F19", border: "#3A362F",
        sale: "#E8735F", success: "#6CC08A"
    )
}

/// The colour tokens. Each follows the light/dark appearance where it's drawn. Text on `sale` uses `paper`.
public struct ArgonColors {
    public let ink, muted, paper, surface, border, accent, onAccent, sale, success: Color

    init(look: ArgonLook) {
        let light = ArgonPalette.themed(look), dark = ArgonPalette.dark
        let accentHex = look.accentHex
        ink = dynamicColor(light.ink, dark.ink)
        muted = dynamicColor(light.muted, dark.muted)
        paper = dynamicColor(light.paper, dark.paper)
        surface = dynamicColor(light.surface, dark.surface)
        border = dynamicColor(light.border, dark.border)
        sale = dynamicColor(light.sale, dark.sale)
        success = dynamicColor(light.success, dark.success)
        if let hex = accentHex, let brand = ArgonTheme.color(hex: hex) {
            accent = brand
            onAccent = dynamicColor(ArgonTheme.onAccentHex(hex), ArgonTheme.onAccentHex(hex))
        } else {
            accent = ink
            onAccent = dynamicColor(ArgonTheme.onAccentHex(light.ink), ArgonTheme.onAccentHex(dark.ink))
        }
    }
}

extension ArgonPalette {
    /// The light palette with `look`'s background and text as paper and ink, and muted, border and surface made from
    /// them as contract/theme.js `themeTokens` makes them; Argon's own without either.
    public static func themed(_ look: ArgonLook) -> ArgonPalette {
        let background = ArgonTheme.rgb(hex: look.backgroundHex) != nil ? look.backgroundHex?.uppercased() : nil
        let text = ArgonTheme.rgb(hex: look.textHex) != nil ? look.textHex?.uppercased() : nil
        guard background != nil || text != nil else { return .light }
        let paper = background ?? ArgonPalette.light.paper, ink = text ?? ArgonPalette.light.ink
        let surface = (ArgonTheme.luminance(hex: paper) ?? 1) > 0.5
            ? ArgonTheme.mix("#FFFFFF", paper, 0.7) : ArgonTheme.mix(ink, paper, 0.08)
        return ArgonPalette(
            ink: ink, muted: ArgonTheme.mix(ink, paper, 0.62), paper: paper, surface: surface,
            border: ArgonTheme.mix(ink, paper, 0.14), sale: ArgonPalette.light.sale, success: ArgonPalette.light.success
        )
    }
}

private func dynamicColor(_ light: String, _ dark: String) -> Color {
    let black = (red: 0.0, green: 0.0, blue: 0.0)
    let l = ArgonTheme.rgb(hex: light) ?? black, d = ArgonTheme.rgb(hex: dark) ?? black
    return Color(uiColor: UIColor { traits in
        let c = traits.userInterfaceStyle == .dark ? d : l
        return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    })
}

extension ArgonTheme {
    /// `#RRGGBB` (the `#` is optional) as red, green and blue in 0...1; nil when it's absent or unreadable.
    public static func rgb(hex: String?) -> (red: Double, green: Double, blue: Double)? {
        guard let hex = hex else { return nil }
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// `a` at `amount` (0...1) over `b`, each channel rounded, as `#RRGGBB` (contract/theme.js `mix`).
    public static func mix(_ a: String, _ b: String, _ amount: Double) -> String {
        guard let x = rgb(hex: a), let y = rgb(hex: b) else { return b }
        let channel = { (p: Double, q: Double) in Int((p * 255 * amount + q * 255 * (1 - amount)).rounded()) }
        return String(format: "#%02X%02X%02X", channel(x.red, y.red), channel(x.green, y.green), channel(x.blue, y.blue))
    }

    /// The colour for `#RRGGBB`; nil when it's absent or unreadable.
    public static func color(hex: String?) -> Color? {
        guard let c = rgb(hex: hex) else { return nil }
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    /// WCAG relative luminance, 0 (black) to 1 (white); nil when the colour is unreadable.
    public static func luminance(hex: String?) -> Double? {
        guard let c = rgb(hex: hex) else { return nil }
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    /// Whether black text contrasts more with this colour than white does (so text on any accent gets at least 4.58:1).
    /// False when the colour is unreadable. Same rule as Android's `onAccentFor`.
    public static func isLight(hex: String?) -> Bool {
        guard let l = luminance(hex: hex) else { return false }
        return (l + 0.05) / 0.05 >= 1.05 / (l + 0.05)
    }

    /// `#000000` or `#FFFFFF`, whichever contrasts more with `accentHex`.
    public static func onAccentHex(_ accentHex: String) -> String {
        isLight(hex: accentHex) ? "#000000" : "#FFFFFF"
    }

    /// WCAG contrast ratio of two colours, 1...21; nil when either is unreadable.
    public static func contrastRatio(_ a: String, _ b: String) -> Double? {
        guard let la = luminance(hex: a), let lb = luminance(hex: b) else { return nil }
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

// MARK: Type, spacing, radius

/// Text roles. Display and title are Instrument Serif, the rest Hanken Grotesk; all follow Dynamic Type, and fall back
/// to the system font when the bundled fonts aren't available.
public struct ArgonTypography {
    public let display, title, headline, body, label, caption: Font

    init(dynamicTypeSize: DynamicTypeSize) {
        display = Self.make(serif: true, size: 40, weight: 400, style: .largeTitle, dynamicTypeSize)
        title = Self.make(serif: true, size: 28, weight: 400, style: .title, dynamicTypeSize)
        headline = Self.make(serif: false, size: 17, weight: 600, style: .headline, dynamicTypeSize)
        body = Self.make(serif: false, size: 16, weight: 400, style: .body, dynamicTypeSize)
        label = Self.make(serif: false, size: 14, weight: 500, style: .subheadline, dynamicTypeSize)
        caption = Self.make(serif: false, size: 12, weight: 400, style: .caption, dynamicTypeSize)
    }

    /// Hanken Grotesk at a fixed size (badges, avatars: text sized to its shape, not to Dynamic Type).
    static func fixed(size: CGFloat, weight: Int) -> Font {
        ArgonFonts.text(size: size, weight: weight).map { Font($0) } ?? .system(size: size, weight: fontWeight(weight))
    }

    private static func make(serif: Bool, size: CGFloat, weight: Int, style: Font.TextStyle, _ dynamicTypeSize: DynamicTypeSize) -> Font {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let scaled = UIFontMetrics(forTextStyle: uiTextStyle(style)).scaledValue(for: size, compatibleWith: traits)
        let font = serif ? ArgonFonts.display(size: scaled) : ArgonFonts.text(size: scaled, weight: weight)
        let design: Font.Design = serif ? .serif : .default
        return font.map { Font($0) } ?? .system(style, design: design, weight: fontWeight(weight))
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .caption: return .caption1
        default: return .body
        }
    }

    private static func fontWeight(_ weight: Int) -> Font.Weight {
        switch weight {
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        default: return .bold
        }
    }
}

/// Spacing steps in points: 2, 4, 8, 12, 16, 24, 32.
public struct ArgonSpacing {
    public let xxs: CGFloat = 2, xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
}

/// Corner radii in points: s, m and l by the theme's corners (rounded: 4, 8, 16), and pill (fully rounded); `button` is
/// the buttons' corner radius.
public struct ArgonRadius {
    public let s, m, l: CGFloat
    public let pill: CGFloat = 999
    public let button: CGFloat

    public init(corners: ArgonCorners = .rounded, buttons: ArgonButtonShape = .pill) {
        (s, m, l) = (corners.points[0], corners.points[1], corners.points[2])
        button = buttons.points
    }
}

/// Small, medium and large, for components that come in sizes.
public enum ArgonSize: Sendable {
    case s, m, l
}

// MARK: Environment

private struct ArgonThemeKey: EnvironmentKey {
    static let defaultValue = ArgonTheme()
}

extension EnvironmentValues {
    public var argonTheme: ArgonTheme {
        get { self[ArgonThemeKey.self] }
        set { self[ArgonThemeKey.self] = newValue }
    }
}

extension View {
    /// Argon's tokens for this view and everything in it, with the shop's brand colour (`#RRGGBB`) as the accent and the
    /// tint (ink when it's nil or unreadable).
    public func argonTheme(accentHex: String?) -> some View {
        modifier(ArgonThemeModifier(look: ArgonLook(accentHex: accentHex)))
    }

    /// Argon's tokens with the merchant's whole `look` (accent, background, text, corners, buttons).
    public func argonTheme(look: ArgonLook) -> some View {
        modifier(ArgonThemeModifier(look: look))
    }
}

private struct ArgonThemeModifier: ViewModifier {
    let look: ArgonLook
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    func body(content: Content) -> some View {
        let theme = ArgonTheme(look: look, dynamicTypeSize: dynamicTypeSize)
        return content.environment(\.argonTheme, theme).tint(theme.colors.accent)
    }
}
