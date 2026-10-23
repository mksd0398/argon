import ArgonUI
import SwiftUI

// Today's screens read the brand through these; ArgonTheme owns the rules (components read `\.argonTheme`).

/// The shop's brand colour (`#RRGGBB`) for the app's tint; nil when it's absent or unreadable (the default accent stays).
func brandColor(_ hex: String?) -> Color? {
    ArgonTheme.color(hex: hex)
}

/// Whether text on the brand colour should be black rather than white: its relative luminance is above 0.5, Android's
/// `onPrimary` rule. False without a readable brand colour (the default accent takes white text).
func brandIsLight(_ hex: String?) -> Bool {
    ArgonTheme.isLight(hex: hex)
}

/// Black or white, whichever reads on the brand colour.
@MainActor
func onBrandColor() -> Color {
    brandIsLight(AppGraph.brand.value?.accent) ? .black : .white
}

extension View {
    /// For text drawn on the brand colour: a prominent button's label, the banner box without an image.
    @MainActor
    func onBrand() -> some View { modifier(OnBrand()) }
}

struct OnBrand: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    // a disabled button keeps the system's disabled label colour
    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.foregroundStyle(onBrandColor())
        } else {
            content
        }
    }
}

extension ThemeLook {
    /// The look as ArgonTheme takes it, with `accent` (`#RRGGBB`, nil for ink).
    func argon(accent: String?) -> ArgonLook {
        ArgonLook(
            accentHex: accent, backgroundHex: background, textHex: text,
            corners: ArgonCorners(rawValue: corners) ?? .rounded, buttons: ArgonButtonShape(rawValue: buttons) ?? .pill
        )
    }
}
