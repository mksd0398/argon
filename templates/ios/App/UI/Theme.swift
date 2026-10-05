import Foundation
import SwiftUI

/// `#RRGGBB` as red, green and blue in 0...1; nil when it's absent or unreadable.
private func rgb(_ hex: String?) -> (red: Double, green: Double, blue: Double)? {
    guard let hex = hex else { return nil }
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
    return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
}

/// The shop's brand colour (`#RRGGBB`) for the app's tint; nil when it's absent or unreadable (the default accent stays).
func brandColor(_ hex: String?) -> Color? {
    guard let c = rgb(hex) else { return nil }
    return Color(red: c.red, green: c.green, blue: c.blue)
}

/// Whether text on the brand colour should be black rather than white: its relative luminance is above 0.5, Android's
/// `onPrimary` rule. False without a readable brand colour (the default accent takes white text).
func brandIsLight(_ hex: String?) -> Bool {
    guard let c = rgb(hex) else { return false }
    func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue) > 0.5
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
