import SwiftUI

/// The shop's brand colour (`#RRGGBB`) for the app's tint; nil when it's absent or unreadable (the default accent stays).
/// ponytail: no contrasting label colour is derived (Android picks black or white by luminance), so a very light brand
/// colour makes the white labels of prominent buttons hard to read; add a luminance check if a store needs it.
func brandColor(_ hex: String?) -> Color? {
    guard let hex = hex else { return nil }
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
    return Color(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255
    )
}
